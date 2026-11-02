#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
./build-app.sh
PREVIEW_APP="$PROJECT_ROOT/dist/EmberCat-PixelFX-Preview.app"
rm -rf "$PREVIEW_APP"
cp -R "$PROJECT_ROOT/dist/EmberCat.app" "$PREVIEW_APP"
python3 - "$PREVIEW_APP/Contents/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
path=Path(sys.argv[1])
info=plistlib.loads(path.read_bytes())
info.update(CFBundleIdentifier='com.johann.embercat.pixelfx-preview',
            CFBundleName='EmberCat PixelFX Preview',CFBundleDisplayName='EmberCat PixelFX Preview',
            EmberCatPixelFXWalkPreview=True,LSUIElement=False)
path.write_bytes(plistlib.dumps(info))
PY
codesign --force --deep --sign - "$PREVIEW_APP"
"$PREVIEW_APP/Contents/MacOS/EmberCat" --check-assets
printf '%s\n' "$PREVIEW_APP"
