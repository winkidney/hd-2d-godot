extends SceneTree
## Actual Light3D controls and CharacterBody3D traversal of the light gradients.
## Headless distances and frame bindings do not claim rendered brightness.
const ENTRY := "res://scenes/ancient_canal.tscn"
const BROAD_IDS := ["broad_tavern_warm", "broad_cloth_cool"]
const EXPECTED_POSITIONS := [Vector3(7.3,1.8,-.4), Vector3(-6.7,1.8,3.2)]
var scene: Node3D
var output := "res://build/ancient-canal/tavern-lighting-20261007"
var runtime_fingerprint := ""
var failures: Array[String] = []
var checks: Array[Dictionary] = []
var report: Dictionary = {}
var samples: Array[Dictionary] = []
var neighborhoods: Dictionary = {}
var binding_pairs: Dictionary = {}

func _initialize() -> void:
    root.size = Vector2i(1920,1080)
    root.content_scale_size = Vector2i(1920,1080)
    Input.use_accumulated_input = false
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--lighting-output="):
            output = argument.trim_prefix("--lighting-output=")
        elif argument.begins_with("--canal-fingerprint="):
            runtime_fingerprint = argument.trim_prefix("--canal-fingerprint=")
    call_deferred("run")

func check(passed: bool, id: String, detail: Dictionary = {}) -> void:
    checks.append({"id":id,"passed":passed,"detail":detail})
    if not passed:
        failures.append(id)
        print("LIGHTING_ROUTE_FAIL ",id," ",detail)

func vector_array(point: Vector3) -> Array:
    return [point.x,point.y,point.z]

func equal_value(left: Variant, right: Variant) -> bool:
    if left is Color and right is Color: return left.is_equal_approx(right)
    if typeof(left) in [TYPE_FLOAT,TYPE_INT] and typeof(right) in [TYPE_FLOAT,TYPE_INT]:
        return absf(float(left)-float(right)) < .0002
    return left == right

func settle(frames := 3) -> void:
    for index in frames: await physics_frame

