#!/bin/zsh
# Removes SpaceKeeper (tool, app, skill, settings and watcher). Doesn't undo anything it already cleaned.
"$HOME/.local/bin/spacekeeper" watch off 2>/dev/null
pkill -x SpaceKeeper 2>/dev/null
rm -rf "/Applications/SpaceKeeper.app" "$HOME/Applications/SpaceKeeper.app"
rm -f "$HOME/.local/bin/spacekeeper"
rm -rf "$HOME/.claude/skills/spacekeeper" "$HOME/.codex/skills/spacekeeper" "$HOME/.config/spacekeeper"
print -r -- "✓ SpaceKeeper removed. (History stays at ~/Library/Logs/spacekeeper.log)"
