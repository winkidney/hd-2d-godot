"""Offline P6/P7 contracts, asset provenance and deterministic image checks."""
from pathlib import Path
import hashlib
import importlib.util
import io
import json
import math
import struct
ROOT=Path(__file__).resolve().parents[1]
checks=[]
def check(value,label):
    checks.append({'name':label,'passed':bool(value)})
    print(('PASS ' if value else 'FAIL ')+label)

def load_module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

clouds=load_module('cloud_generator',ROOT/'tools/generate_background_assets.py')
manifest=json.loads((ROOT/'art_source/background/clouds.json').read_text())
check(manifest['source_type']=='procedural-original' and len(manifest['assets'])==3,'cloud_source_contract')
for index,item in enumerate(manifest['assets']):
    path=ROOT/item['path']
    check(hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256'],'cloud_hash:'+path.name)
    output=io.BytesIO();clouds.cloud_image(index).save(output,format='PNG')
    check(hashlib.sha256(output.getvalue()).hexdigest()==item['sha256'],'cloud_deterministic:'+path.name)
models=json.loads((ROOT/'art_source/background/models.json').read_text())
check(len(models['models'])==4,'four_background_sources')
for item in models['models']:
    path=ROOT/item['glb']; data=path.read_bytes()
    magic,version,length=struct.unpack_from('<4sII',data)
    check(magic==b'glTF' and version==2 and length==len(data),'background_glb:'+item['id'])
    check(hashlib.sha256(data).hexdigest()==item['sha256'],'background_hash:'+item['id'])
    check((ROOT/item['blend']).is_file(),'background_blend:'+item['id'])
layout=json.loads((ROOT/'resources/world_layout.json').read_text())
route=layout['walkway']; camera=layout['camera']
check(24<=route['length']<=32 and 2.5<=route['width']<=3.5,'route_dimensions')
d=route['direction']
check(abs(sum(x*x for x in d)-1)<0.001 and d[1]==0,'route_horizontal_unit_direction')
forward=[b-a for a,b in zip(camera['position'],camera['target'])]
check(abs(d[0]*forward[0]+d[2]*forward[2])<0.01,'route_aligned_screen_right')
pitch=math.degrees(math.atan2(-forward[1],math.hypot(forward[0],forward[2])))
check(0<pitch<camera['fov']/2,'default_camera_sees_horizon')
check(camera['far']>=1200 and camera['follow_gain']>0,'far_clip_and_follow_contract')
background=json.loads((ROOT/'resources/background.json').read_text())
check(background['schema']==1 and set(background['palettes'])=={'day','dusk','night'},'background_three_periods')
check(len(background['cloud_wind_speeds'])==2,'two_independent_cloud_layers')
for id in ('soft','standard','strong'):
    check((ROOT/'resources/dof'/(id+'.tres')).is_file(),'dof_resource:'+id)
for id in ('traveler','keeper'):
    text=(ROOT/'assets/sprites'/(id+'.png.import')).read_text()
    check('compress/mode=0' in text and 'mipmaps/generate=false' in text and 'detect_3d/compress_to=0' in text,'pixel_actor_import:'+id)
for name in ('scripts/camera_rig.gd','scripts/dof_controller.gd','scripts/background_rig.gd','shaders/waystation_sky.gdshader','Plan/features/near-far-dof.md','Plan/features/distant-background-parallax.md'):
    check((ROOT/name).is_file(),'feature_entry:'+name)
for directory in ('tools','tests'):
    for path in (ROOT/directory).glob('*.py'):
        compile(path.read_text(),str(path),'exec')
check(True,'feature_python_syntax')
result={'passed':all(item['passed'] for item in checks),'checks':checks,'scope':'Offline contracts and provenance; not GPU or visual acceptance'}
out=ROOT/'build/p6p7/static-report.json';out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(result,indent=2)+'\n')
raise SystemExit(0 if result['passed'] else 1)
