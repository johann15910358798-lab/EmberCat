#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_ROOT/.build/ModuleCache"
swiftc -module-cache-path "$PROJECT_ROOT/.build/ModuleCache" \
    "$PROJECT_ROOT/Sources/EmberCat/AnimationClock.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/SpeedTier.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/CatMotion.swift" \
    "$PROJECT_ROOT/Sources/EmberCat/MotionDirector.swift" \
    "$PROJECT_ROOT/scripts/check-motion.swift" -o "$PROJECT_ROOT/.build/MotionCheck"
exec "$PROJECT_ROOT/.build/MotionCheck" "$@"
