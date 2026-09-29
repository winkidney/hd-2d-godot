extends "res://scripts/background_rig.gd"
## City facades replace mountain decoration; the same five parallax IDs remain.
var city_materials: Dictionary = {}
const CITY_TONES := [Color("eee0c9"), Color("cedbd5"), Color("e1c5ae"), Color("d6ccd0"), Color("dfe1cd")]

func build_tree_line() -> void:
    pass

func configure(env: Environment) -> void:
    super.configure(env)
    for key in ["valley","ridge_near","ridge_mid","ridge_far"]:
        var previous: Node3D = layers[key]
        remove_child(previous)
        previous.free()
    layers.erase("valley")
    var recipes := [["ridge_near",-24.0,0.0,1.2],["ridge_mid",-46.0,-12.0,1.8],["ridge_far",-86.0,-35.0,2.8]]
    for layer_index in range(recipes.size()):
        var entry: Array = recipes[layer_index]
        var group := Node3D.new()
        group.name=entry[0]
        add_child(group)
        layers[entry[0]]=group
        city_materials[entry[0]]=[]
        build_city_foundation(group,entry)
        for i in range(15):
            var x := float(i-7)*8.3*float(entry[3])
            if absf(x+7.0)<6.0: continue
            var variation := (i+layer_index*2)%5
            var kind := "tower" if (i+layer_index*2)%5 == 1 else "townhouse"
            var item := (load("res://assets/reference-scene/models/"+kind+".glb") as PackedScene).instantiate() as Node3D
            group.add_child(item)
            # Deterministic offsets keep each row distinct without more buildings.
            x += float(layer_index%2)*3.2*float(entry[3])
            item.position=Vector3(x,float(entry[2]),float(entry[1])-float((i+layer_index)%3)*2.4)
            var width_scale: float = [0.94,1.08,0.98,1.12,0.92][variation]
            var height_scale: float = [0.88,1.08,0.94,1.18,1.00][variation]
            item.scale=Vector3(width_scale,height_scale,1.0)*float(entry[3])
            item.rotation.y=deg_to_rad(float((i+layer_index)%3-1)*3.0)
            adapt_city_materials(item,entry[0],CITY_TONES[variation])
    apply_preset("dusk")

func build_city_foundation(group: Node3D, entry: Array) -> void:
    # Two boxes per row close the sky holes under and between house shells.
    # These are decoration in the same parallax group, with no physics bodies.
    var scale_value := float(entry[3])
    var width := 15.0*8.3*scale_value+100.0
    var depth := 32.0*scale_value
    var front := float(entry[1])+8.4*scale_value
    var floor_y := float(entry[2])-0.20
    var center_z := front-depth*0.5
    city_box(group,"ContinuousMasonryBase",Vector3(0,floor_y-12.0,center_z),
        Vector3(width,24.0,depth),"brick",Color("aab3ad"),Vector3(width/1.6,14.0,1.0))
    city_box(group,"ContinuousStoneCap",Vector3(0,floor_y+0.075,center_z),
        Vector3(width+0.4,0.15,depth+0.2),"paving",Color("c5c4b2"),Vector3(width/1.6,depth/1.6,1.0))

func city_box(group: Node3D, label: String, center: Vector3, size: Vector3,
        texture_id: String, tone: Color, texture_scale: Vector3) -> void:
    var item := MeshInstance3D.new()
    item.name=label
    var mesh := BoxMesh.new()
    mesh.size=size
    item.mesh=mesh
    item.position=center
    item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material := StandardMaterial3D.new()
    material.albedo_texture=load("res://assets/reference-scene/textures/"+texture_id+".png")
    material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
    material.roughness=1.0
    material.uv1_scale=texture_scale
    material.set_meta("city_tone",tone)
    item.material_override=material
    group.add_child(item)
    city_materials[group.name].append(material)

func adapt_city_materials(node: Node, id: String, tone := Color.WHITE) -> void:
    if node is MeshInstance3D:
        node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        for i in node.mesh.get_surface_count():
            var old: Material=node.mesh.surface_get_material(i)
            if old is StandardMaterial3D:
                var material := old.duplicate() as StandardMaterial3D
                material.set_meta("city_tone",tone if old.resource_name.ends_with("plaster") else Color.WHITE)
                material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
                if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
                    material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
                node.set_surface_override_material(i,material)
                city_materials[id].append(material)
    for child in node.get_children(): adapt_city_materials(child,id,tone)

func apply_preset(id: String) -> void:
    # Parent palettes still own sky and cloud appearance.
    super.apply_preset(id)
    sky_material.set_shader_parameter("horizon",Color({"day":"7e99a6","dusk":"344752","night":"0b1828"}[id]))
    sky_material.set_shader_parameter("zenith",Color({"day":"618199","dusk":"273846","night":"051021"}[id]))
    for key in city_materials:
        var tint := Color("bacad0") if id == "day" else (Color("bba498") if id == "dusk" else Color("788bab"))
        for material in city_materials[key]:
            material.albedo_color=tint*material.get_meta("city_tone",Color.WHITE)
            if material.emission_enabled:
                material.emission_energy_multiplier=0.1 if id == "day" else 1.2
