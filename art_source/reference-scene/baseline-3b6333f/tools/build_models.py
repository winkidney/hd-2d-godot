"""Canal kit authored in Godot coordinates and exported using Blender."""
from pathlib import Path
import bpy, bmesh, math, json, hashlib
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/reference-scene/models'
SOURCE=ROOT/'art_source/reference-scene/blender'
TEXTURES=ROOT/'assets/reference-scene/textures'
MATS={}
RESULTS=[]

def xyz(p):
    return (p[0],-p[2],p[1])

def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    MATS.clear()
    colors={'brick':(.53,.29,.20,1),'stone':(.62,.58,.48,1),'paving':(.60,.56,.46,1),'plaster':(.78,.65,.46,1),'roof':(.48,.19,.08,1),'wood':(.29,.19,.10,1),'canvas':(.80,.75,.59,1),'green':(.10,.21,.12,1),'iron':(.06,.13,.10,1),'glass':(1,.58,.21,1),'red':(.62,.09,.04,1),'leaf':(.13,.26,.09,1),'gold':(.79,.49,.14,1)}
    decals=['door_green','window_arch','window_shutter','flowerbox','sign_banner','sign_menu','planter','awning_green']
    for name in list(colors)+decals:
        color=colors.get(name,(1,1,1,1))
        mat=bpy.data.materials.new('p9_'+name)
        mat.diffuse_color=color
        mat.use_nodes=True
        bs=mat.node_tree.nodes.get('Principled BSDF')
        bs.inputs['Base Color'].default_value=color
        bs.inputs['Roughness'].default_value=.88
        tex=TEXTURES/(name+'.png')
        if tex.exists():
            node=mat.node_tree.nodes.new('ShaderNodeTexImage')
            node.image=bpy.data.images.load(str(tex),check_existing=True)
            node.interpolation='Closest'
            mat.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color'])
            if name in decals and name!='awning_green':
                mat.node_tree.links.new(node.outputs['Alpha'],bs.inputs['Alpha'])
                mat.surface_render_method='DITHERED'
        if name=='glass':
            bs.inputs['Emission Color'].default_value=color
            bs.inputs['Emission Strength'].default_value=2.4
        MATS[name]=mat

def apply(obj,mat):
    obj.data.materials.append(MATS[mat])
    return obj

def uv_world(obj,scale=.65):
    mesh=obj.data
    uv=mesh.uv_layers.active or mesh.uv_layers.new(name='UVMap')
    for face in mesh.polygons:
        axis=max(range(3),key=lambda k:abs(face.normal[k]))
        axes=[i for i in range(3) if i!=axis]
        for li in face.loop_indices:
            v=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=(v[axes[0]]*scale,v[axes[1]]*scale)

def box(name,p,size,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p))
    obj=bpy.context.object; obj.name=name
    obj.scale=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    uv_world(obj)
    return apply(obj,mat)

def beam(name,a,b,width,mat):
    a,b=Vector(xyz(a)),Vector(xyz(b)); delta=b-a
    bpy.ops.mesh.primitive_cube_add(size=1,location=(a+b)/2)
    obj=bpy.context.object; obj.name=name
    obj.scale=(width,width,delta.length)
    obj.rotation_euler=delta.to_track_quat('Z','Y').to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    uv_world(obj)
    return apply(obj,mat)

def mesh_obj(name,verts,faces,mat):
    data=bpy.data.meshes.new(name)
    data.from_pydata([xyz(v) for v in verts],[],faces)
    data.update()
    bm=bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    bm.to_mesh(data); bm.free()
    obj=bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(obj)
    apply(obj,mat); uv_world(obj)
    return obj

def decal(name,p,w,h,mat):
    x,y,z=p
    obj=mesh_obj(name,[(x-w/2,y-h/2,z),(x+w/2,y-h/2,z),(x+w/2,y+h/2,z),(x-w/2,y+h/2,z)],[(0,1,2,3)],mat)
    uv=obj.data.uv_layers.active
    for face in obj.data.polygons:
        for li in face.loop_indices:
            v=obj.data.vertices[obj.data.loops[li].vertex_index].co
            uv.data[li].uv=((v.x-(x-w/2))/w,(v.z-(y-h/2))/h)
    return obj

def cylinder(name,p,radius,height,mat,vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=height,location=xyz(p))
    obj=bpy.context.object;obj.name=name;uv_world(obj)
    return apply(obj,mat)

