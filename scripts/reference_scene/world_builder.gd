extends "res://scripts/world_builder.gd"
## Reference-scene authoring only. Old world and collision are not modified.
var graybox := false

func surface(kind: String) -> Material:
    if materials.has(kind): return materials[kind]
    var result: Material
    if graybox or kind in ["iron","glass"]:
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color("777e81") if graybox else (Color("132c24") if kind == "iron" else Color("ffcc80"))
        mat.roughness = 0.85
        if kind == "glass" and not graybox:
            mat.emission_enabled = true
            mat.emission = Color("ffbe6d")
            mat.emission_energy_multiplier = 2.0
            mat.resource_name = "waystation_glass"
        result = mat
    else:
        var mat := ShaderMaterial.new()
        mat.shader = load("res://shaders/pixel_surface.gdshader")
        mat.set_shader_parameter("albedo_tex",load("res://assets/reference-scene/textures/"+kind+".png"))
        mat.set_shader_parameter("texture_scale",0.60 if kind != "paving" else 0.75)
        result = mat
    materials[kind] = result
    return result

func model(kind: String, pos: Vector3, scale_value := 1.0) -> Node3D:
    var item := (load("res://assets/reference-scene/models/"+kind+".glb") as PackedScene).instantiate() as Node3D
    item.name = kind.capitalize()+"_"+str(get_child_count())
    item.position=pos; item.scale=Vector3.ONE*scale_value
    add_child(item)
    dress(item)
    return item

func dress(node: Node) -> void:
    if node is MeshInstance3D:
        for index in node.mesh.get_surface_count():
            var old: Material = node.mesh.surface_get_material(index)
            if old is StandardMaterial3D:
                var key := old.resource_name
                if not materials.has(key):
                    var mat := old.duplicate() as StandardMaterial3D
                    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
                    mat.roughness = 0.88
                    if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
                        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
                        mat.alpha_scissor_threshold = 0.5
                        mat.cull_mode = BaseMaterial3D.CULL_DISABLED
                    if "glass" in key: mat.resource_name = "waystation_glass"
                    materials[key] = mat
                node.set_surface_override_material(index,surface("stone") if graybox else materials[key])
    for child in node.get_children(): dress(child)

func build(data: Dictionary) -> void:
    layout=data; rng.seed=int(data.seed); name="World"
    for part in data.platforms:
        var p := vector(part.center); var size := vector(part.size)
        block(part.id,p,size,"brick",true)
        block(part.id+"Paving",p+Vector3.UP*(size.y/2+0.022),Vector3(size.x,0.045,size.z),"paving")
    model("arch_bridge",vector(data.bridge_center))
    collider("BridgeDeck",Vector3(-7,1.05,3.5),Vector3(10,.30,4))
    for z in [1.60,5.40]: collider("BridgeParapet",Vector3(-7,1.8,z),Vector3(9.7,1.2,.25))
    for stair in data.stairs: build_stair(stair)
    for building in data.buildings:
        var p := vector(building.position); var s := float(building.scale)
        model(building.model,p,s)
        var size := Vector3(7,6.8,5) if building.model == "palazzo" else Vector3(4.8,5.4,4.2)
        collider("Building",p+Vector3.UP*size.y*s/2,size*s)
    for lamp in data.lamps: model("lamp",vector(lamp))
    build_water_and_bounds()
    build_railings()
    if not graybox: build_props()

func build_stair(entry: Dictionary) -> void:
    var bottom := vector(entry.bottom)
    var item := model("stairs",bottom)
    item.scale=Vector3(float(entry.width)/3.6,float(entry.rise)/2.8,float(entry.run)/4.2)
    item.rotation_degrees.y=float(entry.yaw)
    var body := StaticBody3D.new()
    body.name=entry.id+"Ramp";body.position=bottom;body.rotation_degrees.y=float(entry.yaw)
    var shape := ConvexPolygonShape3D.new()
    var w := float(entry.width)/2;var run := float(entry.run);var h := float(entry.rise)
    shape.points=PackedVector3Array([Vector3(-w,0,0),Vector3(w,0,0),Vector3(-w,h,-run),Vector3(w,h,-run),Vector3(-w,-.3,0),Vector3(w,-.3,0),Vector3(-w,-.3,-run),Vector3(w,-.3,-run)])
    var node := CollisionShape3D.new();node.shape=shape;body.add_child(node);add_child(body)

func rail_run(a: Vector3,b: Vector3) -> void:
    var delta := b-a
    var count := maxi(1,int(ceil(delta.length()/2.5)))
    for i in range(count):
        var item := model("railing",a+delta*(float(i)+.5)/count)
        item.scale.x=delta.length()/count/2.5
        item.rotation.y=-atan2(delta.z,delta.x)
    var barrier := collider("Rail",(a+b)/2+Vector3.UP*.52,Vector3(delta.length(),1.04,.10))
    barrier.rotation.y=-atan2(delta.z,delta.x)

func build_railings() -> void:
    var runs := [[Vector3(-11,1.2,-16),Vector3(-11,1.2,1.1)],
        [Vector3(-11,1.2,5.9),Vector3(-11,1.2,17)],
        [Vector3(-3,1.2,-12),Vector3(-3,1.2,1.0)],
        [Vector3(-3,1.2,6),Vector3(-3,1.2,10.8)],
        [Vector3(-3,1.2,13.3),Vector3(-3,1.2,17.8)],
        [Vector3(-3,1.2,17.8),Vector3(23.7,1.2,17.8)],
        [Vector3(-1.8,4,-4.92),Vector3(.0,4,-4.92)],
        [Vector3(4,4,-4.92),Vector3(13.8,4,-4.92)],
        [Vector3(14,4,-1.95),Vector3(15.5,4,-1.95)],
        [Vector3(19.5,4,-1.95),Vector3(20.8,4,-1.95)]]
    for ends in runs:
        rail_run(ends[0],ends[1])
        for p in ends: model("pillar",p,.78)
    for x in [0.05,3.95]: model("pillar",Vector3(x,1.2,-.75),.8)
    for x in [15.45,19.55]: model("pillar",Vector3(x,1.2,2.25),.8)

