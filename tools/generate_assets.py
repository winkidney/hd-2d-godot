#!/usr/bin/env python3
"""Deterministic original pixel assets. No network, AI service, or third-party art."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib
import json
import random

ROOT = Path(__file__).resolve().parents[1]
SEED = 290928
OUT = ROOT / 'assets'

def save(im, relative):
    path = OUT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path)
    # Explicit import contract; do not rely on editor-wide defaults.
    sprite = relative.startswith('sprites/')
    config = """[remap]
importer="texture"
type="CompressedTexture2D"

[deps]
source_file="res://assets/{relative}"

[params]
compress/mode=0
mipmaps/generate={mips}
process/fix_alpha_border=true
process/premult_alpha=false
"""
    path.with_suffix(path.suffix + '.import').write_text(config.format(relative=relative, mips='false' if sprite else 'true'))

def texture(kind):
    rng = random.Random(SEED + sum(map(ord, kind)))
    n = 128
    colors = {
        'stone': ['#716b65','#817970','#93877b','#635e5a','#a09481'],
        'brick': ['#62666a','#81817d','#969087','#525960','#b0a090'],
        'wood': ['#4a3028','#684331','#83563a','#a17347','#362826'],
        'roof': ['#263c48','#355160','#486b73','#587e80','#20313d'],
        'plaster': ['#b49e78','#c9b68b','#dbc99a','#978363','#bfa778'],
        'grass': ['#394538','#47563b','#586543','#6d774a','#323c32'],
        'soil': ['#3a3432','#4f4439','#66533c','#7c6444','#322d2d'],
    }[kind]
    im = Image.new('RGB', (n,n), colors[0]); d=ImageDraw.Draw(im)
    if kind in ('stone','brick','roof'):
        h = 16 if kind != 'roof' else 12
        w = 32 if kind != 'stone' else 24
        for row,y in enumerate(range(-h,n+h,h)):
            for x in range(-w,n+w,w):
                xx=x+(row%2)*(w//2)
                col=rng.choice(colors[1:4])
                d.rectangle((xx+1,y+1,xx+w-1,y+h-1),fill=col)
                d.line((xx+2,y+2,xx+w-2,y+2),fill=colors[4],width=1)
                d.line((xx+w-1,y+3,xx+w-1,y+h-1),fill=colors[0])
                for _ in range(9):
                    dx,dy=xx+rng.randrange(2,w-2),y+rng.randrange(3,h-1)
                    d.rectangle((dx,dy,dx+rng.randrange(1,4),dy+1),fill=rng.choice(colors[:4]))
    elif kind=='wood':
        for x in range(0,n,16):
            d.rectangle((x+1,0,x+14,n),fill=rng.choice(colors[1:4]))
            d.line((x+2,0,x+2,n),fill=colors[3])
            for _ in range(19):
                xx=x+rng.randrange(3,14); y=rng.randrange(n)
                d.line((xx,y,xx,y+rng.randrange(4,28)),fill=rng.choice(colors[:3]))
            d.ellipse((x+5,28,x+11,43),outline=colors[0],width=1)
    else:
        for _ in range(1800):
            x,y=rng.randrange(n),rng.randrange(n)
            c=rng.choices(colors,weights=[2,4,3,1,2])[0]
            s=rng.choice([1,2,2,3,4])
            d.rectangle((x,y,x+s,y+s//2),fill=c)
    save(im, 'textures/'+kind+'.png')

def foliage():
    for name, palette in [('oak',['#222f2d','#334437','#46583c','#607044','#809053','#a4a864']),('autumn',['#3c3530','#665035','#907040','#b98a46','#cfaa5b','#d9c57f'])]:
        rng=random.Random(SEED); im=Image.new('RGBA',(128,128)); d=ImageDraw.Draw(im)
        clusters=[(64,31,28),(39,48,29),(85,47,27),(23,70,21),(65,71,37),(101,74,24),(43,95,25),(81,96,25)]
        for cx,cy,r in clusters:
            d.ellipse((cx-r,cy-r,cx+r,cy+r),fill=palette[0])
        for _ in range(1900):
            x,y=rng.randrange(7,121),rng.randrange(4,121)
            if im.getpixel((x,y))[3]:
                shade=max(1,min(5,int((1-y/145)*4)+rng.randrange(-1,2)))
                s=rng.randrange(2,6)
                d.rectangle((x,y,x+s,y+s//2),fill=palette[shade])
        # Keep a soft organic silhouette without semi-transparent edge pixels.
        save(im,'sprites/'+name+'.png')
    rng=random.Random(SEED)
    im=Image.new('RGBA',(48,64));d=ImageDraw.Draw(im)
    for i in range(17):
        x=rng.randrange(10,40); y=rng.randrange(10,40)
        d.line((24,63,x,y),fill=rng.choice(['#5b6741','#89945b','#b1ab66']),width=1)
        if i%3==0: d.rectangle((x-1,y-6,x+1,y+1),fill='#8b754b')
    save(im,'sprites/reeds.png')
    im=Image.new('RGBA',(32,32));d=ImageDraw.Draw(im)
    for x,y in [(8,15),(17,9),(24,20),(13,26)]:
        d.line((x,31,x,y),fill='#637e49',width=1)
        d.rectangle((x-2,y-2,x+2,y+2),fill='#deb971')
        d.point((x,y),fill='#7d523a')
    save(im,'sprites/flowers.png')

def character_frame(direction, frame, npc=False):
    im=Image.new('RGBA',(32,48)); d=ImageDraw.Draw(im)
    outline='#252833'; dark='#43313b'; hair='#6b4331'; hair_hi='#b4864f'
    cape='#9c563d' if npc else '#466e7f'; cape_hi='#ce8952' if npc else '#82a5ae'; cape_sh='#633c35' if npc else '#2d475b'
    skin='#dbb487'; skin_sh='#a67858'; cream='#e4d6a5'
    bob=1 if frame in (1,3) else 0
    step=(-1,1,0,0)[frame]
    def rect(box,color):
        x1,y1,x2,y2=box;d.rectangle((x1,y1+bob,x2,y2+bob),fill=color)
    # Boots keep a consistent contact baseline; leg alternation is intentional.
    d.rectangle((10,39,14,44-step),fill=outline);d.rectangle((18,39,22,44+step),fill=outline)
    d.rectangle((9,44-step,14,45-step),fill='#7e5840');d.rectangle((18,44+step,24,45+step),fill='#7e5840')
    rect((9,27,24,39),outline);rect((10,26,23,38),cape_sh)
    rect((8,24,24,35),cape);rect((9,24,12,33),cape_hi)
    rect((13,25,19,38),cream);rect((15,26,17,37),'#998964')
    rect((9,36,23,38),'#684733');rect((15,36,18,38),'#d8b36b')
    rect((6,26,9,34),outline);rect((7,27,10,32),cape_hi);rect((7,33,10,35),skin)
    rect((23,26,26,34),outline);rect((23,27,25,32),cape_sh);rect((24,33,26,35),skin_sh)
    rect((10,10,22,23),outline);rect((11,11,22,21),hair)
    rect((11,15,22,23),skin_sh);rect((12,15,21,22),skin)
    rect((13,22,20,24),skin_sh)
    rect((9,10,23,14),hair);rect((11,8,21,12),hair)
    rect((12,9,19,10),hair_hi);rect((10,13,13,18),hair);rect((20,12,23,16),hair)
    if direction==0:
        rect((13,18,14,19),outline);rect((19,18,20,19),outline)
        rect((16,22,18,22),skin_sh)
    elif direction==1:
        rect((10,12,23,23),hair);rect((11,12,15,19),hair_hi)
        rect((11,24,22,37),cape);rect((11,24,13,35),cape_hi)
        rect((10,28,23,36),'#71543d');rect((12,29,21,34),'#a27d50')
    else:
        rect((10,15,18,22),hair);rect((19,16,24,22),skin)
        rect((22,18,23,19),outline);rect((24,20,25,21),skin_sh)
        rect((11,26,19,38),cape);rect((12,26,14,36),cape_hi)
    # A small teal/gold scarf separates the head from the coat.
    rect((11,23,21,25),'#d6ae64' if not npc else '#84a6a5')
    if direction==2: im=im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return im

def actors():
    for npc,name in [(False,'traveler'),(True,'keeper')]:
        atlas=Image.new('RGBA',(128,192))
        for direction in range(4):
            for frame in range(4):
                atlas.alpha_composite(character_frame(direction,frame,npc),(frame*32,direction*48))
        save(atlas,'sprites/'+name+'.png')
    im=Image.new('RGBA',(64,24));p=im.load()
    for y in range(24):
        for x in range(64):
            r=((x-31.5)/31.5)**2+((y-11.5)/11.5)**2
            p[x,y]=(18,20,24,int(max(0,1-r)**2*145))
    save(im,'sprites/contact_shadow.png')

def main():
    for name in ['stone','brick','wood','roof','plaster','grass','soil']: texture(name)
    foliage();actors()
    manifest={'source_type':'procedural-original','seed':SEED,'generator':'tools/generate_assets.py','attribution':'Original procedural assets authored for this project; no extracted game content.','sprite_frame':[32,48],'sprite_grid':[4,4],'assets':[]}
    for p in sorted([*(OUT/'textures').glob('*.png'), *(OUT/'sprites').glob('*.png')]):
        im=Image.open(p)
        manifest['assets'].append({'path':p.relative_to(ROOT).as_posix(),'size':list(im.size),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    (ROOT/'art_source/generated/manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print('ASSETS_OK',len(manifest['assets']))

if __name__=='__main__': main()
