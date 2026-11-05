#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/ModuleCache}"

swift build --disable-sandbox -c release -debug-info-format none
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
APP="$ROOT/dist/EmberCat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SPARKLE="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
test -d "$SPARKLE"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$BIN_DIR/EmberCat" "$APP/Contents/MacOS/EmberCat"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
cp -R "$ROOT/Sources/EmberCat/Resources/MenuBarPets" "$APP/Contents/Resources/"
cp -R "$ROOT/Sources/EmberCat/Resources/PetPreview" "$APP/Contents/Resources/"
cp -R "$ROOT/Sources/EmberCat/Resources/SourceIcons" "$APP/Contents/Resources/"
cp -R "$ROOT/Sources/EmberCat/Resources/DockIdleCat" "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$ROOT/Vendor/AGENT-SPEED-LICENSE" "$APP/Contents/Resources/Licenses/"
cp "$ROOT/Vendor/GHOSTTY-BLACKHOLE-LICENSE" "$APP/Contents/Resources/Licenses/"
cp "$ROOT/Vendor/CZstd/LICENSE" "$APP/Contents/Resources/Licenses/ZSTD-LICENSE"
cp "$ROOT/Vendor/PixelFX/LICENSE" "$APP/Contents/Resources/Licenses/PIXELFX-LICENSE"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Licenses/SPARKLE-LICENSE"
# Retain Sparkle's vendor-signed framework and helpers; sign only our enclosing app.
codesign --verify --deep --strict "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/EmberCat" --check-assets
printf '%s
' "$APP"
