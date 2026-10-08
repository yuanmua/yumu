#!/bin/sh
# Build the one thing you ship: dist/Yumu.app. Double-click it, or run dist/Yumu.app/Contents/MacOS/yumu-cli.
# (The CLI cannot be called `yumu` inside the bundle: macOS file systems ignore case and `Yumu` is the app.)
#
# Usage: ./build.sh [dev]
#   dev  allows offline accounts without a Microsoft account (testing before Mojang approval)
set -eu
cd "$(dirname "$0")"
FEATURES=""
if [ "${1:-}" = "dev" ]; then FEATURES="--features dev-offline"; fi
APP=dist/Yumu.app
MAC=apps/macos

# 1. Rust: core library for the app, plus the command line.
(cd heartwood && MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --release -p grain -p yumu $FEATURES)

# 2. Generated inputs: translations, design tokens, icon.
python3 bark/i18n/build.py
python3 bark/codegen/swift.py
if [ ! -f "$MAC/.build/AppIcon.icns" ] || [ bark/icon/make-icon.swift -nt "$MAC/.build/AppIcon.icns" ]; then
    rm -rf "$MAC/.build/AppIcon.iconset"
    swift bark/icon/make-icon.swift "$MAC/.build/AppIcon.iconset"
    iconutil -c icns "$MAC/.build/AppIcon.iconset" -o "$MAC/.build/AppIcon.icns"
fi

# 3. Swift app linked against the Rust static library.
mkdir -p "$MAC/.build/grain"
cp heartwood/target/release/libgrain.a "$MAC/.build/grain/"
(cd "$MAC" && swift build -c release)

# 4. Assemble and ad-hoc sign the bundle.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$MAC/.build/release/Yumu" "$APP/Contents/MacOS/"
cp heartwood/target/release/yumu "$APP/Contents/MacOS/yumu-cli"
cp -R "$MAC/.build/release/Yumu_Yumu.bundle" "$APP/Contents/Resources/"
cp "$MAC/.build/AppIcon.icns" "$APP/Contents/Resources/"
cp "$MAC/Info.plist" "$APP/Contents/"
codesign --force --deep --sign - "$APP" 2>/dev/null
echo "built $APP"
