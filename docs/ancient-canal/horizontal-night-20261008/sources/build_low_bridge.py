"""Run with Blender; preserve the original kit and publish a separate low arch."""
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('canal_kit',ROOT/'tools/ancient_canal/build_models.py')
kit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kit)
import bpy
import bmesh
from mathutils import Vector
kit.bpy,kit.bmesh,kit.Vector = bpy,bmesh,Vector
kit.BLENDS = ROOT/'art_source/ancient-canal/blender/low-bridge'
kit.BLENDS.mkdir(parents=True,exist_ok=True)
bpy.context.preferences.filepaths.save_version=0
kit.reset()
kit.bridge(.6)
kit.export('bridge_low')
record=kit.RESULTS[0]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/record['blend']))
assert len([o for o in bpy.context.scene.objects if o.type=='MESH'])==record['material_meshes']
assert all(i.packed_file for i in bpy.data.images if i.source=='FILE')
(kit.BLENDS/'recipe.json').write_text(json.dumps({'schema':1,'generator':'tools/ancient_canal/build_low_bridge.py',
    'source':'tools/ancient_canal/build_models.py:bridge','height':.6,'half_span':4.2,'width':2.8,
    'original_model_retained':True,'reopened':True,'model':record},indent=2)+'\n')
