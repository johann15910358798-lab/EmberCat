"""Continuous clothing contours around authored side-view poses.

The source head, braid and shirt retain the character's identity. Limbs are
connected contours, not independent rectangular/polygonal scraps of a photo.
"""
import math

import numpy as np
from PIL import Image, ImageChops, ImageDraw

from makima_design import ART_SCALE, ART_SIZE, Drawing, cutouts, rigid

INK = '#121212'


def path(draw, commands, fill=INK, outline=None, width=2):
    points = []
    current = None
    for command in commands:
        if command[0] in ('M', 'L'):
            current = np.asarray(command[1:3], dtype=float)
            points.append(current)
        elif command[0] == 'C':
            a, b, end = [np.asarray(command[i:i+2], dtype=float) for i in (1,3,5)]
            start = current
            for u in np.linspace(0,1,13)[1:]:
                points.append((1-u)**3*start+3*(1-u)**2*u*a+3*(1-u)*u*u*b+u**3*end)
            current = end
    pixels = [tuple(p*ART_SCALE) for p in points]
    draw.polygon(pixels, fill=fill)
    if outline:
        draw.line(pixels+[pixels[0]], fill=outline, width=round(width*ART_SCALE), joint='curve')


def line(draw, points, fill=INK, width=2):
    draw.line([tuple(np.asarray(p)*ART_SCALE) for p in points],
              fill=fill,width=max(1,round(width*ART_SCALE)),joint='curve')


def ellipse(draw, center, radius, fill, outline=None, width=2):
    c=np.asarray(center);r=np.asarray(radius)
    draw.ellipse(tuple((c-r)*ART_SCALE)+tuple((c+r)*ART_SCALE),
                 fill=fill,outline=outline,width=max(1,round(width*ART_SCALE)))


def contour(draw,a,b,c,widths,fill,outline=None):
    a,b,c=[np.asarray(p,dtype=float) for p in (a,b,c)]
    v1=(b-a)/np.linalg.norm(b-a);v2=(c-b)/np.linalg.norm(c-b)
    n1=np.array([-v1[1],v1[0]]);n2=np.array([-v2[1],v2[0]])
    middle=n1+n2;middle/=np.linalg.norm(middle)
    middle*=min(1.25,1/max(.5,float(np.dot(middle,n1))))
    r1,r2,r3=widths
    left=[a+n1*r1,b+middle*r2,c+n2*r3]
    right=[a-n1*r1,b-middle*r2,c-n2*r3]
    commands=[('M',*left[0])]
    for points in [left,right[::-1]]:
        if points is not left:commands.append(('L',*points[0]))
        for i in range(2):
            start,end=points[i],points[i+1]
            # Keep the bones straight; only round the join next to the elbow/knee.
            control1=start+(end-start)*.42
            control2=end-(end-start)*.22
            if i==0:control2=end-(v1 if points is left else -v2)*8
            if i==1:control1=start+(v2 if points is left else -v1)*8
            commands.append(('C',*control1,*control2,*end))
    commands.append(('C',*(right[0]-v1*r1*.9),*(left[0]-v1*r1*.9),*left[0]))
    path(draw,commands,fill,outline,1.8)


def transformed(commands,origin,angle):
    a=math.radians(angle);c,s=math.cos(a),math.sin(a)
    result=[]
    for command in commands:
        points=[]
        for x,y in zip(command[1::2],command[2::2]):
            points.extend([origin[0]+c*x-s*y,origin[1]+s*x+c*y])
        result.append((command[0],*points))
    return result


def draw_shoe(draw,ankle,angle):
    # A narrow sock/cuff connects directly to the trouser leg.
    path(draw,transformed([('M',-7,-12),('L',7,-12),('L',8,9),('L',-8,9)],ankle,angle),
         'white',INK,1.5)
    shoe=[('M',-12,1),('C',-7,-1,-2,0,3,5),('L',12,14),
          ('C',20,16,32,13,39,11),('C',45,10,47,16,43,21),
          ('C',37,26,15,26,-11,26),('L',-14,22),('L',-14,10),
          ('C',-14,6,-13,3,-12,1)]
    path(draw,transformed(shoe,ankle,angle),INK)
    sole=transformed([('M',-11,21),('L',5,22),('L',25,21),('L',39,18)],ankle,angle)
    line(draw,[(p[1],p[2]) for p in sole],fill='white',width=1.3)
    lace=transformed([('M',7,12),('L',12,10),('M',11,15),('L',16,13)],ankle,angle)
    for i in (0,2):line(draw,[(p[1],p[2]) for p in lace[i:i+2]],fill='white',width=1.4)


