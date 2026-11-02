#!/usr/bin/env python3
"""Register authored transition poses against the new loops at all three sizes."""
import hashlib
import importlib.util
import json
import shutil
import sys
from pathlib import Path

from PIL import Image
from vehicle_art import ink,export_image

ROOT=Path(__file__).resolve().parents[2]
RES=ROOT/'Sources/EmberCat/Resources'
ARCHIVE=ROOT/'Artwork/Makima/PixelFX-Transitions'
sys.path.insert(0,str(ROOT/'scripts'))
spec=importlib.util.spec_from_file_location('prepare_pets',ROOT/'scripts/prepare-pets.py')
prepare=importlib.util.module_from_spec(spec);spec.loader.exec_module(prepare)


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def split(path):
    mask=ink(Image.open(path))
    middle=prepare.blank_gutter(mask,1,mask.height//2)
    result=[]
    for top,bottom in ((0,middle),(middle,mask.height)):
        row=mask.crop((0,top,mask.width,bottom))
        divider=prepare.blank_gutter(row,0,row.width//2)
        result.extend([row.crop((0,0,divider,row.height)),row.crop((divider,0,row.width,row.height))])
    return result


def main():
    meta_path=ROOT/'Artwork/derivation.json';meta=json.loads(meta_path.read_text())
    ARCHIVE.mkdir(parents=True,exist_ok=True)
    old_path=ARCHIVE/'manifest.json'
    originals=json.loads(old_path.read_text())['originalSHA256'] if old_path.exists() else {}
    manifest={'fps':60,'duration':0.8,'keyframesPerPair':4,'originalSHA256':originals,
        'method':'Authored boarding poses; crown registration from continuous loops; live 60 Hz smooth blending',
        'sourceSHA256':{},'renderSHA256':{},'previewSHA256':{},'pairs':{}}
    # The idle detail comes from the full source image, preserving the original
    # menu resource and stopped timer behavior.
    idle=ink(Image.open(ROOT/'Artwork/Makima/Modes/00-idle.png'))
    box=prepare.bounds(idle);scale=meta['sheets']['Makima/Modes/00-idle']['scale']
    alpha=idle.transform((1152,640),Image.Transform.AFFINE,
        (1/(scale*32),0,(box[0]+box[2])/2-18/scale,0,1/(scale*32),box[3]-19/scale),Image.Resampling.BICUBIC)
    detail=RES/'PetPreview/Makima/idle';detail.mkdir(parents=True,exist_ok=True)
    export_image(alpha,(576,320)).save(detail/'frame-01.png',optimize=True)
    manifest['idlePreviewSHA256']=digest(detail/'frame-01.png')
    # Measure the actual installed artwork, including the earlier walk/vehicle
    # studies. Their old source-sheet landmarks no longer describe every rig.
    registrations={}
    for name,sheet in meta['sheets'].items():
        if not name.startswith('Makima/Modes/'):continue
        mode=name.rsplit('/',1)[1]
        paths=sorted((RES/'PetPreview/Makima'/mode.split('-',1)[1]).glob('*.png'))
        landmarks=[prepare.head_landmark(Image.open(path).getchannel('A'))
            for path in paths[::max(1,len(paths)//12)]]
        assert landmarks,('missing detail loop',mode)
        center=[sum(p[i] for p in landmarks)/len(landmarks)/16 for i in (0,1)]
        width=sum(p[2] for p in landmarks)/len(landmarks)/16
        sheet.update(headCenter=center,headWidth=width,headRegistration='Measured from the installed high-resolution continuous loop')
        registrations[mode]={'headCenter':center,'headWidth':width}
    manifest['registrations']=registrations
    for file in sorted((ROOT/'Artwork/Makima/Transitions').glob('[0-9][0-9]-*_[0-9][0-9]-*.png')):
        key=file.stem;start,end=key.split('_')
        source=meta['sheets']['Makima/Modes/'+start];target=meta['sheets']['Makima/Modes/'+end]
        relative='Makima/Transitions/'+key
        folder=RES/'MenuBarPets'/relative
        backup=ARCHIVE/'original'/key;backup.mkdir(parents=True,exist_ok=True)
        for old in folder.glob('*.png'):
            name=key+'/'+old.name;path=backup/old.name
            if not path.exists():shutil.copy2(old,path)
            if name not in originals:originals[name]=digest(path)
            assert digest(path)==originals[name]
        preview=RES/'PetPreview/Makima/transitions'/key;preview.mkdir(parents=True,exist_ok=True)
        rows=[]
        for i,mask in enumerate(split(file)):
            amount=(i+1)/5
            center=[a+(b-a)*amount for a,b in zip(source['headCenter'],target['headCenter'])]
            width=source['headWidth']+(target['headWidth']-source['headWidth'])*amount
            hx,hy,hw=prepare.head_landmark(mask);box=prepare.bounds(mask)
            scale=min(width/hw,(center[1]-.7)/(hy-box[1]),(19.4-center[1])/(box[3]-hy))
            alpha=mask.transform((1152,640),Image.Transform.AFFINE,
                (1/(scale*32),0,hx-center[0]/scale,0,1/(scale*32),hy-center[1]/scale),Image.Resampling.BICUBIC)
            for density,suffix in [(1,''),(2,'@2x')]:
                name=f'frame-{i+1:02d}{suffix}.png';path=folder/name
                export_image(alpha,(36*density,20*density)).save(path,optimize=True)
                manifest['renderSHA256'][key+'/'+name]=digest(path)
                meta['outputSHA256'][relative+'/'+name]=digest(path)
            name=f'frame-{i+1:02d}.png';path=preview/name
            export_image(alpha,(576,320)).save(path,optimize=True)
            manifest['previewSHA256'][key+'/'+name]=digest(path)
            rows.append({'sourceBounds':box,'headCenter':center,'scale':scale,
                'hairCapWidth':hw,'renderedHairCapWidth':hw*scale,'requestedHairCapWidth':width,
                'vehicleMayEnterFromCanvasEdge':True})
        meta['sheets'][relative].update(frames=4,keys=rows,
            registration='New continuous-loop crown registration; 32x sampling and full-resolution preview')
        manifest['pairs'][key]={'from':start,'to':end,'keys':rows}
        manifest['sourceSHA256'][str(file.relative_to(ROOT))]=digest(file)
    dependencies=['scripts/pixelfx/render-transitions.py','scripts/prepare-pets.py',
        'scripts/pixelfx/vehicle_art.py','Artwork/Makima/Modes/00-idle.png',
        'Artwork/Makima/PixelFX-Walk/manifest.json','Artwork/Makima/PixelFX-Vehicles/manifest.json',
        'Artwork/Makima/PixelFX-Suite/manifest.json']
    manifest['dependenciesSHA256']={name:digest(ROOT/name) for name in dependencies}
    old_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    meta_path.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'pairs':len(manifest['pairs']),'directions':2*len(manifest['pairs']),
        'highResolutionKeys':len(manifest['previewSHA256'])}))


if __name__=='__main__':main()
