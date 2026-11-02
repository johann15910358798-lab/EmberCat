"""Original round-cat rig. Makima uses her complete original drawings.

Pillow only. No Makima joints or limbs are drawn by this module.
"""
import math
from PIL import Image, ImageChops, ImageDraw

TAU = math.tau
CAT_FRAMES = 96
CAT_CURL_FRAMES = 40

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

def body_transform(size, pivot, angle, shift, stretch=(1.0, 1.0)):
    """Return one rigid transform plus its matching joint transform."""
    c, s = math.cos(angle), math.sin(angle)
    px, py = pivot
    dx, dy = shift
    sx, sy = stretch
    def point(p):
        x, y = p[0]-px, p[1]-py
        return (px+dx+c*sx*x-s*sy*y, py+dy+s*sx*x+c*sy*y)
    def layer(im):
        return im.transform(size,Image.Transform.AFFINE,
            (c/sx,s/sx,px-(c*(px+dx)+s*(py+dy))/sx,
             -s/sy,c/sy,py+(s*(px+dx)-c*(py+dy))/sy),Image.Resampling.BICUBIC)
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

def ease(value):
    value = max(0.0, min(1.0, value))
    return value*value*(3-2*value)

def lerp(a, b, amount):
    return tuple(x+(y-x)*amount for x,y in zip(a,b))

