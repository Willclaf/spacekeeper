// SpaceKeeper — menu bar app that shows and frees up space on your Mac.
// Hover the menu bar icon for a quick summary; click to keep it open.
// Uses the `spacekeeper` command-line tool (~/.local/bin) under the hood.

import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Command-line tool

enum CLI {
    static let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    static let path = home + "/.local/bin/spacekeeper"
    static let log = home + "/Library/Logs/spacekeeper.log"
    static var installed: Bool { FileManager.default.isExecutableFile(atPath: path) }

    static func run(_ args: [String]) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = [path] + args
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(returning: ""); return }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }
}

// MARK: - Self-install (for people who downloaded the .dmg and never opened Terminal)

enum Installer {
    static let home = CLI.home

    /// "VERSION=\"1.1.0\"" → "1.1.0"
    static func version(_ path: String) -> String? {
        guard let txt = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in txt.split(separator: "\n").prefix(30) where line.hasPrefix("VERSION=") {
            return line.dropFirst(8).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    /// Installs or updates the tool bundled inside the app. On first run it also
    /// turns on the watcher with the default goal (30 GB). Returns true if it installed now.
    @discardableResult
    static func ensure() async -> Bool {
        let fm = FileManager.default
        guard let bundled = Bundle.main.path(forResource: "spacekeeper", ofType: nil) else { return false }
        let firstRun = !fm.fileExists(atPath: home + "/.config/spacekeeper/config")
        let current = version(CLI.path)
        if current != nil && current == version(bundled) && !firstRun { return false }

        try? fm.createDirectory(atPath: home + "/.local/bin", withIntermediateDirectories: true)
        try? fm.removeItem(atPath: CLI.path)
        guard (try? fm.copyItem(atPath: bundled, toPath: CLI.path)) != nil else { return false }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: CLI.path)

        // skill for Claude Code / Codex, if the user has them
        if let skill = Bundle.main.path(forResource: "skill-spacekeeper", ofType: nil) {
            for dir in [".claude", ".codex"] where fm.fileExists(atPath: home + "/" + dir) {
                let dest = home + "/" + dir + "/skills/spacekeeper"
                try? fm.createDirectory(atPath: home + "/" + dir + "/skills", withIntermediateDirectories: true)
                try? fm.removeItem(atPath: dest)
                try? fm.copyItem(atPath: skill, toPath: dest)
            }
        }

        // spacekeeper command in Terminal
        let zshrc = home + "/.zshrc"
        let current_zshrc = (try? String(contentsOfFile: zshrc, encoding: .utf8)) ?? ""
        if !current_zshrc.contains(".local/bin") {
            let line = "\n# spacekeeper\nexport PATH=\"$HOME/.local/bin:$PATH\"\n"
            if let h = FileHandle(forWritingAtPath: zshrc) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
            else { try? line.write(toFile: zshrc, atomically: true, encoding: .utf8) }
        }

        if firstRun {
            _ = await CLI.run(["config", "goal", "30"])
            _ = await CLI.run(["config", "auto-clean", "no"])
            _ = await CLI.run(["watch", "on"])
        }
        return true
    }
}

// MARK: - Support

enum Support {
    /// Donation page (Ko-fi, PayPal, GitHub Sponsors…). The ☕ button only shows up when this is set.
    static let url: URL? = nil
}

// MARK: - Data

struct Summary: Decodable {
    var free: Int64
    var total: Int64
    var goalKb: Int64
    var goalGb: Int
    var watching: Bool
    var autoClean: Bool
    var interval: Int
    var trendKb: Int64?
    var firstScanDone: Bool?
    var junk: [Junk]
    var crashes: [Crash]
    var tasks: [BackgroundTask]
    var remote: [Remote]
}

struct Junk: Decodable, Identifiable {
    var kb: Int64; var desc: String; var busy: Bool; var path: String
    var id: String { path }
}

struct Crash: Decodable, Identifiable {
    var n: Int; var kb: Int64; var app: String; var path: String
    var id: String { path }
}

struct BackgroundTask: Decodable, Identifiable {
    var kind: String; var label: String; var info: String; var prog: String
    var id: String { label }
}

struct Remote: Decodable, Identifiable {
    var app: String; var port: String; var profile: String
    var id: String { app + port }
}

struct ScanItem: Decodable, Identifiable {
    var id: String; var tier: String; var kb: Int64; var inUseBy: String
    var desc: String; var note: String; var toTrash: Bool
    var safe: Bool { tier == "safe" }
    var busy: Bool { !inUseBy.isEmpty }
}

struct Scan: Decodable {
    var free: Int64
    var items: [ScanItem]
}

struct Skipped: Decodable, Hashable { var desc: String; var inUseBy: String }

struct CleanResult: Decodable {
    var freedKb: Int64
    var trashedKb: Int64
    var items: Int
    var freeBefore: Int64
    var freeAfter: Int64
    var skipped: [Skipped]
}

struct Folder: Decodable, Identifiable {
    var kb: Int64; var path: String; var hidden: Bool; var tip: String
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var short: String { path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

/// Decimal GB/MB, same as Finder.
func size(_ kb: Int64) -> String {
    let b = Double(abs(kb)) * 1024
    if b >= 1e9 { return String(format: "%.1f GB", b / 1e9) }
    if b >= 1e6 { return String(format: "%.0f MB", b / 1e6) }
    return "\(abs(kb)) KB"
}

@MainActor
final class AppState: ObservableObject {
    @Published var summary: Summary?
    @Published var folders: [Folder]?
    @Published var loading = false
    @Published var measuringFolders = false
    @Published var cleaning = false
    @Published var notice: String?

    // full scan (first run and on demand)
    enum ScanPhase { case closed, scanning, list, cleaning, result }
    @Published var phase: ScanPhase = .closed
    @Published var scan: Scan?
    @Published var selected: Set<String> = []
    @Published var result: CleanResult?
    @Published var emptyingTrash = false
    @Published var trashEmptied = false
    @Published var newVersion: String?
    @Published var updating = false

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// true if version a is newer than b ("1.10.0" > "1.9.2")
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    func checkForUpdate() async {
        guard let url = URL(string: "https://api.github.com/repos/Willclaf/spacekeeper/releases/latest"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return }
        let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        newVersion = AppState.isNewer(v, than: AppState.appVersion) ? v : nil
    }

    /// Runs the tool's updater. It quits and reopens the app by itself.
    func updateApp() {
        updating = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "\"$HOME/.local/bin/spacekeeper\" update >> \"$HOME/Library/Logs/spacekeeper.log\" 2>&1"]
        try? p.run()
    }

    var onRefresh: (() -> Void)?
    var pedirJanela: (() -> Void)?
    private var lastRefresh = Date.distantPast
    private var goalTask: Task<Void, Never>?

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    func refresh(ifStale: Bool = false) async {
        guard CLI.installed else { onRefresh?(); return }
        if ifStale && Date().timeIntervalSince(lastRefresh) < 60 { return }
        if loading { return }
        loading = true
        let txt = await CLI.run(["data", "summary"])
        if let s = try? decoder().decode(Summary.self, from: Data(txt.utf8)) {
            summary = s
            lastRefresh = Date()
        }
        loading = false
        onRefresh?()
    }

    func measureFolders() async {
        measuringFolders = true
        let txt = await CLI.run(["data", "folders"])
        folders = (try? decoder().decode([Folder].self, from: Data(txt.utf8))) ?? []
        measuringFolders = false
    }

    func clean() async {
        let before = summary?.free ?? 0
        cleaning = true
        notice = nil
        _ = await CLI.run(["clean", "--run", "--yes"])
        lastRefresh = .distantPast
        await refresh()
        cleaning = false
        let gain = (summary?.free ?? 0) - before
        notice = gain > 102_400 ? "Done! Freed \(size(gain))." : "Done! Junk cleaned."
    }

    func setGoal(_ gb: Int) {
        summary?.goalGb = gb
        summary?.goalKb = Int64(gb) * 976_562
        onRefresh?()
        goalTask?.cancel()
        goalTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            _ = await CLI.run(["config", "goal", "\(gb)"])
        }
    }

