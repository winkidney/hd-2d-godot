extends "res://scripts/background_rig.gd"
## City facades replace mountain decoration; the same five parallax IDs remain.
var city_materials: Dictionary = {}

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
    for entry in recipes:
        var group := Node3D.new()
        group.name=entry[0]
        add_child(group)
        layers[entry[0]]=group
        city_materials[entry[0]]=[]
        for i in range(15):
            var x := float(i-7)*8.3*float(entry[3])
            if absf(x+7.0)<6.0: continue
            var kind := "tower" if i%5 == 1 else "townhouse"
            var item := (load("res://assets/reference-scene/models/"+kind+".glb") as PackedScene).instantiate() as Node3D
            group.add_child(item)
            item.position=Vector3(x,float(entry[2]),float(entry[1])-(i%3)*2.4)
            item.scale=Vector3.ONE*float(entry[3])
            adapt_city_materials(item,entry[0])
    apply_preset("dusk")

func adapt_city_materials(node: Node, id: String) -> void:
    if node is MeshInstance3D:
        node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        for i in node.mesh.get_surface_count():
            var old: Material=node.mesh.surface_get_material(i)
            if old is StandardMaterial3D:
                var material := old.duplicate() as StandardMaterial3D
                material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
                if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
                    material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
                node.set_surface_override_material(i,material)
                city_materials[id].append(material)
    for child in node.get_children(): adapt_city_materials(child,id)

func apply_preset(id: String) -> void:
    # Parent palettes still own sky and cloud appearance.
    super.apply_preset(id)
    sky_material.set_shader_parameter("horizon",Color({"day":"7e99a6","dusk":"344752","night":"0b1828"}[id]))
    sky_material.set_shader_parameter("zenith",Color({"day":"618199","dusk":"273846","night":"051021"}[id]))
    for key in city_materials:
        var tint := Color("bacad0") if id == "day" else (Color("bba498") if id == "dusk" else Color("788bab"))
        for material in city_materials[key]:
            material.albedo_color=tint
            if material.emission_enabled:
                material.emission_energy_multiplier=0.1 if id == "day" else 1.2
