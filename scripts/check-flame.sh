#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_ROOT/.build/ModuleCache"
swiftc -O -module-cache-path "$PROJECT_ROOT/.build/ModuleCache" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameRenderer.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/NotchFlameSettings.swift" \
    "$PROJECT_ROOT/scripts/check-flame.swift" -o "$PROJECT_ROOT/.build/FlameCheck"
exec "$PROJECT_ROOT/.build/FlameCheck" "$PROJECT_ROOT/Sources/EmberCat/Resources/NotchFlame" "$@"
