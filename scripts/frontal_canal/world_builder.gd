extends "res://scripts/reference_scene/world_builder.gd"
## New frontal composition. Reuse material/model primitives, never old layout builders.

func build(data: Dictionary) -> void:
    layout=data
    rng.seed=int(data.seed)
    name="World"
    for entry in data.platforms:
        var p := vector(entry.center)
        var size := vector(entry.size)
        block(entry.id,p,size,"brick",true)
        block(entry.id+"Paving",p+Vector3.UP*(size.y*0.5+0.022),Vector3(size.x,0.045,size.z),"paving")
    build_frontal_apron(data)
    build_frontal_bridge(data)
    for entry in data.stairs:
        build_stair(entry)
    for entry in data.buildings:
        var p := vector(entry.position)
        var scale_value := float(entry.scale)
        var building := model(entry.model,p,scale_value)
        building.name=entry.id
        building.rotation_degrees.y=float(entry.get("yaw",0.0))
        var dimensions := Vector3(7,6.8,5) if entry.model=="palazzo" else Vector3(4.8,5.4,4.2)
        var body := collider(entry.id,p+Vector3.UP*dimensions.y*scale_value*0.5,dimensions*scale_value)
        body.rotation_degrees.y=building.rotation_degrees.y
    for position_data in data.lamps:
        model("lamp",vector(position_data))
    build_frontal_water(data)
    build_frontal_edges(data)
    for ends in data.rail_runs:
        if vector(ends[0]).distance_to(vector(ends[1]))>0.15:
            rail_run(vector(ends[0]),vector(ends[1]))
    for position_data in data.pillars:
        model("pillar",vector(position_data),0.62)
    if not graybox:
        build_frontal_props(data)

func build_frontal_apron(data: Dictionary) -> void:
    # Off-route set dressing closes the viewport without expanding playable bounds.
    # Its paving meets the two physical banks at exactly the same visual height.
    for entry in data.visual_aprons:
        var p := vector(entry.center)
        var size := vector(entry.size)
        block(entry.id,p,size,"brick")
        block(entry.id+"Paving",p+Vector3.UP*(size.y*0.5+0.022),Vector3(size.x,0.045,size.z),"paving")
    if graybox:
        return
    for entry in data.edge_buildings:
        var item := model("townhouse",vector(entry.position),float(entry.scale))
        item.name=entry.id
        item.rotation_degrees.y=float(entry.yaw)
    for entry in data.edge_trees:
        var p := vector(entry.position)
        var s := float(entry.scale)
        block(entry.id+"Trunk",p+Vector3.UP*1.35*s,Vector3(0.32,2.7,0.32)*s,"wood")
        var leaves := foliage("oak",p+Vector3.UP*3.2*s,0.035*s)
        leaves.name=entry.id+"Crown"

func build_frontal_bridge(data: Dictionary) -> void:
    var center := vector(data.bridge_center)
    var bridge := model("arch_bridge",center)
    bridge.name="FrontalArchBridge"
    bridge.scale=vector(data.bridge_scale)
    collider("FrontalBridgeDeck",center-Vector3.UP*0.15,Vector3(10,0.30,4.4))
    for offset in [-2.04,2.04]:
        collider("FrontalBridgeParapet",center+Vector3(0,0.6,offset),Vector3(9.7,1.2,0.22))

func build_frontal_water(data: Dictionary) -> void:
    var river: Dictionary=data.river
    var length := float(river.near_z)-float(river.far_z)
    var center_z := (float(river.near_z)+float(river.far_z))*0.5
    var water := MeshInstance3D.new()
    water.name="WaterSurface"
    var mesh := PlaneMesh.new()
    mesh.size=Vector2(float(river.width),length)
    water.mesh=mesh
    water.position=Vector3(float(river.center_x),float(river.surface_y),center_z)
    var material := ShaderMaterial.new()
    material.shader=load("res://scripts/reference_scene/water.gdshader")
    material.set_shader_parameter("caustics",load("res://assets/reference-scene/textures/water.png"))
    water.material_override=material
    water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(water)
    block("FrontalRiverBed",Vector3(float(river.center_x),float(river.bed_y),center_z),Vector3(float(river.width),0.2,length),"stone")
    # Continuous low distant embankments leave the canal open to the horizon.
    # They are decorative and never form a wall across the river or the sky.
    var distant_length := -18.0-float(river.far_z)
    var distant_center_z := (-18.0+float(river.far_z))*0.5
    for side in [-1,1]:
        var x := float(river.center_x)+float(side)*(float(river.width)*0.5+0.22)
        block("DistantCanalWall",Vector3(x,-0.9,distant_center_z),Vector3(0.44,3.2,distant_length),"brick")
        block("DistantCanalCoping",Vector3(x,0.76,distant_center_z),Vector3(0.65,0.12,distant_length),"stone")
    var dock: Dictionary=data.dock
    var landing := model("dock",vector(dock.position),float(dock.scale))
    landing.name="LowerCanalLanding"
    collider("LowerLandingDeck",vector(dock.deck_center),vector(dock.deck_size))

func movement_barrier(label: String, center: Vector3, size: Vector3) -> void:
    var body := collider(label,center,size)
    body.add_to_group("movement_only_barrier",true)

func build_frontal_edges(_data: Dictionary) -> void:
    # Water blockers leave the bridge and the inset dock ramp entirely open.
    movement_barrier("RiverRear",Vector3(-5,1.5,-29.65),Vector3(6,8,60.7))
    movement_barrier("RiverMiddle",Vector3(-5,1.5,6.6),Vector3(6,8,2.6))
    movement_barrier("RiverFront",Vector3(-5,1.5,13.65),Vector3(6,8,3.1))
    movement_barrier("RiverDockWest",Vector3(-6.65,1.5,10),Vector3(2.7,8,4.2))
    for x in [-22.05,20.05]:
        movement_barrier("WorldSide",Vector3(x,4,-3.5),Vector3(0.1,14,34))
    movement_barrier("WorldRear",Vector3(-1,4,-20.1),Vector3(43,14,0.1))
    movement_barrier("WorldFront",Vector3(-1,4,13.1),Vector3(43,14,0.1))

func build_frontal_props(data: Dictionary) -> void:
    for entry in data.props:
        var p := vector(entry.position)
        var item := model(entry.model,p,float(entry.get("scale",1.0)))
        item.name=entry.id
        item.rotation_degrees.y=float(entry.get("yaw",0.0))
        if entry.has("solid_size"):
            var size := vector(entry.solid_size)
            var body := collider(entry.id,p+Vector3.UP*size.y*0.5,size)
            body.rotation_degrees.y=item.rotation_degrees.y
    # Keep wires beside/above the bridge; the main palazzo face remains clear.
    for ends in data.wires:
        wire(vector(ends[0]),vector(ends[1]))
