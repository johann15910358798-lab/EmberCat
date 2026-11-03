#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$PROJECT_ROOT/.build/dock-orbit-check"
mkdir -p "$CHECK_DIR" "$PROJECT_ROOT/.build/ModuleCache"
swiftc -O -swift-version 6 -module-cache-path "$PROJECT_ROOT/.build/ModuleCache" \
  "$PROJECT_ROOT/Sources/EmberCat/AnimationClock.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/SpeedTier.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/PetStyle.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/CatMotion.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/MotionDirector.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/AppResources.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/SpriteLibrary.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/DockOrbitPath.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/DockPawTrail.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/DockOrbitMotion.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/DockOrbitSettings.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/CatGaze.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/DockIdleCatView.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/DockLocator.swift" \
  "$PROJECT_ROOT/Sources/EmberCat/DockOrbitController.swift" \
  "$PROJECT_ROOT/scripts/check-dock-orbit.swift" -o "$CHECK_DIR/DockOrbitCheck"
ditto "$PROJECT_ROOT/Sources/EmberCat/Resources/MenuBarPets" "$CHECK_DIR/MenuBarPets"
ditto "$PROJECT_ROOT/Sources/EmberCat/Resources/DockIdleCat" "$CHECK_DIR/DockIdleCat"
exec "$CHECK_DIR/DockOrbitCheck" "$@"
