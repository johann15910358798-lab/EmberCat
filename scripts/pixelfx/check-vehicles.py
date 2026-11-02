#!/usr/bin/env python3
"""Check asset order, loop continuity, contact particles and preserved source art."""
import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT=Path(__file__).resolve().parents[2]
RES=ROOT/'Sources/EmberCat/Resources'
ARCHIVE=ROOT/'Artwork/Makima/PixelFX-Vehicles'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--report',type=Path)
args=parser.parse_args()
manifest=json.loads((ARCHIVE/'manifest.json').read_text())
assert (manifest['frames'],manifest['fps'],manifest['duration'])==(144,60,2.4)
for name,expected in manifest['dependenciesSHA256'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==expected,(name,'source changed')
report={'pass':True,'fps':60,'duration':2.4,'modes':{}}
for mode,data in manifest['modes'].items():
    config,render,poses=data['config'],data['render'],data['poses']
    folder=RES/'MenuBarPets/Makima/Modes'/mode
    assert len(poses)==144
    assert {p.name for p in folder.glob('*.png')}==set(render['sha256']),('extra or missing frames',mode)
    assert render['renderedEndpointMeanError']<0.05,(mode,'loop endpoint changed')
    assert len(render['dustVisibleAreaPoints'])==144
    assert min(render['dustVisibleAreaPoints'])>0.25,(mode,'dust disappears')
    for box in render['dustBounds']:
        assert box and box[0]>0 and box[2]<36*32,(mode,'dust clipped at canvas edge',box)
        assert box[1]>14*32 and box[3]<20*32,(mode,'dust reaches the face or leaves ground band',box)
    for i,row in enumerate(poses):
        assert len(row['particles'])>=3
        assert abs(row['contact'][1]-18.92)<1e-9
        assert abs(row['bodyY']*config['scale'])<.25,(mode,'excessive body movement')
        for p in row['particles']:
            assert all(math.isfinite(p[key]) for key in ['x','y','radius','opacity','age','life'])
            assert 0<=p['opacity']<=1 and 0<=p['age']<p['life']
            assert p['x']<=row['contact'][0]+1e-9
            assert p['y']>14 and p['y']<=row['contact'][1]
        previous={p['id']:p for p in poses[(i-1)%144]['particles']}
        for p in row['particles']:
            old=previous.get(p['id'])
            if old and p['age']>old['age']:
                assert p['x']<old['x'],(mode,'dust moves forward')
                assert p['age']-old['age']<1/60+1e-9
        if i:
            assert abs(row['bodyY']-poses[i-1]['bodyY'])*config['scale']<.06
    scales=[]
    for density,suffix in [(1,''),(2,'@2x')]:
        files=[folder/f'frame-{i+1:03d}{suffix}.png' for i in range(144)]
        assert sorted(files)==files,(mode,'nonchronological file order')
        frames=[]
        for file in files:
            assert hashlib.sha256(file.read_bytes()).hexdigest()==render['sha256'][file.name]
            image=Image.open(file)
            assert image.mode=='RGBA' and image.size==(36*density,20*density)
            assert all(pixel[:3]==(0,0,0) for pixel in image.get_flattened_data())
            alpha=image.getchannel('A')
            box=alpha.point(lambda a:255 if a>64 else 0).getbbox()
            assert box and box[0]>0 and box[2]<image.width and box[1]>0 and box[3]<=image.height
            assert any(4<a<251 for a in alpha.get_flattened_data()),(file,'missing antialiasing')
            frames.append(alpha)
        assert len({im.tobytes() for im in frames})==144,(mode,density,'duplicate frame')
        steps=[ImageStat.Stat(ImageChops.difference(a,b)).mean[0]
               for a,b in zip(frames,frames[1:]+frames[:1])]
        assert steps[-1]<=max(steps[:-1])*1.3+.05,(mode,density,'loop seam spike')
        original=[Image.open(ARCHIVE/'original'/mode/f'frame-{i+1:02d}{suffix}.png').getchannel('A')
                  for i in range(8)]
        old_steps=[ImageStat.Stat(ImageChops.difference(a,b)).mean[0]
                   for a,b in zip(original,original[1:]+original[:1])]
        assert max(steps)<max(old_steps)*.6,(mode,density,'large interframe jump')
        scales.append({'density':density,'distinctFrames':144,
                       'maximumMeanAlphaStep':max(steps),'originalMaximumMeanAlphaStep':max(old_steps),
                       'loopSeamMeanAlphaStep':steps[-1]})
    details=RES/'PetPreview/Makima'/mode.split('-',1)[1]
    assert {p.name for p in details.glob('*.png')}==set(render['previewSHA256'])
    for name,expected in render['previewSHA256'].items():
        path=details/name
        assert hashlib.sha256(path.read_bytes()).hexdigest()==expected
        image=Image.open(path)
        assert image.mode=='RGBA' and image.size==(576,320)
    report['modes'][mode]={'scales':scales,'dustAlwaysVisible':True,
        'minimumDustAreaPoints':min(render['dustVisibleAreaPoints']),
        'maximumDustAreaPoints':max(render['dustVisibleAreaPoints']),
        'renderedEndpointMeanError':render['renderedEndpointMeanError']}
if args.report:
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
