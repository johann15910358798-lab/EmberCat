# PixelFX subset

- Upstream: https://github.com/patch-gg/pixelfx
- Commit: `a84159688af3ca37a4be05a0d422b94451b2e24e` (version 0.3.0)
- Retrieved: 2026-11-02
- License: MIT; `LICENSE` and upstream `NOTICE.md` are included.
- Included: `src/core/{rig,actor,color,math}.js`. No gallery fonts or combat effects are included.

The offline Makima renderer calls `skeleton()` to solve hands, feet, knees, elbows,
pelvis and spine. Artwork is supplied by EmberCat's approved Makima drawing. The support/swing path and rigid transforms reuse EmberCat's cat helpers. PixelFX's
stock dummy renderer and 12 fps `poseAt()` player are not used.

One local change in `core/rig.js`: `solve()` and `skeleton()` accept an optional
measurement object so the chibi drawing can use its own limb proportions.
Omitting it preserves all upstream defaults. The measurement constant was renamed
to `DEFAULT_MEASUREMENTS`; the solver itself is unchanged.

Node is used only to generate the assets. The macOS application has no new runtime dependency.