    func setWatching(_ on: Bool) async {
        summary?.watching = on
        _ = await CLI.run(["watch", on ? "on" : "off"])
        lastRefresh = .distantPast
        await refresh()
    }

    func setAutoClean(_ on: Bool) async {
        summary?.autoClean = on
        _ = await CLI.run(["config", "auto-clean", on ? "yes" : "no"])
    }

    func runScan() async {
        phase = .scanning
        result = nil
        trashEmptied = false
        let txt = await CLI.run(["data", "scan"])
        guard let s = try? decoder().decode(Scan.self, from: Data(txt.utf8)) else {
            phase = .closed
            notice = "Couldn't run the scan right now."
            return
        }
        scan = s
        // pre-selected: only what's safe and can be cleaned right now
        selected = Set(s.items.filter { $0.safe && !$0.busy }.map(\.id))
        phase = .list
    }

    func toggle(_ item: ScanItem) {
        guard !item.busy else { return }
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }

    var selectedTotal: Int64 {
        (scan?.items ?? []).filter { selected.contains($0.id) }.reduce(0) { $0 + $1.kb }
    }

    func cleanSelected() async {
        guard !selected.isEmpty else { return }
        phase = .cleaning
        let txt = await CLI.run(["clean-items"] + Array(selected) + ["--json"])
        result = try? decoder().decode(CleanResult.self, from: Data(txt.utf8))
        phase = .result
        lastRefresh = .distantPast
        await refresh()
    }

