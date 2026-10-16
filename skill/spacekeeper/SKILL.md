---
name: spacekeeper
description: Safely analyzes and frees up disk space on a Mac using the spacekeeper tool. Use when the user mentions a full disk, "out of space", "storage almost full", Mac storage, a folder that's huge for no reason, a giant "System Data", a folder that looks empty but weighs GBs, an app that reopens by itself, or asks to set a free-space goal or the automatic watcher.
---

# spacekeeper — free up Mac disk space without breaking anything

You're helping someone who is probably **not technical** and stressed about their Mac running out of space. Use plain language and explain the *why* behind everything. Never delete anything that belongs to the user without an explicit "yes" for that item.

## 1. Make sure the tool exists

```bash
command -v spacekeeper || ls ~/.local/bin/spacekeeper
```

If it doesn't, have them install it (see the project README / AGENTS.md). Don't rewrite the tool on the fly.

## 2. Start with the full scan

It's the fastest safe way to free up space:

```bash
spacekeeper data scan        # JSON: items with id, tier (safe/review), kb, in_use_by, desc, note, to_trash
```

Show the total found and a table (Safe / Review). Ask them to quit the apps for items with `in_use_by`. Ask what to clean, and only then:

```bash
spacekeeper clean-items <id> <id> --json
```

Celebrate with the real `freed_kb`. If `trashed_kb > 0`, explain it went to the Trash and ask whether to empty it (`spacekeeper empty-trash --yes`).

## 2b. Full report (to go further)

```bash
spacekeeper analyze
```

Takes ~20–60 s. The output has 6 blocks:

1. **Safe junk** — caches, old logs, crash reports, downloaded updates. Everything rebuilds itself.
2. **Crash-looping apps** — an app in a crash loop can write tens of GB in days.
3. **Biggest folders** — with a tip for each and a **hidden folder** marker (Finder doesn't show folders starting with a dot, which is why people "look and find nothing").
4. **Background tasks** — LaunchAgents that fail or **reopen an app by themselves** (KeepAlive).
5. **Remote-controlled browsers** — Chrome/Edge running with `--remote-debugging-port` (AI automation). A security risk, and it often "hijacks" the user's browser.
6. **Other** — Trash, Time Machine local snapshots.

## 3. Investigate anything big and odd

The tool points; you explain. For a big folder with no tip:

```bash
du -sh "<folder>"/* "<folder>"/.[!.]* 2>/dev/null | sort -h | tail -15
ls -la "<folder>" | head
```

Find out **which app** created it (folder name, file extensions, `mdfind`, processes with `pgrep -fl`). Don't guess — if you're not sure, say so.

## 4. Propose a plan and ask permission

Present a short table: what, size, what it is, what to do. Then offer numbered actions and wait for the go-ahead:

| Situation | Action |
|---|---|
| Safe junk | `spacekeeper clean --run --yes` |
| User's folder they want to keep (videos, photos, projects, DaVinci stills) | `spacekeeper move <folder> "/Volumes/<Drive>/<destination>"` — copies, verifies file by file, deletes the original and leaves a link |
| User's stuff they no longer want | they drag it to the Trash, or you move it to the Trash — never `rm -rf` personal files |
| Background task they don't use | `spacekeeper pause-task <label>` (reversible with `resume-task`) — don't delete the .plist |
| Cache that needs the app closed (Chrome, Lightroom) | ask them to quit the app, then clean |
| Lightroom / Camera Raw | Lightroom → Settings → Performance → move the cache to an external drive and cap its size |
| AI models (LM Studio, Ollama) | delete unused ones or point the models folder to an external drive in the app |

Before moving or deleting something an app uses, check whether the app is running (`pgrep -fl <app>`). If it reopens by itself after quitting, find the responsible task in `spacekeeper analyze` (block 4).

## 5. Leave it watching

Ask for their goal (default 30 GB) and whether they want auto-clean:

```bash
spacekeeper config goal 30
spacekeeper config auto-clean no   # or yes
spacekeeper watch on
```

The watcher runs every 3 h and sends a Mac notification when: free space drops below the goal, the disk loses more than 10 GB in 24 h, or an app gets stuck in a crash loop (its reports are deleted automatically).

## Real cases (learn from them)

- **"Movies" shows 4 GB but the folder is empty** → `~/Movies/.gallery` (hidden): DaVinci Resolve gallery stills in DPX. Fix: `spacekeeper move` it to an external drive with Resolve closed.
- **Codex / an Electron app filling the disk** → `~/Library/Application Support/<App>/Crashpad/pending` with hundreds of thousands of `.dmp` files (16 GB in 3 days). Pure junk; the watcher cleans it and alerts.
- **"My Chrome lost all its profiles"** → an automation installed a LaunchAgent with `KeepAlive` that launched Chrome with its own `--user-data-dir` and `--remote-debugging-port`. The Dock's Chrome landed on that empty profile and reopened when quit. The real profiles were intact. Fix: `spacekeeper pause-task <label>`, quit Chrome, open it again.
- **`Documents/Codex/YYYY-MM-DD` folders** → work folders Codex creates for tasks without a project. May contain browser profiles and automation output.

## Never

- Delete anything in `/System`, `/Library` (root), `/private/var`, or touch SIP.
- Empty the Trash on the user's behalf without asking.
- Delete whole app folders (`Application Support/<App>`) — only caches/crashes/logs.
- Turn off a background task without explaining what it does.
