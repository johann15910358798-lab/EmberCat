#!/usr/bin/env python3
"""Separate the selected Sunburst concept into transparent tube and leak layers."""

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Artwork/NotchLightning/direction-reference-v3.png"
DESTINATION = ROOT / "Sources/EmberCat/Resources/NotchLightning"
CELL = (512, 256)
CENTER = (256, 96)
BODY = (448, 64)
# Measured source-art bounds, not runtime display dimensions.
STAGES = [
    {"name": "white", "center": (281, 230.5), "size": (344, 37), "light_offset": 441,
     "roots": [(195, 247)], "directions": [(-0.12, 1)]},
    {"name": "blue", "center": (778, 237.5), "size": (386, 49), "light_offset": 441,
     "roots": [(686, 258), (907, 215)], "directions": [(-0.30, 1), (0.1, -1)]},
    {"name": "violet", "center": (1273, 249.5), "size": (432, 69), "light_offset": 442,
     "roots": [(1159, 278), (1378, 218)], "directions": [(-0.28, 1), (0.65, -0.75)]},
]


def smooth(lo, hi, value):
    v = min(1, max(0, (value - lo) / (hi - lo)))
    return v * v * (3 - 2 * v)


def foreground(pixel, background, alpha):
    if alpha < 0.0001:
        return (0, 0, 0)
    return tuple(round(255 * min(1, max(0, (p / 255 - b * (1 - alpha)) / alpha)))
                 for p, b in zip(pixel, background))


