#!/usr/bin/env python3
"""Build a portable full-suite review from the installed menu and detail assets."""
import argparse
import base64
import json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from vehicle_art import ink,export_image

ROOT=Path(__file__).resolve().parents[2]
RES=ROOT/'Sources/EmberCat/Resources'
MODES=['idle','walk','brisk','run','rollers','board','bicycle','motorcycle','roadster','jetpack']
TITLES=['待机','走路','快走','跑步','轮滑','滑板','自行车','摩托车','敞篷跑车','飞行背包']
DESCRIPTIONS=['停止时保持原来的待机画面。','落地支撑、摆臂与辫子随动。',
    '加大步幅与摆臂，脚掌落地后向后推。','跑步带腾空和更高的抬腿，落地时出现少量尘粒。',
    '两腿交替蹬地、收腿滑行，轮毂持续转动。','一脚站稳滑板，另一脚蹬地、收回后滑行。',
    '双脚沿相反方向的曲柄踩踏，车轮、身体和辫子一起运动。',
    '转轮、悬挂起伏与后轮接地点扬尘。','转轮、悬挂起伏与后轮接地点扬尘。',
    '悬停起伏、腿部随动、连续喷流与逐渐散开的尾迹。']


def urls(folder,pattern='*.png'):
    return ['data:image/png;base64,'+base64.b64encode(path.read_bytes()).decode() for path in sorted(folder.glob(pattern))]


