extends Node3D
## Shared greybox and final collision recipe. Visual models never alter routes.
var layout: Dictionary
var water: MeshInstance3D
var material_overrides: Array[StandardMaterial3D] = []
var lantern_positions: Array[Vector3] = []
var lantern_labels: Array[String] = []
var lantern_light_positions: Array[Vector3] = []
var streetlamp_definitions: Array[Dictionary] = []
var streetlamps: Array[Dictionary] = []
var greybox := false

static func vec(v: Array) -> Vector3:
    return Vector3(v[0], v[1], v[2])

func configure(data: Dictionary, blockout := false) -> void:
    layout = data
    greybox = blockout
    var bank: Dictionary = layout.banks
    var half: float = layout.river.half_width
    var length: float = bank.max_z-bank.min_z
    for side in [-1.0, 1.0]:
        var width: float = bank.outer_x-half
        if side<0:
            bank_rect(-bank.outer_x,-half,bank.min_z,bank.max_z)
        else:
            # Cut the ground below the lower dock and its ramp, so the visible
            # descending surface also matches collision height.
            bank_rect(5.7,bank.outer_x,bank.min_z,bank.max_z)
            bank_rect(half,5.7,bank.min_z,5.4)
            bank_rect(half,5.7,8.6,bank.max_z)
            bank_rect(4.65,5.7,5.4,6.1)
            bank_rect(4.65,5.7,7.9,8.6)
        # River blockers leave a gap only at the bridge and the right dock.
        for span in [[bank.min_z,-2.65],[.65,5.1],[8.9,bank.max_z]]:
            if side<0 and float(span[0])==.65:
                span = [.65,bank.max_z]
            if side<0 and float(span[0])==8.9: continue
            var z: float = (span[0]+span[1])/2.0
            box("WaterGuard",Vector3(side*(half+.06),.4,z),Vector3(.12,.8,float(span[1])-float(span[0])),Color(.36,.4,.42), true)
    bridge_collision()
    # Dock joins the right bank through a shallow ramp, separate from visual steps.
    # Its collision top matches the plank top at -.32. Rendering both creates
    # coplanar depth conflicts; the helper is visible only in the greybox.
    box("DockFloor",Vector3(3.65,-.47,7.0),Vector3(2,.3,3),Color(.33,.23,.16),true,greybox)
    ramp_segment("DockApproach",Vector3(5.7,0,7),Vector3(4.55,-.32,7),1.65)
    box("DockRiverGuard",Vector3(2.59,.2,7),Vector3(.12,1.0,3),Color(.35,.25,.16),true)
    for z in [5.45,8.55]: box("DockEndGuard",Vector3(3.65,.15,z),Vector3(2.1,.9,.1),Color(.35,.25,.16),true)
    for side in [-1.0,1.0]:
        box("Boundary",Vector3(side*bank.outer_x,1,0),Vector3(.2,2,length+3),Color(.4,.4,.4),true,false)
    for z in [bank.min_z,bank.max_z]: box("Boundary",Vector3(0,1,z),Vector3(26,2,.2),Color(.4,.4,.4),true,false)
    water = MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(half*2,layout.river.length)
    water.mesh = plane
    water.position.y = layout.river.water_y
    var wm := StandardMaterial3D.new()
    wm.albedo_color = Color(.08,.27,.32)
    wm.roughness = .28
    water.material_override = wm
    add_child(water)
    for entry in layout.models:
        if entry.has("collision_size"):
            var size := vec(entry.collision_size)
            box("Obstacle_"+entry.id,vec(entry.position)+Vector3.UP*size.y/2,size,Color(.73,.66,.56),true,greybox)
        if not greybox:
            var path: String = "res://assets/ancient-canal/models/"+entry.id+".glb"
            if ResourceLoader.exists(path):
                var model: Node3D = load(path).instantiate()
                model.position = vec(entry.position)
                model.rotation_degrees.y = entry.yaw
                add_child(model)
                prepare_model(model)
        if entry.id=="lantern":
            lantern_positions.append(vec(entry.position))
            lantern_labels.append(entry.get("label", "檐下灯笼 "+str(lantern_positions.size())))
            lantern_light_positions.append(vec(entry.position)+vec(entry.get("light_offset",[0,-.15,.12])))
    for entry in layout.get("streetlamps", []):
        var foot := vec(entry.position)
        var offset := vec(entry.light_offset)
        streetlamp_definitions.append({"id": entry.id, "label": entry.label,
            "foot_position": entry.position.duplicate(),
            "light_position": [foot.x+offset.x, foot.y+offset.y, foot.z+offset.z],
            "cast_shadow": entry.cast_shadow, "pole_height": 2.6})
        var pole := StaticBody3D.new()
        pole.name = entry.id
        pole.position = foot
        add_child(pole)
        var shape := CollisionShape3D.new()
        var cylinder := CylinderShape3D.new()
        cylinder.radius = .12
        cylinder.height = 2.6
        shape.shape = cylinder
        shape.position.y = 1.3
        pole.add_child(shape)
        if greybox:
            var visible_pole := MeshInstance3D.new()
            var mesh := CylinderMesh.new()
            mesh.top_radius = .12
            mesh.bottom_radius = .12
            mesh.height = 2.6
            visible_pole.mesh = mesh
            visible_pole.position.y = 1.3
            pole.add_child(visible_pole)
        elif ResourceLoader.exists("res://assets/ancient-canal/models/streetlamp.glb"):
            var model: Node3D = load("res://assets/ancient-canal/models/streetlamp.glb").instantiate()
            pole.add_child(model)
            prepare_model(model)
    streetlamps = streetlamp_definitions