func lights_and_controls() -> void:
    var catalog: Array = scene.light_catalog()
    check(scene.lanterns.size()==6,"six_hanging_lantern_lights")
    check(scene.streetlamps.size()==6,"six_existing_streetlamps")
    check(scene.broad_lights.size()==2,"two_large_area_lights")
    check(catalog.size()==14 and scene.lamp_nodes.size()==14,"fourteen_environment_catalog_lights")
    var ids: Dictionary = {}
    for entry in catalog:
        check(not ids.has(entry.id) and scene.lamp_nodes.get(entry.id) is OmniLight3D,"catalog_unique_real_light_"+entry.id)
        ids[entry.id] = true
    var lantern_models: Array = scene.layout.models.filter(func(entry): return entry.id=="lantern")
    check(lantern_models.size()==6,"six_visible_hanging_lantern_models")
    for index in range(2):
        var model_point: Vector3 = scene.vec(lantern_models[4+index].position)
        var wanted := Vector3(6.0 if index==0 else 7.6,2.6,-2.32)
        check(model_point.distance_to(wanted)<.001,"new_lantern_flanks_tavern_door_"+str(index),{"model_position":vector_array(model_point)})
        var lamp: OmniLight3D = scene.lamp_nodes["lantern_"+str(4+index)]
        check(lamp.global_position.distance_to(wanted+Vector3(0,-.4,.24))<.001,"new_lantern_model_light_alignment_"+str(index))
    for index in BROAD_IDS.size():
        var id: String = BROAD_IDS[index]
        check(scene.lamp_nodes.has(id) and scene.lamp_metadata[id].group=="broad","stable_broad_catalog_id_"+id)
        var lamp: OmniLight3D = scene.lamp_nodes[id]
        check(lamp.global_position.distance_to(EXPECTED_POSITIONS[index])<.001,"broad_actual_world_position_"+id)
        check(equal_value(lamp.omni_range,7.0) and lamp.shadow_enabled,"broad_default_large_range_and_shadow_"+id)
    check(scene.lamp_nodes[BROAD_IDS[0]].light_color.r>scene.lamp_nodes[BROAD_IDS[0]].light_color.b,"tavern_light_is_warm")
    check(scene.lamp_nodes[BROAD_IDS[1]].light_color.b>scene.lamp_nodes[BROAD_IDS[1]].light_color.r,"cloth_light_is_cool")
    for period in ["day","dusk","night"]:
        scene.apply_time_preset(period)
        var wanted_energy: float = {"day":.1,"dusk":1.7,"night":2.6}[period]
        for id in BROAD_IDS:
            check(equal_value(scene.lamp_nodes[id].light_energy,wanted_energy) and equal_value(scene.lamp_nodes[id].omni_range,7.0),"actual_broad_preset_"+period+"_"+id)
    scene.restore_defaults()
    for id in BROAD_IDS:
        check(scene.select_lamp(id),"select_new_broad_light_"+id)
        scene.console.refresh()
        var option: String = scene.console.lamp_selector.get_item_text(scene.console.lamp_selector.selected)
        check(option.contains(scene.lamp_metadata[id].label),"broad_UI_catalog_label_"+id)
        var target := {"enabled":false,"color":Color(.8,.6,.3,1),"energy":1.25,"range":8.0,"shadow":false}
        for property in target:
            check(scene.set_selected_lamp(property,target[property]),"broad_single_control_accept_"+id+"_"+property)
            check(equal_value(scene.lamp_state(id)[property],target[property]),"broad_single_actual_value_"+id+"_"+property)
            scene.console.refresh()
            var control: Control = scene.console.fields["lamp_"+property]
            var visible_value: Variant = control.color if property=="color" else (control.button_pressed if property in ["enabled","shadow"] else control.value)
            if property in ["energy","range"]:
                visible_value = float(scene.console.readouts["lamp_"+property].text.trim_suffix("m"))
            check(equal_value(visible_value,target[property]),"broad_single_UI_actual_"+id+"_"+property)
        scene.set_selected_lamp("enabled",true)
        var original: Dictionary = scene.settings.candidate_from_values(scene.values,scene.lamp_overrides)
        scene.isolate_selected_lamp()
        check(scene.camera_locked and not scene.player.controls_enabled and scene.lamp_nodes.keys().all(func(key): return scene.lamp_nodes[key].visible==(key==id)),"broad_isolation_real_light_only_"+id)
        check(equal_value(scene.main_light.light_energy,0.0) and not scene.test_light.visible,"broad_isolation_removes_main_and_sweep_"+id)
        scene.set_selected_lamp("energy",3.1)
        scene.restore_lamp_isolation()
        check(scene.lamp_overrides==original.lamp_overrides and not scene.camera_locked and scene.player.controls_enabled,"broad_isolation_restores_complete_override_"+id)
        check(equal_value(scene.lamp_nodes[id].light_energy,1.25),"broad_isolation_restores_light_energy_"+id)
    var original_path: String = scene.settings.path
    scene.settings.path = output.path_join("broad-light-settings.cfg")
    var expected: Dictionary = scene.settings.candidate_from_values(scene.values,scene.lamp_overrides)
    check(scene.save_settings(),"broad_settings_actual_file_save")
    scene.restore_defaults()
    check(scene.load_settings(),"broad_settings_actual_file_load")
    check(scene.settings.candidate_from_values(scene.values,scene.lamp_overrides)==expected,"broad_settings_complete_roundtrip")
    for id in BROAD_IDS:
        check(equal_value(scene.lamp_state(id).range,8.0) and equal_value(scene.lamp_state(id).energy,1.25) and equal_value(scene.lamp_state(id).color,Color(.8,.6,.3,1)),"new_broad_override_restored_"+id)
    scene.settings.path = original_path
    check(scene.set_parameter("broad_energy",2.2),"broad_group_energy_control")
    check(BROAD_IDS.all(func(id): return equal_value(scene.lamp_nodes[id].light_energy,2.2) and not scene.lamp_overrides[id].has("energy")),"broad_group_edit_clears_single_energy_overrides")
    scene.restore_defaults()
    check(scene.set_parameter("broad_enabled",false) and BROAD_IDS.all(func(id): return not scene.lamp_nodes[id].visible),"broad_group_disable")
    check(scene.set_parameter("broad_enabled",true) and BROAD_IDS.all(func(id): return scene.lamp_nodes[id].visible),"broad_group_enable")
    scene.restore_defaults()

