extends SceneTree
## Independent GPU inspection, not a recording of player traversal.
## Keep the gameplay pose and vertical framing; expand only horizontal coverage.
const OUTPUT := "res://build/p9-experiments/building-probe"
const POSITIONS := {"left":Vector3(-17,1.2,3.5), "center":Vector3(3,1.2,6.7), "right":Vector3(20,1.2,3.5)}
var scene: Node3D
var viewport: SubViewport
var probe_camera: Camera3D
var records: Array[Dictionary] = []
var success := true

func _initialize() -> void:
    call_deferred("run_probe")

func run_probe() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("Building inspection requires a real GPU.")
        quit(2)
        return
    var path := ProjectSettings.globalize_path(OUTPUT)
    if DirAccess.make_dir_recursive_absolute(path) != OK:
        push_error("Cannot create building inspection directory.")
        quit(2)
        return
    scene = (load("res://scenes/reference_scene.tscn") as PackedScene).instantiate()
    root.add_child(scene)
    for frame in range(3): await process_frame
    scene.set_process(false)
    scene.player.set_physics_process(false)
    scene.hud.container.hide()
    scene.clock_frozen = true
    scene.tour = false
    scene.follow = true
    scene.rig.enabled = true
    scene.rig.frozen = true
    scene.background.wind_enabled = false
    scene.background.wind_phases.assign([0.0, 0.0])
    scene.background.advance(0.0)
    scene.lighting.water.set_shader_parameter("motion", 0.0)
    scene.lighting.apply_preset("dusk")
    scene.dof.enabled = false
    scene.dof.apply()
    viewport = SubViewport.new()
    viewport.name = "BuildingProbe3840"
    viewport.size = Vector2i(3840, 1080)
    viewport.world_3d = scene.get_world_3d()
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    probe_camera = Camera3D.new()
    probe_camera.keep_aspect = Camera3D.KEEP_HEIGHT
    viewport.add_child(probe_camera)
    probe_camera.current = true
    for variant in ["A", "B", "C", "D"]:
        if not scene.select_experiment(variant):
            records.append({"variant":variant, "passed":false, "reason":scene.experiment_notice})
            success = false
            continue
        scene.parallax.reset_all()
        scene.background.wind_enabled = false
        for station in POSITIONS:
            scene.player.position = POSITIONS[station]
            scene.player.velocity = Vector3.ZERO
            scene.rig.select_variant(variant, scene.player.global_position)
            scene.parallax.update(0.0, true)
            scene.impostor.update_view(0.0, true)
            clone_pose()
            await capture(variant + "-" + station, {"variant":variant, "station":station,
                "fixture":"same building at three existing gameplay poses; wider horizontal viewport only"})
    if scene.impostor.available:
        scene.select_experiment("D")
        scene.parallax.reset_all()
        scene.background.wind_enabled = false
        scene.player.position = POSITIONS.center
        scene.rig.select_variant("D", scene.player.global_position)
        scene.parallax.update(0.0, true)
        scene.impostor.update_view(0.0, true)
        clone_pose()
        for value in [0.0,1.0,2.0,3.0,4.0,5.0,6.0,3.5]:
            scene.impostor.frame_position = value
            scene.impostor.material.set_shader_parameter("frame_position", value)
            await capture("D-fixed-view-%02d" % int(value * 10), {"variant":"D", "station":"center",
                "fixture":"manual atlas-frame fixture; camera and feet fixed; not a gameplay route",
                "manual_frame_position":value})
    var file := FileAccess.open(path.path_join("report.json"), FileAccess.WRITE)
    if file == null:
        push_error("Cannot save building inspection report.")
        quit(2)
        return
    file.store_string(JSON.stringify({"passed":success, "real_gpu":true,
        "viewport":[3840,1080], "keep_aspect":"KEEP_HEIGHT", "period":"dusk",
        "dof":false, "wind":false, "water_motion":false, "records":records,
        "scope":"Independent same-building inspection. Viewpoint and projection match gameplay; expanded horizontal viewport is not gameplay framing. Integer D views are explicit manual fixtures. Vertical clipping is reported, never hidden."}, "  ") + "\n")
    file.close()
    print("P9_BUILDING_PROBE_COMPLETE ",records.size(), " passed=",success)
    quit(0 if success else 1)

