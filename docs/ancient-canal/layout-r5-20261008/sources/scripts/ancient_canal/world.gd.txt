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
    if layout.river.get("axis", "z") == "x":
        horizontal_ground()
        populate()
        return
    var bank: Dictionary = layout.banks
    var half: float = layout.river.half_width
    var length: float = bank.max_z-bank.min_z
    for side in [-1.0, 1.0]:
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
    for z in [bank.min_z,bank.max_z]: box("Boundary",Vector3(0,1,z),Vector3(2*float(bank.outer_x),2,.2),Color(.4,.4,.4),true,false)
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
    populate()

func populate() -> void:
    for entry in layout.models:
        if entry.has("collision_size"):
            var size := vec(entry.collision_size)
            box("Obstacle_"+entry.id,vec(entry.position)+Vector3.UP*size.y/2,size,Color(.73,.66,.56),true,greybox)
        if not greybox:
            var path: String = "res://assets/ancient-canal/models/"+entry.get("asset",entry.id)+".glb"
            if entry.id == "willow":
                var tree := preload("res://scripts/ancient_canal/foliage.gd").make_tree(self,vec(entry.position),float(entry.get("scale",1.0)),bool(entry.get("cast_shadow",true)))
                tree.name = entry.get("site_id","PixelWillow")
            elif ResourceLoader.exists(path):
                var model: Node3D = load(path).instantiate()
                model.position = vec(entry.position)
                model.rotation_degrees.y = entry.yaw
                model.name = entry.get("site_id",entry.id)
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
            "cast_shadow": entry.cast_shadow, "pole_height": entry.pole_height})
        var pole := StaticBody3D.new()
        pole.name = entry.id
        pole.position = foot
        add_child(pole)
        var shape := CollisionShape3D.new()
        var cylinder := CylinderShape3D.new()
        cylinder.radius = entry.collision_radius
        cylinder.height = entry.pole_height
        shape.shape = cylinder
        shape.position.y = entry.pole_height/2.0
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

func horizontal_ground() -> void:
    var bank: Dictionary = layout.banks
    var half: float = layout.river.half_width
    var centre: float = layout.river.center_z
    var rear := centre-half
    var front := centre+half
    var dock: Dictionary = layout.dock
    var dx: float = dock.center_x
    var entry_z: float = dock.approach_z
    # The same measured tiles drive top surfaces and their ground collision.
    # Three shared meshes replace separate coplanar road overlays.
    if layout.has("ground_tiles"):
        measured_ground()
    else:
        bank_rect(-bank.outer_x,dx-1.15,bank.min_z,rear)
        bank_rect(dx+1.15,bank.outer_x,bank.min_z,rear)
        bank_rect(dx-1.15,dx+1.15,bank.min_z,entry_z)
        bank_rect(-bank.outer_x,bank.outer_x,front,bank.max_z)
    var bridge: Dictionary = layout.bridge
    var bx: float = bridge.center_x
    for shoreline in [rear,front]:
        var breaks: Array = [[bx-bridge.width/2-.15,bx+bridge.width/2+.15]]
        var dock_shore: float = front if dock.get("bank","rear")=="front" else rear
        if shoreline == dock_shore: breaks.append([dx-1.05,dx+1.05])
        breaks.sort_custom(func(a,b): return a[0]<b[0])
        var left: float = -bank.outer_x
        for gap in breaks:
            shoreline_guard(left,gap[0],shoreline)
            left = gap[1]
        shoreline_guard(left,bank.outer_x,shoreline)
    for i in range(int(bridge.segments)):
        var z0: float = centre-bridge.half_span+2*bridge.half_span*i/bridge.segments
        var z1: float = z0+2*bridge.half_span/bridge.segments
        slope("BridgeWalk",Vector3(bx,bridge_y(z0-centre),z0),Vector3(bx,bridge_y(z1-centre),z1),bridge.width)
    for side in [-1,1]:
        for i in range(12):
            var z: float = centre-bridge.half_span+(i+.5)*2*bridge.half_span/12
            box("BridgeRail",Vector3(bx+side*(bridge.width/2+.045),bridge_y(z-centre)+.5,z),Vector3(.16,1,2*bridge.half_span/12+.03),Color(.46,.49,.49),true,greybox)
    var deck_z: float = dock.center_z
    var deck_y: float = dock.surface_y
    var deck_size: Array = dock.get("deck_size_xz",[2,3])
    var bank_side: float = 1 if dock.get("bank","rear")=="front" else -1
    box("DockFloor",Vector3(dx,deck_y-.15,deck_z),Vector3(deck_size[0],.3,deck_size[1]),Color(.33,.23,.16),true,greybox)
    slope("DockApproach",Vector3(dx,0,entry_z),Vector3(dx,deck_y,dock.get("ramp_deck_z",deck_z+bank_side*deck_size[1]/2)),dock.get("ramp_width",1.65),true)
    box("DockRiverGuard",Vector3(dx,.2,deck_z-bank_side*deck_size[1]/2),Vector3(deck_size[0],1,.12),Color(.35,.25,.16),true)
    for side in [-1,1]: box("DockEndGuard",Vector3(dx+side*1.02,.15,deck_z),Vector3(.1,.9,3),Color(.35,.25,.16),true)
    for side in [-1,1]: box("Boundary",Vector3(side*bank.outer_x,1,0),Vector3(.2,2,bank.max_z-bank.min_z),Color.WHITE,true,false)
    for z in [bank.min_z,bank.max_z]: box("Boundary",Vector3(0,1,z),Vector3(2*bank.outer_x,2,.2),Color.WHITE,true,false)
    water = MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(340,half*2)
    water.mesh = plane
    water.position = Vector3(0,layout.river.water_y,centre)
    water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(water)
    # Background coverage meets the physical banks without duplicate coplanar faces.
    box("RearLandscape",Vector3(0,-.5,-56),Vector3(340,1,80),Color(.38,.43,.35),false)
    box("FrontLandscape",Vector3(0,-.5,30),Vector3(340,1,32),Color(.42,.46,.36),false)
    for side in [-1,1]:
        box("OuterRear",Vector3(side*98,-.5,(bank.min_z+rear)/2),Vector3(144,1,rear-bank.min_z),Color(.42,.46,.36),false)
        box("OuterFront",Vector3(side*98,-.5,(bank.max_z+front)/2),Vector3(144,1,bank.max_z-front),Color(.42,.46,.36),false)

