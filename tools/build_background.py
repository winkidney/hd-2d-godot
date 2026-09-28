"""Original seeded mountain meshes. Run with Blender --background --python.
World metres, Godot Y-up converted once to Blender Z-up. No online assets.
"""
from pathlib import Path
import bpy
import math
import random
import json
import hashlib
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/background'
SOURCE = ROOT / 'art_source/background'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
SEED = 290928
results = []

def xyz(p):
    return (p[0], -p[2], p[1])

def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

def build(name, rows, cols, width, z_front, z_back, height, color):
    clear()
    rng = random.Random(SEED + sum(map(ord, name)))
    peaks = [(rng.uniform(-width*.48,width*.48),rng.uniform(.5,1.0),rng.uniform(width*.025,width*.08)) for _ in range(18)]
    verts = []
    for j in range(rows+1):
        t = j/rows
        z = z_front+(z_back-z_front)*t
        for i in range(cols+1):
            x = -width/2+width*i/cols
            crest = max(a*math.exp(-((x-p)/s)**2) for p,a,s in peaks)
            ridge = max(0,math.sin(math.pi*t))**.8
            y = -0.10 + height*(.28+.72*crest)*ridge
            if name == 'valley':
                y = -0.10 + height*max(0,math.sin(t*math.pi*2))**2*(.3+.7*crest)
            elif 0 < j < rows:
                y += rng.uniform(-height*.07,height*.07)
            verts.append(xyz((x,y,z)))
    faces = []
    for j in range(rows):
        for i in range(cols):
            a=j*(cols+1)+i; b=a+1; c=a+cols+1; d=c+1
            faces.extend([(a,b,c),(b,d,c)])
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active=obj; obj.select_set(True)
    attr=mesh.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
    for face in mesh.polygons:
        shade=rng.uniform(.78,1.1)
        for index in face.loop_indices:
            y=verts[mesh.loops[index].vertex_index][2]
            snow=max(0,min(1,(y/height-.78)*5)) if name=='ridge_far' else 0
            rgb=[v*shade*(1-snow)+.86*snow for v in color]
            attr.data[index].color=(*rgb,1)
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF')
    vertex=mat.node_tree.nodes.new('ShaderNodeVertexColor');vertex.layer_name='Color'
    mat.node_tree.links.new(vertex.outputs['Color'],bs.inputs['Base Color'])
    bs.inputs['Roughness'].default_value=1.0
    obj.data.materials.append(mat)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True,export_apply=True,export_cameras=False,export_lights=False)
    results.append({'id':name,'seed':SEED,'vertices':len(verts),'triangles':len(faces),'glb':'assets/background/'+name+'.glb','blend':'art_source/background/'+name+'.blend','sha256':hashlib.sha256((OUT/(name+'.glb')).read_bytes()).hexdigest()})
    print('BACKGROUND_MODEL_OK',name,flush=True)

build('valley',18,80,1800,-20,-1150,3.5,(.25,.35,.27))
build('ridge_near',8,80,1100,-65,-155,21,(.31,.44,.42))
build('ridge_mid',8,88,1500,-200,-410,42,(.43,.57,.62))
build('ridge_far',8,96,2300,-580,-1040,83,(.59,.69,.74))
(SOURCE/'models.json').write_text(json.dumps({'source_type':'procedural-original','generator':'tools/build_background.py','blender':bpy.app.version_string,'models':results},indent=2)+'\n')
print('BACKGROUND_BUILD_OK',flush=True)
