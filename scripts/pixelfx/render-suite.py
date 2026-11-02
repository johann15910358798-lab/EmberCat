#!/usr/bin/env python3
"""Render the remaining six continuous actions from preserved character artwork."""
import argparse
import hashlib
import json
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image,ImageDraw,ImageStat,ImageChops

from makima_design import cat_foot_samples,SCALE,SAMPLING
from suite_art import render,export_image

ROOT=Path(__file__).resolve().parents[2]
RES=ROOT/'Sources/EmberCat/Resources'
ARCHIVE=ROOT/'Artwork/Makima/PixelFX-Suite'
DESIGNS=json.loads(Path(__file__).with_name('suite-design.json').read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def motion(node):
    samples={mode:cat_foot_samples(config['frames'],config['stride'],config['lift'],config['duty'])
        for mode,config in DESIGNS.items() if 'stride' in config}
    return json.loads(subprocess.check_output([node,str(Path(__file__).with_name('makima-suite.mjs'))],
        input=json.dumps(samples),text=True))


def export_mode(mode,data,output,draft):
    config=data['config'];count=config['frames']
    output.mkdir(parents=True,exist_ok=True)
    selected=sorted({round(i*count/12)%count for i in range(12)})
    indices=selected if draft else range(count)
    frames,detail=output/'frames',output/'detail'
    for folder in [frames,detail]:folder.mkdir(parents=True,exist_ok=True)
    hashes,preview_hashes,bounds,effects,head_centers,head_widths={},{},[],[],[],[]
    cards=[]
    for i in indices:
        combined,body,fx=render(mode,config,data['poses'][i])
        box=body.point(lambda a:255 if a>64 else 0).getbbox()
        bounds.append(box)
        # The crown, before the braid joins the silhouette, gives a stable
        # registration landmark for the authored getting-on/off transition art.
        top,height=box[1],box[3]-box[1]
        cap=body.crop((0,round(top+height*.04),body.width,round(top+height*.14)))
        cap_box=cap.point(lambda a:255 if a>64 else 0).getbbox()
        hw=cap_box[2]-cap_box[0]
        head_centers.append([(cap_box[0]+cap_box[2])/2/SAMPLING,(top+hw*.55)/SAMPLING])
        head_widths.append(hw/SAMPLING)
        effects.append(ImageStat.Stat(fx).sum[0]/(SAMPLING*SAMPLING*255))
        if not draft:
            for density,suffix in [(1,''),(2,'@2x')]:
                path=frames/f'frame-{i+1:03d}{suffix}.png'
                export_image(combined,(36*density,20*density)).save(path,optimize=True)
                hashes[path.name]=digest(path)
            path=detail/f'frame-{i+1:03d}.png'
            export_image(combined,(576,320)).save(path,optimize=True)
            preview_hashes[path.name]=digest(path)
        if i in selected:cards.append((i,export_image(combined,(324,180))))
        if i==0:first=combined
        if not draft and (i+1)%36==0: print(f'{mode}: {i+1}/{count}',flush=True)
    sheet=Image.new('RGB',(324*4,204*3),'#f4f3ef');d=ImageDraw.Draw(sheet)
    for cell,(index,im) in enumerate(cards):
        x,y=cell%4*324,cell//4*204
        sheet.paste(im,(x,y+24),im)
        d.text((x+12,y+7),f'{mode}  {index+1:03d} / {count}',fill='#37413f')
    sheet.save(output/'contact.png')
    endpoint=render(mode,config,data['endpoint'])[0]
    return dict(sha256=hashes,previewSHA256=preview_hashes,bodyBounds=bounds,
        effectVisibleAreaPoints=effects,
        renderedEndpointMeanError=ImageStat.Stat(ImageChops.difference(first,endpoint)).mean[0],
        headCenter=[sum(p[i] for p in head_centers)/len(head_centers) for i in (0,1)],
        headWidth=sum(head_widths)/len(head_widths),sampling=SAMPLING)


def install(out,manifest):
    original=json.loads((ROOT/'Artwork/Makima/original-frame-sha256.json').read_text())['frames']
    meta_path=ROOT/'Artwork/derivation.json';meta=json.loads(meta_path.read_text())
    for mode,data in manifest['modes'].items():
        relative='Makima/Modes/'+mode;target=RES/'MenuBarPets'/relative
        archive=ARCHIVE/'original'/mode;archive.mkdir(parents=True,exist_ok=True)
        for name,expected in original.items():
            if not name.startswith(relative+'/'):continue
            backup=archive/Path(name).name
            if not backup.exists():
                source=RES/'MenuBarPets'/name
                assert digest(source)==expected,('original source differs',source)
                shutil.copy2(source,backup)
            assert digest(backup)==expected
        target.mkdir(parents=True,exist_ok=True)
        for path in target.glob('*.png'):path.unlink()
        for path in (out/mode/'frames').glob('*.png'):shutil.copy2(path,target/path.name)
        detail=RES/'PetPreview/Makima'/mode.split('-',1)[1];detail.mkdir(parents=True,exist_ok=True)
        for path in detail.glob('*.png'):path.unlink()
        for path in (out/mode/'detail').glob('*.png'):shutil.copy2(path,detail/path.name)
        meta['sheets'][relative].update(frames=data['config']['frames'],source=manifest['generator'],
            pixelfx='Makima/PixelFX-Suite/manifest.json',
            scale=data['config'].get('scale',SCALE),bounds=data['render']['bodyBounds'],
            headCenter=data['render']['headCenter'],headWidth=data['render']['headWidth'],
            headRegistration='Mean rendered crown registration, continuous source-art rig')
        meta['outputSHA256']={name:value for name,value in meta['outputSHA256'].items() if not name.startswith(relative+'/')}
        meta['outputSHA256'].update({relative+'/'+name:value for name,value in data['render']['sha256'].items()})
        shutil.copy2(out/mode/'contact.png',ARCHIVE/(mode+'-contact.png'))
    shutil.copy2(out/'manifest.json',ARCHIVE/'manifest.json')
    meta_path.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'work/makima-suite')
    parser.add_argument('--node',default='node')
    parser.add_argument('--install',action='store_true')
    parser.add_argument('--draft',action='store_true')
    args=parser.parse_args()
    if args.draft and args.install:parser.error('Draft frames cannot be installed')
    out=args.out/('draft' if args.draft else '')
    out.mkdir(parents=True,exist_ok=True)
    data=motion(args.node)
    dependencies=['scripts/pixelfx/suite-design.json','scripts/pixelfx/makima-suite.mjs',
        'scripts/pixelfx/suite_art.py','scripts/pixelfx/render-suite.py','scripts/pixelfx/makima_design.py',
        'scripts/pixelfx/vehicle_art.py','scripts/motion_rigs.py',
        'Vendor/PixelFX/core/rig.js','Vendor/PixelFX/core/math.js']
    dependencies += ['Artwork/Makima/Modes/'+mode+'.png' for mode in ['01-walk',*DESIGNS]]
    manifest=dict(data,generator='Source-art skinning + shared cat foot_path + PixelFX skeleton and deterministic effects',
        upstreamCommit='a84159688af3ca37a4be05a0d422b94451b2e24e',
        dependenciesSHA256={name:digest(ROOT/name) for name in dependencies})
    # Independent mode folders can render concurrently; installation and the
    # shared provenance document are updated only after every export succeeds.
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs={mode:pool.submit(export_mode,mode,row,out/mode,args.draft)
            for mode,row in data['modes'].items()}
        for mode,job in jobs.items():
            manifest['modes'][mode]['render']=job.result()
            print('Completed '+mode,flush=True)
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    if args.install:install(out,manifest)
    print(json.dumps({'modes':len(data['modes']),'fps':60,'draft':args.draft,'out':str(out)}))


if __name__=='__main__':main()