def remove_baked_contacts(image, roots):
    """Keep shell detail, but let runtime strikes own every seam highlight."""
    original = image.copy().load()
    pixels = image.load()
    for rx, ry in roots:
        # The upper fracture leans sideways; its short painted leader reaches
        # farther along the rim than the compact lower contact flare.
        radius = 76 if ry < CENTER[1] else 30
        left = max(48, round(rx - radius - 8))
        right = min(CELL[0] - 48, round(rx + radius + 8))
        for y in range(max(0, round(ry - 30)), min(CELL[1], round(ry + 31))):
            wall = smooth(18, 27, abs(y - CENTER[1]))
            if wall == 0:
                continue
            a, b = original[left, y], original[right, y]
            for x in range(max(0, round(rx - radius)), min(CELL[0], round(rx + radius + 1))):
                weight = wall * (1 - smooth(radius * 0.55, radius, abs(x - rx)))
                weight *= 1 - smooth(18, 30, abs(y - ry))
                if weight == 0:
                    continue
                mix = min(1, max(0, (x - left) / (right - left)))
                alpha = (1 - mix) * a[3] + mix * b[3]
                repaired = [(a[c] * a[3] * (1 - mix) + b[c] * b[3] * mix) / max(1, alpha)
                            for c in range(3)]
                old = original[x, y]
                alpha = min(alpha, old[3])
                out_alpha = (1 - weight) * old[3] + weight * alpha
                rgb = [round(((1 - weight) * old[c] * old[3] + weight * repaired[c] * alpha)
                             / max(1, out_alpha)) for c in range(3)]
                pixels[x, y] = (*rgb, round(out_alpha))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--review-dir', type=Path, default=ROOT / 'work/notch-lightning/energy-tube')
    args = parser.parse_args()
    DESTINATION.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGB")
    body_atlas = Image.new("RGBA", (CELL[0] * 2, CELL[1] * 6))
    leak_atlas = Image.new("RGBA", body_atlas.size)
    review = Image.new("RGB", (CELL[0] * 3, CELL[1] * 2))
    records = []
    for stage_index, stage in enumerate(STAGES):
        cx, cy = stage["center"]
        width, height = stage["size"]
        sx, sy = width / BODY[0], height / BODY[1]
        transform = (sx, 0, cx - CENTER[0] * sx, 0, sy, cy - CENTER[1] * sy)
        dark = source.transform(CELL, Image.Transform.AFFINE, transform, Image.Resampling.BICUBIC)
        light = source.transform(CELL, Image.Transform.AFFINE,
            (*transform[:5], transform[5] + stage["light_offset"]), Image.Resampling.BICUBIC)
        roots = [((x - cx) / sx + CENTER[0], (y - cy) / sy + CENTER[1]) for x, y in stage["roots"]]
        body_layers = [Image.new("RGBA", CELL), Image.new("RGBA", CELL)]
        leak_layers = [[Image.new("RGBA", CELL), Image.new("RGBA", CELL)] for _ in range(2)]
        dark_pixels, light_pixels = dark.load(), light.load()
        channels = dark.split()
        peak = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
        local_light = peak.filter(ImageFilter.GaussianBlur(2.5)).load()
        bodies = [im.load() for im in body_layers]
        leaks = [[im.load() for im in pair] for pair in leak_layers]
        cap = height * 0.25 / sx
        bg_dark, bg_light = (11 / 255, 13 / 255, 18 / 255), (1, 1, 1)
        for y in range(CELL[1]):
            for x in range(CELL[0]):
                source_x, source_y = cx + (x - CENTER[0]) * sx, cy + (y - CENTER[1]) * sy
                left = 48 + stage_index * 496
                if not (left + 8 < source_x < left + 456 and 188 < source_y < 440):
                    continue
                dp, lp = dark_pixels[x, y], light_pixels[x, y]
                emission = max(max(0, (c / 255 - b) / (1 - b)) for c, b in zip(dp, bg_dark))
                opacity_light = max(1 - c / 255 for c in lp)
                dx = max(0, abs(x - CENTER[0]) - (BODY[0] / 2 - cap)) / cap
                dy = (y - CENTER[1]) / (BODY[1] / 2)
                distance = (math.hypot(dx, dy) - 1) * BODY[1] / 2
                inside = 1 - smooth(-1, 2, distance)
                alpha = max(emission, opacity_light * inside)
                clean = smooth(0.014, 0.042, alpha)
                if clean == 0:
                    continue
                body_mask = 1 - smooth(5, 11, distance)
                colors = [foreground(dp, bg_dark, alpha), foreground(lp, bg_light, alpha)]
                for theme in range(2):
                    bodies[theme][x, y] = (*colors[theme], round(255 * alpha * clean * body_mask))
                if body_mask > .999:
                    continue
                candidates = []
                for group, ((rx, ry), (vx, vy)) in enumerate(zip(roots, stage["directions"])):
                    norm = math.hypot(vx, vy)
                    along = ((x - rx) * vx + (y - ry) * vy) / norm
                    across = abs((x - rx) * vy - (y - ry) * vx) / norm
                    # The blue right-hand fracture vents on both sides of the shell.
                    if stage_index == 1 and group == 1:
                        along = abs(y - CENTER[1]) - 28
                        across = abs(x - rx)
                    cone = smooth(-5, 3, along) * (1 - smooth(10 + max(0, along) * .75,
                        19 + max(0, along) * .85, across))
                    candidates.append((cone, group))
                cone, group = max(candidates)
                # Keep the thin discharge structure, not the source mockup's
                # broad background glow, which would expose the cone mask.
                ridge = (max(dp) - local_light[x, y]) / 255
                detail = max(smooth(.006, .10, ridge), smooth(.55, .90, emission) * .60)
                leak_alpha = alpha * clean * (1 - body_mask) * cone * detail
                if leak_alpha > 0.003:
                    for theme in range(2):
                        leaks[theme][group][x, y] = (*colors[theme], round(255 * leak_alpha))
        body_roots = roots[:]
        if stage_index == 1:
            # The blue right-hand fracture is drawn on both sides of the tube.
            body_roots.append((roots[1][0], 2 * CENTER[1] - roots[1][1]))
        for body in body_layers:
            remove_baked_contacts(body, body_roots)
        for theme in range(2):
            row = theme * 3 + stage_index
            body_atlas.paste(body_layers[theme], (0, row * CELL[1]))
            # Overlap the ends instead of mirroring the current: a mirrored
            # pattern becomes an artificial repeating diamond lattice in motion.
            interior = body_layers[theme].crop((96, 0, 416, CELL[1]))
            tile = interior.crop((0, 0, 256, CELL[1]))
            for column in range(64):
                tail = interior.crop((256 + column, 0, 257 + column, CELL[1]))
                head = interior.crop((column, 0, column + 1, CELL[1]))
                tile.paste(Image.blend(tail, head, smooth(0, 63, column)), (column, 0))
            body_atlas.paste(tile.resize(CELL, Image.Resampling.LANCZOS), (CELL[0], row * CELL[1]))
            for group in range(2):
                leak_atlas.paste(leak_layers[theme][group], (group * CELL[0], row * CELL[1]))
            preview = Image.new("RGBA", CELL, (12, 14, 20, 255) if theme == 0 else (255, 255, 255, 255))
            preview.alpha_composite(body_layers[theme])
            for layer in leak_layers[theme]:
                preview.alpha_composite(layer)
            review.paste(preview.convert("RGB"), (stage_index * CELL[0], theme * CELL[1]))
        records.append({**stage, "rootsUV": [[x / CELL[0], y / CELL[1]] for x, y in roots]})
    for name, atlas in [("tube-atlas.png", body_atlas), ("leak-atlas.png", leak_atlas)]:
        atlas.save(DESTINATION / name, optimize=True)
    output = args.review_dir
    output.mkdir(parents=True, exist_ok=True)
    review.save(output / "material-extraction.png")
    metadata = {"source": str(SOURCE.relative_to(ROOT)),
        "sourceSHA256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "generator": "gpt-image-2.5-sunburst", "sourceType": "user-selected generated concept",
        "cellSize": CELL, "tubeBounds": [32, 64, 448, 64],
        "rows": ["dark-white", "dark-blue", "dark-violet", "light-white", "light-blue", "light-violet"],
        "tubeColumns": ["fixed shell and caps", "seamless internal flow"],
        "leakColumns": ["left fracture", "right fracture"], "stages": records,
        "contactCleanup": "shell seam highlights repaired from adjacent wall; runtime strikes supply moving contacts",
        "assets": {name: hashlib.sha256((DESTINATION / name).read_bytes()).hexdigest()
            for name in ["tube-atlas.png", "leak-atlas.png"]}}
    (DESTINATION / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print("Prepared transparent tube, interior flow and separate leak atlases.")


if __name__ == "__main__":
    main()