func prepare_model(node: Node) -> void:
    if node is MeshInstance3D:
        for surface in range(node.mesh.get_surface_count()):
            var source: Material = node.get_active_material(surface)
            if source is StandardMaterial3D:
                var mat: StandardMaterial3D = source.duplicate()
                mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
                node.set_surface_override_material(surface,mat)
                material_overrides.append(mat)
    for child in node.get_children(): prepare_model(child)

func bridge_y(x: float) -> float:
    return float(layout.bridge.height)*(1.0-pow(x/float(layout.bridge.half_span),2))

func bridge_collision() -> void:
    var b: Dictionary = layout.bridge
    for i in range(int(b.segments)):
        var x0: float = -b.half_span+2*b.half_span*i/b.segments
        var x1: float = -b.half_span+2*b.half_span*(i+1)/b.segments
        ramp_segment("BridgeWalk",Vector3(x0,bridge_y(x0),b.center_z),Vector3(x1,bridge_y(x1),b.center_z),b.width)
    for z in [b.center_z-b.width/2,b.center_z+b.width/2]:
        for i in range(12):
            var x: float = -b.half_span+(i+.5)*2*b.half_span/12
            box("BridgeRail",Vector3(x,bridge_y(x)+.5,z),Vector3(2*b.half_span/12+.03,1,.16),Color(.46,.49,.49),true,greybox)

func ramp_segment(id: String,a: Vector3,b: Vector3,width: float) -> void:
    var center := (a+b)/2
    var length := Vector2(b.x-a.x,b.y-a.y).length()
    var body := box(id,center-Vector3.UP*.12,Vector3(length+.018,.24,width),Color(.48,.51,.5),true,greybox or id=="DockApproach")
    body.rotation.z = atan2(b.y-a.y,b.x-a.x)

func bank_rect(x0: float,x1: float,z0: float,z1: float) -> void:
    box("Bank",Vector3((x0+x1)/2,-.5,(z0+z1)/2),Vector3(x1-x0,1,z1-z0),Color(.5,.49,.45),true)

func box(id: String,pos: Vector3,size: Vector3,color: Color,collision: bool,visual := true) -> Node3D:
    var result: Node3D = StaticBody3D.new() if collision else Node3D.new()
    result.name = id
    result.position = pos
    add_child(result)
    if collision:
        var shape := CollisionShape3D.new()
        var data := BoxShape3D.new()
        data.size = size
        shape.shape = data
        result.add_child(shape)
    if visual:
        var mesh := MeshInstance3D.new()
        var cube := BoxMesh.new()
        cube.size = size
        mesh.mesh = cube
        var material := StandardMaterial3D.new()
        material.albedo_color = color
        material.roughness = .9
        if not greybox and ResourceLoader.exists("res://assets/ancient-canal/textures/stone.png"):
            material.albedo_texture = load("res://assets/ancient-canal/textures/stone.png")
            material.normal_enabled = true
            material.normal_texture = load("res://assets/ancient-canal/textures/stone_normal.png") if ResourceLoader.exists("res://assets/ancient-canal/textures/stone_normal.png") else null
            material.uv1_triplanar = true
            material.uv1_scale = Vector3.ONE*.5
            material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
        mesh.material_override = material
        result.add_child(mesh)
        material_overrides.append(material)
    return result
