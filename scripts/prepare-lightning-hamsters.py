#!/usr/bin/env python3
"""Prepare the three user-supplied GIFs without changing their frame timing."""

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Artwork/NotchLightning/Hamsters'
DESTINATION = ROOT / 'Sources/EmberCat/Resources/NotchLightning'
CELL = 224
COLUMNS = 8
ANCHOR = (102, 128)
# Align the wheel, rather than the smoke above it, across the three drawings.
CLIPS = [
    ('slow', '慢速.gif', (119, 136), 206),
    ('fast', '高速.gif', (111, 124), 230),
    ('turbo', '极速.gif', (107, 156), 192),
]


def clear_border_fragments(frame):
    """Remove detached slivers at the GIF boundary, retaining the actual art."""
    width, height = frame.size
    alpha = frame.getchannel('A')
    values = alpha.load()
    visited = set()
    for y in range(height):
        for x in [*range(16), *range(width - 16, width)]:
            if (x, y) in visited or values[x, y] < 8:
                continue
            component, pending = [], [(x, y)]
            visited.add((x, y))
            while pending:
                point = pending.pop()
                component.append(point)
                px, py = point
                for neighbor in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]:
                    nx, ny = neighbor
                    if 0 <= nx < width and 0 <= ny < height and neighbor not in visited and values[nx, ny] >= 8:
                        visited.add(neighbor)
                        pending.append(neighbor)
            xs, ys = zip(*component)
            if (max(xs) < 16 or min(xs) >= width - 16) and len(component) < 1500 and max(ys) - min(ys) > 8:
                for px, py in component:
                    for ny in range(max(0, py - 1), min(height, py + 2)):
                        for nx in range(max(0, px - 1), min(width, px + 2)):
                            values[nx, ny] = 0
    frame.putalpha(alpha)
    return frame


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    frames, clips = [], []
    review = Image.new('RGB', (CELL * 3, CELL * 2))
    for index, (key, original_name, center, wheel_height) in enumerate(CLIPS):
        source = SOURCE / (key + '.gif')
        gif = Image.open(source)
        scale = 146 / wheel_height
        durations = []
        first = len(frames)
        for frame_index in range(gif.n_frames):
            gif.seek(frame_index)
            rgba = clear_border_fragments(gif.convert('RGBA'))
            duration = gif.info.get('duration', 100) / 1000
            if duration <= 0:
                raise ValueError(f'{source.name}: invalid frame duration')
            transformed = rgba.transform((CELL, CELL), Image.Transform.AFFINE,
                (1 / scale, 0, center[0] - ANCHOR[0] / scale,
                 0, 1 / scale, center[1] - ANCHOR[1] / scale), Image.Resampling.BICUBIC)
            bounds = transformed.getchannel('A').getbbox()
            if bounds is None or min(bounds[:2]) < 2 or max(bounds[2:]) > CELL - 2:
                raise ValueError(f'{source.name}: frame {frame_index} exceeds atlas cell')
            frames.append(transformed)
            durations.append(duration)
        for row, background in enumerate([(14, 17, 23, 255), (255, 255, 255, 255)]):
            panel = Image.new('RGBA', (CELL, CELL), background)
            panel.alpha_composite(frames[first])
            review.paste(panel.convert('RGB'), (index * CELL, row * CELL))
        clips.append({'name': key, 'originalName': original_name,
            'source': str(source.relative_to(ROOT)), 'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'firstFrame': first, 'frameDurations': durations,
            'wheelCenter': center, 'scale': scale})
    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    atlas = Image.new('RGBA', (CELL * COLUMNS, CELL * rows))
    for index, frame in enumerate(frames):
        atlas.paste(frame, (index % COLUMNS * CELL, index // COLUMNS * CELL))
    target = DESTINATION / 'hamster-atlas.png'
    atlas.save(target, optimize=True)
    manifest = {'cellSize': CELL, 'columns': COLUMNS, 'rows': rows, 'frameCount': len(frames),
        'wheelAnchor': [v / CELL for v in ANCHOR], 'clips': clips,
        'cleanup': 'Only detached narrow fragments in the outermost sixteen source columns are removed.',
        'atlasSHA256': hashlib.sha256(target.read_bytes()).hexdigest()}
    (DESTINATION / 'hamster-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    folder = ROOT / 'work/notch-lightning/hamster-energy'
    folder.mkdir(parents=True, exist_ok=True)
    review.save(folder / 'atlas-review.png')
    print(f'Prepared {len(frames)} transparent frames; original GIF timing and source files retained.')


if __name__ == '__main__':
    main()
