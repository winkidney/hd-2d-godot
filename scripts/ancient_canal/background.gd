extends Node3D
## Decorative town, mountain and cloud layers. Collision remains in World.
const LAYER_IDS := ["near_town", "far_town", "near_hills", "far_mountains", "near_clouds", "far_clouds"]
const NEAR_HOUSES := [[-8,-23],[7,-25],[-8,-31],[7,-34],[-8,-42],[7,-44],[-8,-53],[7,-55],
    [-17,-14],[17,-16],[-17,-24],[17,-26],[-17,-34],[17,-36],[-17,-44],[17,-46]]
const NEAR_TREES := [[-5.5,-18],[5.6,-21],[-10,-29],[-12,-39],[11,-42],[-19,-9],[19,-12]]
const FAR_HOUSES := [[-12,-62],[-19,-64],[-26,-72],[-33,-74],[12,-66],[19,-62],[26,-70],[33,-76]]
const PALETTES := {
    "day": {"near_hills": "82928b", "far_mountains": "a8b4b1", "near_clouds": "dbe2dc", "far_clouds": "e4e9e2"},
    "dusk": {"near_hills": "596d70", "far_mountains": "8c9a9b", "near_clouds": "cfb3a1", "far_clouds": "bcb9b5"},
    "night": {"near_hills": "253d49", "far_mountains": "455966", "near_clouds": "687b87", "far_clouds": "566e7d"}}
var world: Node3D
var layers: Dictionary = {}
var layer_materials: Dictionary = {}
var clouds: Array[Dictionary] = []
var wind_speeds: Array[float] = [0.35, 0.12]
var wind_phases: Array[float] = [0.0, 0.0]
var wind_enabled := true
var cloud_time := 0.0
var profile_id := "dusk"

func configure(value: Node3D, _layout: Dictionary) -> void:
    world = value
    name = "CanalBackground"
    for id in LAYER_IDS:
        var layer := Node3D.new()
        layer.name = id
        add_child(layer)
        layers[id] = layer
    for position in NEAR_HOUSES:
        town_model("house", Vector3(position[0], 0, position[1]), layers.near_town)
    for position in NEAR_TREES:
        town_model("willow", Vector3(position[0], 0, position[1]), layers.near_town)
    for index in range(FAR_HOUSES.size()):
        var position: Array = FAR_HOUSES[index]
        var model := town_model("house", Vector3(position[0], 0, position[1]), layers.far_town)
        if model != null:
            model.scale = Vector3(1.0, 1.0 + float(index % 4) * 0.1, 1.0)
            disable_shadows(model)
    ridge("near_hills", "ridge_near", Vector3(0,-2,-67), Vector3(.45,.65,.55))
    ridge("far_mountains", "ridge_mid", Vector3(0,-1.5,-112), Vector3(.44,.45,.30))
    for index in range(4):
        cloud("near_clouds", index, Vector3([-80.0,-22.0,36.0,90.0][index], 14.0 + index % 3, -160.0 - (index % 2) * 10.0), Vector2(18,4.5), 0, 240.0)
        cloud("far_clouds", index, Vector3([-140.0,-45.0,90.0,150.0][index], 16.0 + index % 3, -250.0 - index * 5.0), Vector2(32,7), 1, 400.0)
    # Foundation strips touch the playable bank edges rather than overlap them.
    # They stay fixed in world space; only decorative layer roots move.
    for side in [-1.0,1.0]:
        world.box("DistantBank", Vector3(side*22.6,-.5,-71), Vector3(40,1,110), Color(.5,.49,.45), false)
        world.box("OuterStreet", Vector3(side*32.5,-.5,-1), Vector3(39,1,30), Color(.5,.49,.45), false)
        world.box("FarBank", Vector3(side*82.6,-.5,-210), Vector3(160,1,168), Color(.46,.48,.45), false)
    var water_mesh := world.water.mesh as PlaneMesh
    water_mesh.size = Vector2(5.2,320)
    world.water.position.z = -134.0
    apply_preset("dusk")

func town_model(id: String, position: Vector3, parent: Node3D) -> Node3D:
    var path := "res://assets/ancient-canal/models/" + id + ".glb"
    if not ResourceLoader.exists(path): return null
    var model: Node3D = load(path).instantiate()
    model.position = position
    parent.add_child(model)
    world.prepare_model(model)
    return model

func ridge(id: String, asset: String, position: Vector3, scale_value: Vector3) -> void:
    var path := "res://assets/background/" + asset + ".glb"
    if not ResourceLoader.exists(path): return
    var model: Node3D = load(path).instantiate()
    model.position = position
    model.scale = scale_value
    layers[id].add_child(model)
    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.disable_fog = true
    material.roughness = 1.0
    layer_materials[id] = [material]
    dress(model, material)

func cloud(id: String, index: int, position: Vector3, size: Vector2, wind_layer: int, span: float) -> void:
    var card := MeshInstance3D.new()
    card.name = "Cloud_%d" % index
    var mesh := QuadMesh.new()
    mesh.size = size
    card.mesh = mesh
    card.position = position
    var material := StandardMaterial3D.new()
    material.albedo_texture = load("res://assets/background/cloud-%d.png" % (index % 3))
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
    material.alpha_scissor_threshold = 0.5
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
    material.disable_fog = true
    card.material_override = material
    card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    layers[id].add_child(card)
    if not layer_materials.has(id): layer_materials[id] = []
    layer_materials[id].append(material)
    clouds.append({"node": card, "origin": position, "layer": wind_layer, "span": span})

func dress(node: Node, material: Material) -> void:
    if node is MeshInstance3D:
        node.material_override = material
        node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for child in node.get_children(): dress(child, material)

func disable_shadows(node: Node) -> void:
    if node is GeometryInstance3D: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for child in node.get_children(): disable_shadows(child)

func apply_preset(id: String) -> void:
    if not PALETTES.has(id): return
    profile_id = id
    for layer in PALETTES[id]:
        for material in layer_materials.get(layer, []):
            material.albedo_color = Color(PALETTES[id][layer])

func set_cloud_wind(enabled: bool, near_speed: float, far_speed: float) -> void:
    wind_enabled = enabled
    wind_speeds[0] = near_speed
    wind_speeds[1] = far_speed
    # Existing phase is deliberately retained when speed or switch changes.

func advance(delta: float) -> void:
    if wind_enabled:
        cloud_time += maxf(delta, 0.0)
        wind_phases[0] = fposmod(wind_phases[0] + wind_speeds[0] * maxf(delta, 0.0), 240.0)
        wind_phases[1] = fposmod(wind_phases[1] + wind_speeds[1] * maxf(delta, 0.0), 400.0)
    for item in clouds:
        var position: Vector3 = item.origin
        position.x = wrapf(position.x + wind_phases[int(item.layer)], -float(item.span)*0.5, float(item.span)*0.5)
        item.node.position = position

func diagnostics() -> Dictionary:
    var counts: Dictionary = {}
    for id in LAYER_IDS: counts[id] = layers[id].get_child_count()
    return {"layers": counts, "preset": profile_id, "cloud_time": cloud_time,
        "wind_enabled": wind_enabled, "wind_speeds": wind_speeds.duplicate(),
        "wind_phases": wind_phases.duplicate(), "foundation_collision": false}
