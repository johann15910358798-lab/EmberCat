"""Source-art skinning for six additional actions; no generated replacement face."""
import math
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

from makima_design import cutouts, affine, rigid, ANCHORS, ART_SCALE, ART_SIZE, Drawing
from vehicle_art import draw_dust, export_image, ink, register, SAMPLING, CANVAS

ROOT=Path(__file__).resolve().parents[2]


@lru_cache(maxsize=6)
def source(mode):
    im=Image.open(ROOT/'Artwork/Makima/Modes'/(mode+'.png')).crop((0,0,384,512)).convert('RGBA')
    silhouette=ink(im).point(lambda a:255 if a>32 else 0).filter(ImageFilter.MaxFilter(3))
    ImageDraw.floodfill(silhouette,(0,0),128)
    silhouette=silhouette.point(lambda a:0 if a==128 else 255)
    im.putalpha(silhouette)
    return im.resize(ART_SIZE,Image.Resampling.LANCZOS)


def polygon(layer,points):
    mask=Image.new('L',ART_SIZE)
    ImageDraw.Draw(mask).polygon([(x*ART_SCALE,y*ART_SCALE) for x,y in points],fill=255)
    result=layer.copy()
    result.putalpha(ImageChops.multiply(result.getchannel('A'),mask))
    return result


def shape(draw,kind,points,**kwargs):
    getattr(draw,kind)([(x*ART_SCALE,y*ART_SCALE) for x,y in points],**kwargs)


@lru_cache(maxsize=1)
def accessories():
    skate=polygon(source('04-rollers'),[(226,402),(264,402),(267,414),(299,428),(301,443),
        (299,469),(222,469),(222,437)])
    board=polygon(source('05-board'),[(137,413),(223,414),(225,394),(264,394),(271,404),
        (301,409),(341,406),(355,413),(353,472),(137,472)])
    return skate,board


def wheel_spokes(layer,centers,angle,radius,stroke=1.5):
    draw=ImageDraw.Draw(layer)
    for x,y in centers:
        # Keep source tires, boots, deck and axle; replace only the inner hub.
        shape(draw,'ellipse',[(x-radius,y-radius),(x+radius,y+radius)],fill='white')
        for n in range(3):
            a=angle+n*math.tau/3
            shape(draw,'line',[(x,y),(x+radius*math.cos(a),y+radius*math.sin(a))],
                  fill='#111111',width=max(1,round(stroke*ART_SCALE)))


def draw_gait(mode,config,row):
    parts=cutouts()
    joints={key:(213+p[0]*10,460+p[1]*10) for key,p in row['joints'].items()}
    result=Image.new('RGBA',ART_SIZE,(255,255,255,0))
    skate,board=accessories()
    def limb(name,a,b):
        result.alpha_composite(affine(parts[name],*ANCHORS[name],joints[a],joints[b]))
    if mode=='05-board':
        deck=board.copy()
        wheel_spokes(deck,[(177,448),(305,447)],row['wheelAngle'],5.5)
        result.alpha_composite(rigid(deck,(240,400),joints['ankleN']))
    for side,foot in [('F',row['far']),('N',row['near'])]:
        ankle=joints['ankle'+side]
        if mode=='04-rollers':
            shoe=skate.copy()
            wheel_spokes(shoe,[(240,455),(282,455)],row['wheelAngle'],6)
            result.alpha_composite(rigid(shoe,(247,410),ankle,foot['pitch']*0.5))
        elif not (mode=='05-board' and side=='N'):
            result.alpha_composite(rigid(parts['shoe'],(266,433),ankle,13+foot['pitch']))
        a,k=np.asarray(ankle),np.asarray(joints['knee'+side])
        cuff=a+(k-a)/np.linalg.norm(k-a)*15
        d=ImageDraw.Draw(result)
        shape(d,'line',[a,cuff],fill='#151515',width=11*ART_SCALE)
        shape(d,'line',[a,cuff],fill='white',width=7*ART_SCALE)
        shape(d,'ellipse',[k-11,k+11],fill='#111111')
        limb('shin'+side,'knee'+side,'ankle'+side)
        limb('thigh'+side,'hip'+side,'knee'+side)
    def arm(side):
        # The original sleeve pieces overlap in the drawing but separate when
        # the elbow bends. A cloth-colored joint underneath closes that seam.
        elbow=np.asarray(joints['elbow'+side])
        shoulder=np.asarray(joints['shoulder'+side])
        d=ImageDraw.Draw(result)
        for center,radius in [(shoulder,9),(elbow,9)]:
            shape(d,'ellipse',[center-radius,center+radius],fill='white',outline='#151515',width=2*ART_SCALE)
        limb('upper'+side,'shoulder'+side,'elbow'+side)
        limb('fore'+side,'elbow'+side,'hand'+side)
    arm('F')
    limb('torso','pelvis','neck')
    arm('N')
    neck=joints['neck'];t=row['phase']*math.tau
    braid=rigid(parts['braid'],(157,177),(157,177),row['braidAngle'])
    result.alpha_composite(rigid(braid,(213,203),neck,.45*math.sin(t)))
    result.alpha_composite(rigid(parts['head'],(213,203),neck,.45*math.sin(t)))
    body=Drawing(result).mask
    dust=draw_dust(row)
    # Ground effects are behind the shoes. Preserve white interiors as occluders.
    silhouette=result.getchannel('A')
    solid=register_gait(silhouette)
    dust=ImageChops.multiply(dust,ImageChops.invert(solid))
    return union(body,dust),body,dust


