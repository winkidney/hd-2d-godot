"""Deterministic original PNG -> rectified crops -> pixels -> runtime atlases.

The archived low-resolution intake is deliberately not sampled. All coordinates
are original-image pixels and all paths in the provenance output are relative.
"""
from pathlib import Path
from PIL import Image, ImageOps, ImageEnhance, __version__ as PILLOW_VERSION
from collections import deque
import hashlib, json
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/reference-scene'
MANIFESTS = ROOT / 'art_source/reference-scene/manifests'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def pixel_digest(image):
    return hashlib.sha256(image.convert('RGBA').tobytes()).hexdigest()

def model_texture_digest(assets):
    textures=[asset for asset in assets if '/textures/' in asset['path']]
    return hashlib.sha256(json.dumps(textures,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def cut_background(im, minimum=204, spread=46):
    """Only remove border-connected paper, preserving enclosed whites."""
    im = im.convert('RGBA')
    w, h = im.size
    pixels = im.load()
    visited = set()
    queue = deque([(x, y) for x in range(w) for y in (0, h-1)])
    queue.extend([(x, y) for x in (0, w-1) for y in range(h)])
    while queue:
        x, y = queue.popleft()
        if (x, y) in visited or not (0 <= x < w and 0 <= y < h):
            continue
        visited.add((x, y))
        r, g, b, _ = pixels[x, y]
        if min(r,g,b) < minimum or max(r,g,b)-min(r,g,b) > spread:
            continue
        pixels[x, y] = (0, 0, 0, 0)
        queue.extend([(x-1,y), (x+1,y), (x,y-1), (x,y+1)])
    return im

def cut_actor_ground_shadow(image, start=.82, minimum=70, spread=42):
    """Remove paper-shadow grays only in the foot band and from the exterior.

    White aprons, bonnets and faces above the foot band are never considered.
    Dark shoes and saturated hems stop the flood fill before it enters clothing.
    """
    image=image.copy()
    w,h=image.size; pixels=image.load(); first=int(h*start)
    queue=deque((x,y) for y in range(first,h) for x in range(w)
                if pixels[x,y][3]==0 or x in (0,w-1) or y==h-1)
    visited=set()
    while queue:
        x,y=queue.popleft()
        if (x,y) in visited or not (0<=x<w and first<=y<h):
            continue
        visited.add((x,y))
        r,g,b,a=pixels[x,y]
        if a and (min(r,g,b)<minimum or max(r,g,b)-min(r,g,b)>spread):
            continue
        pixels[x,y]=(0,0,0,0)
        queue.extend([(x-1,y),(x+1,y),(x,y-1),(x,y+1)])
    return image

def pixel(im, colors=64, saturation=.92, contrast=1.04):
    alpha = im.getchannel('A') if im.mode == 'RGBA' else None
    rgb = ImageEnhance.Color(im.convert('RGB')).enhance(saturation)
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    result = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT,
                         dither=Image.Dither.NONE).convert('RGB')
    if alpha is not None:
        result.putalpha(alpha.point(lambda value:255 if value>127 else 0))
        result.paste((0,0,0,0), mask=ImageOps.invert(result.getchannel('A')))
    return result

def periodic(im):
    im=im.convert('RGB'); p=im.load(); w,h=im.size
    for x in range(w):
        avg=tuple((p[x,0][k]+p[x,h-1][k])//2 for k in range(3))
        p[x,0]=p[x,h-1]=avg
    for y in range(h):
        avg=tuple((p[0,y][k]+p[w-1,y][k])//2 for k in range(3))
        p[0,y]=p[w-1,y]=avg
    return im

def source_crop(sheet, recipe):
    if 'quad' in recipe:
        # QUAD is upper-left, lower-left, lower-right, upper-right.
        return sheet.transform((64,64),Image.Transform.QUAD,recipe['quad'],Image.Resampling.BICUBIC)
    return sheet.crop(recipe['source_rect'])

def fit_sprite(image, size=(64,64), padding=2, actor=False):
    image=cut_background(image)
    if actor:
        image=cut_actor_ground_shadow(image)
    bounds=image.getbbox()
    if bounds is None:
        raise ValueError('Empty crop after paper removal')
    image=image.crop(bounds)
    image.thumbnail((size[0]-padding*2,size[1]-padding*2),Image.Resampling.LANCZOS)
    result=Image.new('RGBA',size)
    result.alpha_composite(image,((size[0]-image.width)//2,size[1]-padding-image.height))
    return result

def save(im, relative):
    path=OUT/relative
    path.parent.mkdir(parents=True,exist_ok=True)
    im.save(path,format='PNG',optimize=False,compress_level=9)
    sprite=relative.startswith('sprites/')
    config='[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n[deps]\nsource_file="res://assets/reference-scene/'+relative+'"\n[params]\ncompress/mode=0\nmipmaps/generate='+('false' if sprite else 'true')+'\nprocess/fix_alpha_border=true\ndetect_3d/compress_to=0\n'
    # Existing remap IDs belong to Godot. Avoid invalidating an identical rebuild.
    if not path.with_suffix(path.suffix+'.import').exists():
        path.with_suffix(path.suffix+'.import').write_text(config)
    return {'path':path.relative_to(ROOT).as_posix(),'size':list(im.size),
            'sha256':digest(path),'rgba_sha256':pixel_digest(im),'mode':im.mode}

def main():
    spec=json.loads((MANIFESTS/'intake.json').read_text())
    source=ROOT/spec['intake']['path']
    assert digest(source)==spec['intake']['sha256'], 'Original PNG changed'
    sheet=Image.open(source).convert('RGB')
    assert list(sheet.size)==spec['intake']['size']
    assert pixel_digest(sheet)==spec['intake']['rgba_sha256']
    cells={}; entries=[]
    for item in spec['items']:
        crop=source_crop(sheet,item); cells[item['id']]=crop
        if item['kind']=='texture':
            tile=crop.resize((64,64),Image.Resampling.LANCZOS)
            entries.append(save(periodic(pixel(tile)), 'textures/'+item['id']+'.png'))
        elif item['kind']=='decal':
            entries.append(save(pixel(fit_sprite(crop)), 'textures/'+item['id']+'.png'))
    awning=Image.new('RGB',(64,64))
    green=cells['green'].resize((64,64),Image.Resampling.LANCZOS)
    canvas=cells['canvas'].resize((64,64),Image.Resampling.LANCZOS)
    for x in range(0,64,8):
        sample=green if x//8%2==0 else canvas
        awning.paste(sample.crop((x,0,x+8,64)),(x,0))
    entries.append(save(periodic(pixel(awning)), 'textures/awning_green.png'))
    for name in ['hero','merchant','keeper','baker','noble']:
        directions=['hero_front','hero_back','hero_side','hero_side'] if name=='hero' else [name+'_front']*4
        atlas=Image.new('RGBA',(192,256))
        for row,key in enumerate(directions):
            frame=fit_sprite(cells[key],size=(48,64),padding=3,actor=True)
            if row==2 and name=='hero': frame=ImageOps.mirror(frame)
            frame=pixel(frame,48)
            for column in range(4):
                pose=frame.copy()
                if name=='hero' and column in (1,3):
                    # Derived two-pixel foot swing, not an ImageGen animation.
                    left=frame.crop((10,52,24,62)); right=frame.crop((24,52,38,62))
                    pose.paste((0,0,0,0),(9,52,39,62))
                    pose.alpha_composite(left,(9 if column==1 else 11,52))
                    pose.alpha_composite(right,(25 if column==1 else 23,52))
                atlas.alpha_composite(pose,(column*48,row*64))
        entries.append(save(atlas,'sprites/'+name+'.png'))
    result={'schema':2,'source_type':'imagegen-original-derived',
            'input_path':spec['intake']['path'],'input_sha256':digest(source),
            'input_rgba_sha256':pixel_digest(sheet),'recipe_sha256':digest(MANIFESTS/'intake.json'),
            'generator':'tools/p9/process_assets.py','pillow':PILLOW_VERSION,
            'texture_size':[64,64],'sprite_frame':[48,64],
            'model_texture_manifest_sha256':model_texture_digest(entries),
            'directions':['front','back','left','right'],'processing':spec['processing'],
            'animation_note':'Hero has three sourced directions plus mirroring and derived lower-leg swing. NPCs are front-only static sprites repeated in atlas for API compatibility.',
            'assets':entries}
    (MANIFESTS/'processed.json').write_text(json.dumps(result,indent=2)+'\n')
    print('P9_PIXEL_ASSETS',len(entries),'original',digest(source),flush=True)

if __name__=='__main__':
    main()
