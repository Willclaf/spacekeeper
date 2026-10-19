#!/bin/zsh
# Removes SpaceKeeper completely, even if you only dragged the app to the Trash.
# Works from anywhere:
#   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Willclaf/spacekeeper/main/uninstall.sh)"
launchctl bootout "gui/$(id -u)/com.spacekeeper.watch" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/com.spacekeeper.watch.plist"
pkill -x SpaceKeeper 2>/dev/null
rm -rf "/Applications/SpaceKeeper.app" "$HOME/Applications/SpaceKeeper.app"
rm -f "$HOME/.local/bin/spacekeeper"
rm -rf "$HOME/.claude/skills/spacekeeper" "$HOME/.codex/skills/spacekeeper" "$HOME/.config/spacekeeper"
tccutil reset All com.spacekeeper.app >/dev/null 2>&1
print -r -- "✓ SpaceKeeper removed completely. (History stays at ~/Library/Logs/spacekeeper.log)"
