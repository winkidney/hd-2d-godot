"""Reopen the saved Blender file and verify its portable measured instances."""
from pathlib import Path
import json
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art_source/ancient-canal/layout-assembly/20261008-r5'
manifest=json.loads((OUT/'assembly-manifest.json').read_text())
bpy.ops.wm.open_mainfile(filepath=str(ROOT/manifest['model']))
checks=[]
for entry in manifest['instances']:
    obj=bpy.data.objects.get(entry['id'])
    x,y,z=entry['godot_position']
    checks.append(dict(id=entry['id'],passed=obj is not None and obj.instance_collection is not None and
                       max(abs(a-b) for a,b in zip(obj.location,(x,-z,y)))<.00001))
blueprint=json.loads((ROOT/manifest['blueprint']['path']).read_text())
graph=bpy.context.evaluated_depsgraph_get()
points_by_id={}
for inst in graph.object_instances:
    if inst.is_instance and inst.parent is not None and inst.object.type=='MESH':
        points=points_by_id.setdefault(inst.parent.name,[])
        for corner in inst.object.bound_box:
            point=inst.matrix_world @ Vector(corner)
            points.append((point.x,point.z,-point.y))
for entry in blueprint['objects']:
    points=points_by_id.get(entry['id'],[])
    expected_min=[a+b for a,b in zip(entry['position'],entry['model_bounds']['min'])]
    expected_max=[a+b for a,b in zip(entry['position'],entry['model_bounds']['max'])]
    actual_min=[min(p[i] for p in points) for i in range(3)] if points else []
    actual_max=[max(p[i] for p in points) for i in range(3)] if points else []
    error=max(abs(a-b) for a,b in zip(actual_min+actual_max,expected_min+expected_max)) if points else 999
    checks.append(dict(id='model_bounds_'+entry['id'],passed=error<.001,error_m=error))
images=[im for im in bpy.data.images if im.source=='FILE']
checks.append(dict(id='textures_packed',passed=all(im.packed_file for im in images),count=len(images)))
checks.append(dict(id='three_ground_batches',passed=sum(obj.name.startswith('GroundSurface_') for obj in bpy.data.objects)==3))
checks.append(dict(id='fourteen_point_lights',passed=len(bpy.data.lights)==14))
checks.append(dict(id='deleted_L5_absent',passed=bpy.data.objects.get('L5') is None))
passed=all(c['passed'] for c in checks)
(OUT/'reopen-checks.json').write_text(json.dumps(dict(passed=passed,checks=checks),indent=2)+'\n')
assert passed,checks
print('ASSEMBLY_REOPEN_PASS',len(checks),'checks')
