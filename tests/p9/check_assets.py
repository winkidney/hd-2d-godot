"""P9 source provenance, pixel contracts, model containers and repeatability."""
from pathlib import Path
from PIL import Image
import hashlib, json, struct, importlib.util, tempfile, shutil, sys
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'build/p9'
checks=[]
def check(ok,name):
    checks.append({'name':name,'passed':bool(ok)})
    print(('PASS ' if ok else 'FAIL ')+name)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
intake=json.loads((ROOT/'art_source/reference-scene/manifests/intake.json').read_text())
check(sha(ROOT/intake['intake']['path'])==intake['intake']['sha256'],'retained_intake_hash')
check(len(intake['items'])==24,'source_crops_accounted')
processed=json.loads((ROOT/'art_source/reference-scene/manifests/processed.json').read_text())
check(len(processed['assets'])==23,'processed_asset_count')
for asset in processed['assets']:
    path=ROOT/asset['path']
    check(sha(path)==asset['sha256'],'asset_hash:'+path.name)
    image=Image.open(path)
    check(list(image.size)==asset['size'],'asset_size:'+path.name)
    if '/sprites/' in asset['path']:
        check(image.size==(192,256) and image.mode=='RGBA','atlas:'+path.name)
        for row in range(4):
            for col in range(4):
                frame=image.crop((col*48,row*64,col*48+48,row*64+64))
                box=frame.getbbox()
                check(box is not None and box[3]<=62,'foot_anchor:%s:%d:%d'%(path.name,row,col))
for name in ['brick','paving','stone','plaster','roof','wood','canvas','green','water','awning_green']:
    image=Image.open(ROOT/'assets/reference-scene/textures'/f'{name}.png').convert('RGB')
    w,h=image.size
    check(all(image.getpixel((0,y))==image.getpixel((w-1,y)) for y in range(h)),'periodic_x:'+name)
    check(all(image.getpixel((x,0))==image.getpixel((x,h-1)) for x in range(w)),'periodic_y:'+name)
models=json.loads((ROOT/'art_source/reference-scene/manifests/models.json').read_text())
check(len(models['models'])==16,'module_kit_count')
for model in models['models']:
    path=ROOT/model['glb'];data=path.read_bytes()
    magic,version,size=struct.unpack_from('<4sII',data)
    check(magic==b'glTF' and version==2 and size==len(data),'glb:'+model['id'])
    check(sha(path)==model['glb_sha256'],'model_hash:'+model['id'])
    check((ROOT/model['blend']).stat().st_size>1000,'blend_source:'+model['id'])
    length=struct.unpack_from('<I',data,12)[0]
    meta=json.loads(data[20:20+length])
    check(not any('uri' in b for b in meta.get('buffers',[])),'embedded_buffers:'+model['id'])
shared=json.loads((ROOT/'art_source/reference-scene/manifests/shared-baseline.json').read_text())
for name,digest in shared['files'].items():
    check(sha(ROOT/name)==digest,'old_baseline_unchanged:'+name)
for path in [*(ROOT/'tools/p9').glob('*.py'),*(ROOT/'tests/p9').glob('*.py')]:
    compile(path.read_text(),path.name,'exec')
    check(True,'python_syntax:'+path.name)
for name in ['scenes/reference_scene.tscn','scenes/reference_scene_graybox.tscn','scenes/reference_scene_world.tscn','resources/reference-scene/layout.json']:
    check((ROOT/name).is_file(),'entry:'+name)
check('instance=ExtResource' not in (ROOT/'scenes/reference_scene_world.tscn').read_text(),'flattened_baked_world')