def register_gait(mask):
    from makima_design import SCALE,ORIGIN
    return mask.transform(CANVAS,Image.Transform.AFFINE,
        (ART_SCALE/(SCALE*SAMPLING),0,(ORIGIN[0]-18/SCALE)*ART_SCALE,
         0,ART_SCALE/(SCALE*SAMPLING),(ORIGIN[1]-19.2/SCALE)*ART_SCALE),Image.Resampling.BICUBIC)


def union(a,b):
    return ImageChops.invert(ImageChops.multiply(ImageChops.invert(a),ImageChops.invert(b)))


@lru_cache(maxsize=1)
def bicycle_parts():
    src=source('06-bicycle')
    upper=polygon(src,[(0,0),(384,0),(384,275),(279,277),(252,269),(213,267),
        (192,275),(158,285),(137,295),(121,289),(116,254),(0,254)])
    thigh=polygon(src,[(130,271),(157,275),(183,297),(212,317),(218,334),(198,351),
        (177,351),(152,330),(130,307),(124,288)])
    shin=polygon(src,[(183,330),(211,333),(209,356),(195,405),(167,405),(164,392),(169,366)])
    shoe=polygon(src,[(166,402),(194,404),(197,413),(222,426),(227,435),(223,441),
        (205,440),(178,433),(156,429),(155,416)])
    return upper,thigh,shin,shoe


@lru_cache(maxsize=1)
def cycling_trouser_skin():
    parts=cutouts();result={}
    for name,radius in [('thighN',17),('shinN',14)]:
        mask=Image.new('L',ART_SIZE);d=ImageDraw.Draw(mask)
        a,b=ANCHORS[name]
        shape(d,'line',[a,b],fill=255,width=radius*2*ART_SCALE)
        for p in [np.asarray(a),np.asarray(b)]:shape(d,'ellipse',[p-radius,p+radius],fill=255)
        layer=parts[name].copy();layer.putalpha(ImageChops.multiply(layer.getchannel('A'),mask))
        result[name]=layer
    return result


def draw_bicycle(config,row):
    upper,_,_,_=bicycle_parts()
    pants=cutouts()
    trouser_skin=cycling_trouser_skin()
    base=source('06-bicycle').copy()
    d=ImageDraw.Draw(base)
    # Remove the old rider from the mechanical base. The source upper body and
    # original trouser/shoe cutouts are composited back after solving the pedals.
    shape(d,'rectangle',[(0,0),(384,337)],fill='white')
    shape(d,'polygon',[(128,287),(220,287),(231,447),(151,447),(148,349)],fill='white')
    for cx,cy in [(94,400),(305,400)]:
        shape(d,'ellipse',[(cx-51,cy-51),(cx+51,cy+51)],fill='white')
        for n in range(6):
            a=row['wheelAngle']+n*math.tau/6
            shape(d,'line',[(cx,cy),(cx+50*math.cos(a),cy+50*math.sin(a))],fill='#111111',width=3*ART_SCALE)
        shape(d,'ellipse',[(cx-9,cy-9),(cx+9,cy+9)],fill='#111111')
    def leg_layer(leg):
        # The walking source provides intact trousers; the cycling source has
        # frame tubes crossing the leg, which must not rotate with the knee.
        from motion_rigs import body_transform
        _,shoe_transform=body_transform(ART_SIZE,(266*ART_SCALE,433*ART_SCALE),math.radians(13),
            ((leg['ankle'][0]-266)*ART_SCALE,(leg['ankle'][1]-433)*ART_SCALE),stretch=(.65,.65))
        base.alpha_composite(shoe_transform(pants['shoe']))
        k=np.asarray(leg['knee'])
        shape(ImageDraw.Draw(base),'ellipse',[k-12,k+12],fill='#111111')
        base.alpha_composite(affine(trouser_skin['shinN'],*ANCHORS['shinN'],leg['knee'],leg['ankle']))
        base.alpha_composite(affine(trouser_skin['thighN'],*ANCHORS['thighN'],leg['hip'],leg['knee']))
    leg_layer(row['legs'][1])
    for a,b in [((94,400),(151,298)),((151,298),(198,398)),((94,400),(198,398)),
                ((151,298),(276,310)),((198,398),(276,310)),((276,310),(305,400)),
                ((276,310),(268,269)),((268,269),(286,256)),((151,298),(145,285))]:
        shape(d,'line',[a,b],fill='#111111',width=8*ART_SCALE)
    shape(d,'ellipse',[(122,287),(162,300)],fill='#111111')
    shape(d,'ellipse',[(184,384),(212,412)],fill='#111111')
    shape(d,'ellipse',[(190,390),(206,406)],fill='white')
    for leg in row['legs']:
        shape(d,'line',[config['crank'],leg['pedal']],fill='#111111',width=4*ART_SCALE)
        px,py=leg['pedal']
        shape(d,'line',[(px-13,py),(px+13,py)],fill='#111111',width=5*ART_SCALE)
    shape(d,'ellipse',[(124,266),(166,307)],fill='#111111')
    leg_layer(row['legs'][0])
    from motion_rigs import braid_warp
    upper=braid_warp(upper,row['braidPhase'],170*ART_SCALE,(174*ART_SCALE,252*ART_SCALE),4*ART_SCALE)
    base.alpha_composite(rigid(upper,(146,284),(146,284+row['bodyY'])))
    flat=Image.new('RGBA',ART_SIZE,'white');flat.alpha_composite(base)
    body=register(ink(flat),config)
    # Keep dust outside the wheels; it trails the rear contact point.
    dust=draw_dust(row)
    solid=body.point(lambda a:255 if a>24 else 0).filter(ImageFilter.MaxFilter(5))
    dust=ImageChops.multiply(dust,ImageChops.invert(solid))
    return union(body,dust),body,dust


