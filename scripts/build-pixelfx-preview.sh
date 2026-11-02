#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
STUDY="${1:-walk}"
case "$STUDY" in
  walk) PREVIEW_NAME="EmberCat-PixelFX-Preview" ;;
  vehicles) PREVIEW_NAME="EmberCat-PixelFX-Vehicles-Preview" ;;
  suite) PREVIEW_NAME="EmberCat-PixelFX-Suite-Preview" ;;
  *) printf '%s\n' "Usage: $0 [walk|vehicles|suite]" >&2; exit 2 ;;
esac
./build-app.sh
PREVIEW_APP="$PROJECT_ROOT/dist/$PREVIEW_NAME.app"
rm -rf "$PREVIEW_APP"
cp -R "$PROJECT_ROOT/dist/EmberCat.app" "$PREVIEW_APP"
python3 - "$PREVIEW_APP/Contents/Info.plist" "$STUDY" <<'PY'
import plistlib,sys
from pathlib import Path
path=Path(sys.argv[1])
info=plistlib.loads(path.read_bytes())
study=sys.argv[2]
name={'walk':'EmberCat PixelFX Preview','vehicles':'EmberCat PixelFX Vehicles Preview',
      'suite':'EmberCat PixelFX Suite Preview'}[study]
info.update(CFBundleIdentifier='com.johann.embercat.pixelfx-preview'+('' if study=='walk' else '.'+study),
            CFBundleName=name,CFBundleDisplayName=name,
            EmberCatPixelFXWalkPreview=study=='walk',EmberCatPixelFXVehiclePreview=study=='vehicles',
            EmberCatPixelFXSuitePreview=study=='suite',
            LSUIElement=False)
path.write_bytes(plistlib.dumps(info))
PY
codesign --force --deep --sign - "$PREVIEW_APP"
"$PREVIEW_APP/Contents/MacOS/EmberCat" --check-assets
printf '%s\n' "$PREVIEW_APP"
