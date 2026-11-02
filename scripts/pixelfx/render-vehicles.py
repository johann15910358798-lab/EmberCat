#!/usr/bin/env python3
"""Generate 60 Hz vehicle loops with contact dust from the preserved Makima art."""
import argparse
import base64
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat

from vehicle_art import ART_SCALE, SAMPLING, draw_vehicle, export_image, ink, register

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT/'Sources/EmberCat/Resources'
ARCHIVE = ROOT/'Artwork/Makima/PixelFX-Vehicles'
TITLES = {'07-motorcycle': '摩托车', '08-roadster': '敞篷跑车'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reference(mode, config, output):
    """Use the high-resolution source sheet for enlarged old/new comparisons."""
    folder = output/'original-detail'
    folder.mkdir(parents=True,exist_ok=True)
    source = Image.open(ROOT/'Artwork/Makima/Modes'/(mode+'.png'))
    for i in range(8):
        alpha = ink(source.crop(((i%4)*384,(i//4)*512,(i%4+1)*384,(i//4+1)*512)))
        box = alpha.point(lambda a: 255 if a>64 else 0).getbbox()
        registration = dict(config,bounds=box)
        alpha = alpha.resize((384*ART_SCALE,512*ART_SCALE),Image.Resampling.LANCZOS)
        export_image(register(alpha,registration),(576,320)).save(folder/f'frame-{i+1:02d}.png')


def export_mode(mode, data, output):
    for name in ['frames','detail']:
        (output/name).mkdir(parents=True,exist_ok=True)
    hashes, detail_hashes, dust_mass, body_bounds, dust_bounds = {}, {}, [], [], []
    sampled = []
    for i,row in enumerate(data['poses']):
        combined, body, dust = draw_vehicle(mode,data['config'],row)
        for density,suffix in [(1,''),(2,'@2x')]:
            path = output/'frames'/f'frame-{i+1:03d}{suffix}.png'
            export_image(combined,(36*density,20*density)).save(path,optimize=True)
            hashes[path.name] = digest(path)
        path = output/'detail'/f'frame-{i+1:03d}.png'
        export_image(combined,(576,320)).save(path,optimize=True)
        detail_hashes[path.name] = digest(path)
        dust_mass.append(ImageStat.Stat(dust).sum[0]/(SAMPLING*SAMPLING*255))
        dust_bounds.append(dust.point(lambda a: 255 if a>16 else 0).getbbox())
        body_bounds.append(body.point(lambda a: 255 if a>64 else 0).getbbox())
        if i in [0,24,48,72,96,120]:
            sampled.append(export_image(combined,(432,240)))
        if i == 0:
            first = combined
    endpoint = draw_vehicle(mode,data['config'],data['endpoint'])[0]
    seam = ImageStat.Stat(ImageChops.difference(first,endpoint)).mean[0]
    sheet = Image.new('RGB',(432*3,264*2),'#f4f3ef')
    draw = ImageDraw.Draw(sheet)
    for i,im in enumerate(sampled):
        xy = ((i%3)*432,(i//3)*264)
        sheet.paste(im,(xy[0],xy[1]+24),im)
        draw.text((xy[0]+14,xy[1]+7),f'{i*24+1:03d} / 144',fill='#37413f')
    sheet.save(output/'contact.png')
    reference(mode,data['config'],output)
    return {'sha256':hashes,'previewSHA256':detail_hashes,
            'dustVisibleAreaPoints':dust_mass,'bodyBounds':body_bounds,'dustBounds':dust_bounds,
            'renderedEndpointMeanError':seam}


def original_files(mode):
    archive = ARCHIVE/'original'/mode
    return archive if archive.is_dir() else RES/'MenuBarPets/Makima/Modes'/mode


def review_page(output):
    def urls(folder,pattern):
        return ['data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()
                for p in sorted(folder.glob(pattern))]
    data = {}
    for mode in TITLES:
        folder = output/mode
        data[mode] = {
            'title':TITLES[mode],
            'old':urls(original_files(mode),'*@2x.png'),
            'oldLarge':urls(folder/'original-detail','*.png'),
            'new':urls(folder/'frames','*@2x.png'),
            'newLarge':urls(folder/'detail','*.png'),
        }
        assert [len(data[mode][key]) for key in ['old','oldLarge','new','newLarge']]==[8,8,144,144]
    template = Path(__file__).with_name('vehicle-review.html').read_text()
    (output/'comparison.html').write_text(template.replace('__FRAMES__',json.dumps(data,ensure_ascii=False)))


def make_gif(output):
    font_path = Path('/System/Library/Fonts/PingFang.ttc')
    if not font_path.is_file():
        font_path = Path('/System/Library/Fonts/STHeiti Light.ttc')
    font = ImageFont.truetype(str(font_path),18) if font_path.is_file() else ImageFont.load_default()
    old = {mode:[Image.open(p).copy() for p in sorted((output/mode/'original-detail').glob('*.png'))]
           for mode in TITLES}
    new = {mode:[Image.open(p).copy() for p in sorted((output/mode/'detail').glob('*.png'))]
           for mode in TITLES}
    cards=[]
    for i in range(72):
        card=Image.new('RGB',(960,600),'#f4f3ef')
        draw=ImageDraw.Draw(card)
        for row,mode in enumerate(TITLES):
            for col,(title,frame) in enumerate([
                    ('原版',old[mode][int(i/72*8)]),('转轮 · 起伏 · 扬尘',new[mode][i*2])]):
                x,y=col*480,row*300
                draw.text((x+25,y+16),TITLES[mode]+'  /  '+title,font=font,fill='#37413f')
                im=frame.resize((432,240),Image.Resampling.LANCZOS)
                card.paste(im,(x+24,y+46),im)
        cards.append(card)
    durations=[round((i+1)*240/72)*10-round(i*240/72)*10 for i in range(72)]
    cards[0].save(output/'comparison.gif',save_all=True,append_images=cards[1:],
                  duration=durations,loop=0,disposal=2)
    cards[0].save(output/'comparison.png')


def install(output,manifest):
    original = json.loads((ROOT/'Artwork/Makima/original-frame-sha256.json').read_text())['frames']
    meta_path=ROOT/'Artwork/derivation.json'
    meta=json.loads(meta_path.read_text())
    for mode,data in manifest['modes'].items():
        relative='Makima/Modes/'+mode
        target=RES/'MenuBarPets'/relative
        archive=ARCHIVE/'original'/mode
        archive.mkdir(parents=True,exist_ok=True)
        for name,expected in original.items():
            if not name.startswith(relative+'/'):
                continue
            reference_path=archive/Path(name).name
            if not reference_path.exists():
                source=RES/'MenuBarPets'/name
                assert digest(source)==expected,('original missing or modified',source)
                shutil.copy2(source,reference_path)
            assert digest(reference_path)==expected
        for old in target.glob('*.png'):
            old.unlink()
        for path in (output/mode/'frames').glob('*.png'):
            shutil.copy2(path,target/path.name)
        detail=RES/'PetPreview/Makima'/mode.split('-',1)[1]
        detail.mkdir(parents=True,exist_ok=True)
        for old in detail.glob('*.png'):
            old.unlink()
        for path in (output/mode/'detail').glob('*.png'):
            shutil.copy2(path,detail/path.name)
        meta['sheets'][relative].update(
            frames=144,source=manifest['generator'],
            pixelfx='Makima/PixelFX-Vehicles/manifest.json',
            headRegistration='Original source registration retained; transitions use their existing keyframes')
        meta['outputSHA256']={name:value for name,value in meta['outputSHA256'].items()
                              if not name.startswith(relative+'/')}
        meta['outputSHA256'].update({relative+'/'+name:value for name,value in data['render']['sha256'].items()})
        shutil.copy2(output/mode/'contact.png',ARCHIVE/(mode+'-contact.png'))
    shutil.copy2(output/'manifest.json',ARCHIVE/'manifest.json')
    meta_path.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'work/makima-vehicles')
    parser.add_argument('--node',default='node')
    parser.add_argument('--install',action='store_true')
    args=parser.parse_args()
    args.out.mkdir(parents=True,exist_ok=True)
    motion=json.loads(subprocess.check_output([args.node,str(Path(__file__).with_name('makima-vehicles.mjs'))]))
    dependencies=['scripts/pixelfx/vehicle-design.json','scripts/pixelfx/makima-vehicles.mjs',
        'scripts/pixelfx/vehicle_art.py','scripts/pixelfx/render-vehicles.py','Vendor/PixelFX/core/math.js']
    dependencies += ['Artwork/Makima/Modes/'+mode+'.png' for mode in TITLES]
    manifest=dict(motion,generator='Preserved Makima vehicle art + PixelFX deterministic contact particles',
        upstreamCommit='a84159688af3ca37a4be05a0d422b94451b2e24e',
        dependenciesSHA256={name:digest(ROOT/name) for name in dependencies})
    for mode,data in motion['modes'].items():
        print('Rendering '+mode,flush=True)
        manifest['modes'][mode]['render']=export_mode(mode,data,args.out/mode)
    (args.out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    review_page(args.out)
    make_gif(args.out)
    if args.install:
        install(args.out,manifest)
    print(json.dumps({'framesPerMode':144,'fps':60,'duration':2.4,'out':str(args.out)}))


if __name__=='__main__':
    main()
