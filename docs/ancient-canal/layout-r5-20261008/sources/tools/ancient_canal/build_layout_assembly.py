"""Editable Blender assembly of the measured R5 layout; runtime remains instanced."""
from pathlib import Path
import hashlib
import json
import math
import os
import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'art_source/ancient-canal/layout-assembly/20261008-r5'
LAYOUT = json.loads((ROOT / 'resources/ancient-canal/layout.json').read_text())
BLUEPRINT = json.loads((ROOT / LAYOUT['blueprint']['path']).read_text())
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
PROTOTYPES = {}
RECORDS = []


def coordinates(point):
    return point[0], -point[2], point[1]


def material(name, color, texture=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = .95
    if texture:
        image = bpy.data.images.load(str(ROOT / texture), check_existing=True)
        node = mat.node_tree.nodes.new('ShaderNodeTexImage')
        node.image = image
        node.interpolation = 'Closest'
        mat.node_tree.links.new(node.outputs['Color'], shader.inputs['Base Color'])
        mat.node_tree.links.new(node.outputs['Alpha'], shader.inputs['Alpha'])
        if hasattr(mat, 'surface_render_method'):
            mat.surface_render_method = 'DITHERED'
    return mat


def prototype(asset):
    if asset not in PROTOTYPES:
        bpy.ops.object.select_all(action='DESELECT')
        path = ROOT / f'assets/ancient-canal/models/{asset}.glb'
        bpy.ops.import_scene.gltf(filepath=str(path))
        collection = bpy.data.collections.new('Source_' + asset)
        for obj in list(bpy.context.selected_objects):
            for parent in list(obj.users_collection):
                parent.objects.unlink(obj)
            collection.objects.link(obj)
        PROTOTYPES[asset] = collection
    return PROTOTYPES[asset]


def instance(asset, name, position, yaw=0, scale=(1, 1, 1)):
    obj = bpy.data.objects.new(name, None)
    obj.instance_type = 'COLLECTION'
    obj.instance_collection = prototype(asset)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = coordinates(position)
    obj.rotation_euler.z = math.radians(yaw)
    obj.scale = scale[0], scale[2], scale[1]
    obj['godot_position'] = position
    obj['source_asset'] = asset
    RECORDS.append(dict(id=name, asset=asset, godot_position=position, yaw=yaw))
    return obj


def mesh(name, vertices, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata([coordinates(v) for v in vertices], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    data.materials.append(mat)
    uv = data.uv_layers.new(name='World metres')
    for loop in data.loops:
        point = vertices[loop.vertex_index]
        uv.data[loop.index].uv = (point[0] * .5, point[2] * .5)
    return obj


def card(name, position, texture, pixel_size, offset_y, scale=1):
    from mathutils import Vector
    image = bpy.data.images.load(str(ROOT / texture), check_existing=True)
    width, height = (n * pixel_size * scale for n in image.size)
    center = offset_y * pixel_size * scale
    x, y, z = position
    obj = mesh(name, [[x-width/2,y+center-height/2,z], [x+width/2,y+center-height/2,z],
                      [x+width/2,y+center+height/2,z], [x-width/2,y+center+height/2,z]],
               [(0,1,2,3)], material(name+'_cutout', (1,1,1), texture))
    uv = obj.data.uv_layers.active
    for loop, coord in zip(obj.data.loops, [(0,0),(1,0),(1,1),(0,1)]):
        uv.data[loop.index].uv = coord
    obj['godot_foot_position'] = position
    obj['runtime_billboard'] = 'fixed_y'
    return obj


for kind, color in [('bank',(.38,.43,.35)),('street',(.57,.56,.50)),('court',(.48,.51,.43))]:
    vertices, faces = [], []
    for tile in LAYOUT['ground_tiles']:
        if tile['kind'] != kind:
            continue
        x0,z0,x1,z1 = tile['rect'];i=len(vertices)
        vertices.extend([[x0,0,z0],[x0,0,z1],[x1,0,z1],[x1,0,z0]])
        faces.append((i,i+1,i+2,i+3))
    mesh('GroundSurface_'+kind,vertices,faces,material(kind,color,'assets/ancient-canal/textures/stone.png'))

river=LAYOUT['river'];z=river['center_z'];half=river['half_width']
mesh('HorizontalRiver', [[-170,-.62,z-half],[-170,-.62,z+half],[170,-.62,z+half],[170,-.62,z-half]],
     [(0,1,2,3)],material('Water',(.08,.27,.32)))
dock=LAYOUT['dock'];x=dock['center_x'];a=dock['ramp_deck_z'];b=dock['approach_z'];w=dock['ramp_width']/2
mesh('DockApproach',[[x-w,-.32,a],[x+w,-.32,a],[x+w,0,b],[x-w,0,b]],[(0,3,2,1)],material('Ramp',(.33,.23,.16)))
for i, entry in enumerate(LAYOUT['models']):
    name=entry.get('site_id',entry['id']+'_'+str(i))
    if entry['id']=='willow':
        obj=card(name,entry['position'],'assets/ancient-canal/scenery/willow.png',.025,120)
    else:
        obj=instance(entry.get('asset',entry['id']),name,entry['position'],entry.get('yaw',0))
    obj['runtime_cast_shadow']=entry.get('cast_shadow',True)
for entry in LAYOUT['background']['houses']:
    obj=instance(entry['asset'],entry['id'],entry['position'],entry['yaw_deg'],entry['scale_xyz'])
    obj['parallax_layer']=entry['layer'];obj['runtime_cast_shadow']=False
for entry in LAYOUT['background']['trees']:
    obj=card(entry['id'],entry['position'],'assets/ancient-canal/scenery/willow.png',.025,120,entry['scale'])
    obj['parallax_layer']=entry['layer'];obj['runtime_cast_shadow']=False
for entry in LAYOUT['streetlamps']:
    instance('streetlamp',entry['site_id'],entry['position'])
for entry in LAYOUT['npcs']:
    card(entry['id'],entry['position'],f"assets/ancient-canal/npcs/{entry['id']}.png",.009,112)
for entry in BLUEPRINT['lights']:
    lamp=bpy.data.lights.new(entry['diagram_id']+'_'+entry['id'],'POINT')
    lamp.energy=75 if entry['kind']=='broad' else 15
    lamp.color=entry['tint_rgba'][:3]
    obj=bpy.data.objects.new(lamp.name,lamp)
    bpy.context.scene.collection.objects.link(obj)
    obj.location=coordinates(entry['position'])
    obj['godot_range']=entry['range_m'];obj['runtime_cast_shadow']=entry['cast_shadow']
bpy.context.scene.unit_settings.system='METRIC'
bpy.context.scene['blueprint']=LAYOUT['blueprint']['path']
bpy.context.scene['blueprint_sha256']=LAYOUT['blueprint']['sha256']
bpy.context.scene['coordinate_mapping']='Godot (x,y,z) -> Blender (x,-z,y)'
bpy.ops.file.pack_all()
for image in bpy.data.images:
    if image.source=='FILE' and image.filepath:
        image.filepath='//'+os.path.relpath(image.filepath,OUT).replace(os.sep,'/')
        for packed in image.packed_files:
            packed.filepath=image.filepath
destination=OUT/'ancient-r5.blend'
for screen in bpy.data.screens:
    for area in screen.areas:
        for space in area.spaces:
            if space.type=='FILE_BROWSER' and space.params:
                space.params.directory=b'//'
bpy.ops.wm.save_as_mainfile(filepath=str(destination),compress=False)
manifest=dict(source='tools/ancient_canal/build_layout_assembly.py',model=destination.relative_to(ROOT).as_posix(),
              sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),blueprint=LAYOUT['blueprint'],
              instances=RECORDS,ground_batches=3,lamps=14,packed_textures=True,
              runtime_authority='resources/ancient-canal/layout.json; Blender point energies are preview-only')
(OUT/'assembly-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('ASSEMBLY_R5_SAVED',destination.name,len(RECORDS),'instances')