func sample_route() -> void:
    var foot: Vector3 = scene.player.global_position
    var face: int = scene.player.facing
    var frame: int = scene.player.animation_frame
    var distances: Dictionary = {}
    var direction: String = scene.player.animation.DIRECTIONS[face]
    for id in BROAD_IDS:
        var light: OmniLight3D = scene.lamp_nodes[id]
        var horizontal := Vector2(foot.x-light.global_position.x,foot.z-light.global_position.z).length()
        var distance := foot.distance_to(light.global_position)
        distances[id] = {"horizontal_metres":horizontal,"foot_distance_metres":distance,"range_metres":light.omni_range,"enabled":light.visible,"energy":light.light_energy}
        var area: Dictionary = neighborhoods[id]
        area.minimum_horizontal_metres = minf(area.minimum_horizontal_metres,horizontal)
        area.maximum_horizontal_metres = maxf(area.maximum_horizontal_metres,horizontal)
        if distance<light.omni_range: area.inside_range_samples += 1
        else: area.outside_range_samples += 1
        if horizontal<3.0 and scene.player.walking:
            area.near_samples += 1
            area.animation_frames[str(frame)] = true
            area.directions[direction] = true
            var key: String = id+":"+str(face)+":"+str(frame)
            if not binding_pairs.has(key):
                binding_pairs[key] = true
                check(scene.player.surface.get_shader_parameter("normal_atlas")==scene.player.normal_atlases[face] and scene.player.surface.get_shader_parameter("silver_atlas")==scene.player.silver_atlases[face],"route_light_neighborhood_direction_binding_"+key)
                var definition: Dictionary = scene.player.color_definitions[face].frames[frame]
                var region: Array = definition.region
                var atlas_size: Vector2 = scene.player.color_atlases[face].get_size()
                var actual: Vector4 = scene.player.surface.get_shader_parameter("atlas_region")
                var wanted := Vector4(region[0]/atlas_size.x,region[1]/atlas_size.y,region[2]/atlas_size.x,region[3]/atlas_size.y)
                check(actual.is_equal_approx(wanted),"route_light_neighborhood_frame_slice_"+key)
    samples.append({"physics_frame":Engine.get_physics_frames(),"route_index":scene.route_index,"foot":vector_array(foot),"direction":direction,"frame":frame,"walking":scene.player.walking,"lamp_distances":distances})

