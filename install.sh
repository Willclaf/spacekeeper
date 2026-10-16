#!/bin/zsh
# Installs SpaceKeeper: command-line tool + menu bar app + AI skill + watcher.
#
#   ./install.sh                          asks for your goal and options, then opens the full scan
#   ./install.sh --yes                    installs with defaults, no questions (good for AI assistants)
#   ./install.sh --goal 30 --watch yes --auto-clean no
#   Other options: --no-app  --build (build the app instead of downloading it)  --no-open
set -e
cd "${0:A:h}"

B=$'\e[1m' D=$'\e[2m' G=$'\e[32m' Y=$'\e[33m' N=$'\e[0m'
[[ -t 1 ]] || B= D= G= Y= N=
BIN="$HOME/.local/bin"
REPO="Willclaf/spacekeeper"
VERSION=$(sed -n 's/^VERSION="\(.*\)"/\1/p' bin/spacekeeper)

GOAL= WATCH= AUTO= NO_APP= BUILD= NO_OPEN= ASK=1
[[ -t 0 ]] || ASK=0
while (( $# )); do
  case $1 in
    --yes|-y)       ASK=0 ;;
    --goal)         GOAL=$2; shift ;;
    --watch)        WATCH=$2; shift ;;
    --auto-clean)   AUTO=$2; shift ;;
    --no-app)       NO_APP=1 ;;
    --build)        BUILD=1 ;;
    --no-open)      NO_OPEN=1 ;;
    -h|--help)      sed -n '2,7p' "$0"; exit 0 ;;
    *) print -r -- "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done
# installed by an AI assistant (no questions): the assistant runs the full scan and opens the app afterwards
(( ASK )) || NO_OPEN=${NO_OPEN:-1}

print -r -- ""
print -r -- "${B}💽 Installing SpaceKeeper $VERSION${N}"
[[ $(uname) == Darwin ]] || { print -r -- "SpaceKeeper only runs on macOS."; exit 1; }
MAC=$(sw_vers -productVersion)
(( ${MAC%%.*} >= 13 )) || { print -r -- "Requires macOS 13 (Ventura) or later. This Mac is on $MAC."; exit 1; }

# 1. Command-line tool
mkdir -p "$BIN"
cp bin/spacekeeper "$BIN/spacekeeper"
chmod +x "$BIN/spacekeeper"
print -r -- "${G}✓${N} Tool at ~/.local/bin/spacekeeper"

if [[ ":$PATH:" != *":$BIN:"* ]] && ! grep -q '.local/bin' "$HOME/.zshrc" 2>/dev/null; then
  print -r -- '' >> "$HOME/.zshrc"
  print -r -- '# spacekeeper' >> "$HOME/.zshrc"
  print -r -- 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
  print -r -- "${G}✓${N} spacekeeper command available in Terminal (in new windows)"
fi

# 2. Skill for Claude Code / Codex
for dir in "$HOME/.claude" "$HOME/.codex"; do
  if [[ -d $dir ]]; then
    mkdir -p "$dir/skills"
    rm -rf "$dir/skills/spacekeeper"
    cp -R skill/spacekeeper "$dir/skills/spacekeeper"
    print -r -- "${G}✓${N} Skill at ${dir/#$HOME/~}/skills/spacekeeper"
  fi
done

# 3. Settings (on an update, keep what the user already chose)
CURRENT_CONF="$HOME/.config/spacekeeper/config"
UPDATING=
if [[ -f $CURRENT_CONF ]]; then
  UPDATING=1
  [[ -z $GOAL ]] && GOAL=$(sed -n 's/^GOAL_GB=//p' "$CURRENT_CONF")
  [[ -z $AUTO ]] && AUTO=$(sed -n 's/^AUTO_CLEAN=//p' "$CURRENT_CONF")
  if [[ -z $WATCH ]]; then
    [[ -f $HOME/Library/LaunchAgents/com.spacekeeper.watch.plist ]] && WATCH=yes || WATCH=no
  fi
fi
if (( ASK )); then
  print -r -- ""
  [[ -z $GOAL ]]  && { read -r "GOAL?How many GB of free space do you want to keep at minimum? [30] " || true; }
  [[ -z $WATCH ]] && { read -r "WATCH?Turn on the automatic watcher (alerts you when you drop below the goal)? [Y/n] " || true; }
  if [[ $WATCH != [nN]* && -z $AUTO ]]; then
    read -r "AUTO?When you drop below the goal, clean safe junk automatically? [y/N] " || true
  fi