    func skipScan() async {
        _ = await CLI.run(["scan", "--skip"])
        phase = .closed
        lastRefresh = .distantPast
        await refresh()
    }

    func finishScan() {
        phase = .closed
        scan = nil
        result = nil
    }

    func emptyTrash() async {
        emptyingTrash = true
        _ = await CLI.run(["empty-trash", "--yes"])
        emptyingTrash = false
        trashEmptied = true
        lastRefresh = .distantPast
        await refresh()
    }

    func pause(_ label: String) async {
        _ = await CLI.run(["pause-task", label])
        lastRefresh = .distantPast
        await refresh()
        notice = "Task \(label) paused."
    }
}

// MARK: - UI building blocks

/// Ring with free space in the middle and a tick marking the goal.
struct SpaceRing: View {
    let s: Summary

    var colors: [Color] {
        if s.free < s.goalKb { return [.red, .pink] }
        if s.free < s.goalKb + s.goalKb / 3 { return [.orange, .yellow] }
        return [Color(red: 0.16, green: 0.80, blue: 0.56), Color(red: 0.10, green: 0.55, blue: 0.95)]
    }

    var body: some View {
        let free = CGFloat(s.free) / CGFloat(max(s.total, 1))
        let goal = CGFloat(s.goalKb) / CGFloat(max(s.total, 1))
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
            Circle()
                .trim(from: 0, to: free)
                .stroke(AngularGradient(colors: colors + [colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // goal tick
            Capsule()
                .fill(Color.primary.opacity(0.8))
                .frame(width: 2.5, height: 11)
                .offset(y: -29)
                .rotationEffect(.degrees(Double(goal) * 360))
            VStack(spacing: -2) {
                Text("\(Int((Double(s.free) * 1024 / 1e9).rounded()))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("GB").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 58, height: 58)
        .help("Ring = free space. Tick = your goal.")
    }
}

/// White icon on a colored rounded square, like System Settings.
struct SquareIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
    }
}

/// An "icon · label ........ value" row in the compact summary.
struct Row<Value: View>: View {
    let icon: String
    let color: Color
    let title: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 10) {
            SquareIcon(symbol: icon, color: color)
            Text(title)
            Spacer(minLength: 8)
            value
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 38)
    }
}

/// Gradient capsule button.
struct Pill: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.gradient))
            .shadow(color: color.opacity(0.35), radius: 3, y: 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Grouped background (System Settings list style).
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct Block<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Main panel

struct PanelView: View {
    @EnvironmentObject var e: AppState
    @State private var details = false
    @State private var confirming = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !CLI.installed {
                notInstalled
            } else if e.phase != .closed {
                ScanView()
            } else if let s = e.summary {
                summary(s).padding(14)
                if details {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            alerts(s)
                            junkDetails(s)
                            folders
                            settings(s)
                        }
                        .padding(14)
                    }
                    .frame(maxHeight: 420)
                }
                Divider()
                footer(s)
            } else {
                HStack { ProgressView().controlSize(.small); Text("Checking your disk…").foregroundStyle(.secondary) }
                    .padding(20)
            }
        }
        .frame(width: e.phase == .closed ? 300 : 340)
        .animation(.easeInOut(duration: 0.2), value: details)
        .animation(.easeInOut(duration: 0.25), value: e.phase)
    }

    var notInstalled: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The command-line tool is missing").font(.headline)
            Text("In the spacekeeper folder, run ./install.sh in Terminal.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // ── the four essentials ──────────────────────────────────────────────

    func summary(_ s: Summary) -> some View {
        let total = s.junk.filter { !$0.busy }.reduce(Int64(0)) { $0 + $1.kb }
        let ok = s.free >= s.goalKb
        return VStack(alignment: .leading, spacing: 12) {
            // 1. free space
            HStack(spacing: 14) {
                SpaceRing(s: s)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free space").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text(size(s.free)).font(.system(size: 22, weight: .bold, design: .rounded))
                    HStack(spacing: 4) {
                        Circle().fill(ok ? Color.green : Color.red).frame(width: 6, height: 6)
                        Text(ok ? "\(size(s.free - s.goalKb)) above your goal"
                                : "\(size(s.goalKb - s.free)) short of your goal")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(ok ? Color.secondary : Color.red)
                }
                Spacer()
                if e.loading { ProgressView().controlSize(.mini) }
            }

            Card {
                // 2. goal
                Row(icon: "flag.fill", color: .blue, title: "Goal") {
                    HStack(spacing: 2) {
                        Button { e.setGoal(max(5, s.goalGb - 5)) } label: {
                            Image(systemName: "minus").frame(width: 20, height: 20)
                        }
                        Text("\(s.goalGb) GB").monospacedDigit().fontWeight(.semibold).frame(minWidth: 46)
                        Button { e.setGoal(min(500, s.goalGb + 5)) } label: {
                            Image(systemName: "plus").frame(width: 20, height: 20)
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                Divider().padding(.leading, 42)
                // 3. watcher
                Row(icon: s.watching ? "eye.fill" : "eye.slash.fill", color: s.watching ? .purple : .gray, title: "Watcher") {
                    Text(s.watching ? "every \(s.interval)h" : "off")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Toggle("", isOn: Binding(get: { s.watching }, set: { v in Task { await e.setWatching(v) } }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                }
                Divider().padding(.leading, 42)
                // 4. to clean
                Row(icon: "sparkles", color: .green, title: "To clean") {
                    if e.cleaning {
                        ProgressView().controlSize(.mini)
                    } else if total == 0 {
                        Text("nothing 👌").foregroundStyle(.secondary)
                    } else {
                        Text(size(total)).monospacedDigit().foregroundStyle(.secondary)
                        Button(confirming ? "Confirm" : "Clean") {
                            if confirming {
                                confirming = false
                                Task { await e.clean() }
                            } else {
                                confirming = true
                            }
                        }
                        .buttonStyle(Pill(color: confirming ? .orange : .green))
                        .help("Deletes only caches, old logs and crash reports. Everything rebuilds itself.")
                    }
                }
            }

            if confirming {
                HStack {
                    Text("Delete \(size(total)) of safe junk?").font(.caption)
                    Spacer()
                    Button("Cancel") { confirming = false }.buttonStyle(.borderless).font(.caption)
                }
            }
            if let n = e.notice {
                Label(n, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            }
        }
    }

    func footer(_ s: Summary) -> some View {
        let alertCount = s.crashes.count + s.tasks.count + s.remote.count
        return HStack {
            Button {
                details.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(details ? "Show less" : "Show more")
                    Image(systemName: details ? "chevron.up" : "chevron.down").font(.caption2)
                    if alertCount > 0 && !details {
                        Text("\(alertCount) alert\(alertCount > 1 ? "s" : "")")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            if let v = e.newVersion {
                Button { e.updateApp() } label: {
                    if e.updating {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("⬆️ \(v)")
                    }
                }
                .buttonStyle(Pill(color: .blue))
                .disabled(e.updating)
                .help("A new version of SpaceKeeper is out. Click to update (your settings are kept).")
            }
            if let url = Support.url {
                Button { NSWorkspace.shared.open(url) } label: { Text("☕").font(.system(size: 14)) }
                    .help("Buy me a coffee — SpaceKeeper is free")
            }
            Button { e.pedirJanela?() } label: { Image(systemName: "macwindow") }
                .help("Open as a window")
            Button { Task { await e.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // ── details (Show more) ──────────────────────────────────────────────

    @ViewBuilder
    func alerts(_ s: Summary) -> some View {
        if !s.crashes.isEmpty || !s.tasks.isEmpty || !s.remote.isEmpty {
            Block(title: "Alerts") {
                ForEach(s.crashes) { c in
                    alert("xmark.octagon.fill", .red, "\(c.app) keeps crashing",
                          "\(c.n) crash reports (\(size(c.kb))). Clean up and restart the app.")
                }
                ForEach(s.tasks) { t in
                    HStack(alignment: .top) {
                        alert(t.kind == "reopens" ? "arrow.triangle.2.circlepath" : "exclamationmark.circle.fill",
                              t.kind == "reopens" ? .orange : .red, t.label,
                              t.kind == "reopens" ? "Opens \(t.info) by itself and reopens it if you quit."
                                                  : "Background task keeps failing (code \(t.info)).")
                        Button("Pause") { Task { await e.pause(t.label) } }
                            .controlSize(.mini)
                            .help("Stops the task (reversible: spacekeeper resume-task \(t.label))")
                    }
                }
                ForEach(s.remote) { r in
                    alert("dot.radiowaves.left.and.right", .orange, "\(r.app) has remote control enabled",
                          "Any program can drive this browser. If it isn't your own automation, quit it.")
                }
            }
        }
    }

    func alert(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.caption).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.medium)).lineLimit(2)
                Text(text).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    func junkDetails(_ s: Summary) -> some View {
        Block(title: "What can be cleaned") {
            if s.junk.isEmpty {
                Text("Nothing right now.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(s.junk.sorted { $0.kb > $1.kb }) { j in
                HStack {
                    Text(j.desc).lineLimit(1)
                    if j.busy {
                        Text("quit the app").font(.caption2).foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(size(j.kb)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption)
                .opacity(j.busy ? 0.55 : 1)
            }
        }
    }

    var folders: some View {
        Block(title: "Biggest folders") {
            if e.measuringFolders {
                HStack { ProgressView().controlSize(.mini); Text("Measuring… about 15 s").foregroundStyle(.secondary) }
                    .font(.caption)
            } else if let list = e.folders {
                ForEach(list.prefix(10)) { f in
                    HStack(spacing: 4) {
                        Text(f.name).lineLimit(1).truncationMode(.middle)
                        if f.hidden {
                            Text("hidden").font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(size(f.kb)).monospacedDigit().foregroundStyle(.secondary)
                        Button { NSWorkspace.shared.open(URL(fileURLWithPath: f.path)) } label: {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.borderless)
                        .help(f.tip.isEmpty ? "Open in Finder: \(f.short)" : "\(f.tip)\n\(f.short)")
                    }
                    .font(.caption)
                }
            } else {
                Button("Measure folders (including hidden ones)") { Task { await e.measureFolders() } }
                    .controlSize(.small)
            }
        }
    }

    func settings(_ s: Summary) -> some View {
        Block(title: "Settings") {
            Toggle("Clean automatically below the goal",
                   isOn: Binding(get: { s.autoClean }, set: { v in Task { await e.setAutoClean(v) } }))
                .disabled(!s.watching)
            Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: { v in
                do {
                    if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {}
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }))
            Button {
                Task { await e.runScan() }
            } label: {
                Label("Run a full scan of my Mac", systemImage: "wand.and.stars")
            }
            .controlSize(.small)
            HStack {
                Button("History") { NSWorkspace.shared.open(URL(fileURLWithPath: CLI.log)) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.caption)
    }
}

// MARK: - Full scan (welcome)

struct ScanView: View {
    @EnvironmentObject var e: AppState
    @State private var confirmingTrash = false
    @State private var pulse = false
    @State private var party = false

    var body: some View {
        switch e.phase {
        case .scanning: scanning
        case .list: list
        case .cleaning: cleaningView
        case .result: resultView
        case .closed: EmptyView()
        }
    }

    // 1. looking
    var scanning: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 74, height: 74)
                    .scaleEffect(pulse ? 1.15 : 0.9)
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.green, .blue], startPoint: .top, endPoint: .bottom))
            }
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
            VStack(spacing: 4) {
                Text(e.summary?.firstScanDone == false ? "Welcome to SpaceKeeper 👋" : "Full scan")
                    .font(.headline)
                Text("Looking for hidden space on your Mac…")
                    .font(.callout).foregroundStyle(.secondary)
                Text("caches, crash reports, logs, AI tools and more")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            ProgressView().controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // 2. pick what to clean
    var list: some View {
        let items = e.scan?.items ?? []
        let total = items.reduce(Int64(0)) { $0 + $1.kb }
        let safe = items.filter(\.safe)
        let review = items.filter { !$0.safe }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(items.isEmpty ? "All clean here" : "I found")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                if !items.isEmpty {
                    Text(size(total))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.16, green: 0.80, blue: 0.56),
                                                                 Color(red: 0.10, green: 0.55, blue: 0.95)],
                                                        startPoint: .leading, endPoint: .trailing))
                    Text("you can free up on your Mac. Pick what to clean:")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Your Mac has no hidden junk right now 👌").font(.callout)
                }
            }
            .padding(14)

            if !items.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !safe.isEmpty {
                            group("Safe", "rebuilds itself, you lose nothing", safe)
                        }
                        if !review.isEmpty {
                            group("Review", "yours: only removed if you pick it", review)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .frame(maxHeight: 360)
            }

            Divider()
            VStack(spacing: 8) {
                if !items.isEmpty {
                    Button {
                        Task { await e.cleanSelected() }
                    } label: {
                        Text(e.selected.isEmpty ? "Pick what you want to clean" : "Free up \(size(e.selectedTotal))")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(Pill(color: .green))
                    .disabled(e.selected.isEmpty)
                    .opacity(e.selected.isEmpty ? 0.5 : 1)
                }
                HStack {
                    if items.contains(where: \.busy) {
                        Button("I quit the apps, check again") { Task { await e.runScan() } }
                    }
                    Spacer()
                    Button(items.isEmpty ? "Close" : "Not now") { Task { await e.skipScan() } }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    func group(_ title: String, _ sub: String, _ items: [ScanItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11, weight: .bold)).textCase(.uppercase)
                Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Card {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().padding(.leading, 38) }
                    row(item)
                }
            }
        }
    }

    func row(_ item: ScanItem) -> some View {
        let on = e.selected.contains(item.id)
        return Button { e.toggle(item) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.busy ? "lock.circle" : (on ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 17))
                    .foregroundStyle(item.busy ? Color.orange : (on ? Color.green : Color.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.desc).font(.system(size: 12.5)).lineLimit(2).multilineTextAlignment(.leading)
                    if item.busy {
                        Text("Quit \(item.inUseBy) to clean this").font(.caption2).foregroundStyle(.orange)
                    } else if !item.note.isEmpty {
                        Text(item.note).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 6)
                Text(size(item.kb)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(on ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(item.busy ? 0.65 : 1)
        .help(item.busy ? "This app is open. Quit it and click \"check again\"." : "")
    }

    // 3. cleaning
    var cleaningView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Freeing up \(size(e.selectedTotal))…").font(.callout)
            Text("Don't open those apps right now").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // 4. result
    var resultView: some View {
        let r = e.result
        let freed = r?.freedKb ?? 0
        return VStack(spacing: 14) {
            Text(freed > 0 ? "🎉" : "✅")
                .font(.system(size: 52))
                .scaleEffect(party ? 1 : 0.3)
                .rotationEffect(.degrees(party ? 0 : -25))
                .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { party = true } }
            VStack(spacing: 2) {
                Text(freed > 0 ? "You freed up" : "Done!").font(.callout).foregroundStyle(.secondary)
                if freed > 0 {
                    Text(size(freed))
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.16, green: 0.80, blue: 0.56),
                                                                 Color(red: 0.10, green: 0.55, blue: 0.95)],
                                                        startPoint: .leading, endPoint: .trailing))
                    Text("that was hiding on your Mac").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let r {
                HStack(spacing: 8) {
                    VStack(spacing: 1) {
                        Text("before").font(.caption2).foregroundStyle(.secondary)
                        Text(size(r.freeBefore)).font(.callout.weight(.semibold)).monospacedDigit()
                    }
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    VStack(spacing: 1) {
                        Text("free now").font(.caption2).foregroundStyle(.secondary)
                        Text(size(e.summary?.free ?? r.freeAfter)).font(.callout.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.primary.opacity(0.05)))

                if r.trashedKb > 0 { trashCard(r.trashedKb) }

                if !r.skipped.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(r.skipped, id: \.self) { s in
                            Label("Skipped \(s.desc): \(s.inUseBy) was open", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            Button { e.finishScan() } label: { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(Pill(color: .blue))
            if freed > 0, let url = Support.url {
                Button { NSWorkspace.shared.open(url) } label: {
                    Text("☕ Enjoying it? Buy me a coffee").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
    }

    func trashCard(_ kb: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SquareIcon(symbol: "trash.fill", color: .gray)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.trashEmptied ? "Trash emptied ✓" : "Another \(size(kb)) went to the Trash")
                        .font(.callout.weight(.medium))
                    Text(e.trashEmptied ? "That space is free for good." : "Still recoverable. Empty it to free the space for good.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !e.trashEmptied {
                if e.emptyingTrash {
                    HStack { ProgressView().controlSize(.mini); Text("Emptying…").font(.caption) }
                } else if confirmingTrash {
                    HStack {
                        Text("Permanently deletes everything in the Trash.").font(.caption)
                        Spacer()
                        Button("Cancel") { confirmingTrash = false }.buttonStyle(.borderless).font(.caption)
                        Button("Empty") {
                            confirmingTrash = false
                            Task { await e.emptyTrash() }
                        }
                        .buttonStyle(Pill(color: .red))
                    }
                } else {
                    Button("Empty Trash") { confirmingTrash = true }
                        .buttonStyle(Pill(color: .gray))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - App (menu bar icon + popover)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    let popover = NSPopover()
    var item: NSStatusItem!
    var monitors: [Any] = []
    var openTimer: Timer?
    var closeTimer: Timer?
    var pinned = false   // opened with a click: only closes on an outside click
    var janela: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "SpaceKeeper")
            b.imagePosition = .imageLeading
            b.target = self
            b.action = #selector(iconClicked)
        }

        let host = NSHostingController(rootView: PanelView().environmentObject(state))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .applicationDefined
        popover.animates = true

        state.onRefresh = { [weak self] in self?.updateIcon() }
        state.pedirJanela = { [weak self] in self?.openWindow() }

        // hovering the icon opens it; moving away closes it
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            Task { @MainActor in self?.mouseMoved() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] ev in
            Task { @MainActor in self?.mouseMoved() }
            return ev
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.close() }
        }) { monitors.append(m) }

        Task {
            await Installer.ensure()   // installed from the .dmg? the tool ships inside
            await state.refresh()
            // first run (or the installer asked for it): open by itself and run the full scan
            let welcome = CommandLine.arguments.contains("--welcome")
            let primeira = welcome || state.summary?.firstScanDone == false
            if primeira {
                open(pinned: true)
                await state.runScan()
            }
            await askLaunchAtLogin()
            // aberto por quem clicou no app (e não pelo login): mostra a janela
            if !welcome && !primeira && !launchedAtLogin() && CommandLine.arguments.count == 1 { openWindow() }
        }
        if CommandLine.arguments.contains("--show") { open(pinned: true) }
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.state.refresh() }
        }
        // new version: checked at launch and every 6 h
        Task { await state.checkForUpdate() }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.state.checkForUpdate() }
        }
    }

    // MARK: janela (app de verdade), pergunta do login e ícone

    /// Abre o app numa janela normal (Dock + Cmd-Tab) além do ícone da barra.
    func openWindow() {
        close(force: true)
        if janela == nil {
            let host = NSHostingController(rootView: PanelView().environmentObject(state))
            host.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: host)
            w.title = "SpaceKeeper"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.janela = nil
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            janela = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        janela?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow()
        return true
    }

    /// O macOS abriu o app sozinho no login? (nesse caso não mostra janela)
    func launchedAtLogin() -> Bool {
        let ev = NSAppleEventManager.shared().currentAppleEvent
        return ev?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == AEKeyword(keyAELaunchedAsLogInItem)
    }

    /// Pergunta uma única vez se a pessoa quer abrir ao ligar o Mac.
    func askLaunchAtLogin() async {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "askedLaunchAtLogin") else { return }
        d.set(true, forKey: "askedLaunchAtLogin")
        if SMAppService.mainApp.status == .enabled { return }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Open SpaceKeeper when you start your Mac?"
        a.informativeText = "That keeps the icon in your menu bar, always watching your free space. You can change this later in Settings."
        a.addButton(withTitle: "Yes, open at login")
        a.addButton(withTitle: "Not now")
        if a.runModal() == .alertFirstButtonReturn { try? SMAppService.mainApp.register() }
    }

    /// Ícone da barra: anel que mostra quanto do disco está livre.
    func ring(_ free: Double, alert: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let c = NSPoint(x: 9, y: 9)
            let cor: NSColor = alert ? .systemRed : .black
            cor.withAlphaComponent(0.28).setStroke()
            let trilho = NSBezierPath()
            trilho.appendArc(withCenter: c, radius: 6.5, startAngle: 0, endAngle: 360)
            trilho.lineWidth = 2.2
            trilho.stroke()
            cor.setStroke()
            let arco = NSBezierPath()
            arco.appendArc(withCenter: c, radius: 6.5, startAngle: 90, endAngle: 90 - 360 * CGFloat(max(0.03, min(1, free))), clockwise: true)
            arco.lineWidth = 2.2
            arco.lineCapStyle = .round
            arco.stroke()
            cor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7.2, y: 7.2, width: 3.6, height: 3.6)).fill()
            return true
        }
        img.isTemplate = !alert
        return img
    }

    func updateIcon() {
        guard let b = item.button else { return }
        guard let s = state.summary else { b.title = ""; return }
        let gb = Int((Double(s.free) * 1024 / 1e9).rounded())
        let below = s.free < s.goalKb
        b.title = " \(gb) GB"
        b.image = ring(Double(s.free) / Double(max(s.total, 1)), alert: below)
        b.contentTintColor = nil
    }

    var iconFrame: NSRect {
        guard let b = item.button, let w = b.window else { return .zero }
        return w.convertToScreen(b.convert(b.bounds, to: nil))
    }

    var popoverFrame: NSRect {
        popover.contentViewController?.view.window?.frame ?? .zero
    }

    func mouseMoved() {
        let p = NSEvent.mouseLocation
        let onIcon = iconFrame.insetBy(dx: -2, dy: -2).contains(p)
        if !popover.isShown {
            if onIcon {
                if openTimer == nil {
                    openTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            guard let self else { return }
                            self.openTimer = nil
                            if self.iconFrame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) {
                                self.open(pinned: false)
                            }
                        }
                    }
                }
            } else {
                openTimer?.invalidate(); openTimer = nil
            }
            return
        }
        guard !pinned else { return }
        let near = onIcon || popoverFrame.insetBy(dx: -16, dy: -16).contains(p)
        if near {
            closeTimer?.invalidate(); closeTimer = nil
        } else if closeTimer == nil {
            closeTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.closeTimer = nil
                    let q = NSEvent.mouseLocation
                    if !self.iconFrame.contains(q) && !self.popoverFrame.insetBy(dx: -16, dy: -16).contains(q) {
                        self.close(force: true)
                    }
                }
            }
        }
    }

    @objc func iconClicked() {
        if popover.isShown && pinned {
            close(force: true)
        } else if popover.isShown {
            pinned = true   // it was open from hovering: the click "pins" it
        } else {
            open(pinned: true)
        }
    }

    func open(pinned: Bool) {
        guard let b = item.button else { return }
        self.pinned = pinned
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await state.refresh(ifStale: true) }
    }

    func close(force: Bool = false) {
        guard popover.isShown else { return }
        if !force && popoverFrame.contains(NSEvent.mouseLocation) { return }
        closeTimer?.invalidate(); closeTimer = nil
        pinned = false
        popover.performClose(nil)
    }
}

@main
enum SpaceKeeperApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