def reference(mode,index,out,meta):
    source=Image.open(ROOT/'Artwork/Makima/Modes'/(mode+'.png'))
    count=1 if index==0 else 8;scale=meta['scale']
    # Original images use their saved historical registration, not the new rig's.
    if index in [1,2,3,4,5,6,7,8,9]:
        crops=[ink(source.crop(((i%4)*384,(i//4)*512,(i%4+1)*384,(i//4+1)*512))) for i in range(8)]
    else:crops=[ink(source)]
    boxes=[im.point(lambda a:255 if a>64 else 0).getbbox() for im in crops]
    scale=min(33.5/max(b[2]-b[0] for b in boxes),18.1/max(b[3]-b[1] for b in boxes))
    out.mkdir(parents=True,exist_ok=True)
    for i,(mask,box) in enumerate(zip(crops,boxes)):
        baseline=18.0 if index==9 else 19.0
        alpha=mask.transform((1152,640),Image.Transform.AFFINE,
            (1/(scale*32),0,(box[0]+box[2])/2-18/scale,0,1/(scale*32),box[3]-baseline/scale),Image.Resampling.BICUBIC)
        export_image(alpha,(576,320)).save(out/f'frame-{i+1:02d}.png')
    return count


def page(out):
    meta=json.loads((ROOT/'Artwork/derivation.json').read_text())
    data={'modes':{},'transitions':{}}
    for index,name in enumerate(MODES):
        mode=f'{index:02d}-{name}';metadata=meta['sheets']['Makima/Modes/'+mode]
        if index==0:original=RES/'MenuBarPets/Makima/Modes'/mode
        elif index==1:original=ROOT/'Artwork/Makima/PixelFX-Walk/original'
        elif index in [7,8]:original=ROOT/'Artwork/Makima/PixelFX-Vehicles/original'/mode
        else:original=ROOT/'Artwork/Makima/PixelFX-Suite/original'/mode
        reference(mode,index,out/'original-detail'/mode,metadata)
        data['modes'][mode]={'title':TITLES[index],'description':DESCRIPTIONS[index],
            'frames':metadata['frames'],'duration':{1:1.6,2:1.4,3:1.2}.get(index,2.4),
            'speed':[0,3,12,24,36,50,67.6,91,125,185][index],
            'large':urls(RES/'PetPreview/Makima'/name),
            'small':urls(RES/'MenuBarPets/Makima/Modes'/mode,'*@2x.png'),
            'oldLarge':urls(out/'original-detail'/mode),'oldSmall':urls(original,'*@2x.png')}
        assert len(data['modes'][mode]['large'])==metadata['frames']
    for folder in sorted((RES/'PetPreview/Makima/transitions').iterdir()):
        if not folder.is_dir():continue
        data['transitions'][folder.name]={'large':urls(folder),
            'small':urls(RES/'MenuBarPets/Makima/Transitions'/folder.name,'*@2x.png')}
    template=Path(__file__).with_name('suite-review.html').read_text()
    (out/'comparison.html').write_text(template.replace('__FRAMES__',json.dumps(data,ensure_ascii=False)))


def make_gif(out):
    font_path='/System/Library/Fonts/STHeiti Light.ttc'
    title_font=ImageFont.truetype(font_path,22);font=ImageFont.truetype(font_path,16);small=ImageFont.truetype(font_path,11)
    frames={name:[Image.open(path).copy() for path in sorted((RES/'PetPreview/Makima'/name).glob('*.png'))] for name in MODES[1:]}
    # One shared grayscale palette avoids temporal color/edge quantization.
    palette=Image.new('P',(1,1));colors=[]
    for i in range(250):colors.extend([i,i,i])
    for color in [(244,243,239),(39,45,42),(105,113,107),(255,254,250),(216,220,212),(55,100,81)]:colors.extend(color)
    palette.putpalette(colors)
    def card(i):
        im=Image.new('RGB',(900,782),'#f4f3ef');d=ImageDraw.Draw(im)
        d.text((24,16),'玛奇玛 · 九种连续动作',font=title_font,fill='#272d2a')
        d.text((24,49),'人物原画派生 · 各自原速播放 · 下方小图为 36 × 20 实际尺寸',font=small,fill='#69716b')
        for cell,name in enumerate(MODES[1:]):
            x=12+cell%3*296;y=78+cell//3*228
            d.rounded_rectangle((x,y,x+284,y+218),radius=10,fill='#fffefa',outline='#d8dcd4')
            index=cell+1;duration={1:1.6,2:1.4,3:1.2}.get(index,2.4)
            frame=frames[name][int((i/30%duration)/duration*len(frames[name]))%len(frames[name])]
            d.text((x+13,y+9),TITLES[index],font=font,fill='#272d2a')
            large=frame.resize((270,150),Image.Resampling.LANCZOS);im.paste(large,(x+7,y+34),large)
            actual=frame.resize((36,20),Image.Resampling.LANCZOS);im.paste(actual,(x+16,y+190),actual)
            d.text((x+75,y+192),f'{len(frames[name])} 帧 · {duration:g} 秒',font=small,fill='#69716b')
        d.text((24,765),'30 fps 查看副本；完整 60 fps 与上下车过渡请打开整套预览。',font=small,fill='#69716b')
        return im
    card(0).save(out/'all-actions.png')
    cards=(card(i).quantize(palette=palette,dither=Image.Dither.NONE) for i in range(288))
    first=next(cards)
    # Different loop periods share no short common seam. Play this 9.6 s
    # overview once instead of adding an artificial jump to the brisk walk.
    first.save(out/'all-actions.gif',save_all=True,append_images=cards,
        duration=[round((i+1)*100/30)*10-round(i*100/30)*10 for i in range(288)],disposal=1,optimize=True)


def transition_gif(out):
    source=out/'native-transitions';manifest_path=source/'manifest.json'
    if not manifest_path.exists():return
    data=json.loads(manifest_path.read_text())
    chosen=[next(s for s in data['scenes'] if s['from']==a and s['to']==b) for a,b in
        [('01-walk','06-bicycle'),('06-bicycle','01-walk'),('08-roadster','09-jetpack'),('09-jetpack','00-idle')]]
    font=ImageFont.truetype('/System/Library/Fonts/STHeiti Light.ttc',18)
    cards=[]
    for scene in chosen:
        for row in scene['frames'][::2]:
            im=Image.new('RGB',(720,440),'#f4f3ef');d=ImageDraw.Draw(im)
            d.text((26,20),scene['title']+'  ·  应用实际渲染',font=font,fill='#272d2a')
            pic=Image.open(source/scene['name']/'detail'/row['file']);im.paste(pic,(72,60),pic)
            actual=Image.open(source/scene['name']/'actual'/row['file']).resize((36,20),Image.Resampling.LANCZOS)
            im.paste(actual,(342,390),actual)
            cards.append(im)
    cards[0].save(out/'transitions.gif',save_all=True,append_images=cards[1:],
        duration=[round((i+1)*100/30)*10-round(i*100/30)*10 for i in range(len(cards))],loop=0,disposal=2)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--out',type=Path,default=ROOT/'work/makima-suite')
    parser.add_argument('--transitions-only',action='store_true');args=parser.parse_args();args.out.mkdir(parents=True,exist_ok=True)
    if not args.transitions_only:page(args.out);make_gif(args.out)
    transition_gif(args.out)
    print(args.out/'comparison.html')


if __name__=='__main__':main()
