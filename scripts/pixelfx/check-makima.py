#!/usr/bin/env python3
"""Check motion, loop closure and rendered continuity of the PixelFX walk trial."""
import argparse
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--manifest',type=Path,default=ROOT/'Artwork/Makima/PixelFX-Walk/manifest.json')
parser.add_argument('--frames',type=Path,default=ROOT/'Sources/EmberCat/Resources/MenuBarPets/Makima/Modes/01-walk')
parser.add_argument('--report',type=Path)
args=parser.parse_args()
manifest=json.loads(args.manifest.read_text())
assert manifest['frames']==96 and manifest['duration']==1.6 and manifest['fps']==60
assert hashlib.sha256((ROOT/manifest['source']).read_bytes()).hexdigest()==manifest['sourceSHA256']
for name,digest in manifest['dependenciesSHA256'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,name
assert len(manifest['render']['sha256'])==192
assert {p.name for p in args.frames.glob('*.png')}==set(manifest['render']['sha256'])
for name,digest in manifest['render']['sha256'].items():
    assert hashlib.sha256((args.frames/name).read_bytes()).hexdigest()==digest,name

rig=manifest['rig'];poses=rig['poses'];measurements=rig['measurements']
assert len(poses)==96 and rig['seamError']<1e-10
largest_bone_error=0
support_slip=[]
for suffix,side in [('N','near'),('F','far')]:
    for row in poses:
        j=row['joints']
        for a,b,measurement in [('hip','knee','thigh'),('knee','ankle','shin'),('shoulder','elbow','upper'),('elbow','hand','fore')]:
            error=abs(math.dist(j[a+suffix],j[b+suffix])-measurements[measurement])
            largest_bone_error=max(largest_bone_error,error)
            assert error<1e-8,(row['phase'],suffix,a,error)
    planted=[row for row in poses if row[side]['support']]
    assert len(planted)>40
    assert max(abs(row['joints']['ankle'+suffix][1]+3) for row in planted)<1e-8
    velocity=2*rig['gait']['stride']/rig['gait']['duty']
    world=[row['joints']['ankle'+suffix][0]+velocity*row[side]['phase'] for row in planted]
    slip=max(world)-min(world);support_slip.append(slip)
    assert slip<1e-8,(suffix,'planted foot slides',slip)
    assert max(row[side]['lift'] for row in poses)>rig['gait']['lift']*.95

report={'pass':True,'frames':96,'fps':60,'duration':1.6,'maximumBoneLengthError':largest_bone_error,
    'supportFootSlip':support_slip,'exactRigLoopSeam':rig['seamError'],'images':[]}
for density,suffix in [(1,''),(2,'@2x')]:
    files=[args.frames/f'frame-{i+1:02d}{suffix}.png' for i in range(96)]
    images=[Image.open(p) for p in files]
    for path,im in zip(files,images):
        assert im.mode=='RGBA' and im.size==(36*density,20*density),path
        assert not any(any(c for c in pixel[:3]) for pixel in im.get_flattened_data()),path
        # Ignore the faint Lanczos halo when checking visible artwork bounds.
        box=im.getchannel('A').point(lambda a:255 if a>64 else 0).getbbox()
        assert box and box[0]>0 and box[1]>0 and box[2]<im.width and box[3]<=im.height,path
    alpha=[im.getchannel('A') for im in images]
    assert len({im.tobytes() for im in alpha})==96,('duplicate poses',density)
    steps=[ImageStat.Stat(ImageChops.difference(a,b)).mean[0] for a,b in zip(alpha,alpha[1:]+alpha[:1])]
    original=[Image.open(ROOT/'Artwork/Makima/PixelFX-Walk/original'/f'frame-{i+1:02d}{suffix}.png').getchannel('A') for i in range(8)]
    old_steps=[ImageStat.Stat(ImageChops.difference(a,b)).mean[0] for a,b in zip(original,original[1:]+original[:1])]
    assert max(steps)<max(old_steps)/3,('insufficient reduction in pose jumps',density,max(steps),max(old_steps))
    assert steps[-1]<=max(steps[:-1])*1.3+0.05,('visible loop seam',density)
    report['images'].append({'density':density,'distinctFrames':96,'maxMeanAlphaStep':max(steps),
        'originalMaxMeanAlphaStep':max(old_steps),'seamMeanAlphaStep':steps[-1]})
if args.report:
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
