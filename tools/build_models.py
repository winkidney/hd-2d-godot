"""Run with Blender --background --factory-startup --disable-autoexec --python.
All dimensions are authored as Godot (x, y-up, z); conversion occurs here once.
"""
from pathlib import Path
import bpy
from mathutils import Vector
import math
import json

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/models'
SOURCE=ROOT/'art_source/blender'
COLORS={'wood':(0.30,0.18,0.11,1),'plaster':(0.72,0.63,0.46,1),'roof':(0.18,0.30,0.35,1),'brick':(0.42,0.43,0.41,1),'stone':(0.49,0.46,0.41,1),'iron':(0.12,0.15,0.17,1),'glass':(1.0,0.54,0.17,1),'canvas':(0.57,0.36,0.27,1)}
MATS={}
RESULTS=[]

def xyz(p): return (p[0],-p[2],p[1])
def reset():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for m in list(bpy.data.materials): bpy.data.materials.remove(m)
    MATS.clear()
    for name,color in COLORS.items():
        m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True
        bs=m.node_tree.nodes.get('Principled BSDF')
        bs.inputs['Base Color'].default_value=color
        bs.inputs['Roughness'].default_value=0.85
        if name=='glass':
            bs.inputs['Emission Color'].default_value=color
            bs.inputs['Emission Strength'].default_value=1.4
        texpath=ROOT/'assets/textures'/f'{name}.png'
        if texpath.exists():
            node=m.node_tree.nodes.new('ShaderNodeTexImage')
            node.image=bpy.data.images.load(str(texpath),check_existing=True)
            node.interpolation='Closest'
            m.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color'])
        MATS[name]=m

def material(obj,name):
    obj.data.materials.append(MATS[name]);return obj

def box(name,pos,size,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(pos))
    o=bpy.context.object;o.name=name;o.scale=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return material(o,mat)

def beam(name,a,b,width,mat):
    a,b=Vector(xyz(a)),Vector(xyz(b));delta=b-a
    bpy.ops.mesh.primitive_cube_add(size=1,location=(a+b)/2)
    o=bpy.context.object;o.name=name;o.scale=(width,width,delta.length)
    o.rotation_euler=delta.to_track_quat('Z','Y').to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return material(o,mat)

def mesh(name,verts,faces,mat):
    m=bpy.data.meshes.new(name);m.from_pydata([xyz(v) for v in verts],[],faces);m.update()
    o=bpy.data.objects.new(name,m);bpy.context.collection.objects.link(o);material(o,mat)
    # Author UVs by dominant face direction so the blend is useful outside Godot.
    uv=m.uv_layers.new(name='UVMap')
    for poly in m.polygons:
        n=poly.normal;axis=max(range(3),key=lambda i:abs(n[i]));axes=[i for i in range(3) if i!=axis]
        for li in poly.loop_indices:
            v=m.vertices[m.loops[li].vertex_index].co
            uv.data[li].uv=(v[axes[0]]*.6,v[axes[1]]*.6)
    return o

def roof(name,w,d,y,rise):
    v=[(-w/2,y,-d/2),(w/2,y,-d/2),(-w/2,y,d/2),(w/2,y,d/2),(0,y+rise,-d/2),(0,y+rise,d/2)]
    mesh(name,v,[tuple(reversed(f)) for f in [(0,4,5,2),(4,1,3,5),(0,1,4),(2,5,3),(0,2,3,1)]],'roof')
    for z in (-d/2,d/2):
        beam(name+'_gable_l',(-w/2,y,z),(0,y+rise,z),.17,'wood')
        beam(name+'_gable_r',(0,y+rise,z),(w/2,y,z),.17,'wood')
    beam(name+'_ridge',(0,y+rise+.05,-d/2-.1),(0,y+rise+.05,d/2+.1),.19,'wood')
    for x in (-w/2,w/2):beam(name+'_eave',(x,y,-d/2),(x,y,d/2),.19,'wood')

