#!/usr/bin/env python3
"""Build 1x/2x single-ink menu-bar resources from original generated artwork.

Offline and deterministic; requires Pillow. API credentials are never read.
"""
import hashlib
import json
from itertools import combinations
from pathlib import Path

from PIL import Image, ImageFilter
from motion_rigs import cat_rig

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'Artwork'
OUT = ROOT / 'Sources/EmberCat/Resources/MenuBarPets'
SIZE = (36, 20)
MODES = ['idle', 'walk', 'brisk', 'run', 'rollers', 'board', 'bicycle', 'motorcycle', 'roadster', 'jetpack']


def ink(image):
    mask = image.convert('L').point(lambda value: max(0, min(255, (242-value)*6)))
    return mask.filter(ImageFilter.MaxFilter(3))


def blank_gutter(mask, axis, nominal):
    projection = mask.point(lambda a: 255 if a > 64 else 0).getprojection()[axis]
    radius = len(projection) // 8
    start, limit = max(1, nominal-radius), min(len(projection)-1, nominal+radius)
    gaps = []
    while start < limit:
        if projection[start]:
            start += 1
            continue
        end = start+1
        while end < limit and not projection[end]:
            end += 1
        if end-start >= 2:
            gaps.append((start, end))
        start = end
    if not gaps:
        raise ValueError('No blank gutter between transition poses')
    left, right = min(gaps, key=lambda gap: (max(gap[0]-nominal, nominal-gap[1], 0), -(gap[1]-gap[0])))
    return (left+right)//2


