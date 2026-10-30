#!/usr/bin/env python3
"""Build complete review GIFs from the app's production-rendered PNG export.

Pillow only. No sprites are reanimated here. The moving ground is an explicitly
labelled review guide; it is not part of the menu-bar resources.
"""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont

parser=argparse.ArgumentParser()
parser.add_argument('frames',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
frames=args.frames;out=args.output;out.mkdir(parents=True,exist_ok=True)
cadence=frames/'cadence'
report=json.loads((cadence/'trace.json').read_text())
scenes={s['name']:s for s in report['scenes']}
trace=json.loads((frames/'trace.json').read_text())
manifest=json.loads((frames/'manifest.json').read_text())
font='/System/Library/Fonts/STHeiti Light.ttc'
large=ImageFont.truetype(font,23)
normal=ImageFont.truetype(font,16)
small=ImageFont.truetype(font,12)
bg='#f2efe8';ink='#252b28';muted='#6d786f';dark='#242c27';green='#388063'

# A single grayscale palette keeps animation alpha edges consistent from frame
# to frame, instead of independently quantizing each image's moving silhouette.
palette=Image.new('P',(1,1))
colors=[]
for i in range(224):
    c=round(i*255/223);colors.extend([c,c,c])
for h in [bg,ink,muted,dark,green,'#ffffff','#e4e8e1','#94b6a3']:
    colors.extend(bytes.fromhex(h[1:]))
colors+=([0,0,0]*(256-len(colors)//3))
palette.putpalette(colors)


def sprite(scene,index,side='low'):
    return Image.open(cadence/scene['name']/scene['frames'][index][side]).convert('RGBA')


def paste(canvas,im,xy,factor=1,white=False):
    if white:
        layer=Image.new('RGBA',im.size,'white');layer.putalpha(im.getchannel('A'));im=layer
    im=im.resize((round(im.width*factor),round(im.height*factor)),Image.Resampling.NEAREST)
    canvas.paste(im,xy,im)


def encode(images,path,count,repeat=True):
    def indexed():
        for im in images:
            yield im.quantize(palette=palette,dither=Image.Dither.NONE)
    sequence=indexed();first=next(sequence)
    durations=[40 if i%3==2 else 30 for i in range(count)]
    first.save(path,save_all=True,append_images=sequence,duration=durations,
        optimize=True,disposal=1,**({'loop':0} if repeat else {}))
    check=Image.open(path);total=0
    for i in range(check.n_frames):
        check.seek(i);total+=check.info['duration']
    assert total==sum(durations),(path,total,sum(durations))
    return {'frames':check.n_frames,'durationMS':total,'bytes':path.stat().st_size}


order=['cat-idle','cat']+[f'{i:02d}-{name}' for i,name in enumerate(
    ['idle','walk','brisk','run','rollers','board','bicycle','motorcycle','roadster','jetpack'])]


def overview(index):
    im=Image.new('RGB',(780,838),bg);d=ImageDraw.Draw(im)
    d.text((18,12),'玛奇玛 · 原画动作恢复',font=large,fill=ink)
    d.text((18,47),'0.6.2  ·  完整黑白原画姿势  ·  黑猫保持原样  ·  tok/s 不倍速',font=small,fill=muted)
    for cell,key in enumerate(order):
        x=14+cell%3*256;y=77+cell//3*180;scene=scenes[key]
        d.rounded_rectangle((x,y,x+242,y+167),radius=12,fill='white')
        d.text((x+12,y+10),scene['title'],font=normal,fill=ink)
        pic=sprite(scene,index)
        paste(im,pic,(x+49,y+39),2)
        paste(im,pic,(x+18,y+122))
        d.text((x+104,y+137),'实际像素尺寸',font=small,fill=muted)
    d.text((18,807),'原画版恢复预览 · 各动作完整播放多圈 · 本版未合入自动补帧',font=small,fill=muted)
    return im



chapters=manifest['chapters']
mode_keys=manifest['allModes']
mode_titles={k:scenes[k]['title'] for k in mode_keys}


def sequential(row):
    im=Image.new('RGB',(720,364),bg);d=ImageDraw.Draw(im)
    time=row['time']
    chapter=max(i for i,c in enumerate(chapters) if c['start']<=time+1e-6)
    mode=row['mode'];active=row.get('transition')
    d.text((20,12),'完整动作与过渡 · 连续演示',font=large,fill=ink)
    d.text((20,46),'0.6.2  ·  应用生产渲染器 + 模拟输入  ·  原速播放，保留等待和过渡',font=small,fill=muted)
    d.rounded_rectangle((18,72,246,248),radius=12,fill='white')
    d.rounded_rectangle((260,72,702,248),radius=12,fill=dark)
    pic=Image.open(frames/row['file']).convert('RGBA')
    paste(im,pic,(96,132))
    paste(im,pic,(362,93),3.3,True)
    d.text((73,222),'菜单栏实际像素尺寸',font=small,fill=muted)
    d.text((281,222),'动作放大查看',font=small,fill='#e4e8e1')
    d.text((20,262),row['title'],font=normal,fill=ink)
    d.text((310,262),f"输入 {row['rawSpeed']:g} tok/s",font=normal,fill=ink)
    d.text((563,262),f'{time:05.1f} / {manifest["duration"]:g}s',font=small,fill=muted)
    for i,key in enumerate(mode_keys):
        x=20+i*69
        selected=key==(active['to'] if active else mode)
        d.rounded_rectangle((x,295,x+64,320),radius=5,fill=green if selected else '#e4e8e1')
        label=mode_titles[key]
        use_font=small
        tx=x+(64-d.textlength(label,font=use_font))/2
        d.text((tx,301),label,font=use_font,fill='white' if selected else muted)
    hint='依次完整演示全部动作' if chapter<10 else '落地、上下车和非相邻切换：3 → 70 → 3 → 185 → 0'
    d.text((20,334),hint,font=small,fill=muted)
    d.rectangle((20,356,700,359),fill='#e4e8e1')
    d.rectangle((20,356,20+680*time/manifest['duration'],359),fill=green)
    return im


# Coverage is evaluated from rendered states, not just requested speeds.
coverage={}
for key in mode_keys:
    segments=[];start=None
    for i,row in enumerate(trace):
        stable=row['mode']==key and 'transition' not in row
        if stable and start is None:start=i
        if start is not None and (not stable or i==len(trace)-1):
            end=i if not stable else i+1
            segments.append((start/30,end/30));start=None
    longest=max((b-a for a,b in segments),default=0)
    required=2*scenes[key]['cycleDuration'] if key!='00-idle' else 2.4
    assert longest>=required,(key,longest,required)
    coverage[key]={'longestStableSeconds':longest,'requiredSeconds':required,'segments':segments}
transitions=[]
for row in trace:
    tr=row.get('transition')
    if tr and (not transitions or transitions[-1]['from']!=tr['from'] or transitions[-1]['to']!=tr['to']):
        transitions.append({'time':row['time'],'from':tr['from'],'to':tr['to']})
for a,b in [('01-walk','06-bicycle'),('06-bicycle','01-walk'),('01-walk','09-jetpack'),('09-jetpack','00-idle')]:
    assert any(t['from']==a and t['to']==b for t in transitions),(a,b)
comparisons=0
for scene in report['scenes']:
    for row in scene['frames']:
        assert (cadence/scene['name']/row['low']).read_bytes()==(cadence/scene['name']/row['high']).read_bytes()
        comparisons+=1
clips={}
for name,fn,count in [('all-actions-0.6.2.gif',overview,288)]:
    clips[name]=encode((fn(i) for i in range(count)),out/name,count,repeat=False)
    fn(0).save(out/name.replace('.gif','.png'))
    print(name,clips[name],flush=True)
name='complete-demo-0.6.2.gif'
clips[name]=encode((sequential(row) for row in trace),out/name,len(trace),repeat=True)
sequential(trace[0]).save(out/'complete-demo-0.6.2.png')
print(name,clips[name],flush=True)

# Keep a concise chronological contact sheet of real transition composites.
contact=Image.new('RGB',(960,650),bg);d=ImageDraw.Draw(contact)
d.text((15,10),'直接过渡 · 实际合成帧',font=large,fill=ink)
chosen=[t for t in transitions if (t['from'],t['to']) in [
    ('01-walk','06-bicycle'),('06-bicycle','01-walk'),
    ('01-walk','09-jetpack'),('09-jetpack','00-idle')]][-4:]
for row,t in enumerate(chosen):
    y=58+row*145
    d.text((15,y),f'{mode_titles[t["from"]]} → {mode_titles[t["to"]]}',font=normal,fill=ink)
    start=round(t['time']*30)
    for col,offset in enumerate([0,5,10,15,20,25]):
        pic=Image.open(frames/trace[min(start+offset,len(trace)-1)]['file']).convert('RGBA')
        paste(contact,pic,(16+col*158,y+30),2)
contact.save(out/'transition-contact-0.6.2.png')
qa={'version':'0.6.2','source':'application production renderer; simulated speed inputs',
    'fps':30,'allModesCovered':coverage,'directTransitions':transitions,
    'lowHighFrameComparisons':comparisons,'clips':clips}
(out/'preview-qa-0.6.2.json').write_text(json.dumps(qa,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({'coverage':len(coverage),'lowHighIdentical':comparisons,'clips':clips}),flush=True)