fi
[[ $GOAL == <1-> ]] || GOAL=30
[[ $WATCH == [nN]* ]] && WATCH=no || WATCH=yes
[[ $AUTO == [yY]* ]] && AUTO=yes || AUTO=no

"$BIN/spacekeeper" config goal "$GOAL" >/dev/null
"$BIN/spacekeeper" config auto-clean "$AUTO" >/dev/null
print -r -- "${G}✓${N} Goal: $GOAL GB free · auto-clean: $AUTO"
if [[ $WATCH == yes ]]; then
  "$BIN/spacekeeper" watch on
elif [[ -f $HOME/Library/LaunchAgents/com.spacekeeper.watch.plist ]]; then
  "$BIN/spacekeeper" watch off >/dev/null
fi

# 4. Menu bar app
#    a) download the prebuilt app (universal, verified by SHA-256) — works on any Mac, no Apple tools needed
#    b) if that fails, build it here (needs Apple's Command Line Tools)
APP_OK= DEST=
install_app() {   # $1 = .app folder
  DEST=/Applications
  [[ -w $DEST ]] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
  pkill -x SpaceKeeper 2>/dev/null || true
  rm -rf "$DEST/SpaceKeeper.app"
  ditto "$1" "$DEST/SpaceKeeper.app"
  xattr -dr com.apple.quarantine "$DEST/SpaceKeeper.app" 2>/dev/null || true
  APP_OK=1
}

download_app() {
  local tmp expected got
  [[ -f app/SpaceKeeper.zip.sha256 ]] || return 1
  expected=$(cut -d' ' -f1 < app/SpaceKeeper.zip.sha256)
  tmp=$(mktemp -d)
  curl -fsL --retry 2 -o "$tmp/SpaceKeeper.zip" \
    "https://github.com/$REPO/releases/download/v$VERSION/SpaceKeeper.zip" || { rm -rf "$tmp"; return 1; }
  got=$(shasum -a 256 "$tmp/SpaceKeeper.zip" | cut -d' ' -f1)
  if [[ $got != $expected ]]; then
    print -r -- "${Y}!${N} The downloaded app doesn't match the expected checksum — not installing it."
    rm -rf "$tmp"; return 1
  fi
  ditto -x -k "$tmp/SpaceKeeper.zip" "$tmp/app" || { rm -rf "$tmp"; return 1; }
  install_app "$tmp/app/SpaceKeeper.app"
  rm -rf "$tmp"
}

build_app() {
  command -v swiftc >/dev/null 2>&1 || return 1
  print -r -- "  Building the app (about 30 seconds)…"
  app/build.sh >/dev/null 2>&1 || return 1
  install_app "app/build/SpaceKeeper.app"
}

if [[ -z $NO_APP ]]; then
  if [[ -n $BUILD ]]; then
    build_app || download_app || true
  else
    print -r -- "  Downloading the app…"
    download_app || build_app || true
  fi
  if [[ -n $APP_OK ]]; then
    print -r -- "${G}✓${N} App at ${DEST/#$HOME/~}/SpaceKeeper.app"
  else
    print -r -- "${Y}!${N} Couldn't install the menu bar app. The command-line tool works normally."
    print -r -- "  ${D}To try building it: xcode-select --install, then ./install.sh --build${N}"
  fi
fi

print -r -- ""
print -r -- "${G}${B}All set!${N} 🎉"

# 5. First impression: the full scan
if [[ -z $NO_OPEN ]]; then
  if [[ -n $APP_OK ]]; then
    if [[ -n $UPDATING ]]; then
      open "$DEST/SpaceKeeper.app"
      print -r -- "Updated! SpaceKeeper is back in your menu bar."
    else
      open "$DEST/SpaceKeeper.app" --args --welcome
      print -r -- ""
      print -r -- "👉 ${B}Look up at your menu bar:${N} SpaceKeeper just opened a full scan of your Mac."
      print -r -- "   It shows how much hidden space it found, and you pick what to clean."
    fi
  elif (( ASK )); then
    "$BIN/spacekeeper" scan
  fi
else
  print -r -- "  ${D}Next step: spacekeeper scan (full scan of your Mac)${N}"
fi