def stone_pillar(p=(0,0,0),h=1.5):
    x,y,z=p
    box('pillar_foot',(x,y+.09,z),(.82,.18,.82),'stone')
    box('pillar',(x,y+h/2,z),(.64,h,.64),'stone')
    box('pillar_cap',(x,y+h,z),(.88,.14,.88),'stone')
    box('plaque',(x,y+h*.59,z+.327),(.45,.48,.045),'iron')
    for sx in [-1,1]: beam('carved_inlay',(x+sx*.15,y+h*.42,z+.36),(x-sx*.15,y+h*.70,z+.36),.04,'stone')

def railing(length=2.5,p=(0,0,0)):
    x,y,z=p
    for level in [.17,1.0]: box('rail',(x,y+level,z),(length,.075,.07),'iron')
    n=max(1,round(length/.6))
    for i in range(n):
        a=x-length/2+i*length/n;b=a+length/n
        beam('diamond',(a,y+.2,z),(b,y+.94,z),.04,'iron')
        beam('diamond',(a,y+.94,z),(b,y+.2,z),.04,'iron')
    for sx in [-1,1]: cylinder('railpost',(x+sx*length/2,y+.55,z),.055,1.15,'iron',8)

def bridge():
    box('deck',(0,-.12,0),(10,.24,4.0),'paving')
    for z in [-1.82,1.82]:
        for i in range(22):
            a=i*math.pi/22;b=(i+1)*math.pi/22
            verts=[]
            for depth in [z-.22,z+.22]:
                for radius,theta in [(3.45,a),(3.95,a),(3.95,b),(3.45,b)]:
                    verts.append((radius*math.cos(theta),-4.0+radius*math.sin(theta),depth))
            mesh_obj('arch_block',verts,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],'stone')
        for side in [-1,1]:
            box('abutment',(side*4.43,-1.6,z),(.98,3.2,.6),'brick')
        for x in [-4.2,0,4.2]: stone_pillar((x,0,z),1.45)
        for x in [-2.1,2.1]: railing(3.4,(x,.08,z))
        box('coping',(0,.06,z),(9.9,.18,.75),'stone')
    for z in [-1.82,1.82]:
        for i in range(20):
            a=-3.85+i*7.7/20; b=a+7.7/20
            ya=min(-.18,-4+math.sqrt(max(0,3.95**2-a*a)))
            yb=min(-.18,-4+math.sqrt(max(0,3.95**2-b*b)))
            verts=[(a,ya,z-.16),(b,yb,z-.16),(b,-.14,z-.16),(a,-.14,z-.16),(a,ya,z+.16),(b,yb,z+.16),(b,-.14,z+.16),(a,-.14,z+.16)]
            mesh_obj("brick_spandrel",verts,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],"brick")
    for i in range(15):
        x=-3.25+i*6.5/14; top=-4+math.sqrt(3.45**2-x*x)
        beam('gate_vertical',(x,-3.8,1.5),(x,top,1.5),.085,'iron')
    for y in [-3.1,-2.25,-1.5]: box('gate_crossbar',(0,y,1.5),(6.4,.10,.12),'iron')

def stairs(w=3.6,run=4.2,rise=2.8):
    # Origin is the bottom/front lip; rise toward negative Z.
    count=14
    for i in range(count):
        h=(i+1)*rise/count;z=-(i+.5)*run/count
        box('tread',(0,h/2,z),(w,h,run/count+.025),'stone')
        box('nosing',(0,h-.035,z+run/count*.46),(w+.06,.07,.09),'paving')
    for side in [-1,1]:
        beam('stair_cheek',(side*(w/2+.10),.18,0),(side*(w/2+.10),rise+.18,-run),.25,'stone')

def roof(w,d,y,rise):
    verts=[(-w/2,y,-d/2),(w/2,y,-d/2),(w/2,y,d/2),(-w/2,y,d/2),(0,y+rise,-d/2),(0,y+rise,d/2)]
    mesh_obj('terracotta_roof',verts,[(0,4,5,3),(4,1,2,5),(0,1,4),(3,5,2),(0,3,2,1)],'roof')
    for z in [-d/2,d/2]:
        beam('roof_edge',(-w/2,y,z),(0,y+rise,z),.12,'roof')
        beam('roof_edge',(0,y+rise,z),(w/2,y,z),.12,'roof')
    beam('roof_ridge',(0,y+rise,-d/2),(0,y+rise,d/2),.20,'roof')

