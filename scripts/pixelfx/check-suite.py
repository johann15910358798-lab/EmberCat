#!/usr/bin/env python3
"""Check full loops, joint contacts, source preservation and high-resolution transitions."""
import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image,ImageChops,ImageStat

ROOT=Path(__file__).resolve().parents[2]
RES=ROOT/'Sources/EmberCat/Resources'
ARCHIVE=ROOT/'Artwork/Makima/PixelFX-Suite'


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    manifest=json.loads((ARCHIVE/'manifest.json').read_text())
    assert manifest['fps']==60
    expected={'02-brisk':84,'03-run':72,'04-rollers':144,'05-board':144,'06-bicycle':144,'09-jetpack':144}
    assert {key:data['config']['frames'] for key,data in manifest['modes'].items()}==expected
    for name,value in manifest['dependenciesSHA256'].items():assert digest(ROOT/name)==value,(name,'source drift')
    report={'pass':True,'modes':{}}
    for mode,data in manifest['modes'].items():
        config,poses,render=data['config'],data['poses'],data['render'];count=config['frames']
        assert abs(count/config['duration']-60)<1e-9
        assert len(poses)==count and render['renderedEndpointMeanError']<.05,(mode,'open loop')
        bone_error=0
        if data['measurements']:
            for row in poses:
                j=row['joints']
                for side,key in [('N','near'),('F','far')]:
                    for a,b,length in [('hip','knee','thigh'),('knee','ankle','shin'),('shoulder','elbow','upper'),('elbow','hand','fore')]:
                        error=abs(math.dist(j[a+side],j[b+side])-data['measurements'][length])
                        bone_error=max(bone_error,error)
                    foot=row[key];offset=2 if mode=='04-rollers' else 0
                    assert abs(j['ankle'+side][0]-foot['x'])<1e-6,(mode,'unreachable foot')
                    assert abs(j['ankle'+side][1]+3+foot['lift']+offset)<1e-6,(mode,'foot not on authored path')
            assert bone_error<1e-8,(mode,'bone stretch')
        if mode in ['02-brisk','03-run']:
            for side,key in [('N','near'),('F','far')]:
                support=[row for row in poses if row[key]['support']]
                velocity=2*config['stride']/config['duty']
                world=[row['joints']['ankle'+side][0]+velocity*row[key]['phase'] for row in support]
                assert max(world)-min(world)<1e-7,(mode,'foot slips on ground')
            if mode=='03-run':assert any(not r['near']['support'] and not r['far']['support'] for r in poses),'run lacks flight phase'
        if mode=='05-board':
            assert max(math.dist(r['joints']['ankleN'],poses[0]['joints']['ankleN']) for r in poses)<1e-8,'board support foot moves'
            assert any(r['far']['support'] for r in poses) and max(r['far']['lift'] for r in poses)>3.8,'board has no push/recovery'
        if mode=='06-bicycle':
            for row in poses:
                near,far=row['legs']
                for i in (0,1):assert abs(near['pedal'][i]+far['pedal'][i]-2*config['crank'][i])<1e-8
                for leg in row['legs']:
                    assert abs(math.dist(leg['pedal'],config['crank'])-config['crankRadius'])<1e-8
                    assert abs(math.dist(leg['hip'],leg['knee'])-70)<1e-8
                    assert abs(math.dist(leg['knee'],leg['ankle'])-81)<1e-8
                    assert abs(leg['pedal'][0]-leg['ankle'][0]-8)<1e-8
                    assert abs(leg['pedal'][1]-leg['ankle'][1]-20)<1e-8
        if mode=='09-jetpack':
            assert max(r['bodyY'] for r in poses)-min(r['bodyY'] for r in poses)>7
            assert max(r['plumeLength'] for r in poses)-min(r['plumeLength'] for r in poses)>12
        if mode!='02-brisk':assert max(render['effectVisibleAreaPoints'])>.01,(mode,'effect invisible')
        folder=RES/'MenuBarPets/Makima/Modes'/mode
        assert {p.name for p in folder.glob('*.png')}==set(render['sha256']),(mode,'missing or stale frames')
        scales=[]
        for density,suffix in [(1,''),(2,'@2x')]:
            frames=[]
            for i in range(count):
                name=f'frame-{i+1:03d}{suffix}.png';path=folder/name
                assert digest(path)==render['sha256'][name]
                image=Image.open(path)
                assert image.mode=='RGBA' and image.size==(36*density,20*density)
                assert all(pixel[:3]==(0,0,0) for pixel in image.get_flattened_data())
                alpha=image.getchannel('A');box=alpha.point(lambda a:255 if a>64 else 0).getbbox()
                assert box and box[0]>0 and box[2]<image.width and box[1]>0 and box[3]<=image.height,(path,'clipped',box)
                assert any(4<a<251 for a in alpha.get_flattened_data()),(path,'no edge coverage')
                frames.append(alpha)
            distinct=len({im.tobytes() for im in frames})
            assert distinct==count,(mode,density,'duplicate rendered frames',distinct)
            steps=[ImageStat.Stat(ImageChops.difference(a,b)).mean[0] for a,b in zip(frames,frames[1:]+frames[:1])]
            old=[Image.open(ARCHIVE/'original'/mode/f'frame-{i+1:02d}{suffix}.png').getchannel('A') for i in range(8)]
            old_steps=[ImageStat.Stat(ImageChops.difference(a,b)).mean[0] for a,b in zip(old,old[1:]+old[:1])]
            assert max(steps)<max(old_steps)*.65,(mode,density,'large frame-to-frame jump',max(steps),max(old_steps))
            assert steps[-1]<=max(steps[:-1])*1.3+.05,(mode,density,'loop seam spike')
            scales.append({'density':density,'distinctFrames':distinct,'maxMeanAlphaStep':max(steps),
                'originalMaxMeanAlphaStep':max(old_steps),'seamMeanAlphaStep':steps[-1]})
        detail=RES/'PetPreview/Makima'/mode.split('-',1)[1]
        assert {p.name for p in detail.glob('*.png')}==set(render['previewSHA256'])
        for name,value in render['previewSHA256'].items():
            path=detail/name;assert digest(path)==value
            assert Image.open(path).size==(576,320)
        report['modes'][mode]={'scales':scales,'maximumBoneLengthError':bone_error,
            'exactRenderedLoopError':render['renderedEndpointMeanError']}
    transitions=ROOT/'Artwork/Makima/PixelFX-Transitions'
    tm=json.loads((transitions/'manifest.json').read_text())
    assert len(tm['pairs'])==45 and len(tm['renderSHA256'])==360 and len(tm['previewSHA256'])==180
    assert len(tm['originalSHA256'])==360
    for key in ['dependenciesSHA256','sourceSHA256']:
        for name,value in tm[key].items():assert digest(ROOT/name)==value,(name,'transition source drift')
    for key,folder in [('renderSHA256',RES/'MenuBarPets/Makima/Transitions'),
                       ('previewSHA256',RES/'PetPreview/Makima/transitions'),
                       ('originalSHA256',transitions/'original')]:
        for name,value in tm[key].items():assert digest(folder/name)==value,(name,'transition provenance mismatch')
    assert digest(RES/'PetPreview/Makima/idle/frame-01.png')==tm['idlePreviewSHA256']
    report['transitions']={'pairs':45,'directions':90,'detailKeys':180,'preservedOriginalPNGs':360}
    if args.report:args.report.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__':main()
