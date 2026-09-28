extends Node
## Run via --self-test. Physics assertions do not imply visual acceptance.
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var report: Dictionary = {}

func check(condition: bool, label: String) -> void:
    checks.append({"name": label, "passed": condition})
    if not condition:
        failures.append(label)
    print("ASSERT_", "PASS " if condition else "FAIL ", label)

func settle(frames: int) -> void:
    for i in range(frames):
        await get_tree().physics_frame

func place(scene, position: Vector3) -> void:
    scene.player.position = position
    scene.player.velocity = Vector3.ZERO
    scene.player.scripted_direction = Vector2.ZERO
    await settle(20)

func drive(scene, direction: Vector2, frames: int) -> void:
    scene.player.scripted_direction = direction
    await settle(frames)
    scene.player.scripted_direction = Vector2.ZERO
    await settle(3)

func run_core(scene) -> void:
    reparent(get_tree().root)
    scene.player.scripted_input = true
    scene.tour = false
    scene.follow = false
    await settle(30)
    check(scene.get_node("World").get_child_count() >= 290, "baked_world_loaded")
    check(scene.player.is_on_floor(), "actor_starts_on_floor")
    check(scene.player.sprite.hframes == 4 and scene.player.sprite.vframes == 4, "four_direction_atlas")
    scene.player.scripted_direction = Vector2(1, 1)
    check(absf(scene.player.motion_direction().length() - 1.0) < 0.001, "diagonal_input_normalized")
    await place(scene, Vector3(1.2, 0.25, 0.8))
    await drive(scene, Vector2(0, 1), 155)
    check(scene.player.position.z > 7.7 and scene.player.position.y > -0.2, "bridge_north_to_south")
    await drive(scene, Vector2(0, -1), 155)
    check(scene.player.position.z < 1.6 and scene.player.position.y > -0.2, "bridge_south_to_north")
    await place(scene, Vector3(6, 0.25, 0.0))
    await drive(scene, Vector2(0, 1), 90)
    check(scene.player.position.z < 1.85 and scene.player.position.y > -0.2, "river_is_not_walkable")
    await place(scene, Vector3(1.2, 0.25, 4.3))
    await drive(scene, Vector2(1, 0), 80)
    check(scene.player.position.x < 2.35, "bridge_parapet_blocks_actor")
    await place(scene, Vector3(-5.8, 0.25, -1.2))
    await drive(scene, Vector2(0, -1), 70)
    check(scene.player.position.z > -2.3, "inn_walls_block_actor")
    await test_interactions(scene)


func test_interactions(scene) -> void:
    await place(scene, Vector3(-2.3, 0.25, -0.45))
    check(scene.nearest_interaction().get("id") == "keeper", "nearest_npc_selected")
    scene.interact()
    check(scene.hud.dialogue.visible and not scene.player.controls_enabled, "dialogue_opens_and_locks_movement")
    var before: Vector3 = scene.player.position
    await drive(scene, Vector2(1, 0), 20)
    check(scene.player.position.distance_to(before) < 0.04, "dialogue_prevents_movement")
    scene.interact()
    check(not scene.hud.dialogue.visible and scene.player.controls_enabled, "dialogue_closes_and_unlocks")
    await place(scene, Vector3(1.6, 0.25, 8.2))
    check(scene.nearest_interaction().get("id") == "sign", "sign_can_be_investigated")
    await place(scene, Vector3(-15, 0.25, 9))
    check(scene.nearest_interaction().is_empty(), "out_of_range_interaction_rejected")
    var actor_id: int = scene.player.get_instance_id()
    scene.lighting.apply_preset("night")
    check(scene.lighting.preset_id == "night" and scene.lighting.lamps[0].light_energy == 6.0, "night_preset_applies_atomically")
    scene.lighting.apply_preset("dusk")
    check(actor_id == scene.player.get_instance_id(), "preset_preserves_actor_identity")
    scene.lighting.set_effects(false)
    check(not scene.lighting.environment.glow_enabled and not scene.dof.attributes.dof_blur_far_enabled, "effects_comparison_switch")
    scene.lighting.set_effects(true)
    for action in ["move_left", "move_right", "move_up", "move_down"]:
        check(InputMap.action_get_events(action).size() >= 2, "bindings_" + action)

func finish(scene) -> void:
    var real_gpu := DisplayServer.get_name() != "headless"
    var output_dir := "res://build/validation"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture-dir="):
            output_dir = arg.trim_prefix("--capture-dir=")
    if not output_dir.is_absolute_path():
        output_dir = "res://" + output_dir
    output_dir = ProjectSettings.globalize_path(output_dir)
    DirAccess.make_dir_recursive_absolute(output_dir)
    report = {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "real_gpu": real_gpu, "utc": Time.get_datetime_string_from_system(true), "viewport": [get_viewport().size.x, get_viewport().size.y]}
    await place(scene, scene.to_vector(scene.layout.player_spawn))
    scene.player.facing = 0
    if real_gpu:
        report["gpu"] = RenderingServer.get_video_adapter_name()
        await capture_evidence(scene, output_dir)
    report["checks"] = checks
    report["failures"] = failures
    report["passed"] = failures.is_empty()
    var file := FileAccess.open(output_dir.path_join("runtime-report.json"), FileAccess.WRITE)
    if file == null:
        push_error("Cannot write validation report.")
        failures.append("write_report")
    else:
        file.store_string(JSON.stringify(report, "  ") + "\n")
        file.close()
    print("VALIDATION_DONE assertions=", checks.size(), " failures=", failures.size())
    scene.queue_free()
    for i in range(4):
        await get_tree().process_frame
    get_tree().quit(0 if failures.is_empty() else 1)

func capture_evidence(scene, output_dir: String) -> void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    scene.lighting.apply_preset("dusk")
    for i in range(120):
        await get_tree().process_frame
    check(await scene.capture(output_dir.path_join("dusk-hud.png")), "capture_dusk_hud")
    scene.hud.container.hide()
    var performance: Dictionary = {}
    for preset in ["dusk", "night"]:
        scene.lighting.apply_preset(preset)
        for i in range(120):
            await get_tree().process_frame
        check(await scene.capture(output_dir.path_join(preset + ".png")), "capture_" + preset)
        performance[preset] = await measure_frames()
        check(performance[preset].rendered_frames >= 359 and performance[preset].gpu.nonzero_samples > 0, "measured_gpu_frames_" + preset)
    scene.lighting.set_effects(false)
    for i in range(60):
        await get_tree().process_frame
    check(await scene.capture(output_dir.path_join("night-no-effects.png")), "capture_effects_comparison")
    scene.lighting.set_effects(true)
    scene.hud.container.show()
    report["performance"] = performance
    report["capture_files"] = ["dusk-hud.png", "dusk.png", "night.png", "night-no-effects.png"]

func measure_frames() -> Dictionary:
    return await preload("res://tests/render_benchmark.gd").measure(get_viewport())

func run(scene) -> void:
    await run_core(scene)
    await finish(scene)
