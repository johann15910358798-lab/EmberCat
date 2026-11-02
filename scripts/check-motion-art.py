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
assert report['PNG']==3252
cat_sheets={name:sheet for name,sheet in metadata['sheets'].items() if name.startswith('Cat/')}
assert {name:sheet['frames'] for name,sheet in cat_sheets.items()}=={
    'Cat/idle':1,'Cat/walk':96,'Cat/run':96,'Cat/roll':96,'Cat/curl':40}
assert len({(s['scale'],tuple(s['fixedEnvelope'])) for s in cat_sheets.values()})==1,(
    'Cat actions must share one scale, registration and ground line')
for name,sheet in metadata['sheets'].items():
    if 'rig' not in sheet or name.endswith(('/idle','/curl')): continue
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
        limit={'Cat/walk':1.4,'Cat/run':2.6,'Cat/roll':1.3}[name]
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
assert len(report['loops'])==3
roll=cat_sheets['Cat/roll']
for box in roll['bounds']:
    assert .98<(box[2]-box[0])/(box[3]-box[1])<1.02,('rolling body is not a circle',box)
    assert abs((box[0]+box[2])/2-520)<=1 and abs((box[1]+box[3])/2-515)<=1,(
        'rolling ball wobbles around its rotation center',box)
curl_checks=[]
for suffix in ('','@2x'):
    curl_paths=sorted((RES/'Cat/curl').glob(f'*{suffix}.png')) if suffix else sorted(
        p for p in (RES/'Cat/curl').glob('*.png') if '@' not in p.name)
    frames=[Image.open(p).getchannel('A') for p in curl_paths]
    assert (RES/f'Cat/curl/frame-01{suffix}.png').read_bytes()==(RES/f'Cat/run/frame-01{suffix}.png').read_bytes()
    assert (RES/f'Cat/curl/frame-40{suffix}.png').read_bytes()==(RES/f'Cat/roll/frame-01{suffix}.png').read_bytes()
    steps=[ImageStat.Stat(ImageChops.difference(a,b)).mean[0] for a,b in zip(frames,frames[1:])]
    assert max(steps)<5.6,('abrupt curl pose change',suffix,max(steps))
    rolling=sorted((RES/'Cat/roll').glob('*@2x.png')) if suffix else sorted(
        p for p in (RES/'Cat/roll').glob('*.png') if '@' not in p.name)
    assert len({Image.open(p).getchannel('A').tobytes() for p in rolling})==96,(
        'ball has no visible turning detail')
    curl_checks.append({'density':2 if suffix else 1,'maxMeanAlphaStep':max(steps),
        'exactRunAndBallEndpoints':True,'distinctRollingFrames':96})
report['curl']=curl_checks
report['roundBallBounds']=True
# Every animated mode preserves its original PNGs in reference folders.
# The static idle still uses its original menu images byte for byte.
original=json.loads((ROOT/'Artwork/Makima/original-frame-sha256.json').read_text())
import hashlib
preserved_runtime=0
preserved_reference=0
references={
    '01-walk':ROOT/'Artwork/Makima/PixelFX-Walk/original',
    '07-motorcycle':ROOT/'Artwork/Makima/PixelFX-Vehicles/original/07-motorcycle',
    '08-roadster':ROOT/'Artwork/Makima/PixelFX-Vehicles/original/08-roadster'}
references.update({mode:ROOT/'Artwork/Makima/PixelFX-Suite/original'/mode for mode in
    ['02-brisk','03-run','04-rollers','05-board','06-bicycle','09-jetpack']})
for name,digest in original['frames'].items():
    mode=Path(name).parent.name
    if mode in references:
        path=references[mode]/Path(name).name
        preserved_reference+=1
    else:
        path=RES/name
        preserved_runtime+=1
    assert hashlib.sha256(path.read_bytes()).hexdigest()==digest,(name,'original artwork changed')
assert len(original['frames'])==146
assert (preserved_runtime,preserved_reference)==(2,144)
trial=json.loads((ROOT/'Artwork/Makima/PixelFX-Walk/manifest.json').read_text())
assert trial['frames']==96 and trial['fps']==60 and trial['duration']==1.6
assert len(trial['render']['sha256'])==192
for name,digest in trial['render']['sha256'].items():
    assert hashlib.sha256((RES/'Makima/Modes/01-walk'/name).read_bytes()).hexdigest()==digest,(name,'trial provenance mismatch')
report['originalMakimaRuntimePNGsUnchanged']=preserved_runtime
report['originalReferencePNGsUnchanged']=preserved_reference
report['originalPoseCounts']={name:sheet['frames'] for name,sheet in metadata['sheets'].items()
    if name.startswith('Makima/Modes/')}
assert sorted(report['originalPoseCounts'].values())==[1,72,84,96]+[144]*6
vehicles=json.loads((ROOT/'Artwork/Makima/PixelFX-Vehicles/manifest.json').read_text())
for mode,data in vehicles['modes'].items():
    assert len(data['render']['sha256'])==288
    for name,digest in data['render']['sha256'].items():
        path=RES/'Makima/Modes'/mode/name
        assert hashlib.sha256(path.read_bytes()).hexdigest()==digest,(path,'vehicle provenance mismatch')
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
print(json.dumps({'pass':True,'PNG':report['PNG'],'catLoops':3,'roundBall':True,'curlEndpointsExact':True,
    'originalMakimaRuntimePNGsUnchanged':2,'originalReferencePNGsUnchanged':144,
    'pixelfxWalkFrames':96,'pixelfxVehicleFramesPerMode':144,'catBodyMovementBounded':True,
    'registeredTransitionSets':registered}))
