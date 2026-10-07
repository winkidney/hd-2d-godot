"""Author the Jiangnan kit. Python --textures prepares images; Blender builds GLBs.

Game dimensions use metres and Y up. Only xyz() changes the basis, and GLTF's
standard exporter converts Blender Z up back to Y up once. No scene generation.
"""
from pathlib import Path
import hashlib
import json
import math
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source/ancient-canal"
TEXTURES = ROOT / "assets/ancient-canal/textures"
BLENDS = SOURCE / "blender"
MODELS = ROOT / "assets/ancient-canal/models"
SEED = 20261007
MATS = {}
RESULTS = []


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_textures():
    """Diffuse is sourced from ImageGen; relief is separately authored geometry."""
    import numpy as np
    from PIL import Image, ImageDraw
    TEXTURES.mkdir(parents=True, exist_ok=True)
    image = Image.open(SOURCE / "textures/mother-sheet.png").convert("RGB")
    sw, sh = image.size
    materials = ["roof", "wood", "stone", "plaster", "indigo", "red"]
    report = []
    y, x = np.mgrid[0:256, 0:256]
    for index, name in enumerate(materials):
        col, row = index % 3, index // 3
        rect = [col * sw // 3, row * sh // 2, (col+1)*sw//3, (row+1)*sh//2]
        panel = image.crop(rect).resize((256, 256), Image.Resampling.NEAREST)
        # A 128 px mirrored quadrant preserves the mother's clusters and gives
        # exact matching border pixels on both repeat axes. No light is baked.
        patch = panel.crop((32, 32, 160, 160))
        color = Image.new("RGB", (256, 256))
        color.paste(patch, (0, 0))
        color.paste(patch.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (128, 0))
        color.paste(patch.transpose(Image.Transpose.FLIP_TOP_BOTTOM), (0, 128))
        color.paste(patch.transpose(Image.Transpose.ROTATE_180), (128, 128))
        color.save(TEXTURES / (name + ".png"))
        # Authored relief uses material construction only; no color sampling.
        layer = Image.new("L", (256, 256), 160)
        draw = ImageDraw.Draw(layer)
        features = []
        if name == "roof":
            for cx in [12, 55, 98, 157, 200, 243]:
                draw.line((cx, 0, cx, 255), fill=64, width=3)
                draw.line((cx+3, 0, cx+3, 255), fill=212, width=2)
                features.append({"type":"tile_channel", "x":cx, "width":3})
            for cy in [26, 66, 106, 149, 189, 229]:
                draw.line((0, cy, 255, cy), fill=88, width=2)
                features.append({"type":"tile_overlap", "y":cy, "width":2})
        elif name == "wood":
            for cx in [20, 64, 108, 147, 191, 235]:
                draw.line((cx, 0, cx, 255), fill=72, width=2)
                features.append({"type":"plank_seam", "x":cx})
            for n in range(28):
                cx = (n * 41 + 13) % 256
                points = [(cx + int(2*math.sin(yy*.08+n)), yy) for yy in range(0,256,4)]
                draw.line(points, fill=148 if n % 2 else 176, width=1)
                features.append({"type":"grain", "points":points})
        elif name == "stone":
            for cy in [0, 52, 104, 152, 204, 255]:
                draw.line((0, cy, 255, cy), fill=38, width=3)
            for row_index, (ya,yb) in enumerate([(0,52),(52,104),(104,152),(152,204),(204,255)]):
                for cx in range(0,256,64):
                    xx = (cx + (32 if row_index%2 else 0))%256
                    draw.line((xx, ya, xx, yb), fill=38, width=3)
                    draw.line((xx+3, ya+3, xx+3, yb-3), fill=198, width=1)
                    features.append({"type":"mortar", "points":[[xx,ya],[xx,yb]]})
        elif name in ("indigo", "red"):
            for cy in range(8,256,16):
                draw.line((0,cy,255,cy), fill=164, width=1)
            # An editable embroidery relief, independent of pigment brightness.
            for cx in [64,192]:
                points = [(cx,66),(cx+35,128),(cx,190),(cx-35,128),(cx,66)]
                draw.line(points, fill=198, width=3)
                features.append({"type":"embroidered_diamond", "points":points})
        else:
            # Tiny authored plaster pits, no broad height inferred from age color.
            rng = np.random.default_rng(SEED)
            for cx,cy in rng.integers(8,248,(96,2)):
                draw.rectangle((int(cx),int(cy),int(cx)+1,int(cy)+1),fill=154)
            features.append({"type":"plaster_micro_pits", "seed":SEED, "count":96})
        h = np.asarray(layer,dtype=np.float32)/255.0
        # Enforce C1 periodic border heights before differentiating. Two matching
        # rows also make the decoded normal's repeat edge exactly identical.
        h[:,0:2] = h[:,-2:] = .625
        h[0:2,:] = h[-2:,:] = .625
        height = Image.fromarray((h*65535).astype(np.uint16))
        height.save(SOURCE / "textures" / (name + "-height.png"))
        dx = (np.roll(h,-1,1)-np.roll(h,1,1))*.8
        dy = (np.roll(h,-1,0)-np.roll(h,1,0))*.8
        normals = np.stack((-dx,dy,np.ones_like(h)),axis=2)
        normals /= np.linalg.norm(normals,axis=2,keepdims=True)
        # Eight-bit normal vectors retain material construction without palette.
        rgb = np.rint((normals*.5+.5)*255).astype(np.uint8)
        rgb[:,0] = rgb[:,-1] = [128,128,255]
        rgb[0,:] = rgb[-1,:] = [128,128,255]
        Image.fromarray(rgb).save(TEXTURES/(name+"_normal.png"))
        (SOURCE/"textures"/(name+"-structure.json")).write_text(json.dumps({
            "material":name,"size":[256,256],"geometry":features,
            "normal_basis":"OpenGL tangent: X right, Y up, Z outward",
            "height_source":"authored construction features, never diffuse luminance",
            "height_png":name+"-height.png", "normal_derivative_scale":.8,
            "periodic_border_height":.625},indent=2)+"\n")
        arr=np.asarray(color)
        assert np.array_equal(arr[:,0],arr[:,-1]) and np.array_equal(arr[0],arr[-1])
        assert np.array_equal(rgb[:,0],rgb[:,-1]) and np.array_equal(rgb[0],rgb[-1])
        length=np.linalg.norm(rgb.astype(float)/127.5-1,axis=2)
        assert abs(length-1).max()<.012
        report.append({"material":name,"mother_rect":rect,"quadrant_rect_after_resize":[32,32,160,160],
                       "color_sha256":digest(TEXTURES/(name+".png")),
                       "normal_sha256":digest(TEXTURES/(name+"_normal.png")),
                       "structure":name+"-structure.json","height":name+"-height.png",
                       "size":[256,256],"repeat_edges_equal":True,"normal_max_length_error":float(abs(length-1).max())})
    # Willow pigment derives the selected mother's stone pixel clusters; leaf
    # geometry and veins are independently authored. No new generation claimed.
    leaf=np.asarray(Image.open(TEXTURES/"stone.png").convert("RGB"),dtype=float)
    leaf=np.clip(leaf*np.array([.43,.67,.38]),0,255).astype(np.uint8)
    Image.fromarray(leaf).save(TEXTURES/"leaf.png")
    leaf_height=Image.new("L",(256,256),160);leaf_draw=ImageDraw.Draw(leaf_height)
    leaf_draw.line((128,8,128,247),fill=194,width=3)
    veins=[]
    for yy in range(32,225,24):
        for side in [-1,1]:
            segment=[(128,yy),(128+side*70,yy+29)]
            leaf_draw.line(segment,fill=179,width=1);veins.append(segment)
    leaf_height.save(SOURCE/"textures/leaf-height.png")
    h=np.asarray(leaf_height,dtype=float)/255
    dx=(np.roll(h,-1,1)-np.roll(h,1,1))*.8;dy=(np.roll(h,-1,0)-np.roll(h,1,0))*.8
    normals=np.stack([-dx,dy,np.ones_like(h)],axis=2);normals/=np.linalg.norm(normals,axis=2,keepdims=True)
    leaf_normal=np.rint((normals*.5+.5)*255).astype(np.uint8)
    Image.fromarray(leaf_normal).save(TEXTURES/"leaf_normal.png")
    (SOURCE/"textures/leaf-structure.json").write_text(json.dumps({"material":"leaf","size":[256,256],
        "geometry":{"midrib":[[128,8],[128,247]],"veins":veins},
        "normal_basis":"OpenGL tangent: X right, Y up, Z outward",
        "height_source":"authored leaf veins, never diffuse luminance"},indent=2)+"\n")
    assert np.array_equal(leaf[:,0],leaf[:,-1]) and np.array_equal(leaf[0],leaf[-1])
    assert np.array_equal(leaf_normal[:,0],leaf_normal[:,-1]) and np.array_equal(leaf_normal[0],leaf_normal[-1])
    report.append({"material":"leaf","color_source":"stone.png pixel clusters recolored by RGB [.43,.67,.38]",
        "color_sha256":digest(TEXTURES/"leaf.png"),"normal_sha256":digest(TEXTURES/"leaf_normal.png"),
        "size":[256,256],"repeat_edges_equal":True,"structure":"leaf-structure.json","height":"leaf-height.png"})
    (SOURCE/"textures/manifest.json").write_text(json.dumps({
        "schema_version":1,"generator":"tools/ancient_canal/build_models.py --textures",
        "imagegen":{"tool":"builtin image_gen","seed":None,"reference":"art_source/ancient-canal/concepts/2026-10-07/a-bridge-tavern/concept.png",
                    "prompt":"prompt.txt","original":"mother-sheet.png","sha256":digest(SOURCE/"textures/mother-sheet.png"),
                    "detail_reference":"tavern-detail-reference.png","detail_prompt":"detail-prompt.txt",
                    "detail_sha256":digest(SOURCE/"textures/tavern-detail-reference.png"),"calls":2},
        "process":"nearest resample, mirrored quadrant seamless assembly, authored geometric relief, wrapped central derivatives",
        "color_policy":"retain mother-sheet pixel clusters; no directional cast shadow generated or added",
        "normal_policy":"linear tangent vectors, no color palette reduction", "materials":report},indent=2)+"\n")
    preview=Image.new("RGB",(768,512))
    for index,name in enumerate(materials):
        preview.paste(Image.open(TEXTURES/(name+".png")),((index%3)*256,(index//3)*256))
    preview.save(SOURCE/"textures/pixel-material-preview.png")
    print("CANAL_TEXTURES_OK",len(report))


def xyz(p):
    return (p[0],-p[2],p[1])


def uv_world(obj, scale=1.0):
    mesh=obj.data
    uv=mesh.uv_layers.active or mesh.uv_layers.new(name="UVMap")
    # Consistent per-face signed planar tangent basis; exporter writes tangents.
    for face in mesh.polygons:
        axis=max(range(3),key=lambda k:abs(face.normal[k]))
        axes=[i for i in range(3) if i!=axis]
        for li in face.loop_indices:
            v=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=(v[axes[0]]*scale,v[axes[1]]*scale)


def apply(obj, mat):
    obj.data.materials.append(MATS[mat])
    return obj


def box(name,p,size,mat="wood"):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p))
    obj=bpy.context.object;obj.name=name;obj.scale=(size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    uv_world(obj,.7 if mat=="wood" else 1.0)
    return apply(obj,mat)


def beam(name,a,b,width,mat="wood"):
    a,b=Vector(xyz(a)),Vector(xyz(b));delta=b-a
    bpy.ops.mesh.primitive_cube_add(size=1,location=(a+b)/2)
    obj=bpy.context.object;obj.name=name;obj.scale=(width,width,delta.length)
    obj.rotation_euler=delta.to_track_quat("Z","Y").to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    uv_world(obj,.8)
    return apply(obj,mat)


def mesh_obj(name,verts,faces,mat):
    data=bpy.data.meshes.new(name)
    data.from_pydata([xyz(v) for v in verts],[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(data);bm.free()
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
    uv_world(obj);return apply(obj,mat)


def cylinder(name,p,radius,height,mat,vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=height,location=xyz(p))
    obj=bpy.context.object;obj.name=name;uv_world(obj)
    return apply(obj,mat)


def tube(name,a,b,radius,mat,vertices=8):
    av,bv=Vector(xyz(a)),Vector(xyz(b));delta=bv-av
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=delta.length,location=(av+bv)/2)
    obj=bpy.context.object;obj.name=name;obj.rotation_euler=delta.to_track_quat("Z","Y").to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    uv_world(obj);return apply(obj,mat)


def reset():
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    for material in list(bpy.data.materials): bpy.data.materials.remove(material)
    for mesh in list(bpy.data.meshes):
        if mesh.users==0:bpy.data.meshes.remove(mesh)
    for image in list(bpy.data.images):
        if image.users==0:bpy.data.images.remove(image)
    MATS.clear()
    colors={"roof":(.15,.20,.26,1),"wood":(.25,.12,.06,1),"stone":(.55,.57,.59,1),
            "plaster":(.86,.84,.77,1),"indigo":(.10,.18,.33,1),"red":(.58,.09,.07,1),
            "dark":(.035,.042,.05,1),"brass":(.65,.43,.18,1),"paper":(1,.46,.10,1),
            "ceramic":(.10,.13,.17,1),"leaf":(.10,.25,.16,1),"produce":(.79,.38,.13,1)}
    for name,color in colors.items():
        mat=bpy.data.materials.new("canal_"+name);mat.use_nodes=True;mat.diffuse_color=color
        bs=mat.node_tree.nodes.get("Principled BSDF");bs.inputs["Base Color"].default_value=color
        bs.inputs["Roughness"].default_value=.85 if name not in ("brass","ceramic") else .32
        if name=="brass":bs.inputs["Metallic"].default_value=.75
        if name=="paper":
            bs.inputs["Emission Color"].default_value=color;bs.inputs["Emission Strength"].default_value=.6
        path=TEXTURES/(name+".png")
        if path.exists():
            node=mat.node_tree.nodes.new("ShaderNodeTexImage");node.image=bpy.data.images.load(str(path),check_existing=True)
            node.interpolation="Closest";node.extension="REPEAT"
            mat.node_tree.links.new(node.outputs["Color"],bs.inputs["Base Color"])
            normal_path=TEXTURES/(name+"_normal.png")
            normal=mat.node_tree.nodes.new("ShaderNodeTexImage");normal.image=bpy.data.images.load(str(normal_path),check_existing=True)
            normal.image.colorspace_settings.name="Non-Color";normal.interpolation="Closest";normal.extension="REPEAT"
            nmap=mat.node_tree.nodes.new("ShaderNodeNormalMap");nmap.inputs["Strength"].default_value=.8
            mat.node_tree.links.new(normal.outputs["Color"],nmap.inputs["Color"])
            mat.node_tree.links.new(nmap.outputs["Normal"],bs.inputs["Normal"])
        MATS[name]=mat


def curved_roof(w,d,eave_y,rise=1.2):
    """Thick hip roof, flared eaves, ridge roll, individual curved tile channels."""
    def height(x,z):
        t=abs(z)/(d/2)
        hip=max(0,abs(x)-w*.36)/(w*.14)
        return eave_y+rise*(1-t)-.38*hip*(1-t)+.23*t**5+.13*hip*t**4
    nx,nz=28,16
    vertices=[]
    for lower in [0,.13]:
        for j in range(nz+1):
            z=-d/2+j*d/nz
            for i in range(nx+1):
                x=-w/2+i*w/nx;vertices.append((x,height(x,z)-lower,z))
    stride=nx+1;layer=stride*(nz+1);faces=[]
    for j in range(nz):
        for i in range(nx):
            a=j*stride+i;faces.append((a,a+1,a+stride+1,a+stride))
            faces.append((layer+a,layer+a+stride,layer+a+stride+1,layer+a+1))
    for j in range(nz):
        for i in [0,nx]:
            a=j*stride+i;faces.append((a,a+stride,layer+a+stride,layer+a))
    for j in [0,nz]:
        for i in range(nx):
            a=j*stride+i;faces.append((a,layer+a,layer+a+1,a+1))
    mesh_obj("curved_hip_tile_roof",vertices,faces,"roof")
    # Raised channels follow the slope and flare; actual geometric silhouettes.
    count=int(w/.25)
    for i in range(count+1):
        x=-w/2+i*w/count
        for side in [-1,1]:
            for j in range(6):
                za=side*j*d/12;zb=side*(j+1)*d/12
                tube("roof_tile_roll",(x,height(x,za)+.035,za),(x,height(x,zb)+.035,zb),.043,"roof",6)
    tube("ridge_roll",(-w*.39,eave_y+rise+.05,0),(w*.39,eave_y+rise+.05,0),.12,"roof",10)
    for side in [-1,1]:
        x=side*w*.39
        beam("ridge_finial",(x,eave_y+rise,0),(x+side*.18,eave_y+rise+.16,0),.10,"roof")
    for side in [-1,1]:
        z=side*d/2
        beam("eave_fascia",(-w/2,height(-w/2,z)-.11,z),(w/2,height(w/2,z)-.11,z),.10,"wood")


def lattice_window(x,y,z,w,h,side=False):
    # Front +Z; side +X. Every lattice and frame has real depth.
    def window_box(label,u,v,size,mat):
        if side:return box(label,(x+.06+size[2]/2,y+v,z+u),(size[2],size[1],size[0]),mat)
        return box(label,(x+u,y+v,z+.06+size[2]/2),size,mat)
    window_box("window_recess",0,0,(w+.14,h+.14,.10),"dark")
    window_box("warm_window_paper",0,0,(w,h,.12),"paper")
    for u in [-w/2,w/2]:window_box("window_vertical_frame",u,0,(.075,h+.18,.19),"wood")
    for v in [-h/2,h/2]:window_box("window_horizontal_frame",0,v,(w+.20,.075,.19),"wood")
    for u in [-w*.30,-w*.10,w*.10,w*.30]:window_box("lattice_mullion",u,0,(.028,h,.21),"wood")
    for v in [-h*.30,0,h*.30]:window_box("lattice_crossbar",0,v,(w,.028,.21),"wood")
    for u in [-w*.37,0,w*.37]:
        for v in [-h*.4,h*.4]:
            window_box("lattice_key",u,v,(w*.14,.045,.23),"wood")
    window_box("stone_window_sill",0,-h/2-.13,(w+.24,.11,.36),"stone")


def building(w,d,total_h,tavern=False):
    wall_h=total_h-1.25
    box("stone_foundation",(0,.14,0),(w+.18,.28,d+.18),"stone")
    box("white_plaster_wall",(0,wall_h/2+.17,0),(w,wall_h,d),"plaster")
    floors=[.30,wall_h*.53,wall_h+.16] if tavern else [.28,wall_h+.16]
    for yy in floors:
        for zz in [-d/2,d/2]:box("front_rear_timber",(0,yy,zz),(w+.18,.14,.18))
        for xx in [-w/2,w/2]:box("side_timber",(xx,yy,0),(.18,.14,d+.18))
    for xx in [-w/2,-w*.25,0,w*.25,w/2]:
        for zz in [-d/2,d/2]:box("timber_upright",(xx,wall_h/2+.18,zz),(.14,wall_h+.05,.17))
    for xx in [-w/2,w/2]:
        for zz in [-d*.25,0,d*.25]:box("side_upright",(xx,wall_h/2+.18,zz),(.17,wall_h+.05,.14))
    front=d/2
    box("door_recess",(0,1.17,front+.03),(1.27,1.95,.14),"dark")
    for xx in [-.66,.66]:box("door_pillar",(xx,1.15,front+.16),(.12,2.18,.23))
    box("door_lintel",(0,2.22,front+.17),(1.45,.14,.25))
    for xx in [-.37,.37]:
        box("door_panel",(xx,1.1,front+.11),(.45,1.80,.10))
        cylinder("door_metal_stud",(xx,1.17,front+.19),.05,.06,"brass",8)
    for i in range(2):box("entrance_tread",(0,.08+i*.07,front+.42-i*.18),(1.6,.16+i*.14,.42),"stone")
    if tavern:
        for xx in [-w*.34,w*.34]:lattice_window(xx,1.28,front,1.35,1.65)
        for xx in [-w*.34,0,w*.34]:lattice_window(xx,3.64,front,1.35,1.37)
        for zz in [-d*.26,d*.26]:
            lattice_window(w/2,1.32,zz,1.3,1.5,True)
            lattice_window(w/2,3.64,zz,1.3,1.35,True)
        # Shallow balcony below windows; counter roof under it is real geometry.
        box("balcony_floor",(0,2.81,front+.4),(w+.25,.13,.86))
        for xx in [-w*.44,-w*.22,0,w*.22,w*.44]:box("balcony_post",(xx,3.13,front+.78),(.07,.72,.07))
        box("balcony_hand_rail",(0,3.52,front+.78),(w,.07,.07))
        for i in range(28):box("balcony_lattice",(-w/2+i*w/27,3.17,front+.78),(.028,.52,.04))
        # Thin curved secondary eave along front, kept below the upper windows.
        verts=[]
        for yy in [0,.10]:
            for zz in [front-.04,front+.48,front+1.00]:
                for xx in [-w/2-.27,w/2+.27]:
                    hh=2.77-(zz-front)*.31+.12*max(0,zz-front)**4
                    verts.append((xx,hh-yy,zz))
        mesh_obj("ground_floor_eave",verts,[(0,1,3,2),(2,3,5,4),(6,8,9,7),(8,10,11,9),(0,6,7,1),(4,5,11,10),(0,2,4,10,8,6),(1,7,9,11,5,3)],"roof")
        for xx in [-w*.42,w*.42]:
            beam("shop_eave_bracket",(xx,2.13,front),(xx,2.63,front+.8),.09)
        for xx in [-w*.45,-w*.22,0,w*.22,w*.45]:
            box("dougong_block",(xx,wall_h+.02,front),(.44,.16,.53))
            box("dougong_arms",(xx,wall_h+.14,front+.14),(.67,.10,.73))
            beam("eave_brace",(xx,wall_h-.34,front),(xx,wall_h+.14,front+.58),.07)
        for xx in [-w*.19,w*.19]:
            box("indigo_door_curtain",(xx,2.1,front+.96),(w*.30,.54,.04),"indigo")
    else:
        for xx in [-w*.3,w*.3]:lattice_window(xx,1.72,front,1.02,1.36)
        for zz in [-d*.23,d*.23]:lattice_window(w/2,1.72,zz,.92,1.2,True)
    curved_roof(w+.82,d+.76,wall_h-.05,1.09)


def bridge():
    count=24;span=4.2;width=2.8
    def top(x):return 1.3*(1-(x/span)**2)
    # Intrados is a real barrel arch. End springing below waterline; crown open.
    def bottom(x):return top(x)-.31-.73*(abs(x)/span)**4
    verts=[]
    for x in [-span+i*2*span/count for i in range(count+1)]:
        verts.extend([(x,top(x),-width/2),(x,top(x),width/2),
                      (x,bottom(x),-width/2),(x,bottom(x),width/2)])
    faces=[]
    for i in range(count):
        a=i*4;b=a+4
        faces.extend([(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a,a+2,b+2,b),(a+1,b+1,b+3,a+3)])
    faces.extend([(0,1,3,2),(count*4,count*4+2,count*4+3,count*4+1)])
    mesh_obj("stone_arch_barrel",verts,faces,"stone")
    # Individual arch rings and coping reveal the construction under sweep light.
    for side in [-1,1]:
        z=side*(width/2+.045)
        for i in range(count):
            xa=-span+i*2*span/count;xb=xa+2*span/count
            v=[(xa,bottom(xa),z-.07),(xb,bottom(xb),z-.07),(xb,bottom(xb)+.24,z-.07),(xa,bottom(xa)+.24,z-.07),
               (xa,bottom(xa),z+.07),(xb,bottom(xb),z+.07),(xb,bottom(xb)+.24,z+.07),(xa,bottom(xa)+.24,z+.07)]
            mesh_obj("arch_voussoir",v,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],"stone")
        for i in range(11):
            x=-span+i*2*span/10;y=top(x)
            box("bridge_rail_pillar",(x,y+.48,z),(.18,.92,.21),"stone")
            box("bridge_pillar_cap",(x,y+.97,z),(.28,.12,.30),"stone")
        for level in [.39,.75]:
            for i in range(count):
                xa=-span+i*2*span/count;xb=xa+2*span/count
                beam("stone_bridge_handrail",(xa,top(xa)+level,z),(xb,top(xb)+level,z),.09,"stone")
        for end in [-1,1]:box("bridge_abutment",(end*3.91,-.56,z),(.58,1.16,.40),"stone")


def stall(food=False):
    w,d=2.7,1.8
    for xx in [-w/2+.1,w/2-.1]:
        for zz in [-d/2+.06,d/2-.06]:box("stall_upright",(xx,1.2,zz),(.10,2.4,.10))
    box("stall_counter",(0,.91,.46),(w,.12,.81))
    box("stall_counter_front",(0,.44,.85),(w,.86,.10))
    for xx in [-w*.35,w*.35]:box("stall_side_leg",(xx,.43,0),(.13,.86,1.35))
    for zz in [-d/2,d/2]:box("stall_eave",(0,2.31,zz),(w+.24,.10,.13))
    # Curved canopy with real billow, UVs mapped as a single cloth unit.
    verts=[]
    for j in range(9):
        z=-1.06+j*2.15/8
        for xx in [-1.49,1.49]:verts.append((xx,2.39-.15*((z+.0)/1.06)**2,z))
    obj=mesh_obj("cloth_canopy",verts,[(i*2,i*2+2,i*2+3,i*2+1) for i in range(8)],"red" if food else "indigo")
    uv=obj.data.uv_layers.active
    for face in obj.data.polygons:
        for li in face.loop_indices:
            v=obj.data.vertices[obj.data.loops[li].vertex_index].co
            uv.data[li].uv=((v.x+1.49)/2.98,(-v.y+1.06)/2.15)
    for i in range(8):box("canopy_hanging_valance",(-1.30+i*.37,2.10,1.06),(.34,.28,.035),"red" if food else "indigo")
    if food:
        for xx in [-.85,0,.85]:
            box("food_tray",(xx,1.04,.38),(.65,.12,.57))
            for i in range(6):
                bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=.08,location=xyz((xx-.20+(i%3)*.2,1.15,.22+(i//3)*.25)))
                apply(bpy.context.object,"produce")
        cylinder("stew_pot",(.8,1.13,-.43),.23,.25,"ceramic",16)
    else:
        for i in range(5):
            box("folded_cloth",(-.90+i*.44,1.03+.018*(i%2),.45),(.37,.14,.62),"indigo" if i%2 else "red")
        for xx in [-.9,.9]:box("hanging_fabric",(xx,.63,.98),(.44,.62,.05),"indigo")


def bank_wall():
    box("retaining_blocks",(0,-.70,0),(3.0,1.4,.48),"stone")
    for i in range(6):box("bank_coping",(-1.25+i*.50,.025,0),(.47,.14,.63),"stone")


def dock():
    for i in range(12):box("dock_plank",(0,-.065,-1.375+i*.25),(2,.13,.225))
    for xx in [-.78,.78]:box("dock_joist",(xx,-.21,0),(.16,.23,3.0))
    for xx in [-.88,.88]:
        for zz in [-1.25,1.25]:
            cylinder("dock_piling",(xx,-.42,zz),.105,1.46,"wood",10)
            for yy in [.10,.14,.18]:cylinder("rope_binding",(xx,yy,zz),.121,.035,"plaster",10)


def boat():
    outline=[(-.48,-2.2),(.48,-2.2),(.74,-1.4),(.74,1.25),(.42,2.1),(0,2.35),(-.42,2.1),(-.74,1.25),(-.74,-1.4)]
    n=len(outline);v=[(x,.48,z) for x,z in outline]+[(x*.66,.04,z*.91) for x,z in outline]
    mesh_obj("timber_hull",v,[tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],"wood")
    for i,(x,z) in enumerate(outline):
        xn,zn=outline[(i+1)%n];beam("boat_gunwale",(x,.52,z),(xn,.52,zn),.08)
    for zz in [-1.6,-1.2,1.2,1.6]:box("boat_seat",(0,.43,zz),(1.20,.07,.28))
    # Woven curved cabin built as actual barrel vault, rib hoops and slat strips.
    for zz in [-.9,.9]:
        for i in range(12):
            a=i*math.pi/12;b=(i+1)*math.pi/12
            beam("cabin_rib",(.66*math.cos(a),.51+.67*math.sin(a),zz),(.66*math.cos(b),.51+.67*math.sin(b),zz),.035)
    for i in range(24):
        a=i*math.pi/24;b=(i+1)*math.pi/24
        mesh_obj("woven_cabin",[(.64*math.cos(a),.52+.65*math.sin(a),-.91),(.64*math.cos(b),.52+.65*math.sin(b),-.91),
                                 (.64*math.cos(b),.52+.65*math.sin(b),.91),(.64*math.cos(a),.52+.65*math.sin(a),.91)],[(0,1,2,3)],"wood")
    beam("boat_oar",(-.7,.6,1.3),(1.3,.55,2.1),.045)


def lantern():
    # Origin is the hanging point, as layout attaches lanterns under eaves.
    cylinder("hanging_loop",(0,-.05,0),.035,.10,"brass",8)
    cylinder("lantern_roof",(0,-.15,0),.19,.09,"red",8)
    cylinder("lantern_paper",(0,-.40,0),.17,.43,"paper",8)
    cylinder("lantern_base",(0,-.65,0),.20,.08,"red",8)
    for i in range(8):
        a=i*math.tau/8;x,z=.18*math.cos(a),.18*math.sin(a)
        beam("lantern_frame",(x,-.19,z),(x,-.61,z),.018,"red")
    for zz in [-.18,.18]:
        for yy in [-.3,-.5]:box("lantern_paper_crossbar",(0,yy,zz),(.30,.018,.018),"red")
    beam("lantern_tassel",(0,-.68,0),(0,-.88,0),.04,"red")


def streetlamp():
    """2.6 m timber post; +Z bracket places the paper centre at (0,2.2,.36)."""
    box("streetlamp_stone_foot",(0,.07,0),(.24,.14,.24),"stone")
    box("streetlamp_timber_post",(0,1.36,0),(.18,2.48,.18),"wood")
    box("streetlamp_post_crown",(0,2.60,0),(.25,.08,.25),"roof")
    box("streetlamp_lantern_arm",(0,2.56,.22),(.075,.08,.52),"wood")
    beam("streetlamp_arm_brace",(0,2.08,.065),(0,2.53,.40),.065,"wood")
    for yy in [.17,.25,2.34,2.42]:
        box("streetlamp_metal_band",(0,yy,0),(.188,.035,.188),"brass")
    before=set(bpy.context.scene.objects)
    lantern()
    for obj in set(bpy.context.scene.objects)-before:
        obj.location+=Vector(xyz((0,2.6,.36)))


def wine_jar():
    profile=[(0,.24),(.05,.27),(.16,.37),(.40,.41),(.68,.29),(.74,.20),(.79,.21)]
    verts=[];n=16
    for yy,r in profile:
        for i in range(n):
            a=i*math.tau/n;verts.append((r*math.cos(a),yy,r*math.sin(a)))
    faces=[tuple(reversed(range(n)))]
    for j in range(len(profile)-1):
        for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    faces.append(tuple(range((len(profile)-1)*n,len(profile)*n)))
    mesh_obj("glazed_wine_jar",verts,faces,"ceramic")
    cylinder("red_jar_cover",(0,.80,0),.23,.045,"red",12)
    # Raised lacquer diamond motif, readable in native scene lighting.
    for a,b in [((0,.27,.416),(.16,.45,.37)),((.16,.45,.37),(0,.61,.335)),
                ((0,.61,.335),(-.16,.45,.37)),((-.16,.45,.37),(0,.27,.416))]:beam("jar_emblem",a,b,.023,"red")


def cloth_banner():
    tube("banner_rod",(-.43,.05,0),(.43,.05,0),.045,"wood",8)
    verts=[]
    for j in range(13):
        yy=-j*1.6/12
        for xx in [-.37,.37]:verts.append((xx,yy,.06*math.sin(j*.48)))
    obj=mesh_obj("embroidered_banner",verts,[(j*2,j*2+2,j*2+3,j*2+1) for j in range(12)],"indigo")
    for face in obj.data.polygons:
        for li in face.loop_indices:
            v=obj.data.vertices[obj.data.loops[li].vertex_index].co
            obj.data.uv_layers.active.data[li].uv=((v.x+.37)/.74,1+v.z/1.6)


def willow():
    import random
    rng=random.Random(SEED)
    path=[(0,0,0),(.10,1.0,-.03),(.22,2.0,.06),(.03,3.0,.15),(-.13,4.0,.03),(.0,4.8,0)]
    for i,(a,b) in enumerate(zip(path,path[1:])):tube("willow_curved_trunk",a,b,.22-i*.025,"wood",10)
    for side in [-1,1]:
        tube("willow_root",(.05,.17,.04),(side*.85,.04,.16),.11,"wood",8)
    # Branches lift first; their fine twigs hang downward in a willow's silhouette.
    for arm in range(9):
        angle=arm*math.tau/9+.14
        cx,cz=math.cos(angle),math.sin(angle)
        controls=[Vector((0,3.65+.1*(arm%3),0)),Vector((cx*.5,5.4+.10*(arm%2),cz*.5)),
                  Vector((cx*1.6,5.5-.12*(arm%3),cz*1.6)),Vector((cx*2.40,4.58-.10*(arm%3),cz*2.40))]
        def point(t):
            return controls[0]*(1-t)**3+controls[1]*(3*t*(1-t)**2)+controls[2]*(3*t*t*(1-t))+controls[3]*t**3
        for i in range(9):
            tube("willow_curved_branch",tuple(point(i/9)),tuple(point((i+1)/9)),.065*(1-i/9)+.011,"wood",8)
        for strand in range(5):
            t=.49+strand*.115
            anchor=point(t)
            sx,sz=anchor.x,anchor.z
            start_y=anchor.y
            previous=(sx,start_y,sz)
            drop=1.9+.48*rng.random()
            for j in range(8):
                yy=start_y-(j+1)*drop/8
                xx=sx+.12*math.sin(j*.55+arm)+rng.uniform(-.03,.03)
                zz=sz+.13*math.cos(j*.50+strand)
                current=(xx,yy,zz)
                tube("willow_hanging_twig",previous,current,.008,"wood",5)
                previous=current
                # Thin bent five-point leaves have area, normals and UVs. Each
                # triple is oriented in a different plane; there is no billboard.
                for side in [-1,1]:
                    rotation=angle+side*.65+.3*math.sin(j)
                    leaf_h=.27+rng.random()*.13
                    direction=Vector((math.cos(rotation),0,math.sin(rotation)))
                    center=Vector((xx,yy,zz))
                    points=[center+direction*side*.02,
                            center+direction*side*.16+Vector((0,-leaf_h*.38,0)),
                            center+direction*side*.19+Vector((0,-leaf_h,0)),
                            center+direction*side*.05+Vector((0,-leaf_h*.58,0)),
                            center+Vector((0,-leaf_h*.16,0))]
                    # Give the lamina a small 3D fold along its center.
                    points[1].y+=.02
                    normal=Vector((-math.sin(rotation),0,math.cos(rotation)))*.004
                    back=[p-normal for p in points]
                    faces=[(0,1,2,3,4),(9,8,7,6,5)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
                    obj=mesh_obj("willow_leaf",[tuple(p) for p in points+back],faces,"leaf")
                    uv_corners=[(.5,1),(1,.67),(.5,0),(0,.45),(.42,.85)]
                    for polygon in obj.data.polygons:
                        for corner,li in enumerate(polygon.loop_indices):
                            if len(polygon.loop_indices)==5:
                                obj.data.uv_layers.active.data[li].uv=uv_corners[obj.data.loops[li].vertex_index%5]
                            else:
                                obj.data.uv_layers.active.data[li].uv=[(0,0),(1,0),(1,.1),(0,.1)][corner]


def export(name):
    for material in MATS.values():
        objects=[o for o in bpy.context.scene.objects if o.type=="MESH" and material in list(o.data.materials)]
        if not objects:continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        if len(objects)>1:bpy.ops.object.join()
        objects[0].name=name+"_"+material.name
    mesh_objects=[o for o in bpy.context.scene.objects if o.type=="MESH"]
    # glTF tangent computation requires triangulable UV-mapped polygons.
    for obj in mesh_objects:
        bm=bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm,faces=bm.faces);bm.to_mesh(obj.data);bm.free()
        obj.data.calc_tangents(uvmap="UVMap")
    for image in bpy.data.images:
        if image.filepath:
            image.use_fake_user=True
            image.pack()
            image.filepath=bpy.path.relpath(image.filepath,start=str(BLENDS))
            for packed in image.packed_files:
                packed.filepath=image.filepath
    bpy.context.scene.render.filepath="//../../../build/ancient-canal/model-preview"
    blend=BLENDS/(name+".blend");glb=MODELS/(name+".glb")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.export_scene.gltf(filepath=str(glb),export_format="GLB",export_yup=True,export_apply=True,
                              export_cameras=False,export_lights=False,export_tangents=True)
    # Bounds in game coordinates from evaluated positions, after joining.
    points=[o.matrix_world@v.co for o in mesh_objects for v in o.data.vertices]
    game=[(p.x,p.z,-p.y) for p in points]
    result={"id":name,"blend":blend.relative_to(ROOT).as_posix(),"glb":glb.relative_to(ROOT).as_posix(),
            "vertices":sum(len(o.data.vertices) for o in mesh_objects),"triangles":sum(len(o.data.polygons) for o in mesh_objects),
            "material_meshes":len(mesh_objects),"glb_sha256":digest(glb),"blend_sha256":digest(blend),
            "bounds_min":[min(v[i] for v in game) for i in range(3)],"bounds_max":[max(v[i] for v in game) for i in range(3)],
            "uv_layers":1,"tangents":True,"packed_texture_images":len(bpy.data.images)}
    RESULTS.append(result);print("CANAL_MODEL_OK",name,result["triangles"],flush=True)


def main():
    BLENDS.mkdir(parents=True,exist_ok=True);MODELS.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    recipes=[("tavern",lambda:building(6,5,6,True)),("house",lambda:building(4.4,3.6,4.2)),
             ("bridge",bridge),("cloth_stall",stall),("food_stall",lambda:stall(True)),
             ("bank_wall",bank_wall),("dock",dock),("boat",boat),("lantern",lantern),
             ("wine_jar",wine_jar),("cloth_banner",cloth_banner),("willow",willow),
             ("streetlamp",streetlamp)]
    only=next((arg.split("=",1)[1] for arg in sys.argv if arg.startswith("--only=")),None)
    if only and (BLENDS/"manifest.json").exists():
        RESULTS.extend(m for m in json.loads((BLENDS/"manifest.json").read_text())["models"] if m["id"]!=only)
    for name,recipe in recipes:
        if only and only!=name:continue
        reset();recipe();export(name)
    if any(model["id"]=="streetlamp" for model in RESULTS):
        model=next(model for model in RESULTS if model["id"]=="streetlamp")
        model.update(source="art_source/ancient-canal/blender/streetlamp-source.json",
                     licence="original project-authored geometry; no third-party model",
                     pole_height=2.6,light_offset=[0,2.2,.36],collision_radius=.12)
        (BLENDS/"streetlamp-source.json").write_text(json.dumps({
            "schema_version":1,"id":"streetlamp","recipe":"tools/ancient_canal/build_models.py:streetlamp",
            "authorship":"Original deterministic geometry authored for this project",
            "licence":"Project owner may use, modify, export and redistribute the authored geometry without third-party model restrictions",
            "third_party_model":False,"imagegen_calls":0,
            "diffuse_source":"Existing selected-concept ImageGen mother-derived pixel textures; no new texture generation",
            "normal_source":"Existing independently authored tangent-space construction normals; never diffuse luminance",
            "texture_manifest_sha256":digest(SOURCE/"textures/manifest.json"),
            "basis":"Godot Y up via xyz, Blender Z up, glTF export_yup inverse once",
            "dimensions":{"pole_height":2.6,"pole_width":.18,"collision_radius":.12,
                          "hanging_point":[0,2.6,.36],"paper_light_centre":[0,2.2,.36]},
            "blend":model["blend"],"blend_sha256":model["blend_sha256"],
            "glb":model["glb"],"glb_sha256":model["glb_sha256"]},indent=2)+"\n")
    (BLENDS/"manifest.json").write_text(json.dumps({"schema_version":1,"seed":SEED,
        "generator":"tools/ancient_canal/build_models.py","blender":bpy.app.version_string,
        "basis":"Authored Godot Y up to Blender Z up via xyz; GLTF export_yup performs inverse once",
        "texture_manifest_sha256":digest(SOURCE/"textures/manifest.json"),
        "source_type":"authored true 3D geometry with ImageGen mother-derived pixel diffuse and independent geometric normal layers",
        "models":RESULTS},indent=2)+"\n")
    verify_sources()


def verify_sources():
    report=json.loads((BLENDS/"manifest.json").read_text())
    readback=[]
    for model in report["models"]:
        path=ROOT/model["blend"];assert digest(path)==model["blend_sha256"]
        bpy.ops.wm.open_mainfile(filepath=str(path))
        meshes=[o for o in bpy.context.scene.objects if o.type=="MESH"]
        assert len(meshes)==model["material_meshes"]
        assert sum(len(o.data.vertices) for o in meshes)==model["vertices"]
        assert all(image.packed_file for image in bpy.data.images if image.source=="FILE")
        for image in bpy.data.images:
            if image.source=="FILE":
                assert image.filepath.startswith("//")
                assert all(packed.filepath==image.filepath for packed in image.packed_files)
        for obj in meshes:
            assert len(obj.data.uv_layers)==1
            obj.data.calc_tangents(uvmap="UVMap")
            assert all(math.isfinite(c) for loop in obj.data.loops for c in loop.tangent)
        readback.append({"id":model["id"],"blend_sha256":digest(path),"glb_sha256":digest(ROOT/model["glb"]),
                         "vertices":model["vertices"],"material_meshes":len(meshes),
                         "packed_images":len([i for i in bpy.data.images if i.source=="FILE"]),
                         "reopened":True,"all_uv_and_tangents_valid":True})
        print("CANAL_BLEND_READBACK",model["id"],model["vertices"],flush=True)
    print("CANAL_BLEND_READBACK_COMPLETE",len(report["models"]),flush=True)
    (BLENDS/"source-validation.json").write_text(json.dumps({"schema_version":1,"passed":True,
        "scope":"Actual Blender reopen and packed source image/UV/tangent readback",
        "blender":bpy.app.version_string,"models":readback},indent=2)+"\n")
    verify_glb()


def verify_glb():
    import struct
    report=json.loads((BLENDS/"manifest.json").read_text())
    checks=[]
    for model in report["models"]:
        data=(ROOT/model["glb"]).read_bytes()
        magic,version,size=struct.unpack_from("<III",data)
        assert magic==0x46546C67 and version==2 and size==len(data)
        length,typ=struct.unpack_from("<II",data,12)
        assert typ==0x4E4F534A
        document=json.loads(data[20:20+length])
        offset=20+length
        buffer_length,buffer_type=struct.unpack_from("<II",data,offset)
        assert buffer_type==0x004E4942
        binary=data[offset+8:offset+8+buffer_length]
        def values(accessor_index):
            acc=document["accessors"][accessor_index]
            assert acc["componentType"]==5126
            width={"VEC2":2,"VEC3":3,"VEC4":4}[acc["type"]]
            view=document["bufferViews"][acc["bufferView"]]
            start=view.get("byteOffset",0)+acc.get("byteOffset",0)
            stride=view.get("byteStride",width*4)
            return [struct.unpack_from("<"+"f"*width,binary,start+i*stride) for i in range(acc["count"])]
        primitives=[p for mesh in document["meshes"] for p in mesh["primitives"]]
        max_orthogonality_error=0.;max_length_error=0.
        for primitive in primitives:
            attributes=primitive["attributes"]
            assert {"POSITION","NORMAL","TANGENT","TEXCOORD_0"}<=set(attributes),model["id"]
            normals=values(attributes["NORMAL"]);tangents=values(attributes["TANGENT"])
            for n,t in zip(normals,tangents):
                assert all(math.isfinite(v) for v in n+t)
                length=math.sqrt(sum(v*v for v in t[:3]))
                normal_length=math.sqrt(sum(v*v for v in n))
                dot=abs(sum(n[i]*t[i] for i in range(3)))
                # Blender's glTF exporter rounds tangent components to four
                # decimals. Account for the resulting angular/length error;
                # zero vectors and collapsed UV tangents still fail decisively.
                assert abs(length-1)<5e-4 and abs(normal_length-1)<5e-4 and dot<5e-4,model["id"]
                assert abs(abs(t[3])-1)<1e-6
                max_orthogonality_error=max(max_orthogonality_error,dot)
                max_length_error=max(max_length_error,abs(length-1),abs(normal_length-1))
            assert all(math.isfinite(v) for uv in values(attributes["TEXCOORD_0"]) for v in uv)
        assert all("uri" not in image for image in document.get("images",[])),model["id"]
        for sampler in document.get("samplers",[]):
            assert sampler.get("magFilter",9728)==9728
            assert sampler.get("wrapS",10497)==10497 and sampler.get("wrapT",10497)==10497
        checks.append({"model":model["id"],"sha256":digest(ROOT/model["glb"]),
                       "primitives":len(primitives),"embedded_images":len(document.get("images",[])),
                       "max_tangent_normal_dot":max_orthogonality_error,"max_vector_length_error":max_length_error,
                       "all_attributes_finite":True,"nearest_repeat_samplers":True})
    (BLENDS/"geometry-validation.json").write_text(json.dumps({"schema_version":1,
        "validation":"GLB bytes, independent accessor decoding, UV, orthogonal normalized tangent bases, embedded pixels",
        "models":checks,"pass":True},indent=2)+"\n")
    print("CANAL_GLB_ATTRIBUTES_OK",len(checks),flush=True)


def strip_preview_file_stamp(path):
    """Remove the Blender File text stamp without re-encoding pixel data."""
    data=path.read_bytes()
    assert data[:8]==b"\x89PNG\r\n\x1a\n"
    retained=[data[:8]];offset=8;removed=0
    while offset<len(data):
        length=int.from_bytes(data[offset:offset+4],"big")
        end=offset+length+12
        assert end<=len(data),"Truncated construction preview PNG"
        kind=data[offset+4:offset+8]
        payload=data[offset+8:offset+length+8]
        if kind in (b"tEXt",b"zTXt",b"iTXt") and payload.partition(b"\0")[0]==b"File":
            removed+=1
        else:retained.append(data[offset:end])
        offset=end
    result=b"".join(retained)
    if removed:path.write_bytes(result)
    return removed


def render_preview():
    """CPU construction preview, separate from the required Godot GPU evidence."""
    name=next((arg.split("=",1)[1] for arg in sys.argv if arg.startswith("--preview-model=")),"tavern")
    bpy.ops.wm.open_mainfile(filepath=str(BLENDS/(name+".blend")))
    scene=bpy.context.scene
    scene.render.engine="CYCLES";scene.cycles.device="CPU";scene.cycles.samples=16
    scene.cycles.max_bounces=3
    scene.render.resolution_x=1000;scene.render.resolution_y=850;scene.render.resolution_percentage=100
    scene.world.color=(.20,.20,.20)
    world=scene.world;world.use_nodes=True
    world.node_tree.nodes["Background"].inputs["Color"].default_value=(.35,.38,.43,1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value=.6
    bpy.ops.object.camera_add(location=xyz((9,7.8,12)))
    camera=bpy.context.object;camera.rotation_euler=(Vector(xyz((0,2.9,0)))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO";camera.data.ortho_scale=10.2;scene.camera=camera
    bpy.ops.object.light_add(type="AREA",location=xyz((-4,10,8)))
    light=bpy.context.object;light.data.energy=1500;light.data.shape="DISK";light.data.size=7
    light.rotation_euler=(Vector(xyz((0,2,0)))-light.location).to_track_quat("-Z","Y").to_euler()
    scene.render.film_transparent=False;scene.view_settings.view_transform="Standard"
    # Blender writes this stamp into PNG metadata even without a visible overlay.
    scene.render.use_stamp_filename=False
    scene.render.filepath=str(BLENDS/(name+"-construction-preview.png"))
    bpy.ops.render.render(write_still=True)
    strip_preview_file_stamp(BLENDS/(name+"-construction-preview.png"))


if __name__=="__main__":
    if "--textures" in sys.argv:prepare_textures()
    elif "--verify-glb" in sys.argv:verify_glb()
    else:
        import bpy,bmesh
        from mathutils import Vector
        if "--verify-only" in sys.argv:verify_sources()
        elif "--render-preview" in sys.argv:render_preview()
        else:main()
        if "--batch-exit" in sys.argv:
            # This container's PulseAudio teardown blocks after Blender work has
            # completed. Only explicit batch callers request immediate exit.
            import os
            sys.stdout.flush();sys.stderr.flush();os._exit(0)