func clone_pose() -> void:
    probe_camera.global_transform = scene.camera.global_transform
    probe_camera.projection = scene.camera.projection
    probe_camera.fov = scene.camera.fov
    probe_camera.size = scene.camera.size
    probe_camera.near = scene.camera.near
    probe_camera.far = scene.camera.far
    probe_camera.h_offset = scene.camera.h_offset
    probe_camera.v_offset = scene.camera.v_offset
    probe_camera.attributes = scene.camera.attributes

func capture(name: String, metadata: Dictionary) -> void:
    for frame in range(4): await process_frame
    await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        metadata.passed = false
        metadata.reason = "Empty GPU capture."
        records.append(metadata)
        success = false
        return
    var building: Node3D = scene.impostor.source_visual
    var minimum := Vector2(INF, INF)
    var maximum := Vector2(-INF, -INF)
    for x in [-4.0,4.0]:
        for y in [0.0,9.0]:
            for z in [-3.0,3.0]:
                var pixel := probe_camera.unproject_position(building.to_global(Vector3(x,y,z)))
                minimum = minimum.min(pixel)
                maximum = maximum.max(pixel)
    var projected_box := Rect2(minimum, maximum-minimum).grow(20)
    var bounded_box := projected_box.intersection(Rect2(Vector2.ZERO, Vector2(viewport.size)))
    var crop_box := Rect2i(int(floor(bounded_box.position.x)), int(floor(bounded_box.position.y)),
        int(ceil(bounded_box.size.x)), int(ceil(bounded_box.size.y)))
    crop_box = crop_box.intersection(Rect2i(Vector2i.ZERO, viewport.size))
    var wide_name := name + "-wide.png"
    var crop_name := name + "-crop.png"
    var output := ProjectSettings.globalize_path(OUTPUT)
    var wide_ok := image.save_png(output.path_join(wide_name)) == OK
    var crop_ok := false
    if crop_box.size.x > 0 and crop_box.size.y > 0:
        crop_ok = image.get_region(crop_box).save_png(output.path_join(crop_name)) == OK
    var relative: Vector3 = scene.camera.global_position - building.global_position
    var feet := probe_camera.unproject_position(building.global_position)
    var card_feet := feet
    if scene.impostor.active:
        var anchor_local := Vector3(0, (0.5-scene.impostor.ANCHOR_V)*scene.impostor.WORLD_SPAN, 0)
        card_feet = probe_camera.unproject_position(scene.impostor.card.to_global(anchor_local))
    metadata.merge({"passed":wide_ok and crop_ok, "wide":wide_name, "crop":crop_name,
        "projection":"orthographic" if scene.camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective",
        "player_position":[scene.player.position.x,scene.player.position.y,scene.player.position.z],
        "camera_position":[scene.camera.global_position.x,scene.camera.global_position.y,scene.camera.global_position.z],
        "yaw_degrees":scene.rig.yaw_degrees,
        "camera_position_angle_degrees":rad_to_deg(atan2(relative.x,relative.z)),
        "camera_direction_angle_degrees":rad_to_deg(atan2(scene.camera.global_basis.z.x,scene.camera.global_basis.z.z)),
        "d_frame_position":scene.impostor.frame_position if scene.impostor.active else null,
        "building_feet_pixels":[feet.x,feet.y], "impostor_feet_pixels":[card_feet.x,card_feet.y],
        "foot_error_px":feet.distance_to(card_feet),
        "projected_model_box":[projected_box.position.x,projected_box.position.y,projected_box.size.x,projected_box.size.y],
        "crop_box":[crop_box.position.x,crop_box.position.y,crop_box.size.x,crop_box.size.y],
        "model_box_clipped":not Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(projected_box)})
    records.append(metadata)
    success = success and wide_ok and crop_ok
