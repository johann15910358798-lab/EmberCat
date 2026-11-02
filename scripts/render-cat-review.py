#!/usr/bin/env python3
"""Review GIFs/contact sheets from actual --export-cat-preview output.

No animation is synthesized here. GIFs sample the 60 Hz production export at
30 Hz with exact centisecond timing; the original PNG/trace retains every tick.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('frames', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
font_path = '/System/Library/Fonts/STHeiti Light.ttc'
fonts = {size: ImageFont.truetype(font_path, size) for size in (12, 14, 18, 24)}
background, foreground, muted = '#f2f1ed', '#242827', '#686f6b'
titles = {'idle': '站立', 'walk': '行走', 'run': '跑动', 'roll': '蜷成球滚动'}
palette = Image.new('P', (1, 1))
colors = [channel for i in range(240) for channel in [round(i * 255 / 239)] * 3]
for color in [background, foreground, muted, '#ffffff', '#e1e4df', '#39705a']:
    colors.extend(bytes.fromhex(color[1:]))
colors += [0] * (768 - len(colors))
palette.putpalette(colors)


def read_scene(name):
    folder = args.frames / name
    trace = json.loads((folder / 'trace.json').read_text())
    manifest = json.loads((folder / 'manifest.json').read_text())
    assert manifest['fps'] == 60 and len(trace) == round(manifest['duration'] * 60)
    return folder, trace, manifest


def paste(canvas, sprite, xy, factor):
    pic = sprite.resize((round(sprite.width * factor), round(sprite.height * factor)), Image.Resampling.NEAREST)
    canvas.paste(pic, xy, pic)


def encode(images, path, repeat=True):
    frames = [im.quantize(palette=palette, dither=Image.Dither.NONE) for im in images]
    duration = [30, 30, 40] * (len(frames) // 3) + [30, 30, 40][:len(frames) % 3]
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=duration,
        disposal=1, optimize=True, **({'loop': 0} if repeat else {}))
    check = Image.open(path)
    total = 0
    for index in range(check.n_frames):
        check.seek(index)
        total += check.info['duration']
    assert total == sum(duration)
    return {'frames': check.n_frames, 'durationMS': total, 'bytes': path.stat().st_size}


def scene_image(folder, row, title, duration):
    canvas = Image.new('RGB', (640, 326), background)
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 16), title, font=fonts[24], fill=foreground)
    draw.text((20, 51), '应用实际渲染 · 预览速度为模拟 · 原速播放', font=fonts[12], fill=muted)
    draw.rounded_rectangle((18, 82, 203, 239), radius=12, fill='white')
    draw.rounded_rectangle((215, 82, 622, 239), radius=12, fill='white')
    with Image.open(folder / row['file']) as sprite:
        paste(canvas, sprite, (75, 131), 1)
        paste(canvas, sprite, (310, 90), 3)
    draw.text((61, 210), '原始 2× 像素', font=fonts[12], fill=muted)
    draw.text((379, 210), '动作放大', font=fonts[12], fill=muted)
    draw.text((20, 257), row['title'], font=fonts[18], fill=foreground)
    draw.text((280, 257), f"{row['rawSpeed']:.1f} tok/s", font=fonts[18], fill=foreground)
    draw.text((20, 288), '收拢头、四肢与尾巴，整只猫变成球；减速后转正再展开。', font=fonts[12], fill=muted)
    draw.rectangle((20, 316, 620, 319), fill='#e1e4df')
    draw.rectangle((20, 316, 20 + 600 * row['time'] / duration, 319), fill='#39705a')
    return canvas


report = {'source': 'production-rendered PNG frames with isolated synthetic speed inputs', 'clips': {}}
for name, title in [('sequence', '胖黑猫 · 四种动作与完整过渡'), ('ramp', '胖黑猫 · 平滑加速与减速')]:
    folder, trace, manifest = read_scene(name)
    assert {row['gait'] for row in trace} == set(titles)
    assert {'curl', 'uncurl'} <= {row['transition']['kind'] for row in trace if 'transition' in row}
    path = args.output / f'cat-{name}.gif'
    report['clips'][path.name] = encode(
        (scene_image(folder, row, title, manifest['duration']) for row in trace[::2]), path)
    print(path, report['clips'][path.name], flush=True)

scenes = {gait: read_scene('actions/' + gait) for gait in titles}


def overview(index):
    canvas = Image.new('RGB', (640, 294), background)
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 14), '站立 · 行走 · 跑动 · 蜷球翻滚', font=fonts[24], fill=foreground)
    draw.text((18, 49), '同一只胖黑猫，四种独立动作 · 应用生产渲染', font=fonts[12], fill=muted)
    for column, (gait, (folder, trace, _)) in enumerate(scenes.items()):
        x = 12 + column * 158
        draw.rounded_rectangle((x, 78, x + 146, 277), radius=10, fill='white')
        draw.text((x + 12, 92), titles[gait], font=fonts[14], fill=foreground)
        with Image.open(folder / trace[index]['file']) as sprite:
            paste(canvas, sprite, (x + 1, 125), 2)
            paste(canvas, sprite, (x + 37, 213), 1)
    return canvas

report['clips']['cat-actions.gif'] = encode((overview(i) for i in range(0, 240, 2)),
    args.output / 'cat-actions.gif', repeat=False)
overview(0).save(args.output / 'cat-actions.png')

folder, trace, _ = read_scene('sequence')
contact = Image.new('RGB', (920, 380), background)
draw = ImageDraw.Draw(contact)
draw.text((18, 14), '真正收成球，再展开落地', font=fonts[24], fill=foreground)
for row_index, kind in enumerate(['curl', 'uncurl']):
    rows = [row for row in trace if row.get('transition', {}).get('kind') == kind]
    draw.text((18, 62 + 153 * row_index), '收拢 → 球形' if kind == 'curl' else '球形 → 展开',
        font=fonts[18], fill=foreground)
    for column, progress in enumerate([0, .2, .4, .6, .8, 1]):
        row = min(rows, key=lambda row: abs(row['transition']['progress'] - progress))
        with Image.open(folder / row['file']) as sprite:
            paste(contact, sprite, (12 + column * 150, 96 + row_index * 153), 2)
contact.save(args.output / 'cat-curl-contact.png')
(args.output / 'preview-check.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
print(json.dumps(report, ensure_ascii=False), flush=True)
