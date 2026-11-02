#!/usr/bin/env python3
"""Render the source character with an authored two-legged walk cycle."""
import argparse
import base64
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from makima_design import SIZE, SCALE, SAMPLING, ORIGIN
from gait_art import draw_gait as draw_character

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'scripts'))
from motion_rigs import cat_animations, ink


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def image_from_mask(mask, size):
    image = Image.new('RGBA', size)
    alpha = mask.resize(size, Image.Resampling.LANCZOS)
    image.putalpha(alpha.point(lambda a: 0 if a <= 4 else a))
    return image


def export_masks(masks, output):
    frames, detail = output/'frames', output/'detail'
    frames.mkdir(parents=True, exist_ok=True)
    detail.mkdir(parents=True, exist_ok=True)
    hashes, bounds, preview_hashes = {}, [], {}
    for i, mask in enumerate(masks):
        bounds.append(mask.getbbox())
        for density, suffix in [(1, ''), (2, '@2x')]:
            name = f'frame-{i+1:02d}{suffix}.png'
            image_from_mask(mask, (36*density, 20*density)).save(frames/name, optimize=True)
            hashes[name] = digest(frames/name)
        name = f'frame-{i+1:02d}.png'
        image_from_mask(mask, (576, 320)).save(detail/name, optimize=True)
        preview_hashes[name] = digest(detail/name)
    return dict(scale=SCALE, origin=ORIGIN, sampling=SAMPLING, bounds=bounds,
                sha256=hashes, previewSHA256=preview_hashes)


