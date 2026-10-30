#!/usr/bin/env python3
"""Prepare the licensed Unity Labs sequence; never regenerate the flame shapes."""

import hashlib
import io
import json
from pathlib import Path
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Artwork/NotchFlame/UnityLabs-Flame03-hollow.zip"
CORE_SOURCE = ROOT / "Artwork/NotchFlame/UnityLabs-Flame03.zip"
DESTINATION = ROOT / "Sources/EmberCat/Resources/NotchFlame"
FRAME_COUNT = 160
BLEND_FRAMES = 12
COLUMNS = 16


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(SOURCE) as archive:
        names = sorted(name for name in archive.namelist() if name.endswith(".tga"))
        # Skip ignition. Preserve the original motion and use every second frame.
        frames = [Image.open(io.BytesIO(archive.read(names[128 + index * 2]))).convert("RGB")
                  for index in range(FRAME_COUNT + BLEND_FRAMES)]
    with zipfile.ZipFile(CORE_SOURCE) as archive:
        names = sorted(name for name in archive.namelist() if name.endswith(".tga"))
        for index, frame in enumerate(frames):
            core = Image.open(io.BytesIO(archive.read(names[128 + index * 2]))).convert("RGB")
            frames[index] = Image.blend(frame, core, 0.30)

    width, height = frames[0].size
    atlas = Image.new("RGB", (width * COLUMNS, height * (FRAME_COUNT // COLUMNS)))
    for index in range(FRAME_COUNT):
        frame = frames[index]
        if index < BLEND_FRAMES:
            progress = index / (BLEND_FRAMES - 1)
            weight = progress * progress * (3 - 2 * progress)
            # Frame 159 continues into source frame 160 at the loop boundary,
            # then dissolves into the beginning over 0.4 seconds.
            frame = Image.blend(frames[FRAME_COUNT + index], frame, weight)
        atlas.paste(frame, ((index % COLUMNS) * width, (index // COLUMNS) * height))
    atlas_path = DESTINATION / "fire-atlas.png"
    atlas.save(atlas_path, optimize=True)
    metadata = {
        "name": "Unity Labs Flame03 + Flame03-hollow",
        "license": "CC0-1.0",
        "publisherURL": "https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks",
        "sourceURL": "https://unity3d.com/files/labs/downloads/vfx/assets01/Flame03-hollow/Flame03-hollow-sequence-tga.zip",
        "sourceSHA256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "coreSourceURL": "https://unity3d.com/files/labs/downloads/vfx/assets01/Flame03/Flame03-sequence-tga.zip",
        "coreSourceSHA256": hashlib.sha256(CORE_SOURCE.read_bytes()).hexdigest(),
        "coreMix": 0.30,
        "atlasSHA256": hashlib.sha256(atlas_path.read_bytes()).hexdigest(),
        "frameWidth": width,
        "frameHeight": height,
        "gridColumns": COLUMNS,
        "gridRows": FRAME_COUNT // COLUMNS,
        "frameCount": FRAME_COUNT,
        "framesPerSecond": 30,
        "firstSourceFrame": 129,
        "sourceFrameStep": 2,
        "loopBlendFrames": BLEND_FRAMES,
    }
    (DESTINATION / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Prepared {FRAME_COUNT} frames, {width} x {height}, {atlas_path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
