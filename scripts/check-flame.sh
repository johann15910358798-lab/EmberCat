#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_ROOT/.build/ModuleCache"
swiftc -O -swift-version 6 -module-cache-path "$PROJECT_ROOT/.build/ModuleCache" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameAnimation.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameShader.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameRenderer.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameSettings.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchDisplayProfile.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameController.swift" \
    "$PROJECT_ROOT/scripts/check-notch-displays.swift" \
    "$PROJECT_ROOT/scripts/check-flame.swift" -o "$PROJECT_ROOT/.build/FlameCheck"
exec "$PROJECT_ROOT/.build/FlameCheck" "$@"
