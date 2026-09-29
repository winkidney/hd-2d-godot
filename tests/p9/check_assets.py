"""P9 source provenance, pixel contracts, model containers and repeatability."""
from pathlib import Path
from PIL import Image
import hashlib, json, struct, io, sys, importlib.util, re
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'build/p9'
checks=[]
def check(ok,name):
    checks.append({'name':name,'passed':bool(ok)})
    print(('PASS ' if ok else 'FAIL ')+name)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def pixels(image): return hashlib.sha256(image.convert('RGBA').tobytes()).hexdigest()
def check_original(record,label):
    path=ROOT/record['path']
    check(sha(path)==record['sha256'],'original_file_hash:'+label)
    with Image.open(path) as image:
        check(image.format=='PNG','original_png:'+label)
        check(list(image.size)==record['size'],'original_size:'+label)
        check(pixels(image)==record['rgba_sha256'],'original_pixel_hash:'+label)

intake=json.loads((ROOT/'art_source/reference-scene/manifests/intake.json').read_text())
status=json.loads((ROOT/'art_source/reference-scene/manifests/source-status.json').read_text())
check(intake.get('schema')==2 and intake.get('source_type')=='imagegen-original-derived','original_intake_schema2')
check(status.get('schema')==2,'source_status_schema2')
check(sha(ROOT/intake['intake']['path'])==intake['intake']['sha256'],'retained_intake_hash')
for label,key,recipe in [('board','imagegen_asset_board',intake['intake']),('concept','imagegen_extension_concept',intake['concept'])]:
    record=status[key]
    check(record.get('original_archived') is True,'original_archived:'+label)
    check(all(record[field]==recipe[field] for field in ['path','sha256','rgba_sha256','size']),'original_recipe_link:'+label)
    check_original(record,label)
check(status['imagegen_asset_board']['expected_sha256']==intake['upstream']['sha256'],'historical_upstream_hash_retained')
check(intake['intake']['sha256']!=intake['upstream']['sha256'] and 'different' in intake['upstream']['status'],'reupload_byte_mismatch_explicit')
check(status['imagegen_asset_board']['historical_derivative_build_input'] is False and intake['historical_intake']['runtime_build_input'] is False,'lossy_intake_not_production_source')
check(sha(ROOT/intake['historical_intake']['path'])==intake['historical_intake']['sha256'],'historical_intake_preserved')
check(status['imagegen_extension_concept']['runtime_usage'] is False and intake['concept']['runtime_usage'] is False,'concept_reference_only')
reference=status['reference']
check(reference['runtime_usage'] is False and re.fullmatch(r'[0-9a-f]{64}',reference['sha256']) is not None and reference['sha256']==intake['reference']['sha256'],'copyright_reference_research_only')
reference_path=ROOT/reference['path']
if reference_path.is_file():
    check(sha(reference_path)==reference['sha256'],'research_reference_file_hash')
else:
    # Distributable source deliberately omits the third-party research image.
    # Production originals remain mandatory in check_original above.
    check(not reference_path.exists(),'research_not_distributed_expected')
check(len(intake['items'])==24,'source_crops_accounted')
check(len({item['id'] for item in intake['items']})==24,'source_crop_ids_unique')
w,h=intake['intake']['size']
for item in intake['items']:
    left,top,right,bottom=item['source_rect']
    check(0<=left<right<=w and 0<=top<bottom<=h,'original_crop_bounds:'+item['id'])
    if 'quad' in item:
        quad=item['quad']
        check(len(quad)==8 and all(0<=quad[i]<=w and 0<=quad[i+1]<=h for i in range(0,8,2)),'rectification_quad:'+item['id'])
processed=json.loads((ROOT/'art_source/reference-scene/manifests/processed.json').read_text())
check(processed.get('schema')==2 and processed.get('source_type')=='imagegen-original-derived','processed_schema2')
check(processed['input_path']==intake['intake']['path'] and processed['input_sha256']==intake['intake']['sha256'] and processed['input_rgba_sha256']==intake['intake']['rgba_sha256'],'processed_original_link')
check(processed['recipe_sha256']==sha(ROOT/'art_source/reference-scene/manifests/intake.json'),'processed_recipe_hash')
check(len(processed['assets'])==23,'processed_asset_count')
texture_records=[asset for asset in processed['assets'] if '/textures/' in asset['path']]
texture_manifest_hash=hashlib.sha256(json.dumps(texture_records,sort_keys=True,separators=(',',':')).encode()).hexdigest()
check(processed['model_texture_manifest_sha256']==texture_manifest_hash,'model_texture_manifest_projection')
module_spec=importlib.util.spec_from_file_location('p9_asset_processor',ROOT/'tools/p9/process_assets.py')
processor=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(processor)
sheet=Image.open(ROOT/intake['intake']['path'])
for recipe in intake['items']:
    if recipe['kind']!='actor':
        continue
    before=processor.cut_background(processor.source_crop(sheet,recipe))
    after=processor.cut_actor_ground_shadow(before)
    cutoff=int(before.height*intake['processing']['actor_ground_shadow']['start_y_fraction'])
    check(before.crop((0,0,before.width,cutoff)).tobytes()==after.crop((0,0,after.width,cutoff)).tobytes(),'actor_body_pixels_preserved:'+recipe['id'])
    check(sum(before.getchannel('A').tobytes())>sum(after.getchannel('A').tobytes()),'actor_paper_shadow_removed:'+recipe['id'])
