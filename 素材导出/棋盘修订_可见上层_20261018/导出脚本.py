#!/usr/bin/env python3
"""仅拆分本轮棋盘快照；保持原像素、原图透明度，记录图层及画布坐标。"""
import argparse
import csv
import hashlib
import json
import struct
import zlib
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SOURCE = Path('/Users/Zhuanz/Downloads/棋盘(修订).aseprite')
LAYER_NAMES = {
 1:'桌面木纹背景',4:'英雄信息蓝色占位底板',5:'英雄技能灰色方块占位',6:'英雄信息金色手写占位',
 9:'英雄头像外圆占位',10:'英雄头像内圆占位',11:'英雄信息角落灰圆占位',13:'英雄信息角落白圆占位',
 14:'斜向蓝色桌布',17:'右侧资源托盘底框',18:'右侧资源托盘把手',21:'右侧资源蜂窝网格',22:'左侧资源托盘含网格',
 24:'左侧法术托盘底框',26:'左侧法术分类按钮',29:'法术状态彩色槽',32:'左侧法术托盘把手',33:'左侧法术托盘分隔线',
 35:'右侧法术托盘底框与分隔线',36:'右侧法术分类按钮',39:'战场底色补边',40:'战场外框底板',
 43:'层数与天数进度槽',44:'层数与天数已亮进度点',45:'FLOOR与DAY文字',46:'战场金色包角',47:'战场中线进度条',
 50:'中线眼睛标记',56:'四排战场底板',59:'生命与金币数值槽',60:'护盾生命金币图标',69:'指示物托盘',76:'月亮星星太阳图标',
 90:'收藏书外框与书脊',91:'收藏书空白分页标签',92:'收藏分类图案标签',93:'收藏搜索框',94:'元素筛选图标',95:'品级筛选图标',
 96:'收藏蓝色书签上下段',97:'收藏书浅色内页',99:'火枪手卡牌排版示例',102:'贴纸工具箱左右面板',103:'贴纸工具箱右侧格子',
 139:'战斗开始按钮底板',140:'战斗开始双剑图标',217:'下方蓝衣英雄俯视像',218:'上方蓝衣英雄俯视像_画布内部分',
}


def parse_source(path):
    data = path.read_bytes()
    total, magic, frames, width, height, depth = struct.unpack_from('<I5H', data)
    assert total == len(data) and magic == 0xA5E0 and frames == 1 and depth == 32
    assert (width, height) == (1320, 1240), '此脚本的人工拆分坐标仅对应当前1320×1240快照'
    flags = struct.unpack_from('<I', data, 14)[0]
    assert flags == 1, '当前只支持本文件使用的普通图层合成语义'
    frame_size, frame_magic, old_count = struct.unpack_from('<IHH', data, 128)
    assert frame_magic == 0xF1FA and frame_size + 128 == len(data)
    count = struct.unpack_from('<I', data, 140)[0] or old_count
    pos = 144
    layers, cels, ancestors = [], {}, []
    for _ in range(count):
        size, kind = struct.unpack_from('<IH', data, pos)
        assert size >= 6 and pos + size <= len(data)
        raw = data[pos + 6:pos + size]
        if kind == 0x2004:
            layer_flags, layer_type, level = struct.unpack_from('<HHH', raw)
            length = struct.unpack_from('<H', raw, 16)[0]
            name = raw[18:18 + length].decode('utf-8')
            while len(ancestors) > level:
                ancestors.pop()
            assert len(ancestors) == level
            layer = dict(index=len(layers), name=name, type=layer_type, level=level,
                         own_visible=bool(layer_flags & 1), parents=ancestors.copy(),
                         effective_visible=bool(layer_flags & 1) and all(layers[i]['effective_visible'] for i in ancestors),
                         opacity=raw[12], blend=struct.unpack_from('<H', raw, 10)[0])
            layers.append(layer)
            layer['path'] = '/'.join(layers[i]['name'] for i in layer['parents'] + [layer['index']])
            if layer_type == 1:
                ancestors.append(layer['index'])
        elif kind == 0x2005:
            index, x, y, opacity, cel_type = struct.unpack_from('<HhhBH', raw)
            assert cel_type == 2 and struct.unpack_from('<h', raw, 9)[0] == 0
            w, h = struct.unpack_from('<HH', raw, 16)
            pixels = zlib.decompress(raw[20:])
            assert len(pixels) == w * h * 4
            cels[index] = dict(x=x, y=y, opacity=opacity, image=Image.frombytes('RGBA', (w, h), pixels))
        pos += size
    assert pos == len(data)
    return data, width, height, layers, cels


