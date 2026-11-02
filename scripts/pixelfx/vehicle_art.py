"""Animate the existing vehicle drawings; keep Makima's face and clothing intact."""
import math
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
ART_SCALE = 4
ART_SIZE = (384 * ART_SCALE, 512 * ART_SCALE)
SAMPLING = 32
CANVAS = (36 * SAMPLING, 20 * SAMPLING)


def ink(image):
    return image.convert('L').point(lambda value: max(0, min(255, (240 - value) * 5)))


@lru_cache(maxsize=2)
def master(mode):
    source = Image.open(ROOT / 'Artwork/Makima/Modes' / (mode + '.png'))
    source = source.crop((0, 0, 384, 512))
    mask = ink(source)
    silhouette = mask.point(lambda a: 255 if a > 32 else 0).filter(ImageFilter.MaxFilter(3))
    ImageDraw.floodfill(silhouette, (0, 0), 128)
    silhouette = silhouette.point(lambda a: 0 if a == 128 else 255)
    return (mask.resize(ART_SIZE, Image.Resampling.LANCZOS),
            silhouette.resize(ART_SIZE, Image.Resampling.LANCZOS))


def wheel_detail(image, mode, config, angle):
    """Only rebuild the mechanical spokes; the character is always source artwork."""
    d = ImageDraw.Draw(image)
    s = ART_SCALE
    for cx, cy, r in config['wheels']:
        x, y, radius = cx * s, cy * s, r * s
        d.ellipse((x-radius, y-radius, x+radius, y+radius), fill=0)
        if mode == '07-motorcycle':
            for i in range(5):
                a = angle + i * math.tau / 5
                end = (x + math.cos(a) * (radius-2*s), y + math.sin(a) * (radius-2*s))
                d.line([(x,y), end], fill=255, width=7*s)
            d.ellipse((x-10*s,y-10*s,x+10*s,y+10*s), fill=255)
            d.ellipse((x-3*s,y-3*s,x+3*s,y+3*s), fill=0)
        else:
            for i in range(5):
                a = angle + i * math.tau / 5
                px, py = x + math.cos(a)*18*s, y + math.sin(a)*18*s
                rr = 6.6*s
                d.ellipse((px-rr,py-rr,px+rr,py+rr), fill=255)
            d.ellipse((x-7*s,y-7*s,x+7*s,y+7*s), fill=255)
    if config['forkMasks']:
        occlusion = Image.new('L', ART_SIZE)
        draw = ImageDraw.Draw(occlusion)
        for polygon in config['forkMasks']:
            draw.polygon([(x*s,y*s) for x,y in polygon], fill=255)
        image.paste(master(mode)[0], (0,0), occlusion)


def motion_mesh(config, row):
    """Rigid upper body, a small suspension bend, and a root-anchored braid."""
    s = ART_SCALE
    lo, hi = config['suspensionBand']
    braid_lo, braid_hi = config['braidBand']
    pivot_x, pivot_y = config['pivot']

    def source(px, py):
        x, y = px/s, py/s
        u = max(0, min(1, (y-lo)/(hi-lo)))
        weight = 1 - u*u*(3-2*u)
        dx = -row['pitch'] * (y-pivot_y) * weight
        dy = (row['bodyY'] + row['pitch']*(x-pivot_x)) * weight
        if x < config['braidRoot'] and braid_lo < y < braid_hi:
            free = max(0, (config['braidRoot']-x)/config['braidRoot']) ** 1.4
            band = math.sin(math.pi*(y-braid_lo)/(braid_hi-braid_lo))**2
            dy += config['braidAmplitude']*free*band*math.sin(row['braidPhase']+free*1.8)
        return ((x-dx)*s, (y-dy)*s)

    mesh = []
    step = 16*s
    for y in range(0, ART_SIZE[1], step):
        for x in range(0, ART_SIZE[0], step):
            right, bottom = min(x+step,ART_SIZE[0]), min(y+step,ART_SIZE[1])
            mesh.append(((x,y,right,bottom),
                (*source(x,y),*source(x,bottom),*source(right,bottom),*source(right,y))))
    return mesh


def register(mask, config):
    scale = config['scale']
    left, _, right, ground = config['bounds']
    return mask.transform(CANVAS, Image.Transform.AFFINE,
        (ART_SCALE/(scale*SAMPLING), 0, ((left+right)/2-18/scale)*ART_SCALE,
         0, ART_SCALE/(scale*SAMPLING), (ground-19/scale)*ART_SCALE),
        Image.Resampling.BICUBIC)


def draw_dust(row):
    result = Image.new('L', CANVAS)
    s = SAMPLING
    for p in row['particles']:
        if p['opacity'] <= 0:
            continue
        x, y, r = p['x']*s, p['y']*s, p['radius']*s
        # Work in a small particle tile; filtering the full canvas per puff is
        # needlessly expensive and does not change the rendered result.
        box = (max(0,math.floor(x-1.4*r-8)),max(0,math.floor(y-1.4*r-8)),
               min(CANVAS[0],math.ceil(x+1.4*r+8)),min(CANVAS[1],math.ceil(y+1.4*r+8)))
        size = (box[2]-box[0],box[3]-box[1])
        if min(size)<=0:
            continue
        x,y = x-box[0],y-box[1]
        if p['kind'] == 'grit':
            layer = Image.new('L', size)
            d = ImageDraw.Draw(layer)
            d.line([(x-r,y), (x+r*.5,y-.03*s)],
                   fill=round(255*p['opacity']), width=round(.19*s))
        else:
            shape = Image.new('L', size)
            d = ImageDraw.Draw(shape)
            ry = r*p['squash']
            # Connected, unequal lobes give a small dust puff rather than smoke rings.
            for dx, dy, radius in [(-.45,.1,.7),(.2,-.19,.85),(.65,.1,.54)]:
                px,py = x+dx*r,y+dy*ry*p['lobe']
                d.ellipse((px-radius*r,py-radius*ry,px+radius*r,py+radius*ry), fill=255)
            inner = shape.filter(ImageFilter.MinFilter(13))
            border = ImageChops.subtract(shape,inner)
            fill = shape.point(lambda a: round(a*p['opacity']*.23))
            stroke = border.point(lambda a: round(a*p['opacity']*.78))
            layer = ImageChops.lighter(fill,stroke)
        # Alpha union of black marks; opaque source art will occlude this later.
        tile = ImageChops.invert(ImageChops.multiply(ImageChops.invert(result.crop(box)),
                                                     ImageChops.invert(layer)))
        result.paste(tile,box)
    return result


def draw_vehicle(mode, config, row, effects=True):
    source, silhouette = master(mode)
    art = source.copy()
    wheel_detail(art,mode,config,row['wheelAngle'])
    mesh = motion_mesh(config,row)
    art = art.transform(ART_SIZE,Image.Transform.MESH,mesh,Image.Resampling.BICUBIC)
    silhouette = silhouette.transform(ART_SIZE,Image.Transform.MESH,mesh,Image.Resampling.BICUBIC)
    foreground, occlusion = register(art,config), register(silhouette,config)
    dust = draw_dust(row) if effects else Image.new('L',CANVAS)
    dust = ImageChops.multiply(dust,ImageChops.invert(occlusion))
    combined = ImageChops.invert(ImageChops.multiply(ImageChops.invert(foreground),
                                                    ImageChops.invert(dust)))
    return combined, foreground, dust


def export_image(mask, size):
    image = Image.new('RGBA',size)
    image.putalpha(mask.resize(size,Image.Resampling.LANCZOS).point(lambda a: 0 if a <= 4 else a))
    return image