for asset in processed['assets']:
    path=ROOT/asset['path']
    check(sha(path)==asset['sha256'],'asset_hash:'+path.name)
    image=Image.open(path)
    check(list(image.size)==asset['size'],'asset_size:'+path.name)
    check(pixels(image)==asset['rgba_sha256'],'asset_pixel_hash:'+path.name)
    if '/sprites/' in asset['path']:
        check(image.size==(192,256) and image.mode=='RGBA','atlas:'+path.name)
        for row in range(4):
            for col in range(4):
                frame=image.crop((col*48,row*64,col*48+48,row*64+64))
                box=frame.getbbox()
                check(box is not None and box[3]<=62,'foot_anchor:%s:%d:%d'%(path.name,row,col))
        check(set(image.getchannel('A').tobytes())<={0,255},'binary_actor_alpha:'+path.name)
for name in ['brick','paving','stone','plaster','roof','wood','canvas','green','water','awning_green']:
    image=Image.open(ROOT/'assets/reference-scene/textures'/f'{name}.png').convert('RGB')
    w,h=image.size
    check(all(image.getpixel((0,y))==image.getpixel((w-1,y)) for y in range(h)),'periodic_x:'+name)
    check(all(image.getpixel((x,0))==image.getpixel((x,h-1)) for x in range(w)),'periodic_y:'+name)
models=json.loads((ROOT/'art_source/reference-scene/manifests/models.json').read_text())
check(models.get('schema')==2,'models_schema2')
check(models['input_texture_manifest_sha256']==texture_manifest_hash,'model_texture_manifest_hash')
check(len(models['models'])==16,'module_kit_count')
texture_pixels={Path(asset['path']).stem:asset['rgba_sha256'] for asset in processed['assets'] if '/textures/' in asset['path']}
for model in models['models']:
    path=ROOT/model['glb'];data=path.read_bytes()
    magic,version,size=struct.unpack_from('<4sII',data)
    check(magic==b'glTF' and version==2 and size==len(data),'glb:'+model['id'])
    check(sha(path)==model['glb_sha256'],'model_hash:'+model['id'])
    check((ROOT/model['blend']).stat().st_size>1000,'blend_source:'+model['id'])
    check(sha(ROOT/model['blend'])==model['blend_sha256'],'blend_source_hash:'+model['id'])
    length,chunk_type=struct.unpack_from('<II',data,12)
    check(chunk_type==0x4E4F534A and length%4==0,'glb_json_chunk:'+model['id'])
    meta=json.loads(data[20:20+length])
    check(not any('uri' in b for b in meta.get('buffers',[])),'embedded_buffers:'+model['id'])
    binary_length,binary_type=struct.unpack_from('<II',data,20+length)
    binary=data[28+length:]
    check(binary_type==0x004E4942 and binary_length==len(binary),'glb_binary_chunk:'+model['id'])
    check(len(meta.get('meshes',[]))==model['objects'] and len(meta.get('nodes',[]))==model['objects'],'glb_module_object_count:'+model['id'])
    check(all(view.get('buffer',0)==0 and 0<=view.get('byteOffset',0) and view.get('byteOffset',0)+view['byteLength']<=len(binary) for view in meta.get('bufferViews',[])),'glb_buffer_view_bounds:'+model['id'])
    for embedded in meta.get('images',[]):
        label=model['id']+':'+embedded.get('name','unnamed')
        check('bufferView' in embedded and 'uri' not in embedded,'embedded_image:'+label)
        view=meta['bufferViews'][embedded['bufferView']]
        offset=view.get('byteOffset',0)
        with Image.open(io.BytesIO(binary[offset:offset+view['byteLength']])) as image:
            check(embedded['name'] in texture_pixels and pixels(image)==texture_pixels.get(embedded['name']),'glb_uses_current_texture:'+label)
shared=json.loads((ROOT/'art_source/reference-scene/manifests/shared-baseline.json').read_text())
exceptions=status.get('checkpoint_baseline_exceptions',{})
check(set(exceptions)=={'project.godot'},'baseline_exception_scope')
for name,digest in shared['files'].items():
    if name in exceptions:
        exception=exceptions[name]
        check(exception['historical_commit']==shared['git_commit'] and exception['historical_sha256']==digest,'historical_baseline_retained:'+name)
        check(exception['checkpoint_commit']=='3b6333f7b7e3aab09ffac34b4a97ef8d75ac3475' and bool(exception['reason']),'checkpoint_exception_documented:'+name)
        check(sha(ROOT/name)==exception['checkpoint_sha256'],'checkpoint_baseline_unchanged:'+name)
    else:
        check(sha(ROOT/name)==digest,'old_baseline_unchanged:'+name)
for path in [*(ROOT/'tools/p9').glob('*.py'),*(ROOT/'tests/p9').glob('*.py')]:
    compile(path.read_text(),path.name,'exec')
    check(True,'python_syntax:'+path.name)
for name in ['scenes/reference_scene.tscn','scenes/reference_scene_graybox.tscn','scenes/reference_scene_world.tscn','resources/reference-scene/layout.json']:
    check((ROOT/name).is_file(),'entry:'+name)
check('instance=ExtResource' not in (ROOT/'scenes/reference_scene_world.tscn').read_text(),'flattened_baked_world')
failed=[item['name'] for item in checks if not item['passed']]
print('P9_ASSET_CHECKS',len(checks),'failed',len(failed))
sys.exit(1 if failed else 0)
