"""Rebuild original cloud masks without network access. Pillow required."""
from pathlib import Path
from PIL import Image, ImageDraw
import random
import json
import hashlib
ROOT=Path(__file__).resolve().parents[1]

def cloud_image(index: int) -> Image.Image:
    rng=random.Random(290928+index)
    image=Image.new('RGBA',(256,96)); draw=ImageDraw.Draw(image)
    for i in range(15):
        x=28+i*13; y=54+rng.randrange(-12,8); r=rng.randrange(16,30)
        draw.ellipse((x-r,y-r,x+r,y+r//2),fill=(214,228,236,255))
        draw.ellipse((x-r+3,y-r-3,x+r-3,y+3),fill=(250,249,241,255))
    return image

def main() -> None:
    out=ROOT/'assets/background'; out.mkdir(parents=True,exist_ok=True)
    items=[]
    for index in range(3):
        image=cloud_image(index)
        path=out/('cloud-'+str(index)+'.png'); image.save(path)
        items.append({'path':path.relative_to(ROOT).as_posix(),'size':[256,96],'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    source=ROOT/'art_source/background'; source.mkdir(parents=True,exist_ok=True)
    (source/'clouds.json').write_text(json.dumps({'source_type':'procedural-original','seed':290928,'generator':'tools/generate_background_assets.py','assets':items},indent=2)+'\n')
    print('CLOUD_ASSETS_OK',len(items))

if __name__=='__main__':
    main()
