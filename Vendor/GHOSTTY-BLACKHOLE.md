# Ghostty Blackhole reference

- Upstream: https://github.com/s0xDk/ghostty-blackhole
- Reference commit: `b49fa0ab2eaf0644a690f4cb386d70c21eb9f969`
- License: MIT; copyright s13k. Full notice in `GHOSTTY-BLACKHOLE-LICENSE`, included in the application bundle.
- Adaptation: `Sources/EmberCat/NotchMatrixShader.swift` traces a compact thin accretion disk using the upstream shader's Schwarzschild photon acceleration and leapfrog integration. The disk is rendered with transparent premultiplied alpha, a Matrix green/teal palette, a shared load-driven shadow radius, and hover feedback.
- EmberCat supplies the disk material from its own foreground rain: a character retains its id and glyph through handoff, orbit and dissolution. A separate polar material texture carries glyph-derived light into the optical projection. Readable screen-space glyphs use artistic arc placement and size compensation because a near-edge-on optical projection collapses small letters into streaks.
- EmberCat's rain, capture timing, readable glyph motion, body breathing and cursor feedback are artistic motion models. The rendering never samples other applications or desktop contents.