def house(w=7,d=5,h=6.8,balcony=True):
    box('foundation',(0,.18,0),(w+.3,.36,d+.3),'stone')
    box('brick_base',(0,1.45,0),(w,2.9,d),'brick')
    box('upper_plaster',(0,(h+2.9)/2,0),(w,h-2.9,d),'plaster')
    for y in [.45,2.9,h]:
        box('facade_belt',(0,y,d/2+.08),(w+.24,.19,.24),'stone')
    for x in [-w/2,w/2]:
        for y in [0.6,1.1,1.6,2.1,2.6,3.1,4,4.8,5.6,6.4]:
            if y<h: box('corner_quoin',(x,y,d/2+.06),(.42,.22,.22),'brick')
    decal('arched_green_door',(-w*.20,1.55,d/2+.14),1.65,2.95,'door_green')
    for x in [-w*.32,0,w*.32]:
        decal('arched_window',(x,h-1.4,d/2+.15),1.45,1.75,'window_arch')
        decal('window_flowers',(x,h-2.22,d/2+.22),1.5,.63,'flowerbox')
    decal('shutter_window',(w*.25,1.65,d/2+.14),1.6,2.0,'window_shutter')
    for x in [-w*.32,0,w*.32]:
        box('window_warmth',(x,h-1.42,d/2+.065),(.70,1.1,.04),'glass')
    roof(w+.8,d+.7,h+.07,1.2)
    box('chimney',(w*.32,h+.7,-.5),(.65,1.8,.65),'brick')
    box('chimney_cap',(w*.32,h+1.6,-.5),(.88,.16,.87),'stone')
    if balcony:
        box('balcony_slab',(0,3.1,d/2+.6),(w+.3,.2,1.35),'stone')
        railing(w-.2,(0,3.25,d/2+1.18))
        for x in [-w/2,w/2]: stone_pillar((x,3.15,d/2+1.1),1.1)
    beam('sign_bracket',(w/2-.45,3.0,d/2),(w/2-.45,3.0,d/2+1.4),.08,'iron')
    decal('hanging_sign',(w/2-.45,2.6,d/2+1.4),.85,1.2,'sign_banner')

def lamp():
    cylinder('base',(0,.13,0),.26,.26,'iron')
    cylinder('fluted_post',(0,1.45,0),.09,2.8,'iron')
    cylinder('collar',(0,2.68,0),.18,.12,'gold')
    box('lamp_glass',(0,3.08,0),(.35,.55,.35),'glass')
    for x in [-.21,.21]:
        for z in [-.21,.21]: beam('cage',(x,2.76,z),(x,3.42,z),.045,'iron')
    box('lamp_base',(0,2.76,0),(.51,.1,.51),'iron')
    roof(.64,.64,3.39,.27)
    cylinder('finial',(0,3.78,0),.085,.14,'gold',8)

def barrel():
    cylinder('staves',(0,.48,0),.43,.94,'wood',14)
    for h in [.16,.75]:
        bpy.ops.mesh.primitive_torus_add(major_segments=14,minor_segments=4,major_radius=.43,minor_radius=.035,location=xyz((0,h,0)))
        apply(bpy.context.object,'iron')

def crate():
    box('crate',(0,.44,0),(.9,.88,.9),'wood')
    for z in [-.46,.46]:
        for y in [.1,.76]: box('rim',(0,y,z),(.94,.11,.10),'wood')
        beam('crate_diagonal',(-.4,.08,z),(.4,.79,z),.10,'wood')

