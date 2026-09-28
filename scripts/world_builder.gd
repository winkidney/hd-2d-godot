extends Node3D
## Deterministic authoring builder. Baked output is an editable scene.
var materials: Dictionary = {}
var models: Dictionary = {}
var rng := RandomNumberGenerator.new()
var layout: Dictionary

func surface(kind: String) -> Material:
    if materials.has(kind):
        return materials[kind]
    var result: Material
    if kind in ["glass", "iron", "canvas"]:
        var mat := StandardMaterial3D.new()
        mat.albedo_color = {"glass": Color("ffd095"), "iron": Color("283039"), "canvas": Color("916149")}[kind]
        mat.roughness = 0.9
        if kind == "glass":
            mat.emission_enabled = true
            mat.emission = Color("ffac4e")
            mat.emission_energy_multiplier = 1.8
        result = mat
    else:
        var mat := ShaderMaterial.new()
        mat.shader = load("res://shaders/pixel_surface.gdshader")
        mat.set_shader_parameter("albedo_tex", load("res://assets/textures/" + kind + ".png"))
        mat.set_shader_parameter("texture_scale", 0.55)
        result = mat
    result.resource_name = "waystation_" + kind
    materials[kind] = result
    return result

func collider(label: String, pos: Vector3, size: Vector3) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = label + "_Collision_" + str(get_child_count())
    body.position = pos
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    add_child(body)
    return body

func block(label: String, pos: Vector3, size: Vector3, kind: String, solid := false) -> MeshInstance3D:
    var item := MeshInstance3D.new()
    item.name = label + "_" + str(get_child_count())
    var mesh := BoxMesh.new()
    mesh.size = size
    item.mesh = mesh
    item.material_override = surface(kind)
    item.position = pos
    add_child(item)
    if solid:
        collider(label, pos, size)
    return item

static func vector(data: Array) -> Vector3:
    return Vector3(float(data[0]), float(data[1]), float(data[2]))

func model(kind: String, pos: Vector3, scale_value := 1.0) -> Node3D:
    if not models.has(kind):
        models[kind] = load("res://assets/models/" + kind + ".glb")
    var packed: PackedScene = models[kind]
    var item := packed.instantiate() as Node3D
    item.name = kind.capitalize() + "_" + str(get_child_count())
    item.position = pos
    item.scale = Vector3.ONE * scale_value
    add_child(item)
    dress(item)
    return item