func actual_route() -> void:
    check(Engine.time_scale==1.0 and Engine.physics_ticks_per_second==60,"actual_route_original_time_scale_and_physics_rate")
    for id in BROAD_IDS:
        neighborhoods[id] = {"minimum_horizontal_metres":INF,"maximum_horizontal_metres":0.0,"inside_range_samples":0,"outside_range_samples":0,"near_samples":0,"animation_frames":{},"directions":{}}
    scene.player.position = scene.vec(scene.layout.player_spawn)
    scene.player.velocity = Vector3.ZERO
    await settle(20)
    var start_foot: Vector3 = scene.player.global_position
    var start_tick := Engine.get_physics_frames()
    var start_usec := Time.get_ticks_usec()
    var last_tick := -1
    scene.start_route()
    check(scene.route_running and scene.player.scripted_input,"actual_route_starts_actor_scripted_input")
    for index in range(6000):
        await physics_frame
        var tick := Engine.get_physics_frames()
        if tick==last_tick: continue
        last_tick = tick
        sample_route()
        if not scene.route_running: break
    var passed: bool = scene.route_result.get("passed",false)
    if scene.route_running: scene.cancel_route()
    check(passed and not scene.route_running and not scene.player.scripted_input,"actual_route_completes_through_new_lights")
    var return_error := Vector2(scene.player.global_position.x-start_foot.x,scene.player.global_position.z-start_foot.z).length()
    check(return_error<.5,"actual_route_returns_to_spawn",{"horizontal_error_metres":return_error})
    var low := 0.0
    var high := 0.0
    var all_directions: Dictionary = {}
    var frame_ids: Dictionary = {}
    for sample in samples:
        low = minf(low,sample.foot[1])
        high = maxf(high,sample.foot[1])
        all_directions[sample.direction] = true
        frame_ids[str(sample.physics_frame)] = true
    check(low<-.24 and high>1.1,"actual_route_visits_lower_dock_and_bridge",{"minimum_foot_y":low,"maximum_foot_y":high})
    check(all_directions.size()==4,"actual_route_displays_all_four_directions",{"directions":all_directions.keys()})
    check(frame_ids.size()==samples.size() and samples.size()>600,"route_samples_are_unique_actual_physics_frames",{"sample_count":samples.size()})
    for id in BROAD_IDS:
        var area: Dictionary = neighborhoods[id]
        check(area.minimum_horizontal_metres<.3,"actual_route_passes_under_broad_center_"+id,{"distance_metres":area.minimum_horizontal_metres})
        check(area.inside_range_samples>60 and area.outside_range_samples>60,"actual_route_crosses_range_boundary_"+id,{"inside_samples":area.inside_range_samples,"outside_samples":area.outside_range_samples})
        check(area.directions.size()>=2 and area.animation_frames.size()>=20,"actual_route_shows_directions_and_moving_details_near_"+id,{"directions":area.directions.keys(),"animation_frame_count":area.animation_frames.size()})
    report.route = {"passed":passed,"start_foot":vector_array(start_foot),"end_foot":vector_array(scene.player.global_position),"return_horizontal_error_metres":return_error,"physics_elapsed_frames":Engine.get_physics_frames()-start_tick,"wall_elapsed_seconds":float(Time.get_ticks_usec()-start_usec)/1000000.0,"time_scale":Engine.time_scale,"physics_hz":Engine.physics_ticks_per_second,"route_points":scene.layout.route.duplicate(true),"neighborhoods":neighborhoods,"samples":samples}
    scene.start_route()
    await settle(30)
    var before_cancel: Vector3 = scene.player.global_position
    scene.cancel_route()
    await settle(20)
    var stop_error := Vector2(scene.player.global_position.x-before_cancel.x,scene.player.global_position.z-before_cancel.z).length()
    check(not scene.route_running and scene.route_result.get("cancelled",false) and not scene.player.scripted_input and scene.player.scripted_direction==Vector2.ZERO and scene.player.controls_enabled and stop_error<.01,"new_route_cancel_restores_controls_and_stops_feet",{"horizontal_stop_error_metres":stop_error})
    report.cancellation = {"cancelled":scene.route_result.get("cancelled",false),"controls_restored":scene.player.controls_enabled,"scripted_input":scene.player.scripted_input,"horizontal_stop_error_metres":stop_error}

func run() -> void:
    if not output.begins_with("res://build/ancient-canal/"):
        check(false,"evidence_output_inside_ancient_build")
        quit(1)
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    scene = load(ENTRY).instantiate()
    root.add_child(scene)
    await settle(20)
    check(not scene.settings_load_attempted,"everyday_settings_not_loaded")
    lights_and_controls()
    await actual_route()
    report.merge({"passed":failures.is_empty(),"checks":checks,"failures":failures,"runtime_fingerprint":runtime_fingerprint,"entry":ENTRY,"scope":"Real 14-Light3D catalog, selected/group controls, isolation, file settings roundtrip, and actual CharacterBody3D route crossing both broad-light ranges with original animation bindings; headless report does not prove rendered brightness.","display_backend":DisplayServer.get_name(),"fixed_fps":OS.get_cmdline_args().has("--fixed-fps")})
    var file := FileAccess.open(output.path_join("lighting-route-report.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  ")+"\n")
    print("LIGHTING_ROUTE_DONE passed=",report.passed," checks=",checks.size()," actual_route_samples=",samples.size())
    scene.queue_free()
    await process_frame
    quit(0 if report.passed else 1)