def window(x,y,z,w=.75,h=.95):
    box('window_recess',(x,y,z),(w+.18,h+.18,.13),'wood')
    box('window_glow',(x,y,z+.08),(w,h,.07),'glass')
    box('window_mullion',(x,y,z+.13),(.07,h,.06),'wood')
    box('window_cross',(x,y,z+.14),(w,.06,.06),'wood')
    box('window_sill',(x,y-h/2-.07,z+.13),(w+.3,.13,.36),'wood')
    for sx in (-1,1):box('shutter',(x+sx*(w/2+.17),y,z+.06),(.2,h+.04,.1),'wood')

def house(w=6,d=4.3,h=4.2,inn=True):
    box('foundation',(0,.25,0),(w+.3,.5,d+.25),'brick')
    box('walls',(0,h/2+.4,0),(w,h,d),'plaster')
    for x in (-w/2,0,w/2):
        for z in (-d/2-.03,d/2+.03):box('timber_post',(x,h/2+.3,z),(.19,h+.2,.18),'wood')
    for y in (.6,2.2,h+.4):
        for z in (-d/2-.06,d/2+.06):box('timber_course',(0,y,z),(w+.1,.2,.18),'wood')
        for x in (-w/2-.05,w/2+.05):box('side_course',(x,y,0),(.16,.2,d),'wood')
    for x in (-w/2+.1,w/2-.1):
        beam('brace',(x,2.3,d/2+.1),(x+(.9 if x<0 else -.9),3.1,d/2+.1),.13,'wood')
    box('door_frame',(-.65,1.15,d/2+.09),(1.1,1.85,.15),'wood')
    box('door',(-.65,1.12,d/2+.18),(.86,1.64,.12),'wood')
    box('door_handle',(-.34,1.03,d/2+.28),(.05,.13,.08),'iron')
    for i in range(3):box('step',(-.65,.08+i*.1,d/2+.65-i*.2),(1.65,.16+i*.2,.5),'stone')
    for x in (-w*.29,w*.29):
        window(x,3.25,d/2+.05)
    window(w*.28,1.35,d/2+.05,1.0,.9)
    roof('main_roof',w+.8,d+.85,h+.45,1.65)
    box('chimney',(w*.31,h+1.45,-d*.23),(.67,2.2,.67),'brick')
    box('chimney_cap',(w*.31,h+2.58,-d*.23),(.87,.17,.85),'stone')
    if inn:
        # Small projecting balcony and supported shop canopy.
        box('balcony_floor',(0,2.28,d/2+.5),(w+.3,.17,1.1),'wood')
        for x in (-w/2,-w/4,0,w/4,w/2):
            box('baluster',(x,2.72,d/2+1.0),(.09,.9,.09),'wood')
        box('balcony_rail',(0,3.16,d/2+1),(w+.2,.1,.12),'wood')
        for x in (-w/2+.1,w/2-.1):box('canopy_post',(x,1.2,d/2+1.55),(.13,2.4,.13),'wood')
        canopy=box('canvas_canopy',(0,2.3,d/2+.83),(w+.4,.12,1.8),'canvas')
        canopy.rotation_euler.x=math.radians(8)
        beam('sign_bracket',(w/2-.2,2.6,d/2+.1),(w/2-.2,2.6,d/2+1.3),.09,'iron')
        box('inn_sign',(w/2-.2,2.13,d/2+1.27),(.88,.63,.13),'wood')
        box('sign_emblem',(w/2-.2,2.13,d/2+1.36),(.24,.29,.035),'glass')

def bridge():
    # Traversable top y=0.14; decorative arch is below walk plane.
    box('bridge_deck',(0,.04,0),(2.65,.28,6.0),'stone')
    for x in (-1.39,1.39):
        for i in range(16):
            z=-3+i*.4
            box('parapet_stone',(x,.43,z),(.29,.59,.39),'brick')
            box('parapet_cap',(x,.76,z),(.39,.14,.42),'stone')
        for end in (-1,1):box('abutment',(x,-.64,end*2.62),(.6,1.62,.9),'brick')
        # Ring of individually articulated arch stones visible from river.
        for i in range(14):
            theta=(i+.5)*math.pi/14
            z=2.42*math.cos(theta);y=-1.88+1.72*math.sin(theta)
            o=box('arch_voussoir',(x,y,z),(.48,.46,.54),'brick')
            o.rotation_euler.x=math.pi/2-theta
    for z in (-2.65,2.65):box('end_paving',(0,.18,z),(2.6,.12,.7),'stone')

