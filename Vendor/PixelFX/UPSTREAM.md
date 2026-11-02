# PixelFX subset

- Upstream: https://github.com/patch-gg/pixelfx
- Commit: `a84159688af3ca37a4be05a0d422b94451b2e24e` (version 0.3.0)
- Retrieved: 2026-11-02
- License: MIT; `LICENSE` and upstream `NOTICE.md` are included.
- Included: `src/core/{rig,actor,color,math}.js`. No gallery fonts or combat effects are included.

The initial offline trial used `skeleton()` with source-art cutouts and the cat's
foot path. The released walk-through-skateboard loops instead use a locally
authored side-view gait in `scripts/pixelfx/human-gait.mjs`, continuous clothing
contours and the existing source face, braid and shirt. Fixed-length 2D joints
avoid the projection-dependent stretching of those cutouts. The cat contributes
only image transforms and the same antialiased export pipeline. PixelFX's stock
dummy renderer and 12 fps `poseAt()` player are not used.

One local change in `core/rig.js`: `solve()` and `skeleton()` accept an optional
measurement object so the chibi drawing can use its own limb proportions.
Omitting it preserves all upstream defaults. The measurement constant was renamed
to `DEFAULT_MEASUREMENTS`; the solver itself is unchanged.

Node is used only to generate the assets. The macOS application has no new runtime dependency.

The vehicle renderer also uses the unchanged `core/math.js` helpers (`rng`,
`wrap`, `smooth`, `ease`) for reproducible rear-wheel dust particles. The emitters,
wheel animation, suspension and high-resolution raster compositor are local
EmberCat code. No upstream pixelated painter or stock dust effect is bundled.

The full-suite renderer uses independent walk, run, skating and board-push poses,
with explicit ground and deck contacts. Cycling uses a local
two-link pedal constraint; hovering, braid follow-through and exhaust are local
source-art transforms. PixelFX math provides deterministic effect timing.
All moving modes are sampled at 60 Hz. Authored boarding keyframes are registered
to the rendered loops and composited at full preview resolution by AppKit.
