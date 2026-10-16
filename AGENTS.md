# AGENTS.md — instructions for AI assistants

You are an AI assistant (Claude Code, Codex, Cursor, etc.) and the user asked you to install or use **SpaceKeeper**. Follow this guide. The user is probably **not technical**: use plain language and explain every permission prompt before it appears.

## What it is

- `bin/spacekeeper`: command-line tool (pure zsh, no dependencies) that analyzes the disk, cleans safe junk and watches free space.
- `app/`: the "SpaceKeeper" menu bar app (SwiftUI). The installer downloads the prebuilt app from the release (verified by SHA-256); if that fails, it builds it with `swiftc`.
- `skill/spacekeeper/SKILL.md`: skill for Claude Code / Codex to use the tool.
- `get.sh` (one-line install, no git), `install.sh` / `uninstall.sh`: install and removal.

macOS **13 or later** only (Intel or Apple Silicon).

## Install (step by step)

The goal is for the user to finish **impressed**: they installed it and immediately saw how many hidden GB their Mac had. Don't skip the full scan (step 4).

1. **Confirm it's a Mac on macOS 13+:** `sw_vers -productVersion`. If it isn't a Mac, explain SpaceKeeper is macOS-only and stop.

2. **Ask the user** (one question, with suggested defaults):
   - How many GB of free space they want to keep at minimum (default **30**)
   - Whether they want the background watcher (default **yes**)
   - Whether it should clean safe junk automatically when they drop below the goal (default **no**)

3. **Install without interactive questions.** No git or Apple developer tools needed: the app comes prebuilt and verified by SHA-256.
   ```bash
   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Willclaf/spacekeeper/main/get.sh)" -- --yes --goal 30 --watch yes --auto-clean no
   ```
   (swap in the user's choices. If the repo is already cloned, this is equivalent: `./install.sh --yes --goal 30 ...`)

   The installer:
   - copies the tool to `~/.local/bin/spacekeeper` and adds it to `PATH` in `~/.zshrc`
   - copies the skill to `~/.claude/skills/` and `~/.codex/skills/` (if those folders exist)
   - saves the settings and turns on the watcher (LaunchAgent `com.spacekeeper.watch`, every 3 h)
   - installs `/Applications/SpaceKeeper.app` (downloads it; if that fails, builds it; if nothing works, continues with the CLI only)
   - with `--yes`, **does not open the app**: you run the full scan

4. **Full scan (the first impression — required):**
   ```bash
   ~/.local/bin/spacekeeper data scan
   ```
   Returns JSON: `{"free": KB, "items": [{"id","tier","kb","in_use_by","desc","note","to_trash"}]}` (`kb` in KB; 1 GB ≈ 976,562 KB).
   - Show the user a **table** with the total found up front ("I found **26.4 GB** you can free up"), split into:
     - **Safe** (`tier: "safe"`) — rebuilds itself; suggest cleaning all of it.
     - **Review** (`tier: "review"`) — belongs to the user; explain each `note`; only include it if they ask.
   - Items with `in_use_by` set are in use: ask the user to **quit that app** (e.g. "quit Google Chrome") and run `data scan` again afterwards.
   - Ask **which ones to clean** and wait for the answer. Never clean without their "yes".
   - Clean only the chosen ones:
     ```bash
     ~/.local/bin/spacekeeper clean-items <id> <id> ... --json
     ```
     Returns `{"freed_kb","trashed_kb","items","free_before","free_after","skipped":[{"desc","in_use_by"}]}`.
   - Celebrate with the real number: "🎉 You freed up **X GB** that was hiding. Before: A free → now: B free."
   - If `trashed_kb > 0`: explain those files went to the **Trash** (recoverable) and still take up space. Ask whether to empty it. Only with a "yes": `~/.local/bin/spacekeeper empty-trash --yes` (macOS may ask for permission to control Finder: it's to empty the Trash).
   - If the user doesn't want to clean anything now: `~/.local/bin/spacekeeper scan --skip` (the app won't ask again).

5. **Open the app:** `open -a SpaceKeeper`. Tell them the disk icon with their free GB is in the **menu bar** (top right) and hovering shows the summary.

6. **Verify:**
   ```bash
   ~/.local/bin/spacekeeper                      # free space, goal and "Watcher: on"
   launchctl print gui/$(id -u)/com.spacekeeper.watch | grep "last exit"   # should be 0
   ```

## Permission prompts that may appear

| When | What the user sees | What to say |
|---|---|---|
| First notification | "Script Editor would like to send notifications" | "That's the low-space alert, go ahead and allow it" |
| Emptying the Trash | "… wants to control Finder" | "It's only to empty the Trash, you can allow it" |
| Full scan | Maybe "… would like to access files in your Downloads folder" | "It's to find old .dmg installers you forgot about" |

If a prompt is left unanswered, SpaceKeeper skips that item after ~20 s instead of hanging.

## Using it after install

Read `skill/spacekeeper/SKILL.md`: it has the full analyze-and-clean flow, safety rules and real-world cases.

Rules that always apply:
- **Never delete personal files** without an explicit "yes" for that item. Prefer `spacekeeper move <folder> <external drive>` or moving to the Trash.
- `spacekeeper clean --run --yes` only deletes junk that rebuilds itself (caches, old logs, crash reports).
- To stop background tasks, use `spacekeeper pause-task <label>` (reversible). Don't delete the `.plist`.

## Update

`spacekeeper update` (keeps the user's settings). The app also shows a ⬆️ button.

## Uninstall

```bash
./uninstall.sh
```

Removes the tool, app, skill, settings and watcher. Doesn't undo anything already cleaned.

## Development

- Tool: `zsh -n bin/spacekeeper` checks syntax. `SPACEKEEPER_DIR=/tmp/x bin/spacekeeper ...` uses a separate settings folder for tests.
- **Testing without deleting anything:** `SPACEKEEPER_DRY_RUN=1` makes the tool do everything except delete (logged to `$SPACEKEEPER_DIR/dry-run.log`). Always use it when testing cleanup on a real machine.
- The app reads data with `spacekeeper data summary`, `data folders` and `data scan` (JSON).
- App: `app/build.sh` produces `app/build/SpaceKeeper.app` (universal, ad-hoc signed). `open app/build/SpaceKeeper.app --args --show` opens with the summary showing; `--welcome` opens the full scan.
- **New version:** bump `VERSION` in `bin/spacekeeper`, run `app/build.sh`, zip it (`ditto -c -k --keepParent app/build/SpaceKeeper.app app/build/SpaceKeeper.zip`), write the SHA-256 to `app/SpaceKeeper.zip.sha256` and publish the zip in release `v<VERSION>`.
- This project has a Portuguese twin, [Disco Livre](https://github.com/Willclaf/disco-livre). Keep features in sync.
