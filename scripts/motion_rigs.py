"""Original round-cat rig. Makima uses her complete original drawings.

Pillow only. No Makima joints or limbs are drawn by this module.
"""
import math
from PIL import Image, ImageChops, ImageDraw

TAU = math.tau
CAT_FRAMES = 72

def polygon_mask(size, points):
    mask = Image.new('L', size)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask

def ink(image):
    return image.convert('L').point(lambda value: max(0, min(255, (240-value)*5)))

def capsule(draw, points, width, fill=255):
    draw.line(points, fill=fill, width=round(width), joint='curve')
    r = width/2
    for x, y in points:
        draw.ellipse((x-r, y-r, x+r, y+r), fill=fill)

def foot_path(phase, stride, lift, duty):
    """Right-facing gait: grounded foot travels BACK, airborne foot recovers.

    The swing's Hermite tangents match support velocity at toe-off and landing.
    A flat support path pins the sole to one ground plane, including body bob.
    """
    phase %= 1
    if phase < duty:
        return stride*(1-2*phase/duty), 0.0, True, 0.0
    u = (phase-duty)/(1-duty)
    tangent = -2*stride/duty*(1-duty)
    x = ((2*u**3-3*u*u+1)*-stride + (u**3-2*u*u+u)*tangent
        + (-2*u**3+3*u*u)*stride + (u**3-u*u)*tangent)
    return x, lift*math.sin(math.pi*u)**2, False, u

def body_transform(size, pivot, angle, shift):
    """Return one rigid transform plus its matching joint transform."""
    c, s = math.cos(angle), math.sin(angle)
    px, py = pivot
    dx, dy = shift
    def point(p):
        x, y = p[0]-px, p[1]-py
        return (px+dx+c*x-s*y, py+dy+s*x+c*y)
    def layer(im):
        return im.transform(size,Image.Transform.AFFINE,
            (c,s,px-c*(px+dx)-s*(py+dy),
             -s,c,py+s*(px+dx)-c*(py+dy)),Image.Resampling.BICUBIC)
    return point, layer

def braid_warp(master, phase, root, band, amplitude=3.0):
    """A small, periodic bend only in the free braid, tapering to zero at root."""
    mesh = []
    width, height = master.size
    lo, hi = band
    def source(x,y):
        if x >= root or y <= lo or y >= hi:
            return (x,y)
        weight = ((root-x)/root)**1.5 * math.sin(math.pi*(y-lo)/(hi-lo))**2
        return (x,y-amplitude*math.sin(phase)*weight)
    for y in range(0,height,16):
        for x in range(0,width,16):
            r,b = min(width,x+16),min(height,y+16)
            quad = (*source(x,y),*source(x,b),*source(r,b),*source(r,y))
            mesh.append(((x,y,r,b),quad))
    return master.transform(master.size, Image.Transform.MESH, mesh, Image.Resampling.BICUBIC)

def cat_rig(art):
    master=ink(Image.open(art/'Cat/master-v3.png'))
    # Preserve this single body/head/tail shape throughout the entire loop.
    keep=polygon_mask(master.size,[(0,0),(1024,0),(1024,570),(850,570),
        (800,610),(750,642),(706,649),(646,660),(572,679),
        (479,688),(386,686),(292,672),(260,650),(0,650)])
    body=ImageChops.multiply(master,keep)
    frames=[]
    poses=[]
    for index in range(CAT_FRAMES):
        phase=index/CAT_FRAMES
        t=TAU*phase
        point,layer=body_transform(master.size,(520,620),math.radians(.45*math.sin(t)),
            (1.8*math.sin(t),5*math.cos(2*t)))
        im=Image.new('L',master.size)
        legs=[]
        # Four-beat walk: near hind, near fore, far hind, far fore.
        for hip_x,offset,near in [(347,.5,False),(733,.25,False),
                                  (311,0,True),(693,.75,True)]:
            leg_phase=(phase+offset)%1
            x,clearance,support,_=foot_path(leg_phase,36,31,.66)
            ankle=(hip_x+x,726-clearance)
            hip=point((hip_x,634))
            joint=(hip[0]+(25 if hip_x<500 else -12),hip[1]+47)
            d=ImageDraw.Draw(im)
            if near: capsule(d,[hip,joint,ankle],55,0)
            capsule(d,[hip,joint],64)
            capsule(d,[joint,ankle],48)
            x,y=ankle
            d.rounded_rectangle((x-23,y-10,x+41,y+24),radius=15,fill=255)
            if near:
                for dx in (16,29):
                    d.arc((x+dx-4,y+7,x+dx+4,y+27),270,355,fill=0,width=3)
            legs.append({'phase':leg_phase,'support':support,'ankle':ankle,'hip':hip})
        moving_body=braid_warp(body,t,270,(292,545),amplitude=8)
        im=ImageChops.lighter(im,layer(moving_body))
        frames.append(im)
        poses.append({'phase':phase,'head':point((800,390)),'hip':point((520,620)),
            'bodyAngle':math.radians(.45*math.sin(t)),'legs':legs})
    # Idle uses the identical master body, feet and registration as the loop.
    return frames,master,{'master':'Cat/master-v3.png','cell':0,
        'method':'original round body; four-beat forward walk, planted paws, body weight transfer and soft tail',
        'headBox':[640,250,920,530],'groundAnkle':726,'duty':.66,'stride':36,'poses':poses}