def cat_animations(art):
    master=ink(Image.open(art/'Cat/master-v3.png'))
    keep=polygon_mask(master.size,[(0,0),(1024,0),(1024,570),(850,570),
        (800,610),(750,642),(706,649),(646,660),(572,679),
        (479,688),(386,686),(292,672),(260,650),(0,650)])
    body=ImageChops.multiply(master,keep)
    head=ImageChops.multiply(master,polygon_mask(master.size,
        [(600,0),(1024,0),(1024,520),(817,536),(760,510),(680,460),(600,435)]))
    features=Image.new('L',master.size)
    feature_regions=Image.new('L',master.size)
    detail=ImageDraw.Draw(feature_regions)
    detail.rectangle((814,358,870,409),fill=255)
    detail.rectangle((758,398,817,443),fill=255)
    detail.polygon([(743,301),(760,280),(774,322)],fill=255)
    detail.polygon([(818,304),(836,286),(836,315)],fill=255)
    features=ImageChops.multiply(ImageChops.invert(master),feature_regions)

    def draw_leg(im, hip, joint, ankle, near, width=1.0):
        d=ImageDraw.Draw(im)
        if near: capsule(d,[hip,joint,ankle],55*width,0)
        capsule(d,[hip,joint],64*width)
        capsule(d,[joint,ankle],48*width)
        x,y=ankle
        d.rounded_rectangle((x-23*width,y-10*width,x+41*width,y+24*width),
            radius=15*width,fill=255)
        if near:
            for dx in (16,29):
                d.arc((x+(dx-4)*width,y+7*width,x+(dx+4)*width,y+27*width),
                    270,355,fill=0,width=max(1,round(3*width)))

    def gait_frame(phase, running=False):
        t=TAU*phase
        if running:
            angle=math.radians(1.9*math.sin(t))
            shift=(3*math.sin(t),-16+15*math.cos(2*t))
            stretch=(1.035-.025*math.cos(2*t),.96+.04*math.cos(2*t))
            stride,lift,duty=85,64,.34
            offsets=[(347,.48,False),(733,.03,False),(311,.58,True),(693,.13,True)]
        else:
            angle=math.radians(.7*math.sin(t))
            shift=(1.8*math.sin(t),5*math.cos(2*t))
            stretch=(1,1)
            stride,lift,duty=44,35,.66
            offsets=[(347,.5,False),(733,.25,False),(311,0,True),(693,.75,True)]
        point,layer=body_transform(master.size,(520,620),angle,shift,stretch)
        im=Image.new('L',master.size)
        legs=[]
        for hip_x,offset,near in offsets:
            leg_phase=(phase+offset)%1
            x,clearance,support,_=foot_path(leg_phase,stride,lift,duty)
            ankle=(hip_x+x,726-clearance)
            hip=point((hip_x,634))
            joint=(hip[0]+(27 if hip_x<500 else -18)+.24*(ankle[0]-hip[0]),
                hip[1]+.52*(ankle[1]-hip[1]))
            draw_leg(im,hip,joint,ankle,near)
            legs.append({'phase':leg_phase,'support':support,'ankle':ankle,'hip':hip,
                'joint':joint,'near':near})
        moving_body=braid_warp(body,t-.2,270,(292,545),amplitude=12 if running else 8)
        im=ImageChops.lighter(im,layer(moving_body))
        return im,{'phase':phase,'head':point((800,390)),'hip':point((520,620)),
            'bodyAngle':angle,'legs':legs}

    start,start_pose=gait_frame(0,running=True)

    def curl_frame(amount):
        u=ease(amount)
        center=lerp((520,535),(520,515),u)
        rx,ry=lerp((283,152),(235,235),u)
        im=Image.new('L',master.size)
        # The tail wraps into the circle instead of sticking out of a spinning cat.
        tail=[]
        for i in range(81):
            q=i/80
            controls=[(295,525),(178,548),(219,319),(118,352)]
            original=tuple((1-q)**3*controls[0][a]+3*(1-q)**2*q*controls[1][a]
                +3*(1-q)*q*q*controls[2][a]+q**3*controls[3][a] for a in (0,1))
            angle=2.3+3.2*q
            tucked=(center[0]+198*math.cos(angle),center[1]+198*math.sin(angle))
            tail.append(lerp(original,tucked,u))
        capsule(ImageDraw.Draw(im),tail,100-40*u)
        tuck=ease((amount-.14)/.8)
        for index,leg in enumerate(start_pose['legs']):
            hind=leg['hip'][0]<500
            hip=lerp(leg['hip'],(400,580) if hind else (650,530),tuck)
            joint=lerp(leg['joint'],(435,625) if hind else (620,610),tuck)
            ankle=lerp(leg['ankle'],(495+index*7,633) if hind else (590+index*7,637),tuck)
            draw_leg(im,hip,joint,ankle,leg['near'],1-.12*tuck)
        ImageDraw.Draw(im).ellipse((center[0]-rx,center[1]-ry,
            center[0]+rx,center[1]+ry),fill=255)
        _,head_layer=body_transform(master.size,(724,461),math.radians(76*u),
            (-156*u,13*u),(1-.22*u,1-.22*u))
        im=ImageChops.lighter(im,head_layer(head))
        im=ImageChops.subtract(im,head_layer(features))
        # A curled tail and tucked-paw marks make the ball's rotation readable at 20 pt.
        markings=Image.new('L',master.size)
        d=ImageDraw.Draw(markings)
        detail_opacity=round(255*ease((amount-.5)/.5))
        d.arc((center[0]-184,center[1]-184,center[0]+184,center[1]+184),
            135,292,fill=detail_opacity,width=17)
        d.arc((center[0]-31,center[1]+86,center[0]+42,center[1]+126),
            35,150,fill=detail_opacity,width=12)
        im=ImageChops.subtract(im,markings)
        return Image.blend(start,im,ease(amount/.2))

    ball=curl_frame(1)
    sheets={'idle':[master], 'walk':[], 'run':[], 'roll':[],
        'curl':[curl_frame(i/(CAT_CURL_FRAMES-1)) for i in range(CAT_CURL_FRAMES)]}
    metadata={name:{'master':'Cat/master-v3.png','headBox':[640,250,920,530]}
        for name in sheets}
    for name,running in [('walk',False),('run',True)]:
        poses=[]
        for index in range(CAT_FRAMES):
            frame,pose=gait_frame(index/CAT_FRAMES,running)
            sheets[name].append(frame)
            poses.append(pose)
        metadata[name].update({'method':'paired gallop with suspension and body stretch' if running
            else 'four-beat walk with planted paws and tail follow-through',
            'groundAnkle':726,'duty':.34 if running else .66,
            'stride':85 if running else 44,'poses':poses})
    for index in range(CAT_FRAMES):
        # A complete clockwise revolution of the already-curled body.
        frame=ball.rotate(-360*index/CAT_FRAMES,resample=Image.Resampling.BICUBIC,
            center=(520,515),fillcolor=0)
        sheets['roll'].append(frame)
    metadata['roll'].update({'method':'fully tucked circular body, paws and tail inside silhouette; clockwise rotation',
        'center':[520,515],'radius':235,'rotationDegrees':360,'posesAreCircular':True})
    metadata['curl'].update({'method':'head folds down, paws tuck into belly and tail wraps around body',
        'from':'run/frame-01','to':'roll/frame-01','reversible':True})
    metadata['idle']['method']='original standing pose'
    return sheets,metadata
