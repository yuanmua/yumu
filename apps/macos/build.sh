#!/bin/sh
# Build Yumu.app: Rust core as a static library, Swift app on top, assembled into a bundle.
set -eu
cd "$(dirname "$0")"
ROOT=../..
CONFIG=${1:-release}

(cd "$ROOT/heartwood" && MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --release -p grain)
mkdir -p .build/grain
cp "$ROOT/heartwood/target/release/libgrain.a" .build/grain/

python3 "$ROOT/bark/i18n/build.py"
python3 "$ROOT/bark/codegen/swift.py"

swift build -c "$CONFIG"

APP=.build/Yumu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Yumu" "$APP/Contents/MacOS/"
cp -R ".build/$CONFIG/Yumu_Yumu.bundle" "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/"
echo "built $APP"