def draw_jetpack(config,row):
    src=source('09-jetpack').copy()
    # Replace only the static exhaust, never the backpack or character.
    clear=ImageDraw.Draw(src)
    shape(clear,'polygon',[(58,263),(111,258),(129,267),(143,280),(128,298),(106,311),(56,311)],fill='white')
    ex,ey=config['emitter'];length=row['plumeLength'];t=row['plumePhase']
    direction=np.array([-.84,.54]);normal=np.array([-.54,-.84]);origin=np.array([ex,ey])
    plume=[]
    for side in [-1,1]:
        samples=range(17) if side==-1 else range(16,-1,-1)
        for i in samples:
            u=i/16
            width=(1-u)*10+math.sin(math.pi*u)*(3.5+2*math.sin(t-u*11))
            p=origin+direction*length*u+normal*side*width
            plume.append(tuple(p))
    shape(clear,'polygon',plume,fill='white')
    shape(clear,'line',plume+[plume[0]],fill='#111111',width=3*ART_SCALE,joint='curve')
    inner=[tuple(origin+direction*length*u+normal*math.sin(t-u*9)*2) for u in [.12,.22,.35,.48,.61]]
    shape(clear,'line',inner,fill='#111111',width=2*ART_SCALE,joint='curve')
    # Keep the face rigid. Only the free braid and the bent legs follow the bob.
    def point(x,y):
        x,y=x/ART_SCALE,y/ART_SCALE
        w=max(0,min(1,(y-307)/100));w=w*w*(3-2*w)
        dx=row['legSway']*w
        dy=0
        if x<178 and 175<y<236:
            weight=((178-x)/178)**1.4*math.sin(math.pi*(y-175)/61)**2
            dy=8*weight*math.sin(row['braidPhase']+weight)
        return (x-dx)*ART_SCALE,(y-dy)*ART_SCALE
    mesh=[]
    for y in range(0,ART_SIZE[1],64):
        for x in range(0,ART_SIZE[0],64):
            r,b=min(x+64,ART_SIZE[0]),min(y+64,ART_SIZE[1])
            mesh.append(((x,y,r,b),(*point(x,y),*point(x,b),*point(r,b),*point(r,y))))
    src=src.transform(ART_SIZE,Image.Transform.MESH,mesh,Image.Resampling.BICUBIC)
    src=rigid(src,(205,255),(205+row['bodyX'],255+row['bodyY']),row['pitch'])
    flat=Image.new('RGBA',ART_SIZE,'white');flat.alpha_composite(src)
    # Flight registration leaves a clear margin for hovering and trailing exhaust.
    registration=dict(config,bounds=[*config['bounds'][:3],config['bounds'][3]+1/config['scale']])
    body=register(ink(flat),registration)
    smoke=draw_dust(row)
    return union(body,smoke),body,smoke


def render(mode,config,row):
    if mode=='06-bicycle': return draw_bicycle(config,row)
    if mode=='09-jetpack': return draw_jetpack(config,row)
    return draw_gait(mode,config,row)
