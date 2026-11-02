"""Identity-locked Makima artwork on the cat's continuous-motion pipeline.

Face, bangs, braid and clothing come from the approved source, not a geometric
redraw. The cat's foot_path/body_transform functions are reused directly.
"""
import math
import sys
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from motion_rigs import foot_path, body_transform

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'Artwork/Makima/Modes/01-walk.png'
SIZE = (36, 20)
SAMPLING = 32
SCALE = .0433
ORIGIN = (205, 470)
ART_SCALE = 4
ART_SIZE = (384*ART_SCALE, 512*ART_SCALE)

PARTS = {
    'braid': [(154,161),(178,172),(165,193),(136,216),(90,239),(68,257),(36,252),(38,211),(98,198),(121,180)],
    'head': [(134,45),(324,45),(324,231),(269,231),(264,200),(232,200),(219,190),(208,190),(201,201),(179,194),(169,185),(134,182)],
    'torso': [(204,192),(225,201),(233,215),(250,260),(244,282),(220,285),(175,272),(179,250),(189,220),(195,208)],
    'upperN': [(184,211),(199,210),(209,222),(207,241),(194,260),(184,278),(167,275),(160,267),(172,241),(178,225)],
    'foreN': [(166,256),(186,269),(178,289),(171,304),(166,320),(154,326),(143,319),(142,309),(149,294),(150,282),(155,270)],
    'upperF': [(232,225),(246,241),(261,260),(270,272),(259,290),(244,283),(233,266),(226,251)],
    'foreF': [(255,265),(276,274),(292,281),(299,290),(298,303),(285,311),(270,303),(255,295),(247,286)],
    'thighN': [(179,275),(223,277),(234,305),(251,347),(254,375),(221,380),(204,348),(181,320)],
    'shinN': [(220,348),(250,349),(258,381),(279,425),(249,437),(232,406),(224,380)],
    'thighF': [(178,276),(214,279),(215,312),(203,337),(186,363),(179,377),(149,373),(152,351),(164,324)],
    'shinF': [(155,349),(186,365),(166,394),(140,418),(120,413),(112,406),(120,396),(139,372)],
    'shoe': [(253,435),(268,431),(279,436),(306,436),(320,430),(331,436),(329,449),(307,456),(280,462),(254,466),(249,453)],
}
ANCHORS = {
    'upperN': ((195,226),(174,266)), 'foreN': ((174,266),(158,297)),
    'upperF': ((232,242),(257,277)), 'foreF': ((257,277),(279,292)),
    'thighN': ((199,300),(236,365)), 'shinN': ((236,365),(266,433)),
    'thighF': ((192,300),(166,361)), 'shinF': ((166,361),(125,420)),
    'torso': ((209,279),(213,203)),
}


@lru_cache(maxsize=1)
def cutouts():
    source = Image.open(SOURCE).crop((0, 0, 384, 512)).convert('RGBA')
    gray = source.convert('L')
    silhouette = gray.point(lambda v: 255 if v < 224 else 0).filter(ImageFilter.MaxFilter(3))
    ImageDraw.floodfill(silhouette, (0, 0), 128)
    silhouette = silhouette.point(lambda v: 0 if v == 128 else 255)
    # Upsample before skinning. Every later transform uses this same high-res master.
    source = source.resize(ART_SIZE, Image.Resampling.LANCZOS)
    silhouette = silhouette.resize(ART_SIZE, Image.Resampling.LANCZOS)
    parts = {}
    for name, polygon in PARTS.items():
        mask = Image.new('L', ART_SIZE)
        ImageDraw.Draw(mask).polygon([(x*ART_SCALE, y*ART_SCALE) for x,y in polygon], fill=255)
        layer = source.copy()
        layer.putalpha(ImageChops.multiply(mask, silhouette))
        parts[name] = layer
    return parts


