#!/usr/bin/env python3
"""Derive transparent Dock idle artwork and gaze layers from the supplied PNG.

Offline and deterministic; requires Pillow.
The original artwork is never modified.
"""

from pathlib import Path
from collections import deque
import hashlib
import json
from statistics import median

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Artwork/DockIdleCat/black-cat-original.png"
PORTRAIT = ROOT / "Sources/EmberCat/Resources/DockIdleCat/CatIdle.png"
SIZE = 1024


def placement(source):
    # Ignore nearly transparent export specks when centering the illustration.
    bounds = source.getchannel("A").point(lambda alpha: 255 if alpha >= 8 else 0).getbbox()
    if bounds is None:
        raise ValueError("The cat artwork is fully transparent")
    left, top, right, bottom = bounds
    bounds = (max(0, left - 4), max(0, top - 4),
              min(source.width, right + 4), min(source.height, bottom + 4))
    cat = source.crop(bounds)
    cat.thumbnail((776, 776), Image.Resampling.LANCZOS)
    position = ((SIZE - cat.width) // 2, (SIZE - cat.height) // 2 - 4)
    return bounds, cat.size, position


def place_layer(layer, geometry):
    bounds, size, position = geometry
    result = Image.new("RGBA", (SIZE, SIZE))
    result.alpha_composite(layer.crop(bounds).resize(size, Image.Resampling.LANCZOS), position)
    return result


def convex_hull(points):
    points = sorted(set(points))

    def cross(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    halves = []
    for sequence in (points, reversed(points)):
        half = []
        for point in sequence:
            while len(half) > 1 and cross(half[-2], half[-1], point) <= 0:
                half.pop()
            half.append(point)
        halves.extend(half[:-1])
    return halves


def eye_layers(source):
    """Lift the original pupils, including highlights; repair only their old footprint."""
    base = source.copy()
    pupils = []
    both_eyes = Image.new("L", source.size)
    pixels = source.load()
    for box, seed in [((506, 377, 671, 532), (606, 448)),
                      ((774, 338, 932, 491), (841, 409))]:
        left, top, right, bottom = box
        amber = {}
        for y in range(top, bottom):
            for x in range(left, right):
                r, g, b, a = pixels[x, y]
                if a > 128 and r > 160 and g > 70 and b < 140 and r > g * 1.1 and g > b * 1.25:
                    amber[x, y] = (r, g, b)
        if len(amber) < 100:
            raise ValueError("Could not locate the amber eye in the supplied artwork")
        aperture = Image.new("L", source.size)
        ImageDraw.Draw(aperture).polygon(convex_hull(amber), fill=255)
        inside = aperture.load()
        pupil = Image.new("L", source.size)
        component = pupil.load()
        queue = deque([seed])
        seen = {seed}
        while queue:
            x, y = queue.popleft()
            if not inside[x, y] or (x, y) in amber:
                continue
            component[x, y] = 255
            for p in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if left <= p[0] < right and top <= p[1] < bottom and p not in seen:
                    queue.append(p)
                    seen.add(p)
        if pupil.getbbox() is None:
            raise ValueError("Could not isolate the original pupil")

        rows = {}
        for (x, y), rgb in amber.items():
            rows.setdefault(y, []).append(rgb)
        palette = {y: tuple(round(median(values)) for values in zip(*samples))
                   for y, samples in rows.items()}
        fill = source.copy()
        draw = ImageDraw.Draw(fill)
        for y in range(top, bottom):
            nearest = min(palette, key=lambda row: abs(row - y))
            draw.line((left, y, right - 1, y), fill=(*palette[nearest], 255))
        fill = fill.filter(ImageFilter.GaussianBlur(2))
        fill.putalpha(source.getchannel("A"))
        repair = ImageChops.multiply(pupil.filter(ImageFilter.MaxFilter(5))
                                    .filter(ImageFilter.GaussianBlur(0.5)), aperture)
        base = Image.composite(fill, base, repair)
        lifted = source.copy()
        lifted.putalpha(ImageChops.multiply(source.getchannel("A"),
                                           pupil.filter(ImageFilter.GaussianBlur(0.4))))
        pupils.append(lifted)
        both_eyes = ImageChops.lighter(both_eyes, aperture.filter(ImageFilter.GaussianBlur(0.35)))
    mask = Image.new("RGBA", source.size, (255, 255, 255, 0))
    mask.putalpha(both_eyes)
    return base, pupils, mask


def main():
    PORTRAIT.parent.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGBA")
    geometry = placement(source)
    original = place_layer(source, geometry)
    original.resize((256, 256), Image.Resampling.LANCZOS).save(PORTRAIT, optimize=True)
    base, pupils, mask = eye_layers(source)
    layers = {"CatIdleBase.png": place_layer(base, geometry),
              "CatPupilLeft.png": place_layer(pupils[0], geometry),
              "CatPupilRight.png": place_layer(pupils[1], geometry),
              "CatEyesMask.png": place_layer(mask, geometry)}
    for name, image in layers.items():
        image.save(PORTRAIT.parent / name, optimize=True)
    manifest = {
        "source": str(SOURCE.relative_to(ROOT)),
        "sourceKind": "User-supplied transparent PNG, received 2026-11-03",
        "sourceSha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "cropBounds": list(geometry[0]),
        "solidAlphaBounds": list(original.getchannel("A").point(lambda a: 255 if a >= 128 else 0).getbbox()),
        "generator": "scripts/prepare-dock-idle.py",
        "uses": ["transparent cat at the center of the Dock while idle", "mouse-following pupils"],
        "eyeLayers": "Original pupils and highlights lifted from the PNG; amber repaired underneath",
        "outputs": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in [PORTRAIT] + [PORTRAIT.parent / name for name in layers]},
    }
    (SOURCE.parent / "provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