def draw_skate(draw,ankle,angle,wheel_angle):
    boot=[('M',-11,-10),('L',8,-10),('L',9,3),('C',13,8,27,9,35,11),
          ('C',40,12,42,16,39,19),('L',-13,19),('C',-15,12,-14,-1,-11,-10)]
    path(draw,transformed(boot,ankle,angle),INK)
    for y in [-3,5]:
        strap=transformed([('M',-10,y),('L',9,y+2)],ankle,angle)
        line(draw,[(p[1],p[2]) for p in strap],fill='white',width=2)
    for x in [-7,13,33]:
        center=transformed([('M',x,26)],ankle,angle)[0][1:]
        ellipse(draw,center,7,INK)
        ellipse(draw,center,3.5,'white')
        a=wheel_angle+x*.01
        line(draw,[center,np.asarray(center)+[2.8*math.cos(a),2.8*math.sin(a)]],width=1.5)


def draw_board(draw,angle):
    deck=[('M',136,430),('C',146,434,151,437,165,438),('L',282,438),
          ('C',294,437,300,434,310,430),('C',313,429,315,432,312,436),
          ('C',305,442,294,444,281,444),('L',165,444),
          ('C',150,443,141,440,136,436),('C',133,434,133,431,136,430)]
    path(draw,deck,INK)
    line(draw,[(146,435),(164,440),(283,440),(302,435)],fill='white',width=1.5)
    for x in [162,286]:
        line(draw,[(x,442),(x,450)],width=4)
        ellipse(draw,(x,451),9,INK)
        ellipse(draw,(x,451),4.5,'white')
        line(draw,[(x,451),(x+3.7*math.cos(angle),451+3.7*math.sin(angle))],width=2)


def draw_pose(row):
    parts=cutouts()
    j={name:np.array([213+p[0]*10,460-p[1]*10]) for name,p in row['joints'].items()}
    result=Image.new('RGBA',ART_SIZE,(255,255,255,0));draw=ImageDraw.Draw(result)
    if row['mode']=='05-board':draw_board(draw,row['wheelAngle'])

    def leg(side,key):
        ankle,knee,hip=[j[name+side] for name in ['ankle','knee','hip']]
        f=row[key]
        if row['mode']=='04-rollers':draw_skate(draw,ankle,f['pitch'],row['wheelAngle'])
        else:draw_shoe(draw,ankle,f['pitch'])
        cuff=ankle+(knee-ankle)/np.linalg.norm(knee-ankle)*10
        contour(draw,hip,knee,cuff,(19,14,11),INK)
        # One small crease, instead of a white seam across a detached joint.
        direction=(ankle-knee)/np.linalg.norm(ankle-knee)
        normal=np.array([-direction[1],direction[0]])
        if side=='N':line(draw,[knee+normal*7-direction*1,knee+normal*3+direction*4],
                           fill='white',width=1.15)

    leg('F','far');leg('N','near')
    pelvis=j['pelvis'];near=j['hipN'];far=j['hipF']
    path(draw,[('M',pelvis[0]-24,pelvis[1]-5),('L',pelvis[0]+23,pelvis[1]-2),
               ('C',far[0]+23,far[1]+2,far[0]+17,far[1]+15,far[0]+9,far[1]+18),
               ('L',near[0]-12,near[1]+17),
               ('C',near[0]-21,near[1]+8,pelvis[0]-25,pelvis[1]+5,pelvis[0]-24,pelvis[1]-5)])

    def arm(side):
        shoulder,elbow,hand=[j[name+side] for name in ['shoulder','elbow','hand']]
        direction=(hand-elbow)/np.linalg.norm(hand-elbow)
        cuff=hand-direction*10
        contour(draw,shoulder,elbow,cuff,(10.5,8.2,7), 'white',INK)
        normal=np.array([-direction[1],direction[0]])
        line(draw,[cuff-direction*5-normal*6,cuff-direction*5+normal*6],width=1.4)
        center=hand-direction*1
        angle=math.degrees(math.atan2(direction[1],direction[0]))-90
        fist=[('M',-6,-8),('C',-9,-4,-9,4,-5,8),('C',0,11,7,8,8,2),
              ('C',9,-4,5,-8,-1,-8),('L',-6,-8)]
        path(draw,transformed(fist,center,angle),'white',INK,1.8)

    arm('F')
    result.alpha_composite(rigid(parts['torso'],(209,279),j['pelvis'],row['bodyAngle']))
    arm('N')
    neck=j['neck'];angle=row['headAngle']
    braid=rigid(parts['braid'],(157,177),(157,177),row['braidAngle'])
    result.alpha_composite(rigid(braid,(213,203),neck,angle))
    result.alpha_composite(rigid(parts['head'],(213,203),neck,angle))
    return result


def draw_gait(row):
    return Drawing(draw_pose(row))
