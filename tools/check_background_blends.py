"""Blender-only source readback check; run with --disable-autoexec."""
from pathlib import Path
import bpy
import json
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'art_source/background/models.json').read_text())
results=[]
for item in manifest['models']:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/item['blend']))
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    vertices=sum(len(o.data.vertices) for o in objects)
    external=[im.name for im in bpy.data.images if im.filepath and not im.packed_file]
    passed=vertices==item['vertices'] and bool(objects) and not external
    results.append({'id':item['id'],'passed':passed,'mesh_count':len(objects),'vertices':vertices,'unpacked_images':external})
    print('BACKGROUND_READBACK',item['id'],passed,flush=True)
output=ROOT/'build/p6p7/blender-readback.json'
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps({'passed':all(r['passed'] for r in results),'models':results},indent=2)+'\n')
if not all(r['passed'] for r in results):
    raise RuntimeError('Background source readback failed')