def affine(layer, a, b, target_a, target_b):
    a,b,target_a,target_b = [np.asarray(p,dtype=float)*ART_SCALE for p in (a,b,target_a,target_b)]
    v,w = b-a,target_b-target_a
    nv = np.array([-v[1],v[0]])/np.linalg.norm(v)
    nw = np.array([-w[1],w[0]])/np.linalg.norm(w)
    matrix = np.column_stack((w,nw)) @ np.linalg.inv(np.column_stack((v,nv)))
    inverse = np.linalg.inv(matrix)
    shift = a-inverse@target_a
    return layer.transform(ART_SIZE, Image.Transform.AFFINE,
        (*inverse[0],shift[0],*inverse[1],shift[1]), Image.Resampling.BICUBIC)


def rigid(layer, pivot, target, angle=0):
    _, transform = body_transform(ART_SIZE,
        tuple(v*ART_SCALE for v in pivot), math.radians(angle),
        tuple((b-a)*ART_SCALE for a,b in zip(pivot,target)))
    return transform(layer)


class Drawing:
    def __init__(self, image):
        flat = Image.new('RGBA', ART_SIZE, 'white')
        flat.alpha_composite(image)
        # Keep fractional edge coverage until the final Lanczos export.
        alpha = flat.convert('L').point(lambda v: max(0,min(255,(242-v)*6)))
        self.mask = alpha.transform((SIZE[0]*SAMPLING,SIZE[1]*SAMPLING),
            Image.Transform.AFFINE,
            (ART_SCALE/(SCALE*SAMPLING),0,(ORIGIN[0]-18/SCALE)*ART_SCALE,
             0,ART_SCALE/(SCALE*SAMPLING),(ORIGIN[1]-19.2/SCALE)*ART_SCALE),
            Image.Resampling.BICUBIC)


def draw_character(row):
    parts = cutouts()
    t = row['phase']*math.tau
    joints = {key:(213+p[0]*10,460+p[1]*10) for key,p in row['joints'].items()}
    result = Image.new('RGBA', ART_SIZE, (255,255,255,0))
    def limb(name,a,b):
        result.alpha_composite(affine(parts[name],*ANCHORS[name],joints[a],joints[b]))
    for side,foot in [('F',row['far']),('N',row['near'])]:
        ankle = joints['ankle'+side]
        result.alpha_composite(rigid(parts['shoe'],(266,433),ankle,13+foot['pitch']))
        a,k = np.asarray(ankle),np.asarray(joints['knee'+side])
        cuff = a+(k-a)/np.linalg.norm(k-a)*15
        d = ImageDraw.Draw(result)
        points = [tuple(p*ART_SCALE) for p in [a,cuff]]
        d.line(points, fill=(18,18,18,255), width=11*ART_SCALE)
        d.line(points, fill=(255,255,255,255), width=7*ART_SCALE)
        x,y = k*ART_SCALE
        r = 11*ART_SCALE
        d.ellipse((x-r,y-r,x+r,y+r),fill=(15,15,15,255))
        limb('shin'+side,'knee'+side,'ankle'+side)
        limb('thigh'+side,'hip'+side,'knee'+side)
    limb('upperF','shoulderF','elbowF')
    limb('foreF','elbowF','handF')
    limb('torso','pelvis','neck')
    limb('upperN','shoulderN','elbowN')
    limb('foreN','elbowN','handN')
    neck = joints['neck']
    braid = rigid(parts['braid'],(157,177),(157,177),1.4*math.sin(t-.6))
    result.alpha_composite(rigid(braid,(213,203),neck,.4*math.sin(t)))
    result.alpha_composite(rigid(parts['head'],(213,203),neck,.4*math.sin(t)))
    return Drawing(result)


def cat_foot_samples(frames, stride, lift, duty):
    rows = []
    for i in range(frames+1):
        row = {'phase':i/frames}
        for key,offset in [('near',0),('far',.5)]:
            phase = (i/frames+offset)%1
            x,clearance,support,swing = foot_path(phase,stride,lift,duty)
            row[key] = dict(x=x,lift=clearance,support=support,phase=phase,
                pitch=-12*math.sin(math.pi*swing))
        rows.append(row)
    return rows
