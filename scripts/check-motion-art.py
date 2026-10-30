#!/usr/bin/env python3
"""Check forward gait, coordinated body movement, and rendered loop continuity.

These are measurable motion/artifact checks, not a substitute for visual review.
"""
import json
import math
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT/'Sources/EmberCat/Resources/MenuBarPets'
metadata = json.loads((ROOT/'Artwork/derivation.json').read_text())
report = {'pass':True,'PNG':0,'loops':[]}
for path in RES.rglob('*.png'):
    density = 2 if '@2x' in path.name else 1
    with Image.open(path) as image:
        assert image.mode == 'RGBA' and image.size == (36*density,20*density),path
        box=image.getchannel('A').point(lambda a:255 if a>96 else 0).getbbox()
        assert box and box[1]>=0 and box[3]<=image.height,(path,box)
        if '/Transitions/' not in str(path):
            assert box[0]>0 and box[2]<image.width,(path,'steady pose touches canvas edge')
        assert all(pixel[:3]==(0,0,0) for pixel in image.get_flattened_data()),path
    report['PNG']+=1
assert report['PNG']==652
for name,sheet in metadata['sheets'].items():
    if 'rig' not in sheet: continue
    loop={'name':name,'frames':sheet['frames'],'scales':[]}
    for density in (1,2):
        paths=sorted((RES/name).glob('*@2x.png')) if density==2 else sorted(
            p for p in (RES/name).glob('*.png') if '@' not in p.name)
        frames=[Image.open(p).getchannel('A') for p in paths]
        head=sheet['logicalHeadBox']
        box=(math.ceil(head[0]*density),math.ceil(head[1]*density),
            math.floor(head[2]*density),math.floor(head[3]*density))
        head_variants=len({f.crop(box).tobytes() for f in frames})
        if 'poses' in sheet['rig']:
            assert head_variants>1,(name,density,'upper body is unnaturally frozen')
        diffs=[ImageStat.Stat(ImageChops.difference(a,b)).mean[0]
            for a,b in zip(frames,frames[1:]+frames[:1])]
        maximum=max(diffs[:-1])
        assert diffs[-1] <= maximum*1.3+0.05,(name,density,'loop-seam discontinuity')
        # A large spike catches dropped poses or unregistered artwork.
        limit=4.5 if name.endswith(('walk','brisk','run')) and name.startswith('Makima') else 1.2
        assert max(diffs)<=limit,(name,density,'abrupt pose change')
        loop['scales'].append({'density':density,'distinctHeadCrops':head_variants,
            'maxMeanAlphaStep':max(diffs),'seamMeanAlphaStep':diffs[-1]})
    rig=sheet['rig']
    if 'poses' in rig:
        poses=rig['poses']
        scale=sheet['scale']
        head=[p['head'] for p in poses]
        span=max(math.dist(a,b)*scale for a in head for b in head)
        steps=[math.dist(a,b)*scale for a,b in zip(head,head[1:]+head[:1])]
        assert .1<span<1.4,(name,'body is frozen or has excessive displacement',span)
        assert max(steps)<.3,(name,'abrupt head/shoulder movement',max(steps))
        legs=[]
        for leg in range(len(poses[0]['legs'])):
            samples=sorted((p['legs'][leg] for p in poses),key=lambda p:p['phase'])
            support=[p for p in samples if p['support']]
            swing=[p for p in samples if not p['support']]
            assert len(support)>4 and len(swing)>4,(name,'incomplete gait phases')
            assert all(abs(p['ankle'][1]-rig['groundAnkle'])<1e-8 for p in support),(
                name,'support foot slides vertically instead of planting')
            assert all(b['ankle'][0]<a['ankle'][0]
                for a,b in zip(support,support[1:])),(name,'backwards walking')
            # A translating body and the planted foot must agree on ground
            # velocity; this catches a grounded forward slide, the 0.6.0 bug.
            velocity=2*rig['stride']/rig['duty']
            world=[p['ankle'][0]+velocity*p['phase'] for p in support]
            assert max(world)-min(world)<1e-7,(name,'support foot slips on ground')
            assert swing[-1]['ankle'][0]>swing[0]['ankle'][0],(name,'swing foot recovers backwards')
            clearance=max(rig['groundAnkle']-p['ankle'][1] for p in swing)
            assert clearance*scale>.6,(name,'swing foot fails to clear ground')
            if 'legLengths' in rig:
                assert all(math.dist(p['hip'],p['ankle'])<=sum(rig['legLengths'])
                    for p in samples),(name,'unreachable leg pose')
            legs.append({'supportMovesBackward':True,'supportGroundSlip':max(world)-min(world),
                'swingMovesForward':True,'clearancePoints':clearance*scale})
        loop['gait']={'headTravelPoints':span,'maxHeadStepPoints':max(steps),'legs':legs}
    report['loops'].append(loop)
assert len(report['loops'])==1
# Protect the restoration contract: every original drawing at BOTH scales is
# identical to the 0.5.2 original-art release, rather than a new interpretation.
original=json.loads((ROOT/'Artwork/Makima/original-frame-sha256.json').read_text())
import hashlib
for name,digest in original['frames'].items():
    assert hashlib.sha256((RES/name).read_bytes()).hexdigest()==digest,(name,'original artwork changed')
assert len(original['frames'])==146
report['originalMakimaPNGRestoredExactly']=146
report['originalPoseCounts']={name:sheet['frames'] for name,sheet in metadata['sheets'].items()
    if name.startswith('Makima/Modes/')}
assert sorted(report['originalPoseCounts'].values())==[1]+[8]*9
registered=0
for name,sheet in metadata['sheets'].items():
    if '/Transitions/' not in name: continue
    start,end=name.rsplit('/',1)[1].split('_')
    source=metadata['sheets']['Makima/Modes/'+start]['headCenter']
    target=metadata['sheets']['Makima/Modes/'+end]['headCenter']
    assert len(sheet['keys'])==4
    for i,key in enumerate(sheet['keys']):
        amount=(i+1)/5
        assert all(abs(v-(a+(b-a)*amount))<1e-9
            for v,a,b in zip(key['headCenter'],source,target)),name
        assert key['scale']>0
    registered+=1
assert registered==45
report['registeredTransitionSets']=registered
if len(sys.argv)>1:
    Path(sys.argv[1]).write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'pass':True,'PNG':report['PNG'],'catLoops':1,
    'originalMakimaPNGRestoredExactly':146,'catBodyMovementBounded':True,
    'registeredTransitionSets':registered}))