def lantern():
    box('foot',(0,.1,0),(.52,.2,.52),'stone')
    box('lamp_post',(0,1.35,0),(.15,2.6,.15),'wood')
    beam('crook',(0,2.55,0),(.55,2.55,0),.09,'iron')
    box('cap',(.52,2.27,0),(.44,.09,.4),'iron')
    box('glass',(.52,2.0,0),(.33,.49,.29),'glass')
    box('base',(.52,1.72,0),(.4,.09,.36),'iron')
    for x in (.34,.7):
        for z in (-.16,.16):box('cage',(x,2.0,z),(.035,.55,.035),'iron')

def barrel():
    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=.38,depth=.83,location=xyz((0,.42,0)))
    o=bpy.context.object;o.name='staves';material(o,'wood')
    for h in (.13,.69):
        bpy.ops.mesh.primitive_torus_add(major_segments=12,minor_segments=4,major_radius=.37,minor_radius=.035,location=xyz((0,h,0)))
        material(bpy.context.object,'iron')

def crate():
    box('crate',(0,.43,0),(.87,.86,.87),'wood')
    for x in (-.43,.43):
        for z in (-.46,.46):box('corner',(x,.43,z),(.1,.9,.09),'wood')
    for z in (-.48,.48):
        beam('brace',(-.4,.07,z),(.4,.79,z),.11,'wood')

def dock():
    for i in range(14):box('dock_plank',(0,.12,-2+i*.32),(2.3,.18,.29),'wood')
    for x in (-1,1):
        for z in (-1.8,1.7):box('piling',(x,-.28,z),(.17,1.8,.17),'wood')
    for x in (-.85,.85):box('joist',(x,-.08,0),(.15,.24,4.4),'wood')

def tree_trunk():
    beam('trunk',(0,0,0),(.1,3,0),.39,'wood')
    for sign in (-1,1):
        beam('branch',(.05,1.7,0),(sign*.95,3,.2),.19,'wood')
        beam('root',(0,.06,0),(sign*.65,.02,.25),.18,'wood')

def export(name):
    # Merge by material to control draw-call count; keep logical material grouping.
    for mat in MATS.values():
        obs=[o for o in bpy.context.scene.objects if o.type=='MESH' and mat.name in [m.name for m in o.data.materials if m]]
        if not obs:continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in obs:o.select_set(True)
        bpy.context.view_layer.objects.active=obs[0]
        bpy.ops.object.join();obs[0].name=f'{name}_{mat.name}'
    for im in bpy.data.images:
        if im.filepath: im.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/f'{name}.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'{name}.glb'),export_format='GLB',export_yup=True,export_apply=True,export_cameras=False,export_lights=False)
    stats={'name':name,'objects':len(bpy.context.scene.objects),'vertices':sum(len(o.data.vertices) for o in bpy.context.scene.objects if o.type=='MESH'),'blend':f'art_source/blender/{name}.blend','glb':f'assets/models/{name}.glb'}
    RESULTS.append(stats);print('MODEL_OK',json.dumps(stats),flush=True)

for name,fn in [('inn',lambda:house()),('cottage',lambda:house(4.4,3.4,3.1,False)),('bridge',bridge),('lantern',lantern),('barrel',barrel),('crate',crate),('dock',dock),('tree_trunk',tree_trunk)]:
    reset();fn();export(name)
(ROOT/'art_source/blender/manifest.json').write_text(json.dumps({'generator':'tools/build_models.py','source_type':'procedural-original','blender':bpy.app.version_string,'models':RESULTS},indent=2)+'\n')
print('ALL_MODELS_OK',flush=True)
