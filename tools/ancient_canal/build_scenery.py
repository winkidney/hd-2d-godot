"""Deterministic pixel willow and static celestial panorama; no runtime generation."""
from pathlib import Path
import hashlib
import json
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SEED = 20261008
OUT = ROOT / 'assets/ancient-canal/scenery'


def save(image, name):
    path = OUT / name
    image.save(path)
    path.with_suffix(path.suffix + '.import').write_text('''[remap]
importer="texture"
type="CompressedTexture2D"

[deps]
source_file="res://assets/ancient-canal/scenery/%s"

[params]
compress/mode=0
mipmaps/generate=true
process/fix_alpha_border=true
process/premult_alpha=false
''' % name)
    return {'path': path.relative_to(ROOT).as_posix(), 'size': list(image.size),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def willow():
    rng = random.Random(SEED)
    image = Image.new('RGBA', (192, 256))
    draw = ImageDraw.Draw(image)
    # Foot at (96, 248); branches and leaf strands are authored in pixel space.
    draw.polygon([(89, 248), (102, 248), (100, 126), (112, 83), (99, 79), (88, 136)], fill='#554033')
    for tip in [(31, 64), (61, 41), (123, 37), (157, 64)]:
        draw.line([(95, 143), (91, 90), tip], fill='#66513c', width=4)
    palette = ['#283e35', '#344e3c', '#476143', '#58774b', '#779052']
    for cx, cy, radius in [(39, 68, 28), (70, 42, 30), (102, 36, 30), (136, 48, 28), (153, 77, 27), (90, 70, 37)]:
        draw.ellipse((cx-radius, cy-radius//2, cx+radius, cy+radius), fill=palette[0])
        for _ in range(90):
            x, y = cx+rng.randrange(-radius, radius), cy+rng.randrange(-radius//2, radius)
            if image.getpixel((max(0,min(191,x)), max(0,min(255,y))))[3]:
                draw.rectangle((x,y,x+3,y+2), fill=rng.choice(palette[1:]))
    for x in range(16, 177, 4):
        start = 59 + int(18*abs(x-96)/80) + rng.randrange(-14, 15)
        end = start + rng.randrange(56, 130)
        for y in range(start, end, 3):
            dx = int(4*math.sin(y*.06+x))
            draw.rectangle((x+dx,y,x+dx+2,y+3), fill=palette[rng.randrange(1,5)])
    return image


def night():
    width, height = 4096, 2048
    rng = np.random.default_rng(SEED)
    longitude = np.linspace(-math.pi, math.pi, width, dtype=np.float32)[None,:]
    latitude = np.linspace(math.pi/2, -math.pi/2, height, dtype=np.float32)[:,None]
    # A tilted continuous band with offline multi-scale grain and dust lanes.
    centre = .005 + .10*np.sin(longitude+.1)
    distance = latitude-centre
    grain = np.zeros((height,width), dtype=np.float32)
    for sw,sh,weight in [(64,32,.55),(256,128,.3),(1024,512,.15)]:
        noise = Image.fromarray(rng.integers(0,256,(sh,sw),dtype=np.uint8))
        grain += np.asarray(noise.resize((width,height),Image.Resampling.BILINEAR),dtype=np.float32)/255*weight
    band = np.exp(-(distance/.075)**2)*(grain*.7+.3)
    dust = .65*np.exp(-((distance-.01-.01*np.sin(longitude*8))/.012)**2)
    horizon = np.clip(latitude/.075,0,1)
    intensity = band*(1-dust)*horizon*.40
    rgb = np.stack([intensity*.78,intensity*.87,intensity],axis=2)
    rgb = np.uint8(np.clip(rgb*255,0,255))
    image = Image.fromarray(rgb)
    draw = ImageDraw.Draw(image)
    for _ in range(18000):
        lon = rng.uniform(-math.pi,math.pi)
        lat = math.asin(rng.uniform(0,1))
        x = int((lon+math.pi)/(2*math.pi)*(width-1))
        y = int((math.pi/2-lat)/math.pi*(height-1))
        strength = float(rng.power(.38))*.65+.25
        fade = min(1,lat/.025)
        color = np.array(rng.choice([[.92,.96,1],[1,.95,.85],[.85,.92,1]]))*strength*fade
        color = tuple(np.uint8(np.clip(color*255,0,255)))
        radius = 1 if strength>.85 and rng.random()<.25 else 0
        if radius:
            draw.ellipse((x-radius,y-radius,x+radius,y+radius),fill=color)
        else:
            draw.point((x,y),fill=color)
    # Crescent at azimuth 15 degrees / elevation 2.5 degrees: in the existing F sky strip.
    cx,cy = int((.5+15/360)*(width-1)), int((.5-2.5/180)*(height-1))
    radius = .375/360*width
    light = np.array([.58,.08,-.81]);light /= np.linalg.norm(light)
    pixels = image.load()
    for yy in range(cy-10,cy+11):
        for xx in range(cx-10,cx+11):
            dx,dy=(xx-cx)/radius,(cy-yy)/radius
            r2=dx*dx+dy*dy
            if r2<=1:
                normal=np.array([dx,dy,math.sqrt(1-r2)])
                lit=max(0,float(normal@light))
                shade=.012+(lit**.25)*.988
                pixels[xx,yy]=tuple(int(v*shade) for v in [244,242,225])
    # Guarantee the repeat boundary is continuous.
    arr=np.array(image);arr[:,-1]=arr[:,0]
    return Image.fromarray(arr)


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    records=[save(willow(),'willow.png'),save(night(),'night-panorama.png')]
    recipe={'schema':1,'seed':SEED,'generator':'tools/ancient_canal/build_scenery.py',
            'source_type':'original deterministic procedural pixel art',
            'willow':{'pivot':[96,248],'world_height':6.4,'sampling':'nearest with mipmaps, alpha discard, fixed Y billboard'},
            'sky':{'size':[4096,2048],'stars':18000,'moon_azimuth_deg':15,'moon_elevation_deg':2.5,
                   'moon_diameter_deg':.75,'runtime':'one static RGB panorama, no temporal noise'},'outputs':records}
    source=ROOT/'art_source/ancient-canal/scenery';source.mkdir(parents=True,exist_ok=True)
    (source/'recipe.json').write_text(json.dumps(recipe,ensure_ascii=False,indent=2)+'\n')
    print('SCENERY_GENERATED',records)


if __name__ == '__main__': main()
