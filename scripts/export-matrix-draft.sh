#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ne 1 && $# -ne 6 ]]; then
    printf 'Usage: bash scripts/export-matrix-draft.sh OUTPUT_DIRECTORY|--interactive [--configuration SIZE GRAVITY DENSITY OFFSET_PT]\n' >&2
    exit 1
fi
mkdir -p "$PROJECT_ROOT/.build/ModuleCache"
# Compile only the native preview harness. This never builds, signs or installs an app bundle.
swiftc -O -swift-version 6 -module-cache-path "$PROJECT_ROOT/.build/ModuleCache" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameAnimation.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameShader.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchMatrixShader.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchLightningShader.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/AppResources.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchLightningMaterial.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchLightningMotion.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchLightningControls.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/MatrixCodeFlow.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameRenderer.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameSettings.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchDisplayProfile.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlamePaletteEditor.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchMatrixControls.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlamePreviewController.swift" \
    "$PROJECT_ROOT/scripts/export-matrix-draft.swift" -o "$PROJECT_ROOT/.build/MatrixDraftExport"
exec "$PROJECT_ROOT/.build/MatrixDraftExport" "$@"
