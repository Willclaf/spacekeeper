#!/bin/zsh
# Builds "SpaceKeeper.app" (needs only Apple's Command Line Tools: xcode-select --install)
set -e
cd "${0:A:h}"
VERSION=$(sed -n 's/^VERSION="\(.*\)"/\1/p' ../bin/spacekeeper)

APP="build/SpaceKeeper.app"
TMP="build/tmp"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TMP/AppIcon.iconset"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $arch-apple-macos13.0 \
    SpaceKeeper.swift -o "$TMP/SpaceKeeper-$arch"
done
lipo -create "$TMP"/SpaceKeeper-* -output "$APP/Contents/MacOS/SpaceKeeper"

swiftc -O -swift-version 5 icon.swift -o "$TMP/icon"
"$TMP/icon" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# the tool and the skill ship inside the app (self-install for .dmg downloads)
cp ../bin/spacekeeper "$APP/Contents/Resources/spacekeeper"
cp -R ../skill/spacekeeper "$APP/Contents/Resources/skill-spacekeeper"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>SpaceKeeper</string>
  <key>CFBundleIdentifier</key><string>com.spacekeeper.app</string>
  <key>CFBundleName</key><string>SpaceKeeper</string>
  <key>CFBundleDisplayName</key><string>SpaceKeeper</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --sign - "$APP"
rm -rf "$TMP"
print -r -- "✓ $APP"