func build_water_and_bounds() -> void:
    var water := MeshInstance3D.new();water.name="WaterSurface"
    var mesh := PlaneMesh.new();mesh.size=Vector2(8,90);water.mesh=mesh
    water.position=Vector3(-7,-1.55,-10)
    var mat := ShaderMaterial.new();mat.shader=load("res://scripts/reference_scene/water.gdshader")
    mat.set_shader_parameter("caustics",load("res://assets/reference-scene/textures/water.png"))
    water.material_override=mat;water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(water)
    block("RiverBed",Vector3(-7,-2.5,0),Vector3(8,.2,65),"stone")
    model("dock",Vector3(-5.3,-.3,12),.80)
    collider("DockDeck",Vector3(-5.3,-.40,12),Vector3(3.2,.20,3.85))
    rail_run(Vector3(-6.88,-.3,10.1),Vector3(-6.88,-.3,13.9))
    for z in [10.1,13.9]: rail_run(Vector3(-6.88,-.3,z),Vector3(-3.8,-.3,z))
    for extent in [[-15.0,32.5],[7.65,3.3],[22.5,17.0]]:
        var z: float = extent[0]
        var size_z: float = extent[1]
        var barrier := collider("RiverBarrier",Vector3(-7,0,z),Vector3(7.8,5,size_z))
        barrier.add_to_group("movement_only_barrier")
    var middle := collider("RiverBarrierDockSide",Vector3(-9.05,0,12),Vector3(3.9,5,4.8))
    middle.add_to_group("movement_only_barrier")
    for x in [-24.9,23.9]:
        var edge := collider("WorldEdge",Vector3(x,4,0),Vector3(.2,12,39))
        edge.add_to_group("movement_only_barrier")
    for z in [-17.8,18.6]:
        var edge := collider("WorldEdge",Vector3(0,4,z),Vector3(52,12,.2))
        edge.add_to_group("movement_only_barrier")

func wire(a: Vector3,b: Vector3) -> void:
    for i in range(28):
        var t0 := float(i)/28;var t1 := float(i+1)/28
        var p0 := a.lerp(b,t0)-Vector3.UP*sin(t0*PI)*1.3
        var p1 := a.lerp(b,t1)-Vector3.UP*sin(t1*PI)*1.3
        var item := block("Cable",(p0+p1)/2,Vector3(.032,.032,p0.distance_to(p1)),"iron")
        item.look_at(p1)
        if i%3 == 1:
            block("Pendant",p0-Vector3.UP*.14,Vector3(.035,.30,.035),"iron")
            block("LanternGlow",p0-Vector3.UP*.37,Vector3(.16,.24,.16),"glass")
            block("LanternCap",p0-Vector3.UP*.24,Vector3(.22,.045,.22),"iron")
            block("LanternBase",p0-Vector3.UP*.5,Vector3(.22,.045,.22),"iron")

func build_props() -> void:
    model("market",Vector3(8,1.2,-1.5))
    var second := model("market",Vector3(20,1.2,9),.9)
    second.rotation_degrees.y=-12
    for p in [Vector3(5.4,1.2,-1.5),Vector3(10.7,1.2,-2),Vector3(-16,1.2,.5),Vector3(-15,1.2,.2),Vector3(19,1.2,7),Vector3(12,4,-5.8)]:
        model("barrel",p)
        collider("Barrel",p+Vector3.UP*.48,Vector3(.85,.96,.85))
    for p in [Vector3(5.7,1.2,-2.5),Vector3(11.2,1.2,-1),Vector3(-16.8,1.2,-.5),Vector3(20.5,1.2,6.2)]:
        model("crate",p)
        collider("Crate",p+Vector3.UP*.44,Vector3(.9,.88,.9))
    for p in [Vector3(-18,1.2,12),Vector3(9,4,-6.4),Vector3(8,1.2,16.6)]: model("bench",p)
    for p in [Vector3(4.7,4,-4.8),Vector3(8,4,-4.8),Vector3(11.3,4,-4.8),Vector3(4,1.2,17.8),Vector3(10,1.2,17.8),Vector3(16,1.2,17.8)]: model("planter",p)
    model("boat",Vector3(-8.4,-1.5,13.1),.72)
    var west_dock := model("dock",Vector3(-12.4,-.3,11),.75)
    wire(Vector3(-19,7,-2),Vector3(11,8,-4.5))
    wire(Vector3(-16,6,5),Vector3(7,6.6,-1.5))
    for p in [Vector3(-17,1.2,8),Vector3(22,1.2,15),Vector3(20,4,-12)]:
        block("TreeTrunk",p+Vector3.UP*1.9,Vector3(.36,3.8,.36),"wood")
        var leaves := Sprite3D.new()
        leaves.texture=load("res://assets/sprites/oak.png")
        leaves.position=p+Vector3.UP*3.6;leaves.pixel_size=.045
        leaves.billboard=BaseMaterial3D.BILLBOARD_ENABLED
        leaves.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
        leaves.shaded=true;leaves.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
        add_child(leaves)
        collider("Tree",p+Vector3.UP*1.5,Vector3(.40,3,.40))
