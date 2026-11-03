#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ "${1:-}" != "--skip-build" ]]; then
  ./build-app.sh
fi
APP="$ROOT/dist/EmberCat.app"
PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
ACCOUNT="${SPARKLE_ACCOUNT:-com.johann.embercat}"
PUBLIC_KEY="$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)"
test "$PUBLIC_KEY" = "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")"
test -f "$ROOT/docs/releases/$VERSION.md"
codesign --verify --deep --strict "$APP"

STAGE="$(mktemp -d "$ROOT/dist/.release-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
OUT="$ROOT/dist/releases/$VERSION"
mkdir -p "$STAGE/updates" "$STAGE/dmg" "$OUT"
NAME="EmberCat-$VERSION"
REPO_URL="https://github.com/johann15910358798-lab/EmberCat"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/updates/$NAME.zip"
cp "$ROOT/docs/releases/$VERSION.md" "$STAGE/updates/$NAME.md"
"$TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 --maximum-versions 1 \
  --download-url-prefix "$REPO_URL/releases/download/v$VERSION/" \
  --full-release-notes-url "$REPO_URL/releases" --link "$REPO_URL" \
  --embed-release-notes "$STAGE/updates"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$STAGE/updates/appcast.xml"

ditto "$APP" "$STAGE/dmg/EmberCat.app"
ln -s /Applications "$STAGE/dmg/Applications"
hdiutil create -volname "EmberCat $VERSION" -srcfolder "$STAGE/dmg" \
  -ov -format UDZO "$STAGE/$NAME.dmg"
hdiutil verify "$STAGE/$NAME.dmg"
cp "$STAGE/updates/$NAME.zip" "$STAGE/updates/appcast.xml" "$STAGE/$NAME.dmg" "$OUT/"
(
  cd "$OUT"
  shasum -a 256 "$NAME.dmg" "$NAME.zip" appcast.xml > SHA256SUMS.txt
)
python3 "$ROOT/scripts/check-release.py" "$OUT"
SIGNATURE="$(python3 - "$OUT/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
print(ET.parse(sys.argv[1]).find('./channel/item/enclosure').attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'])
PY
)"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$OUT/$NAME.zip" "$SIGNATURE"
printf 'Prepared EmberCat %s (build %s): %s\n' "$VERSION" "$BUILD" "$OUT"
printf 'No release was published. See docs/updates.md for the GitHub Releases step.\n'