func dress(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        for i in mesh_node.mesh.get_surface_count():
            var original := mesh_node.mesh.surface_get_material(i)
            if original == null:
                continue
            var kind := original.resource_name.to_lower().get_slice(".", 0)
            if kind in ["wood", "stone", "brick", "plaster", "roof", "glass", "iron", "canvas"]:
                mesh_node.set_surface_override_material(i, surface(kind))
    for child in node.get_children():
        dress(child)

func foliage(kind: String, pos: Vector3, pixel_size: float) -> Sprite3D:
    var card := Sprite3D.new()
    card.name = kind.capitalize() + "_" + str(get_child_count())
    card.texture = load("res://assets/sprites/" + kind + ".png")
    card.pixel_size = pixel_size
    card.position = pos
    card.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
    card.shaded = true
    card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(card)
    return card

func build(data: Dictionary) -> void:
    layout = data
    rng.seed = int(data.seed)
    name = "World"
    block("NorthEarth", Vector3(0, -1.2, -6.5), Vector3(36, 2.4, 17), "soil", true)
    block("NorthGrass", Vector3(0, -0.015, -6.5), Vector3(36, 0.06, 17), "grass")
    block("SouthEarth", Vector3(0, -1.2, 11.9), Vector3(36, 2.4, 10.2), "soil", true)
    block("SouthGrass", Vector3(0, -0.015, 11.9), Vector3(36, 0.06, 10.2), "grass")
    block("Courtyard", Vector3(-2, 0.025, -0.45), Vector3(15.5, 0.08, 4.5), "stone")
    block("ForestRoad", Vector3(1.2, 0.025, 11.8), Vector3(3.2, 0.08, 10), "stone")
    block("RiverBed", Vector3(0, -1.6, 4.4), Vector3(36, 0.2, 5), "stone")
    build_bridge()
    build_buildings()
    build_decoration()
    build_water()

func build_bridge() -> void:
    model("bridge", vector(layout.bridge_center))
    collider("BridgeDeck", Vector3(1.2, -0.07, 4.3), Vector3(2.65, 0.24, 6.0))
    for x in [-0.19, 2.59]:
        collider("Parapet", Vector3(x, 0.43, 4.3), Vector3(0.30, 0.96, 6.25))
    collider("RiverWest", Vector3(-9.1, 1.0, 4.4), Vector3(17.85, 3, 4.8))
    collider("RiverEast", Vector3(10.3, 1.0, 4.4), Vector3(15.5, 3, 4.8))
    for x in [-17.6, 17.6]:
        collider("WorldEdge", Vector3(x, 2, 0), Vector3(1, 6, 36))
    for z in [-14.5, 16.6]:
        collider("WorldEdge", Vector3(0, 2, z), Vector3(36, 6, 1))
    for i in range(45):
        var x := -17.7 + i * 0.8
        if x > -0.7 and x < 3.0:
            continue
        for z in [1.88, 6.95]:
            block("BankStone", Vector3(x, -0.18, z), Vector3(0.76, 0.5, 0.40), "brick")

func build_buildings() -> void:
    for entry in layout.buildings:
        var pos := vector(entry.position)
        var s := float(entry.scale)
        model(entry.model, pos, s)
        var size := Vector3(6.25, 5, 4.55) if entry.model == "inn" else Vector3(4.65, 4.4, 3.65)
        collider("Building", pos + Vector3(0, 2, 0), size * s)
    for entry in layout.lamps:
        var pos := vector(entry)
        model("lantern", pos)
        collider("Lamp", pos + Vector3(0, 1, 0), Vector3(0.40, 2.2, 0.4))

func build_decoration() -> void:
    model("dock", Vector3(-10.5, -0.25, 2.8))
    for p in [Vector3(-8.8, 0, -1.4), Vector3(-8, 0, -1.1), Vector3(6.9, 0, -4.7), Vector3(-11, 0, 0.1)]:
        model("barrel", p)
        collider("Barrel", p + Vector3(0, 0.4, 0), Vector3(0.7, 0.8, 0.7))
    for p in [Vector3(-9.7, 0, -1.2), Vector3(7.6, 0, -4.9), Vector3(-10.5, 0, -0.6)]:
        model("crate", p)
        collider("Crate", p + Vector3(0, 0.43, 0), Vector3(0.85, 0.86, 0.85))
    for i in range(19):
        var x := -17.0 + i * 1.9
        plant_tree(Vector3(x, 0, -12.8 + rng.randf_range(-1, 1.2)), rng.randf_range(0.9, 1.3), i % 4 == 0)
    for p in [Vector3(-14, 0, -3), Vector3(15, 0, -0.8), Vector3(-12, 0, 10), Vector3(13, 0, 12), Vector3(-5.6, 0, 14.5), Vector3(8.4, 0, 15.2)]:
        plant_tree(p, rng.randf_range(1.0, 1.25), true)
    for i in range(65):
        var x := rng.randf_range(-17, 17)
        if x > -0.9 and x < 3.3:
            continue
        var z := rng.randf_range(1.35, 1.85) if i % 2 == 0 else rng.randf_range(7.05, 7.6)
        var reed := foliage("reeds", Vector3(x, 0.44, z), rng.randf_range(0.013, 0.019))
        reed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for i in range(32):
        var pos := Vector3(rng.randf_range(-16, 16), 0.16, rng.randf_range(8.2, 15))
        if absf(pos.x - 1.2) > 2.0:
            foliage("flowers", pos, 0.015)
    block("SignPost", Vector3(2.9, 0.7, 7.75), Vector3(0.12, 1.4, 0.12), "wood")
    block("SignBoard", Vector3(2.9, 1.3, 7.75), Vector3(1.0, 0.5, 0.14), "wood")

func plant_tree(pos: Vector3, s: float, autumn: bool) -> void:
    model("tree_trunk", pos, s)
    foliage("autumn" if autumn else "oak", pos + Vector3(0, 3.55 * s, 0), 0.04 * s)
    collider("Tree", pos + Vector3(0, 1.2, 0), Vector3(0.48, 2.4, 0.48))

func build_water() -> void:
    var water := MeshInstance3D.new()
    water.name = "WaterSurface"
    var mesh := PlaneMesh.new()
    mesh.size = Vector2(36, 4.8)
    water.mesh = mesh
    water.position = Vector3(0, -0.72, 4.4)
    var mat := ShaderMaterial.new()
    mat.shader = load("res://shaders/water.gdshader")
    water.material_override = mat
    water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(water)

func mark_owners(node: Node) -> void:
    for child in node.get_children():
        child.scene_file_path = ""
        child.owner = self
        mark_owners(child)
