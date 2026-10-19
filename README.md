# SpaceKeeper 💽

**Your Mac never runs out of space out of nowhere again.**

SpaceKeeper shows you what's eating your disk (including the folders Finder hides), cleans only what's truly junk, and keeps watch in the background. When your free space drops below your goal, it tells you.

It lives in your menu bar, works straight from the Terminal, and ships with a **skill for Claude Code and Codex**: just say "my Mac is out of space" and your AI assistant runs the scan and explains everything.

Free and open source. macOS 13+ · Intel & Apple Silicon.

---

## Why this exists

One day my Mac was down to **9 GB free out of 228 GB**. The culprits:

- **16 GB of crash reports.** One app got stuck in a crash loop and wrote almost 200,000 files in 3 days, in a folder nobody ever looks at.
- **My "Movies" folder weighed 4 GB and looked empty.** It was DaVinci Resolve stills sitting in a hidden folder.
- **8 GB of Lightroom cache** on the internal SSD.
- **"My Chrome lost all its profiles."** An automation had installed a background task that kept launching a separate Chrome and reopening it every time I quit. My profiles were fine the whole time.

In one afternoon I got back **more than 35 GB** without deleting anything I cared about. SpaceKeeper is all of that, packaged so it doesn't happen again.

---

## Install

### The easiest way: download the installer (.dmg)

1. Download **[SpaceKeeper.dmg](https://github.com/Willclaf/spacekeeper/releases/latest/download/SpaceKeeper.dmg)**
2. Open it and **drag SpaceKeeper into Applications**
3. Open SpaceKeeper. The first time, your Mac may say it couldn't verify the developer: go to **System Settings → Privacy & Security → Open Anyway** (on macOS 13/14: right-click the app → Open)
4. That's it: it installs itself, shows up in your menu bar and immediately shows how much hidden space it found

### Or ask your AI assistant

Open Claude Code, Codex or Cursor and paste:

> Install SpaceKeeper for me: https://github.com/Willclaf/spacekeeper — follow the repo's AGENTS.md.

It downloads the project, asks for your free-space goal, installs everything, runs the first scan with you and checks that it all works. You just approve what it asks.

### The manual way: one line in Terminal

```bash
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Willclaf/spacekeeper/main/get.sh)"
```

No git and no Apple developer tools needed: the app comes prebuilt (and is verified with SHA-256 before installing). The installer asks for your free-space goal and, at the end, **SpaceKeeper opens a full scan of your Mac**.

No questions: `… get.sh)" -- --yes --goal 30 --watch yes --auto-clean no`

---

## The first scan: the space that was hiding

Right after installing, SpaceKeeper sweeps your Mac and shows **how much you can free up**:

- **Safe** (pre-selected): browser caches, app caches (Claude, Codex, Cursor, Slack, Figma…), developer caches (npm, pip, uv…), Lightroom cache, crash reports, old logs, already-downloaded updates
- **Review** (only if you pick them, and they go to the Trash): forgotten .dmg/.pkg installers in Downloads, old Codex conversations, downloaded AI models, Playwright browsers
- Anything **in use** shows a lock: "Quit Chrome to clean this". Quit it, click **check again**.

Pick, click **Free up**, and you get: **🎉 You freed up X GB that was hiding on your Mac.** Anything that went to the Trash is shown separately, with a button to empty it.

Run it again anytime: in the app (**Show more → Run a full scan**) or in Terminal (`spacekeeper scan`).

---

## The menu bar app

A tiny disk icon shows how many GB you have free. **Hover to see the summary. Move away and it closes.** Click to keep it open.

The summary shows just four things:

| | |
|---|---|
| 🟢 **Free space** | a colored ring (green, orange or red) with a tick marking your goal |
| 🚩 **Goal** | − / + to set how many GB you want to keep free |
| 👁 **Watcher** | turns the background watcher on and off |
| ✨ **To clean** | how much safe junk there is, with a **Clean** button |

**Show more** opens the details: alerts (crash-looping apps, tasks that reopen apps by themselves — with a **Pause** button, remote-controlled browsers), exactly what can be cleaned, the biggest folders (hidden ones included) and settings.

When you drop below your goal, the icon turns red.

---

## Terminal

```bash
spacekeeper                     # summary: free space, goal, watcher
spacekeeper scan                # full scan: finds hidden space, you pick what to clean
spacekeeper analyze             # full report
spacekeeper clean               # shows safe junk (preview only)
spacekeeper clean --run         # deletes safe junk (asks first)
spacekeeper empty-trash         # empties the Trash (asks first)
spacekeeper move <folder> <dst> # moves a folder to an external drive and leaves a link
spacekeeper update              # installs the latest version (keeps your settings)
```

### Settings

```bash
spacekeeper config                  # show everything
spacekeeper config goal 30          # minimum free space (GB)
spacekeeper config auto-clean yes   # clean by itself when below the goal
spacekeeper config interval 3       # check every 3 hours
spacekeeper watch on|off            # turn the watcher on/off
```

### The watcher alerts you when

- free space drops **below your goal**
- the disk loses **more than 10 GB in 24 h** (something new is filling it up)
- an app gets stuck in a **crash loop** (its reports are deleted automatically)
- a **new version** of SpaceKeeper is out

Everything it deletes is logged at `~/Library/Logs/spacekeeper.log`.

### Background tasks

```bash
spacekeeper pause-task com.example.task    # stops it and keeps it off after a restart
spacekeeper resume-task com.example.task   # undo
```

---

## What it deletes (and what it never does)

**Deletes only junk that rebuilds itself:**
crash reports · logs older than 7 days · npm, pip, uv, pnpm, Yarn, Homebrew, Go and CocoaPods caches · Xcode DerivedData · Chrome, Edge, Brave, Arc, Firefox and Opera GX caches · Camera Raw cache · app caches (Electron) · already-downloaded updates

**Only if you pick it (and it goes to the Trash):** old installers in Downloads, Codex conversations older than 90 days, Hugging Face models

**Never deletes:**
your files · photos · projects · browser profiles · anything outside your home folder

Caches of open apps are skipped — it asks you to quit the app first. `move` only deletes the original after checking the copy has the same number of files and the same bytes.

---

## Skill for Claude Code / Codex

`install.sh` copies the skill to `~/.claude/skills/` and `~/.codex/skills/` (if they exist). Then just ask:

> "My Mac is out of space, help me"

Your assistant runs the scan, digs into weird folders, explains what everything is and **asks for your permission** before touching anything.

---

## Update

The app shows a **⬆️** button when a new version is out, and the watcher sends a notification. One click, or run `spacekeeper update`. Your settings stay as they are.

## Uninstall

SpaceKeeper leaves a background "watcher" running (it checks your space every few hours). So **dragging the app to the Trash is not enough**: the watcher keeps running and macOS may keep asking for permissions. Pick one way:

**1. From the app (easiest)**
Menu bar icon › **Settings** › **Uninstall SpaceKeeper…**

**2. From Terminal (works even if you already deleted the app)**
Open **Terminal**, paste this line and press Enter:

```bash
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Willclaf/spacekeeper/main/uninstall.sh)"
```

It removes the app, the watcher, the `spacekeeper` command, the settings and the permissions macOS had stored. It doesn't undo anything it already cleaned.

**3. I already deleted the app and the watcher stayed**
From version 1.2.1 it notices the app is gone and removes itself on its next check (up to 3 hours). To skip the wait, use way 2.

---

MIT License. Made out of pure frustration with "System Data: 63 GB". 😤

Also available in Portuguese: [Disco Livre](https://github.com/Willclaf/disco-livre) 🇧🇷