def market():
    for x in [-1.85,1.85]:
        for z in [-1,1]: box('market_post',(x,1.42,z),(.13,2.84,.13),'wood')
    box('market_counter',(0,.9,.65),(3.8,.65,.85),'wood')
    box('display_counter',(0,1.25,.25),(3.8,.12,1.7),'wood')
    verts=[(-2.15,2.9,-1.3),(2.15,2.9,-1.3),(-2.15,2.55,1.45),(2.15,2.55,1.45)]
    mesh_obj('canvas_cover',verts,[(0,2,3,1)],'canvas')
    box('cloth_valance',(0,2.39,1.45),(4.3,.32,.04),'canvas')
    for x in [-1.25,0,1.25]:
        box('produce_tray',(x,1.4,.50),(1.12,.17,.70),'wood')
        for i in range(8):
            bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=.11,location=xyz((x-.39+(i%4)*.25,1.56,.26+(i//4)*.27)))
            apply(bpy.context.object,'red' if x<0 else ('leaf' if x==0 else 'gold'))
    decal('menu',(2.0,.7,1.5),.7,1.2,'sign_menu')

def dock():
    for i in range(16): box('dock_plank',(0,.09,-2.3+i*.3),(4.0,.18,.275),'wood')
    for x in [-1.8,1.8]:
        for z in [-2,0,2]:
            cylinder('piling',(x,-.3,z),.13,1.7,'wood',10)
            cylinder('rope',(x,.35,z),.155,.12,'canvas',10)

def bench():
    for z in [-.22,0,.22]: box('bench_slats',(0,.54,z),(2.25,.10,.18),'wood')
    for y in [.82,1.1]: box('back_slats',(0,y,-.30),(2.25,.17,.10),'wood')
    for x in [-.85,.85]:
        for z in [-.23,.23]:box('bench_leg',(x,.26,z),(.10,.52,.10),'iron')
        beam('back_support',(x,.2,-.3),(x,1.2,-.3),.09,'iron')

def boat():
    outline=[(-.8,-2.1),(.8,-2.1),(1.05,-1.2),(1.05,1.3),(0,2.4),(-1.05,1.3),(-1.05,-1.2)]
    vertices=[(x,.65,z) for x,z in outline]+[(x*.64,.02,z*.87) for x,z in outline]
    faces=[tuple(range(7,14))]
    for i in range(7):
        faces.append((i,(i+1)%7,(i+1)%7+7,i+7))
    mesh_obj('boat_hull',vertices,faces,'wood')
    for i in range(7):
        x,z=outline[i]
        nx,nz=outline[(i+1)%7]
        beam('gunwale',(x,.7,z),(nx,.7,nz),.11,'wood')
    for z in [-1,0,1]:
        box('seat',(0,.44,z),(1.64,.10,.28),'wood')

def planter():
    box('planter_box',(0,.30,0),(1.7,.60,.65),'wood')
    for x in [-.55,0,.55]:
        decal('flowers',(x,.82,.01),.8,.80,'flowerbox')

def retaining():
    box('retaining_brick',(0,-1.45,0),(3,2.9,.55),'brick')
    box('capstone',(0,.035,0),(3.08,.16,.75),'stone')

def export(name):
    for mat in MATS.values():
        objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and mat in list(o.data.materials)]
        if not objects:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        bpy.ops.object.join()
        objects[0].name=name+'_'+mat.name
    for image in bpy.data.images:
        if image.filepath:
            image.pack()
    blend=SOURCE/(name+'.blend')
    glb=OUT/(name+'.glb')
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',export_yup=True,export_apply=True,export_cameras=False,export_lights=False)
    result={'id':name,'blend':blend.relative_to(ROOT).as_posix(),'glb':glb.relative_to(ROOT).as_posix(),
            'vertices':sum(len(o.data.vertices) for o in bpy.context.scene.objects if o.type=='MESH'),
            'objects':len(bpy.context.scene.objects),'glb_sha256':hashlib.sha256(glb.read_bytes()).hexdigest()}
    RESULTS.append(result)
    print('P9_MODEL',name,result['vertices'],flush=True)

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    SOURCE.mkdir(parents=True,exist_ok=True)
    recipes=[('arch_bridge',bridge),('stairs',stairs),('pillar',stone_pillar),('railing',railing),
             ('palazzo',house),('townhouse',lambda:house(4.8,4.2,5.4,False)),
             ('tower',lambda:house(3.8,4,10,False)),('market',market),('lamp',lamp),
             ('barrel',barrel),('crate',crate),('dock',dock),('bench',bench),
             ('boat',boat),('planter',planter),('retaining',retaining)]
    for name, build in recipes:
        reset()
        build()
        export(name)
    report={'schema':1,'source_type':'authored-blender-with-imagegen-derived-textures',
            'blender':bpy.app.version_string,'generator':'tools/p9/build_models.py',
            'input_manifest_sha256':hashlib.sha256((ROOT/'art_source/reference-scene/manifests/processed.json').read_bytes()).hexdigest(),
            'models':RESULTS}
    (ROOT/'art_source/reference-scene/manifests/models.json').write_text(json.dumps(report,indent=2)+'\n')
    print('P9_MODELS_COMPLETE',len(RESULTS),flush=True)

if __name__=='__main__':
    main()