def split(path, columns, rows, adaptive=False):
    image = Image.open(path).convert('RGB')
    if image.size != (1536, 1024):
        raise ValueError(f'Unexpected sheet dimensions: {path}: {image.size}')
    if adaptive:
        # Generated panels can drift across the mathematical midpoint. Cut in
        # the actual white gutters so wheels, hair and shoes remain complete.
        if (columns, rows) != (2, 2):
            raise ValueError('Adaptive gutters require a 2x2 transition sheet')
        mask = ink(image)
        middle = blank_gutter(mask, 1, image.height//2)
        masks = []
        for top, bottom in ((0, middle), (middle, image.height)):
            row = mask.crop((0, top, image.width, bottom))
            divider = blank_gutter(row, 0, image.width//2)
            masks += [row.crop((0, 0, divider, row.height)), row.crop((divider, 0, row.width, row.height))]
        return masks
    width, height = image.width // columns, image.height // rows
    return [ink(image.crop((i % columns*width, i // columns*height,
        (i % columns+1)*width, (i // columns+1)*height))) for i in range(columns*rows)]


def bounds(mask):
    box = mask.point(lambda a: 255 if a > 64 else 0).getbbox()
    if box is None:
        raise ValueError('Empty artwork')
    return box


def head_landmark(mask):
    """Find the same hair-cap landmark in a full pose or transition panel."""
    box = bounds(mask)
    height = box[3]-box[1]
    # The old 8-23% projection included a horizontal braid in flight poses,
    # doubling the detected head width and making a transition key shrink.
    # Use only the upper hair cap, before any braid joins the silhouette.
    band = mask.crop((0,int(box[1]+height*.04),mask.width,int(box[1]+height*.14)))
    left, _, right, _ = bounds(band)
    return ((left+right)/2,box[1]+(right-left)*.55,right-left)


def export(masks, folder, kind, transition=False):
    boxes = [bounds(mask) for mask in masks]
    max_width = max(b[2]-b[0] for b in boxes)
    max_height = max(b[3]-b[1] for b in boxes)
    head_tops = None
    if kind == 'cat' and len(masks) > 1:
        # Register the nose and ears, rather than the moving paws. This keeps
        # the head still while the legs move, including at the loop seam.
        head_tops = [bounds(mask.crop((int(b[0]+(b[2]-b[0])*.55), 0,
            mask.width, mask.height)))[1] for mask, b in zip(masks, boxes)]
        max_drop = max(b[3]-top for b, top in zip(boxes, head_tops))
        max_height = max(top-b[1] for b, top in zip(boxes, head_tops)) + max_drop
    width_limit, height_limit = (27.5, 16.5) if kind == 'cat' else (33.5, 18.1)
    scale = min(width_limit/max_width, height_limit/max_height)
    folder.mkdir(parents=True, exist_ok=True)
    expected = set()
    for i, (mask, box) in enumerate(zip(masks, boxes)):
        # Stable scale across a sheet. Normalize cell-layout drift, not character size.
        center_x = (box[0]+box[2])/2
        baseline = 19.0
        if head_tops is not None:
            center_x = box[2]-max_width/2
            baseline -= (max_drop-(box[3]-head_tops[i]))*scale
        if kind == 'jetpack':
            baseline = 18.0 + (0, -.25, -.4, -.25, 0, .25, .4, .25)[i % 8]
        if kind == 'run' and len(masks) > 1 and not transition:
            baseline += (0, .1, -.25, -.5, 0, .1, -.25, -.5)[i % 8]
        supersampling = 8
        large = mask.transform((SIZE[0]*supersampling, SIZE[1]*supersampling), Image.Transform.AFFINE,
            (1/(scale*supersampling), 0, center_x-18/scale,
             0, 1/(scale*supersampling), box[3]-baseline/scale), Image.Resampling.BICUBIC)
        for density in (1, 2):
            alpha = large.resize((SIZE[0]*density, SIZE[1]*density), Image.Resampling.LANCZOS)
            image = Image.new('RGBA', alpha.size, (0, 0, 0, 0))
            image.putalpha(alpha)
            name = f'frame-{i+1:02d}{"@2x" if density == 2 else ""}.png'
            image.save(folder/name, optimize=True)
            expected.add(name)
    for old in folder.glob('*.png'):
        if old.name not in expected:
            old.unlink()
    report={'frames':len(masks),'scale':scale,'bounds':boxes,
        'source':'complete original drawings; no reconstructed limbs'}
    if kind!='cat' and not transition:
        hx,hy,hw=head_landmark(masks[0])
        first_box=boxes[0]
        first_center=(first_box[0]+first_box[2])/2
        first_baseline=18.0 if kind=='jetpack' else 19.0
        report['headCenter']=[18+(hx-first_center)*scale,first_baseline+(hy-first_box[3])*scale]
        report['headWidth']=hw*scale
    return report


def export_transition(masks,folder,source,target):
    """Match character registration, allowing the vehicle to enter around it."""
    folder.mkdir(parents=True,exist_ok=True)
    rows=[]
    for i,mask in enumerate(masks):
        amount=(i+1)/(len(masks)+1)
        center=[a+(b-a)*amount for a,b in zip(source['headCenter'],target['headCenter'])]
        width=source['headWidth']+(target['headWidth']-source['headWidth'])*amount
        hx,hy,hw=head_landmark(mask)
        box=bounds(mask)
        # A long car beside a standing person must enter from the canvas edge.
        # Fitting its entire width would shrink the PERSON by up to 40%, then
        # grow her again on boarding. Keep character scale; clip the entering
        # vehicle horizontally. Feet and hair remain within vertical bounds.
        scale=min(width/hw,(center[1]-.7)/(hy-box[1]),(19.4-center[1])/(box[3]-hy))
        large=mask.transform((SIZE[0]*12,SIZE[1]*12),Image.Transform.AFFINE,
            (1/(scale*12),0,hx-center[0]/scale,0,1/(scale*12),hy-center[1]/scale),
            Image.Resampling.BICUBIC)
        for density in (1,2):
            image=Image.new('RGBA',(SIZE[0]*density,SIZE[1]*density))
            image.putalpha(large.resize(image.size,Image.Resampling.LANCZOS))
            image.save(folder/f'frame-{i+1:02d}{"@2x" if density==2 else ""}.png',optimize=True)
        rows.append({'sourceBounds':box,'headCenter':center,'scale':scale,
            'vehicleMayEnterFromCanvasEdge':True,
            'hairCapWidth':hw,'renderedHairCapWidth':hw*scale,'requestedHairCapWidth':width})
    return {'frames':len(masks),'registration':'upper hair-cap interpolation; excludes braid','keys':rows}


def export_registered(masks, folder, metadata, extra=None):
    """Every part uses one scale, origin and baseline for the entire loop."""
    boxes = [bounds(mask) for mask in masks]
    if extra is not None:
        boxes.append(bounds(extra))
    envelope = (min(b[0] for b in boxes), min(b[1] for b in boxes),
        max(b[2] for b in boxes), max(b[3] for b in boxes))
    scale = min(31/(envelope[2]-envelope[0]),17.6/(envelope[3]-envelope[1]))
    if 'headHeight' in metadata:
        scale = min(scale,7.2/metadata['headHeight'])
    center = (envelope[0]+envelope[2])/2
    transform = (1/(scale*12),0,center-18/scale,
        0,1/(scale*12),envelope[3]-19/scale)
    def write(mask, index, target):
        target.mkdir(parents=True,exist_ok=True)
        large=mask.transform((SIZE[0]*12,SIZE[1]*12),Image.Transform.AFFINE,
            transform,Image.Resampling.BICUBIC)
        for density in (1,2):
            alpha=large.resize((SIZE[0]*density,SIZE[1]*density),Image.Resampling.LANCZOS)
            image=Image.new('RGBA',alpha.size)
            image.putalpha(alpha)
            name=f'frame-{index+1:02d}{"@2x" if density==2 else ""}.png'
            image.save(target/name,optimize=True)
    folder.mkdir(parents=True,exist_ok=True)
    expected={f'frame-{i+1:02d}{suffix}.png' for i in range(len(masks)) for suffix in ('','@2x')}
    for old in folder.glob('*.png'):
        if old.name not in expected: old.unlink()
    for i,mask in enumerate(masks): write(mask,i,folder)
    if extra is not None:
        write(extra,0,folder.parent/'idle')
    # Registration stays fixed, while the character may transfer weight inside
    # that canvas. Freezing head pixels would incorrectly reward a rigid torso.
    head=tuple(metadata['headBox'])
    logical_head = [18+(head[0]-center)*scale,19+(head[1]-envelope[3])*scale,
        18+(head[2]-center)*scale,19+(head[3]-envelope[3])*scale]
    hx,hy,hw=head_landmark(masks[0])
    return {'frames':len(masks),'scale':scale,'bounds':boxes[:len(masks)],
        'fixedEnvelope':envelope,'registration':'one scale and origin for the entire loop',
        'logicalHeadBox':logical_head,'rig':metadata,
        'headCenter':[18+(hx-center)*scale,19+(hy-envelope[3])*scale],'headWidth':hw*scale}


def main():
    report = {'canvas': SIZE, 'scales': [1, 2], 'provenance': 'Original generated cat; user-requested Makima fan art; no RunCat image inputs or runtime assets', 'sheets': {}}
    cat, idle, metadata = cat_rig(ART)
    report['sheets']['Cat/run'] = export_registered(cat,OUT/'Cat/run',metadata,extra=idle)
    report['sheets']['Cat/idle'] = {'frames':1,'sharedRegistration':'Cat/run'}
    for rank, name in enumerate(MODES):
        key = f'{rank:02d}-{name}'
        source = ART/'Makima/Modes'/f'{key}.png'
        if name == 'idle':
            report['sheets'][f'Makima/Modes/{key}'] = export([ink(Image.open(source))],OUT/'Makima/Modes'/key,name)
        else:
            masks=split(source,4,2)
            report['sheets'][f'Makima/Modes/{key}']=export(masks,OUT/'Makima/Modes'/key,name)
            report['sheets'][f'Makima/Modes/{key}']['master']=str(source.relative_to(ART))
            report['sheets'][f'Makima/Modes/{key}']['originalKeyframes']=8
    for lower, upper in combinations(range(len(MODES)), 2):
        key = f'{lower:02d}-{MODES[lower]}_{upper:02d}-{MODES[upper]}'
        source = ART/'Makima/Transitions'/f'{key}.png'
        lower_sheet=report['sheets'][f'Makima/Modes/{lower:02d}-{MODES[lower]}']
        upper_sheet=report['sheets'][f'Makima/Modes/{upper:02d}-{MODES[upper]}']
        report['sheets'][f'Makima/Transitions/{key}'] = export_transition(split(source,2,2,adaptive=True),
            OUT/'Makima/Transitions'/key,lower_sheet,upper_sheet)
    # Remove flat resources belonging to the rejected 0.4 drafts, including upstream cat PNGs.
    for style in ('Cat','Makima'):
        for old in (OUT/style).iterdir():
            if old.is_file() and old.suffix in ('.png','.svg'):
                old.unlink()
    report['artworkSHA256'] = {str(p.relative_to(ART)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(ART.rglob('*.png'))}
    report['outputSHA256'] = {str(p.relative_to(OUT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(OUT.rglob('*.png'))}
    (ART/'derivation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'sheets':len(report['sheets']),'PNG':len(report['outputSHA256']),'canvas':SIZE}))


if __name__ == '__main__':
    main()
