#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_ROOT/.build/ModuleCache"
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
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameController.swift" \
    "$PROJECT_ROOT/scripts/check-matrix.swift" -o "$PROJECT_ROOT/.build/MatrixCheck"
exec "$PROJECT_ROOT/.build/MatrixCheck" "$@"
