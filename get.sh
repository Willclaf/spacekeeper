#!/bin/zsh
# One-line install, no git and no Apple developer tools needed:
#   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/Willclaf/spacekeeper/main/get.sh)"
# install.sh options can follow:  ... get.sh)" -- --yes --goal 30
set -e
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
print -r -- "Downloading SpaceKeeper…"
curl -fsSL "https://github.com/Willclaf/spacekeeper/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp"
"$tmp/spacekeeper-main/install.sh" "$@"
