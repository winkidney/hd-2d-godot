extends SceneTree
## Check the assembled scene against the independent measured review drawing.
var checks: Array = []
var scene: Node3D
var destination := "res://build/ancient-canal/blueprint-layout.json"
func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--report="): destination=arg.trim_prefix("--report=")
    call_deferred("run")
func check(value: bool, label: String) -> void:
    checks.append({"id":label,"passed":value})
    if not value: print("BLUEPRINT_FAIL ",label)
func vec(point: Array) -> Vector3:
    return Vector3(point[0],point[1],point[2])
func ground_at(x: float,z: float) -> float:
    var query := PhysicsRayQueryParameters3D.create(Vector3(x,1,z),Vector3(x,-1,z))
    var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
    return hit.position.y if not hit.is_empty() else -999.0
func run() -> void:
    var path := "res://art_source/ancient-canal/layout-review/20261008-r5/layout.review.json"
    var drawing: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
    scene=load("res://scenes/ancient_canal.tscn").instantiate()
    root.add_child(scene)
    scene.frozen=true
    scene.player.set_physics_process(false)
    for i in 4: await physics_frame
    check(scene.layout.blueprint.sha256==FileAccess.get_sha256(path),"drawing_source_hash")
    for entry in drawing.objects:
        var model: Node3D=scene.world.get_node_or_null(NodePath(entry.id))
        check(model!=null and model.position.is_equal_approx(vec(entry.position)) and is_zero_approx(model.rotation_degrees.y-entry.yaw_deg),"model_origin_"+entry.id)
    for pair in [["BR1",drawing.bridge],["D1",drawing.dock],["BO1",drawing.boat]]:
        var model: Node3D=scene.world.get_node_or_null(NodePath(pair[0]))
        check(model!=null and model.position.is_equal_approx(vec(pair[1].center)),"waterfront_model_"+pair[0])
    for entry in drawing.npcs:
        var npc: Sprite3D=scene.get_node_or_null(NodePath(entry.id))
        check(npc!=null and npc.position.is_equal_approx(vec(entry.position)) and npc.hframes==1,"npc_foot_"+entry.id)
    for i in drawing.willows.size():
        var tree: Sprite3D=scene.world.get_node_or_null(NodePath(drawing.willow_ids[i]))
        check(tree!=null and tree.position.is_equal_approx(vec(drawing.willows[i])),"willow_foot_"+drawing.willow_ids[i])
    check(scene.world.get_node_or_null("L5")==null,"removed_tavern_front_tree_stays_absent")
    for entry in drawing.background_buildings+drawing.background_trees:
        var layer: Node3D=scene.farfield.layers[entry.layer]
        var model: Node3D=layer.get_node_or_null(NodePath(entry.id))
        check(model!=null and model.position.is_equal_approx(vec(entry.position)),"background_position_"+entry.id)
    scene.apply_time_preset("night")
    check(scene.lamp_nodes.size()==14,"fourteen_control_ids")
    for entry in drawing.lights:
        var light: OmniLight3D=scene.lamp_nodes.get(entry.id)
        check(light!=null and light.global_position.is_equal_approx(vec(entry.position)),"light_emitter_"+entry.diagram_id)
        if entry.kind=="streetlamp":
            var fixture: Node3D=scene.world.get_node_or_null(NodePath(entry.id))
            check(fixture!=null and fixture.position.is_equal_approx(vec(entry.fixture_position)),"pole_foot_"+entry.diagram_id)
    var dock_light: OmniLight3D=scene.lamp_nodes.streetlamp_dock_south
    check(is_equal_approx(dock_light.omni_range,4.5) and not dock_light.shadow_enabled,"dock_warm_lamp_range_and_shadow")
    scene.select_lamp("streetlamp_dock_south")
    scene.isolate_selected_lamp()
    check(dock_light.visible and not scene.lamp_nodes.broad_cloth_cool.visible,"dock_single_lamp_isolation")
    scene.restore_lamp_isolation()
    scene.restore_defaults()
    check(is_equal_approx(dock_light.omni_range,4.5) and not dock_light.shadow_enabled,"dock_lamp_layout_default_restored")
    for point in [[-23.5,8.5],[23.5,8.5],[-23.5,-2.4],[23.5,-2.4],[1.2,-12]]:
        check(absf(ground_at(point[0],point[1]))<.001,"road_height_"+str(point))
    check(absf(ground_at(-12,3)-(-.32))<.001,"dock_collision_top_minus_032")
    check(absf(ground_at(-12,5.95)-(-.16))<.01,"ramp_midpoint_minus_016")
    var surfaces:=0
    for node in scene.world.get_children():
        if str(node.name).begins_with("GroundSurface_"): surfaces+=1
    check(surfaces==3,"three_batched_ground_surfaces")
    var passed: bool=checks.all(func(x):return x.passed)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
    FileAccess.open(destination,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks,"scope":"Independent drawing against actual instantiated models, lights, background, roads and dock ramp physics."},"  ")+"\n")
    print("BLUEPRINT_DONE passed=",passed," checks=",checks.size())
    scene.queue_free()
    await process_frame
    quit(0 if passed else 1)