func measured_ground() -> void:
    var groups: Dictionary = {}
    for tile in layout.ground_tiles:
        var r: Array = tile.rect
        box("Bank",Vector3((r[0]+r[2])/2.0,-.5,(r[1]+r[3])/2.0),Vector3(r[2]-r[0],1,r[3]-r[1]),Color.WHITE,true,false)
        if not groups.has(tile.kind):
            var surface := SurfaceTool.new()
            surface.begin(Mesh.PRIMITIVE_TRIANGLES)
            groups[tile.kind] = surface
        var surface: SurfaceTool = groups[tile.kind]
        var corners := [Vector3(r[0],0,r[1]),Vector3(r[0],0,r[3]),Vector3(r[2],0,r[3]),Vector3(r[2],0,r[1])]
        for index in [0,2,1,0,3,2]:
            var point: Vector3 = corners[index]
            surface.set_normal(Vector3.UP)
            surface.set_uv(Vector2(point.x,point.z)*.5)
            surface.add_vertex(point)
    for kind in groups:
        var mesh := MeshInstance3D.new()
        mesh.name = "GroundSurface_"+kind
        mesh.mesh = groups[kind].commit()
        var material := StandardMaterial3D.new()
        material.albedo_color = {"bank":Color(.38,.43,.35),"street":Color(.57,.56,.50),"court":Color(.48,.51,.43)}[kind]
        material.roughness = .95
        material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
        material.albedo_texture = load("res://assets/ancient-canal/textures/stone.png")
        material.normal_enabled = true
        material.normal_texture = load("res://assets/ancient-canal/textures/stone_normal.png")
        mesh.material_override = material
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(mesh)
        material_overrides.append(material)

func shoreline_guard(x0: float,x1: float,z: float) -> void:
    if x1 <= x0: return
    box("WaterGuard",Vector3((x0+x1)/2,.35,z),Vector3(x1-x0,.9,.13),Color(.36,.4,.42),true,false)
    box("BankCoping",Vector3((x0+x1)/2,-.12,z),Vector3(x1-x0,.28,.4),Color(.42,.45,.43),false)

func slope(id: String,a: Vector3,b: Vector3,width: float,visual := false) -> void:
    var along := (b-a).normalized()
    var across := along.cross(Vector3.UP).normalized()
    var normal := across.cross(along).normalized()
    var body := box(id,(a+b)/2-normal*.12,Vector3(a.distance_to(b)+.018,.24,width),Color(.48,.51,.5),true,greybox or visual)
    body.basis = Basis(along,normal,across)

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
