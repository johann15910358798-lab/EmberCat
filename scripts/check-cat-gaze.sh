#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_ROOT/.build/ModuleCache"
swiftc -module-cache-path "$PROJECT_ROOT/.build/ModuleCache" \
    "$PROJECT_ROOT/Sources/EmberCat/CatGaze.swift" \
    "$PROJECT_ROOT/scripts/check-cat-gaze.swift" -o "$PROJECT_ROOT/.build/CatGazeCheck"
exec "$PROJECT_ROOT/.build/CatGazeCheck"