def export(source):
    source_bytes, width, height, layers, cels = parse_source(source)
    visible = [layer for layer in layers if layer['effective_visible'] and layer['index'] in cels]
    images = {}
    for layer in visible:
        cel = cels[layer['index']]
        assert layer['blend'] == 0 and layer['opacity'] == cel['opacity'] == 255
        canvas = Image.new('RGBA', (width, height))
        canvas.paste(cel['image'], (cel['x'], cel['y']))
        images[layer['index']] = canvas
        layer['cel_rect'] = [cel['x'], cel['y'], cel['image'].width, cel['image'].height]
        layer['canvas_bounds'] = canvas.getbbox()
    # 从上到下计算实际可见贡献；完全被覆盖的可见图层也不进入本次素材输出。
    transmission = Image.new('L', (width, height), 255)
    contributions = {}
    for layer in reversed(visible):
        alpha = images[layer['index']].getchannel('A')
        contribution = ImageChops.multiply(alpha, transmission)
        contributions[layer['index']] = contribution
        layer['visible_pixel_count'] = sum(contribution.histogram()[1:])
        layer['visible_bounds'] = contribution.getbbox()
        transmission = ImageChops.multiply(transmission, ImageChops.invert(alpha))
    contributing = [layer for layer in visible if layer['visible_pixel_count'] > 0]

    def composite(ids):
        result = Image.new('RGBA', (width, height))
        for index in sorted(ids):
            assert index in images, f'图层{index}当前并不可见'
            result = Image.alpha_composite(result, images[index])
        return result

    flattened = composite(list(images))
    native_path = ROOT / '00_当前可见合成.png'
    assert native_path.exists(), '先用Aseprite原生批处理导出可见合成图到00_当前可见合成.png'
    native = Image.open(native_path).convert('RGBA')
    assert ImageChops.difference(native, flattened).getbbox(alpha_only=False) is None, '合成与Aseprite原生导出不一致'
    layer_dir = ROOT / '图层来源'
    layer_dir.mkdir(exist_ok=True)
    for layer in contributing:
        index = layer['index']
        name = LAYER_NAMES[index]
        file = layer_dir / f'L{index:03d}_{name}.png'
        images[index].crop(layer['canvas_bounds']).save(file)
        layer['export_path'] = file.relative_to(ROOT).as_posix()

    assets, by_digest = [], {}

    def asset(category, name, ids, rect=None, note='', deduplicate=False):
        image = composite(ids)
        if rect is None:
            box = image.getbbox()
        else:
            x, y, w, h = rect
            box = (x, y, x + w, y + h)
            local = image.crop(box).getbbox()
            assert local, f'{name}没有像素'
            box = (x + local[0], y + local[1], x + local[2], y + local[3])
        assert box
        if not any(contributions[index].crop(box).getbbox() for index in ids):
            return None  # 某组件整体被上层遮住时，不作为当前可见素材导出。
        cropped = image.crop(box)
        digest = hashlib.sha256(str(cropped.size).encode() + cropped.tobytes()).hexdigest()
        placement = dict(x=box[0], y=box[1], width=cropped.width, height=cropped.height)
        if deduplicate and digest in by_digest:
            previous = by_digest[digest]
            previous['instances'].append(placement)
            return previous
        unique_name = name
        suffix = 2
        while any(a['category'] == category and a['name'] == unique_name for a in assets):
            unique_name = f'{name}_变体{suffix:02d}'
            suffix += 1
        file = ROOT / '命名素材' / category / (unique_name + '.png')
        file.parent.mkdir(parents=True, exist_ok=True)
        cropped.save(file)
        item = dict(number=len(assets) + 1, category=category, name=unique_name,
                    file=file.relative_to(ROOT).as_posix(), width=cropped.width, height=cropped.height,
                    source_layers=[dict(index=i, original_path=layers[i]['path']) for i in ids],
                    instances=[placement], note=note, pixel_hash=digest)
        assets.append(item)
        by_digest[digest] = item
        return item

    def x_runs(image):
        alpha = image.getchannel('A')
        used = [alpha.crop((x, 0, x + 1, image.height)).getbbox() is not None for x in range(image.width)]
        runs, start = [], None
        for x, value in enumerate(used + [False]):
            if value and start is None:
                start = x
            elif not value and start is not None:
                runs.append((start, x)); start = None
        return runs

    def split_x(category, index, names, deduplicate=False, note=''):
        bounds = images[index].getbbox()
        runs = x_runs(images[index].crop(bounds))
        assert len(runs) == len(names), (index, runs, names)
        for (left, right), name in zip(runs, names):
            asset(category, name, [index], (bounds[0]+left, bounds[1], right-left, bounds[3]-bounds[1]), note, deduplicate)

    asset('背景','桌面木纹背景',[1],note='背景源层完整画布；上层遮挡处保留源像素，便于复用。')
    asset('背景','斜向蓝色桌布',[14])
    for i in [217,218]:
        asset('英雄','蓝衣英雄_下方俯视像' if i==217 else '蓝衣英雄_上方俯视像_画布裁切',[i],note='人物身份未根据图层名推断；上方人物有17像素超出画布，本次仅导出画布内部分。')
    asset('资源','左侧资源托盘_含蜂窝格',[22])
    asset('资源','右侧资源托盘_组合',[17,18,21])
    asset('资源','右侧资源托盘_底框与把手',[17,18])
    asset('资源','资源蜂窝网格',[21])
    asset('法术','左侧法术托盘_空框',[24,32,33])
    asset('法术','右侧法术托盘_空框',[35])
    asset('法术','左侧法术托盘_当前组合',[24,26,29,32,33])
    asset('法术','右侧法术托盘_当前组合',[35,36])
    split_x('法术',26,['左侧分类_闪电','左侧分类_卷轴','左侧分类_沙漏'])
    split_x('法术',36,['右侧分类_闪电','右侧分类_卷轴','右侧分类_沙漏'])
    split_x('法术',29,['法术槽_绿色','法术槽_红色','法术槽_蓝色'])
    asset('战场','战场外框底板与金色包角',[39,40,46],(209,0,902,739),note='仅取当前主战场范围；底层向下延伸的旧画布不并入该组件。')
    for name,y in [('敌方后排底板',33),('敌方前排底板',188),('我方前排底板',367),('我方后排底板',522)]:
        asset('战场',name,[56],(242,y,836,155))
    asset('战场','战场中线_进度条',[47])
    asset('战场','战场中线_眼睛标记',[50])
    asset('战场','战场中线_组合',[47,50])
    asset('战场','战斗开始_按钮底板',[139])
    asset('战场','战斗开始_双剑图标',[140])
    asset('战场','战斗开始_组合按钮',[139,140])
    split_x('顶栏',43,['层数进度_三格底槽','天数进度_九格底槽'])
    split_x('顶栏',44,['层数进度_白色亮点','天数进度_橙红亮点','天数进度_金黄亮点','天数进度_蓝金亮点'])
    asset('顶栏','FLOOR文字',[45],(258,16,43,12))
    asset('顶栏','DAY文字',[45],(383,16,25,12))
    split_x('顶栏',59,['生命与保护_数值底槽','金币_数值底槽'])
    split_x('顶栏',60,['保护_盾牌图标','保护_盾牌图标','生命_红心图标','金币_金色钱币图标'],True)
    asset('收藏','收藏书_外框与内页',[90,97])
    asset('收藏','收藏书_当前完整排版示例',[90,91,92,93,94,95,96,97,99])
    split_x('收藏',91,[f'收藏空白分页标签_{i:02d}' for i in range(1,6)])
    split_x('收藏',92,['卡类筛选_人物轮廓','卡类筛选_星形标志','卡类筛选_护甲轮廓','卡类筛选_钱袋'])
    asset('收藏','收藏搜索框',[93])
    split_x('收藏',94,['元素筛选_水滴','元素筛选_树形','元素筛选_火焰','元素筛选_光芒','元素筛选_旋涡'],note='按可见图形命名；具体元素归属仍需用户核对。')
    split_x('收藏',95,[f'品级筛选_{i}' for i in ['I','II','III','IV','V']])
    asset('收藏','蓝色书签_上段',[96],(1027,722,37,57))
    asset('收藏','蓝色书签_下段',[96],(1027,793,37,23))
    for row,y in enumerate([777,930]):
        for col,(left,right) in enumerate(x_runs(images[99].crop(images[99].getbbox()))):
            asset('收藏','火枪手卡牌_展示样例',[99],(266+left,y,right-left,142),note='当前排版中的卡牌样例；像素一致的重复卡只存一份，保留全部出现坐标。',deduplicate=True)
    asset('指示物与贴纸','指示物托盘_空框',[69])
    asset('指示物与贴纸','指示物托盘_日月星组合',[69,76])
    split_x('指示物与贴纸',76,['指示物_月亮','指示物_星星','指示物_太阳'])
    asset('指示物与贴纸','贴纸工具箱_当前组合',[102,103])
    asset('指示物与贴纸','贴纸工具箱_左侧空板',[102],(25,941,98,152))
    asset('指示物与贴纸','贴纸工具箱_右侧空板',[102],(123,941,97,152))
    asset('指示物与贴纸','贴纸工具箱_四列七行格子',[103])
    asset('占位稿','英雄信息_当前完整占位稿',[4,5,6,9,10,11,13],note='蓝底、灰圆、灰方块、金色手写形状按源文件原样保留，不推定为已完成素材。')
    for i,name in [(4,'英雄信息_蓝色底板'),(6,'英雄信息_金色手写占位'),(9,'英雄头像_灰色外圆'),(10,'英雄头像_白色内圆')]:
        asset('占位稿',name,[i])
    for y in [954,1000]:
        for x in [1152,1208]:
            asset('占位稿','英雄技能_灰色方块',[5],(x,y,36,36),deduplicate=True)
    for y in [756,858]:
        for x in [1110,1245]:
            asset('占位稿','角落球体_灰色圆点',[11],(x,y,41,41),deduplicate=True)
    for x,y in [(1110,740),(1245,842)]:
        asset('占位稿','角落球体_白色图形',[13],(x,y,41,57),deduplicate=True)

    font_path='/System/Library/Fonts/Supplemental/Arial Unicode.ttf'
    font=ImageFont.truetype(font_path,14)
    small=ImageFont.truetype(font_path,12)
    for page,start in enumerate(range(0,len(assets),25),1):
        sheet=Image.new('RGB',(1200,900),'#202630');draw=ImageDraw.Draw(sheet)
        for j,item in enumerate(assets[start:start+25]):
            x=(j%5)*240;y=(j//5)*180
            draw.rectangle((x+4,y+4,x+235,y+175),fill='#353c48')
            art=Image.open(ROOT/item['file']);scale=min(220/art.width,120/art.height)
            scale=min(4,scale)
            art=art.resize((max(1,round(art.width*scale)),max(1,round(art.height*scale))),Image.Resampling.NEAREST)
            sheet.paste(art,(x+(240-art.width)//2,y+8+(120-art.height)//2),art)
            draw.text((x+9,y+134),f"{item['number']:02d} {item['name']}",font=font,fill='white')
            draw.text((x+9,y+155),f"{item['width']}×{item['height']} · {len(item['instances'])}处",font=small,fill='#becad8')
        sheet.save(ROOT/f'02_素材总览_{page:02d}.png')
    annotated=native.convert('RGB');draw=ImageDraw.Draw(annotated)
    # 总览只框独立图形，避免大背景与组合件的框线淹没内容。
    for item in assets:
        if item['width']>300 or item['height']>350 or '组合' in item['name'] or '完整' in item['name']:
            continue
        for position in item['instances']:
            x,y,w,h=(position[k] for k in ['x','y','width','height'])
            draw.rectangle((x,y,x+w-1,y+h-1),outline='#31f2a3',width=1)
            draw.rectangle((x,y,x+22,y+14),fill='#111820')
            draw.text((x+1,y),f"{item['number']:02d}",font=small,fill='#31f2a3')
    annotated.save(ROOT/'01_位置编号.png')
    report=dict(source=str(source),source_sha256=hashlib.sha256(source_bytes).hexdigest(),canvas=[width,height],
                frames=1,total_layers=len(layers),effective_visible_image_layers=len(visible),
                contributing_layers=len(contributing),fully_covered_layers=[l['index'] for l in visible if not l['visible_pixel_count']],
                native_composite_pixel_equal=True,assets=assets,layers=layers)
    (ROOT/'素材对应表.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    with (ROOT/'素材对应表.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.writer(f);writer.writerow(['编号','分类','素材名','导出文件','宽','高','原画布x','原画布y','来源图层索引','来源原图层路径','备注'])
        for item in assets:
            for p in item['instances']:
                writer.writerow([item['number'],item['category'],item['name'],item['file'],item['width'],item['height'],p['x'],p['y'],
                    ','.join(str(l['index']) for l in item['source_layers']),';'.join(l['original_path'] for l in item['source_layers']),item['note']])
    # 从导出的裁切图层按原坐标拼回，确保不遗漏任何最终可见像素。
    reconstruction=Image.new('RGBA',(width,height))
    for layer in contributing:
        im=Image.open(ROOT/layer['export_path']);reconstruction.alpha_composite(im,tuple(layer['canvas_bounds'][:2]))
    assert ImageChops.difference(native,reconstruction).getbbox(alpha_only=False) is None
    for item in assets:
        im=Image.open(ROOT/item['file']);assert im.mode=='RGBA' and im.size==(item['width'],item['height'])
    assert hashlib.sha256(source.read_bytes()).hexdigest()==report['source_sha256']
    print(json.dumps(dict(named_assets=len(assets),recorded_instances=sum(len(a['instances']) for a in assets),
                          source_layers=len(contributing),native_pixel_equal=True,reconstruction_pixel_equal=True,
                          source_unchanged=True,output=str(ROOT)),ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=SOURCE)
    export(parser.parse_args().source)