def reference_details(output):
    """Upscale source art, never a menu PNG, for the enlarged comparison."""
    original = output/'original-detail'
    original.mkdir(parents=True, exist_ok=True)
    source = Image.open(ROOT/'Artwork/Makima/Modes/01-walk.png')
    masks = [ink(source.crop(((i%4)*384, (i//4)*512, (i%4+1)*384, (i//4+1)*512)))
             for i in range(8)]
    boxes = [m.point(lambda a: 255 if a>64 else 0).getbbox() for m in masks]
    scale = min(33.5/max(b[2]-b[0] for b in boxes), 18.1/max(b[3]-b[1] for b in boxes))
    for i, (mask, box) in enumerate(zip(masks, boxes)):
        cx = (box[0]+box[2])/2
        alpha = mask.transform((1152, 640), Image.Transform.AFFINE,
            (1/(scale*32), 0, cx-18/scale, 0, 1/(scale*32), box[3]-19/scale),
            Image.Resampling.BICUBIC)
        image_from_mask(alpha, (576, 320)).save(original/f'frame-{i+1:02d}.png', optimize=True)

    # Render the exact cat drawing and rig used by this branch at high resolution.
    cat = output/'cat-detail'
    cat.mkdir(parents=True, exist_ok=True)
    sheets, _ = cat_animations(ROOT/'Artwork')
    meta = json.loads((ROOT/'Artwork/derivation.json').read_text())['sheets']['Cat/walk']
    envelope, scale = meta['fixedEnvelope'], meta['scale']
    center = (envelope[0]+envelope[2])/2
    for i, mask in enumerate(sheets['walk']):
        alpha = mask.transform((1152, 640), Image.Transform.AFFINE,
            (1/(scale*32), 0, center-18/scale, 0, 1/(scale*32), envelope[3]-19/scale),
            Image.Resampling.BICUBIC)
        image_from_mask(alpha, (576, 320)).save(cat/f'frame-{i+1:02d}.png', optimize=True)


def review_page(output):
    def urls(folder, pattern='*@2x.png'):
        return ['data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()
                for p in sorted(folder.glob(pattern))]
    data = {'original': urls(ROOT/'Artwork/Makima/PixelFX-Walk/original'),
            'trial': urls(output/'frames'),
            'cat': urls(ROOT/'Sources/EmberCat/Resources/MenuBarPets/Cat/walk'),
            'originalLarge': urls(output/'original-detail', '*.png'),
            'trialLarge': urls(output/'detail', '*.png'),
            'catLarge': urls(output/'cat-detail', '*.png')}
    assert {k:len(v) for k,v in data.items()} == dict(original=8, trial=96, cat=96,
                                                   originalLarge=8, trialLarge=96, catLarge=96)
    template = Path(__file__).with_name('review-template.html').read_text()
    (output/'comparison.html').write_text(template.replace('__FRAMES__', json.dumps(data)))
    references = [Image.open(p) for p in sorted((output/'cat-detail').glob('*.png'))]
    new = [Image.open(p) for p in sorted((output/'detail').glob('*.png'))]
    cards = []
    for i in range(48):
        card = Image.new('RGB', (800, 340), '#f4f3ef')
        d = ImageDraw.Draw(card)
        d.text((38, 26), 'BLACK CAT / EXISTING STYLE', fill='#37413f')
        d.text((438, 26), 'MAKIMA / ORIGINAL IDENTITY', fill='#37413f')
        for x, im in [(24, references[i*2]), (424, new[i*2])]:
            large = im.resize((352, 196), Image.Resampling.LANCZOS)
            card.paste(large, (x, 58), large)
            small = im.resize((72, 40), Image.Resampling.LANCZOS)
            card.paste(small, (x+140, 284), small)
        cards.append(card)
    durations = [round((i+1)*160/48)*10-round(i*160/48)*10 for i in range(48)]
    cards[0].save(output/'comparison.gif', save_all=True, append_images=cards[1:],
                  duration=durations, loop=0, disposal=2)
    cards[0].save(output/'comparison.png')


def contact(masks, path):
    sheet = Image.new('RGB', (1152, 4*224), '#f4f3ef')
    d = ImageDraw.Draw(sheet)
    for k, i in enumerate(range(0, 96, 4)):
        frame = image_from_mask(masks[i], (360, 200))
        # Crop only the review card's whitespace, without changing character scale.
        frame = frame.crop((80, 0, 272, 200))
        x, y = (k%6)*192, (k//6)*224
        sheet.paste(frame, (x, y+22), frame)
        d.text((x+12, y+5), f'{i+1:02d} / 96', fill='#37413f')
    sheet.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT/'work/makima-pixelfx')
    parser.add_argument('--node', default='node')
    parser.add_argument('--install', action='store_true')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    rig = json.loads(subprocess.check_output(
        [args.node, str(Path(__file__).with_name('makima-walk.mjs'))],text=True))
    drawings = [draw_character(row) for row in rig['poses']]
    masks = [art.mask for art in drawings]
    details = export_masks(masks, args.out)
    image_from_mask(masks[0], (576, 320)).save(args.out/'design.png')
    contact(masks, args.out/'contact.png')
    reference_details(args.out)
    review_page(args.out)
    sheet = Image.new('RGBA', (576*12, 320*8))
    for i, mask in enumerate(masks):
        sheet.alpha_composite(image_from_mask(mask, (576, 320)), ((i%12)*576, (i//12)*320))
    sheet.save(args.out/'walk-sheet.png', optimize=True)
    source = Path(__file__).with_name('gait_art.py')
    result = dict(generator='Preserved source face and shirt + authored side-view gait and continuous clothing contours',
        upstreamCommit='a84159688af3ca37a4be05a0d422b94451b2e24e',
        source=str(source.relative_to(ROOT)), sourceSHA256=digest(source),
        dependenciesSHA256={name:digest(ROOT/name) for name in [
            'scripts/motion_rigs.py', 'Artwork/Makima/Modes/01-walk.png', 'scripts/pixelfx/makima-walk.mjs',
            'scripts/pixelfx/render-makima.py', 'scripts/pixelfx/human-gait.mjs',
            'scripts/pixelfx/makima_design.py', 'Vendor/PixelFX/core/math.js']},
        frames=96, duration=1.6, fps=60, rig=rig, render=details)
    (args.out/'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    if args.install:
        destination = ROOT/'Sources/EmberCat/Resources/MenuBarPets/Makima/Modes/01-walk'
        destination.mkdir(parents=True, exist_ok=True)
        for name in details['sha256']:
            shutil.copy2(args.out/'frames'/name, destination/name)
        for style, folder in [('Makima', 'detail'), ('Cat', 'cat-detail')]:
            target = ROOT/f'Sources/EmberCat/Resources/PetPreview/{style}/walk'
            target.mkdir(parents=True, exist_ok=True)
            for path in (args.out/folder).glob('*.png'):
                shutil.copy2(path, target/path.name)
        archive = ROOT/'Artwork/Makima/PixelFX-Walk'
        archive.mkdir(parents=True, exist_ok=True)
        for name in ['manifest.json', 'design.png', 'contact.png']:
            shutil.copy2(args.out/name, archive/name)
        path = ROOT/'Artwork/derivation.json'
        meta = json.loads(path.read_text())
        meta['sheets']['Makima/Modes/01-walk'].update(frames=96, scale=SCALE,
            bounds=details['bounds'], source=result['generator'],
            pixelfx='Makima/PixelFX-Walk/manifest.json',
            headRegistration='Original identity retained; existing transitions preserved for comparison')
        for name, value in details['sha256'].items():
            meta['outputSHA256']['Makima/Modes/01-walk/'+name] = value
        path.write_text(json.dumps(meta, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(dict(frames=96, fps=60, out=str(args.out)), ensure_ascii=False))


if __name__ == '__main__':
    main()
