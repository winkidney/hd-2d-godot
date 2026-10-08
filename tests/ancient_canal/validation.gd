extends SceneTree
## Real scene logic, material bindings and CharacterBody3D traversal.
## This headless run does not prove rendered light, shadows, or native focus.
## Pass --canal-test; optional --canal-settings-write / --canal-settings-read.
const ENTRY := "res://scenes/ancient_canal.tscn"
const Settings = preload("res://scripts/ancient_canal/settings.gd")
const OUTPUT := "res://build/ancient-canal/headless"
const CROSS_PROCESS_SETTINGS := "res://build/ancient-canal/scene-settings-cross-process.cfg"
var scene: Node3D
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var report: Dictionary = {}
var output := OUTPUT
var complete := false

func _initialize() -> void:
    root.size = Vector2i(1920, 1080)
    root.content_scale_size = Vector2i(1920, 1080)
    root.gui_embed_subwindows = true
    Input.use_accumulated_input = false
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--canal-output="):
            output = arg.trim_prefix("--canal-output=")
    call_deferred("run")

func check(ok: bool, label: String, detail: Dictionary = {}) -> void:
    checks.append({"name": label, "passed": ok, "detail": detail})
    if not ok:
        failures.append(label)
        print("CANAL_VALIDATION_FAIL ", label, " ", detail)

func same(a: Variant, b: Variant, tolerance := 0.0002) -> bool:
    if a is Color and b is Color:
        return a.is_equal_approx(b)
    if a is Vector2 and b is Vector2:
        return a.distance_to(b) <= tolerance
    if a is Vector3 and b is Vector3:
        return a.distance_to(b) <= tolerance
    if a is Vector4 and b is Vector4:
        return a.distance_to(b) <= tolerance
    if a is Transform3D and b is Transform3D:
        return a.is_equal_approx(b)
    if typeof(a) in [TYPE_FLOAT, TYPE_INT] and typeof(b) in [TYPE_FLOAT, TYPE_INT]:
        return absf(float(a)-float(b)) <= tolerance
    return a == b

func wait_frames(count := 2) -> void:
    for index in count:
        await process_frame

func wait_physics(count := 2) -> void:
    for index in count:
        await physics_frame

func vec(values: Array) -> Vector3:
    return Vector3(values[0], values[1], values[2])

func choose_value(definition: Dictionary) -> Variant:
    match definition.type:
        "bool": return not bool(definition.default)
        "enum":
            for option in definition.options:
                if option.value != definition.default and option.value != "auto" and option.value != "custom":
                    return option.value
        "color": return Color(.24, .51, .79, 1.0)
        "int": return int(definition.min) + int(floor((float(definition.max)-float(definition.min))*.7))
        "float": return clampf(snappedf(float(definition.min) + (float(definition.max)-float(definition.min))*.67,float(definition.step)),float(definition.min),float(definition.max))
    return null

func shader_value(key: String) -> Variant:
    return scene.player.surface.get_shader_parameter(key)

func actual_value(key: String) -> Variant:
    match key:
        "normals_enabled": return shader_value("use_normals")
        "normal_strength": return shader_value("normal_strength")
        "normal_flip_y": return shader_value("flip_y")
        "shading_mode": return "stepped" if scene.player.surface.shader.resource_path.ends_with("sprite_stepped.gdshader") else "native"
        "light_steps": return shader_value("shade_levels")
        "clay": return shader_value("clay_mode")
        "normal_debug": return shader_value("normal_debug")
        "silver_specular": return shader_value("silver_specular")
        "direction": return "auto" if scene.player.direction_override < 0 else scene.player.animation.DIRECTIONS[scene.player.direction_override]
        "animation_pause", "fixed_animation": return scene.player.paused
        "animation_frame": return scene.player.animation_frame
        "main_yaw": return scene.main_light.rotation_degrees.y
        "main_pitch": return scene.main_light.rotation_degrees.x
        "main_energy": return scene.main_light.light_energy
        "main_color": return scene.main_light.light_color
        "main_shadow": return scene.main_light.shadow_enabled
        "scene_shadow":
            var master: bool = scene.values.scene_shadow
            if scene.main_light.shadow_enabled != (master and scene.values.main_shadow) or scene.test_light.shadow_enabled != (master and scene.values.test_light_shadow): return null
            for entry in scene.light_catalog():
                var expected: bool = master and bool(scene.values[entry.group+"_shadow"]) and bool(entry.cast_shadow)
                if scene.lamp_nodes[entry.id].shadow_enabled != expected: return null
            return master
        "ambient": return scene.environment.ambient_light_energy
        "ambient_color": return scene.environment.ambient_light_color
        "sky_top_color": return sky_color("sky_top_color")
        "sky_horizon_color": return sky_color("sky_horizon_color")
        "lantern_energy": return scene.lanterns[0].light_energy if not scene.lanterns.is_empty() else null
        "lantern_enabled": return scene.lanterns[0].visible if not scene.lanterns.is_empty() else null
        "lantern_color": return scene.lanterns[0].light_color if not scene.lanterns.is_empty() else null
        "lantern_range": return scene.lanterns[0].omni_range if not scene.lanterns.is_empty() else null
        "lantern_shadow": return scene.lanterns.all(func(light): return light.shadow_enabled)
        "streetlamp_enabled": return scene.streetlamps[0].visible if not scene.streetlamps.is_empty() else null
        "streetlamp_energy": return scene.streetlamps[0].light_energy if not scene.streetlamps.is_empty() else null
        "streetlamp_color": return scene.streetlamps[0].light_color if not scene.streetlamps.is_empty() else null
        "streetlamp_range": return scene.streetlamps[0].omni_range if not scene.streetlamps.is_empty() else null
        "streetlamp_shadow": return scene.streetlamps[0].shadow_enabled if not scene.streetlamps.is_empty() else null
        "broad_enabled": return scene.broad_lights[0].visible
        "broad_energy": return scene.broad_lights[0].light_energy
        "broad_color":
            var actual: Color = scene.lamp_nodes.broad_tavern_warm.light_color
            var tint: Color = scene.lamp_metadata.broad_tavern_warm.tint
            return Color(actual.r/tint.r,actual.g/tint.g,actual.b/tint.b,actual.a)
        "broad_range": return scene.broad_lights[0].omni_range
        "broad_shadow": return scene.broad_lights.all(func(light): return light.shadow_enabled)
        "test_light_enabled": return scene.test_light.visible
        "test_light_color": return scene.test_light.light_color
        "test_light_energy": return scene.test_light.light_energy
        "test_light_x": return scene.test_light.position.x
        "test_light_y": return scene.test_light.position.y
        "test_light_z": return scene.test_light.position.z
        "test_light_range": return scene.test_light.omni_range
        "test_light_shadow": return scene.test_light.shadow_enabled
        "water_flow": return scene.water_material.get_shader_parameter("flow")
        "water_wave": return scene.water_material.get_shader_parameter("wave_strength")
        "water_reflection": return scene.water_material.get_shader_parameter("reflection")
        "fog": return scene.environment.fog_density
        "bloom": return scene.environment.glow_intensity
        "ssao": return scene.environment.ssao_enabled
        "dof_near": return scene.attributes.dof_blur_near_enabled
        "dof_far": return scene.attributes.dof_blur_far_enabled
        "dof_amount": return scene.attributes.dof_blur_amount
        "focus_distance": return scene.attributes.dof_blur_far_distance - 7.0
        "camera_variant": return scene.rig.variant_id
        "camera_follow": return scene.rig.enabled
        "camera_fov": return scene.camera.fov
        "camera_distance": return scene.camera.global_position.distance_to(scene.rig.target+scene.rig.follow_offset)
        "parallax_mode": return scene.parallax.profile.mode
        "parallax_strength": return scene.parallax.profile.global_strength
        "parallax_transition": return scene.parallax.profile.transition_time
    if key in Settings.LAYER_IDS: return scene.parallax.profile.layer_gains[key]
    return null

func control_value(key: String) -> Variant:
    var control: Control = scene.console.fields[key]
    match scene.parameter_spec.parameters[key].type:
        "bool": return control.button_pressed
        "float", "int": return control.value
        "color": return control.color
        "enum": return scene.parameter_spec.parameters[key].options[control.selected].value
    return null

func behavioral_parameter(key: String, value: Variant) -> bool:
    if key == "time_preset":
        var colors := {"day": Color(.17,.32,.5), "dusk": Color(.12,.19,.34), "night": Color(.018,.035,.09)}
        return same(sky_color("sky_top_color"),colors[value]) and same(scene.main_light.light_energy,{"day":1.35,"dusk":1.1,"night":.48}[value])
    if key == "camera_follow":
        var saved: Vector3 = scene.player.position
        scene.player.position += Vector3.RIGHT*2
        scene.camera_update(0,true)
        var delta: Vector3 = scene.camera_offset
        scene.player.position = saved
        scene.camera_update(0,true)
        return delta.length() > .6 if value else delta.length() < .001
    if key == "focus_protection":
        var saved: Vector3 = scene.player.position
        scene.player.position += Vector3(1,0,-2)
        scene.camera_update(0,true)
        scene.update_focus()
        var expected: float = -(scene.camera.global_transform.affine_inverse()*(scene.player.position+Vector3.UP)).z if value else scene.values.focus_distance
        var valid := same(scene.attributes.dof_blur_far_distance,expected+7.0)
        scene.player.position = saved
        scene.camera_update(0,true)
        scene.update_focus()
        return valid
    if key == "orbit_light" or key == "orbit_speed":
        scene.set_parameter("orbit_light",true)
        scene.set_parameter("fixed_light",false)
        scene.frozen = false
        scene.elapsed = 1.0
        scene._process(.25)
        var angle: float = 1.25*float(scene.values.orbit_speed)
        var expected := Vector3(scene.player.position.x+cos(angle)*3.0,scene.values.test_light_y,scene.player.position.z+sin(angle)*3.0)
        scene.frozen = true
        return same(scene.test_light.position,expected)
    if key == "fixed_light":
        scene.set_parameter("orbit_light",true)
        var before: Vector3 = scene.test_light.position
        scene.frozen = false
        scene._process(.35)
        scene.frozen = true
        return same(scene.test_light.position,before) if value else not same(scene.test_light.position,before)
    if Settings.PARALLAX_ALIASES.has(key) or key in Settings.LAYER_IDS:
        # Verify all six real Node3D transforms and their final screen projection.
        var saved: Vector3 = scene.player.position
        var world_before: Transform3D = scene.world.global_transform
        scene.player.position += Vector3.RIGHT*2
        scene.camera_update(0,true)
        var valid: bool = scene.parallax.states.size() == 6 and scene.parallax.compatible
        var moved := 0
        for id in Settings.LAYER_IDS:
            var state: Dictionary = scene.parallax.states[id]
            var info: Dictionary = scene.parallax.projections.get(id,{})
            valid = valid and bool(info.get("valid",false)) and absf(float(info.get("result_x",INF))-float(info.get("expected_x",0.0))) < .003
            valid = valid and same(scene.parallax.current[id],scene.parallax.profile.effective(id))
            if state.node.global_transform.origin.distance_to(state.base.origin) > .0001: moved += 1
        valid = valid and moved > 0 and scene.world.global_transform == world_before
        scene.player.position = saved
        scene.camera_update(0,true)
        return valid
    return false

func parameters() -> void:
    scene.player.set_physics_process(false)
    scene.frozen = true
    check(scene.parameter_spec.parameters.size() == 73 and scene.parameter_spec.lamp_parameters.size() == 5 and scene.console.fields.size() == 78,"all_parameter_controls",{"global":scene.parameter_spec.parameters.size(),"single_lamp":scene.parameter_spec.lamp_parameters.size(),"controls":scene.console.fields.size()})
    check(scene.npc_materials.size() == 5,"five_independent_npc_materials")
    check(scene.lanterns.size() == 6 and scene.streetlamps.size() == 6 and scene.broad_lights.size() == 2 and scene.lamp_nodes.size() == 14,"fourteen_actual_environment_lights_exist")
    for key in scene.parameter_spec.parameters:
        scene.restore_defaults()
        scene.player.position = vec(scene.layout.player_spawn)
        scene.camera_update(0,true)
        var definition: Dictionary = scene.parameter_spec.parameters[key]
        var value = choose_value(definition)
        if key == "light_steps": scene.set_parameter("shading_mode","stepped")
        if key == "focus_distance": scene.set_parameter("focus_protection",false)
        if Settings.PARALLAX_ALIASES.has(key) or key in Settings.LAYER_IDS:
            scene.set_parameter("parallax_mode","artistic")
        if key == "animation_frame":
            scene.set_frame(int(value))
            check(scene.values.animation_frame == int(value),"accept_"+key)
        else:
            check(scene.set_parameter(key,value),"accept_"+key)
        var actual = actual_value(key)
        var applied := same(actual,value) if actual != null else behavioral_parameter(key,value)
        if key == "camera_follow" or Settings.PARALLAX_ALIASES.has(key) or key in Settings.LAYER_IDS:
            applied = applied and behavioral_parameter(key,value)
        check(applied,"real_property_"+key,{"requested":str(value),"actual":str(actual)})
        if key.begins_with("lantern_") or key.begins_with("streetlamp_") or key.begins_with("broad_"):
            check_group_lights(key,value)
        scene.console.refresh()
        check(same(control_value(key),scene.values[key]),"ui_shows_effective_"+key)
        var before: Dictionary = scene.values.duplicate(true)
        check(not scene.set_parameter(key,{"injected":true}),"reject_type_"+key)
        check(scene.values == before,"invalid_keeps_state_"+key)
    var before_unknown: Dictionary = scene.values.duplicate(true)
    check(not scene.set_parameter("unknown_parameter",1.0) and scene.values == before_unknown,"unknown_parameter_keeps_state")
    scene.set_parameter("normal_strength",1.37)
    scene.console.refresh()
    check(scene.console.readouts.normal_strength.text.begins_with("1.37"),"numeric_label_displays_actual_unrounded_state")
    scene.restore_defaults()
    for material in scene.world.material_overrides:
        check(same(material.normal_scale,.8),"building_normal_strength_bound")
    scene.set_parameter("normals_enabled",false)
    for material in scene.world.material_overrides:
        check(same(material.normal_scale,0.0),"building_normal_off_bound")
    for material in scene.npc_materials:
        check(material.get_shader_parameter("use_normals") == false,"npc_normal_switch_bound")
    scene.set_parameter("scene_shadow",false)
    check(not scene.main_light.shadow_enabled and not scene.test_light.shadow_enabled and scene.lamp_nodes.values().all(func(light): return not light.shadow_enabled),"all_scene_shadows_switch_off")
    scene.restore_defaults()

func check_group_lights(key: String, value: Variant) -> void:
    var group := key.get_slice("_",0)
    var property := key.trim_prefix(group + "_")
    for entry in scene.light_catalog():
        if entry.group != group: continue
        var actual: Dictionary = scene.lamp_state(entry.id)
        var expected = value
        if property == "color": expected = value*entry.get("tint",Color.WHITE)
        if property == "shadow": expected = bool(value) and bool(entry.cast_shadow) and bool(scene.values.scene_shadow)
        check(same(actual[property],expected),"group_actual_"+key+"_"+entry.id)

func camera_profiles_and_layers() -> void:
    scene.restore_defaults()
    var saved_position: Vector3 = scene.player.position
    var expected := {"F":{"radius":30.0,"fov":35.0,"pitch":14.0,"yaw":0.0},"W":{"radius":23.0,"fov":45.0,"pitch":12.0,"yaw":0.0}}
    for id in expected:
        check(scene.select_variant(id),"select_actual_variant_"+id)
        var pose: Dictionary = scene.rig.pose_diagnostics()
        check(pose.supported and same(pose.orbit_radius,expected[id].radius) and same(pose.fov,expected[id].fov) and same(pose.pitch_degrees,expected[id].pitch),"frontal_default_pose_"+id,pose)
        check(scene.set_lens("radius",expected[id].radius+1.0) and scene.set_lens("fov",expected[id].fov+2.0),"edit_independent_lens_"+id)
    for id in expected:
        scene.select_variant(id)
        check(same(actual_value("camera_distance"),expected[id].radius+1.0) and same(scene.camera.fov,expected[id].fov+2.0),"variant_retains_own_lens_"+id)
        scene.player.position = vec(scene.layout.player_spawn)+Vector3.RIGHT*17.0
        scene.camera_update(0,true)
        check(same(scene.rig.yaw_degrees,expected[id].yaw) and scene.rig.supported_pose(),"horizontal_travel_yaw_bound_"+id)
    var profiles_before: Dictionary = scene.rig.lens_profiles_snapshot()
    var pose_before: Transform3D = scene.camera.global_transform
    check(not scene.set_lens("radius",45.1) and not scene.select_variant("unknown") and not scene.select_variant("O") and scene.rig.lens_profiles_snapshot()==profiles_before and same(scene.camera.global_transform,pose_before),"invalid_lens_or_removed_O_keeps_actual_pose")
    scene.player.position = saved_position
    scene.restore_defaults()
    scene.player.position += Vector3.RIGHT*2.0
    scene.camera_update(0,true)
    check(scene.farfield.layers.size()==6 and scene.parallax.states.size()==6,"six_real_background_groups")
    for id in Settings.LAYER_IDS:
        var state: Dictionary = scene.parallax.states[id]
        check(state.node==scene.farfield.layers[id] and state.node.get_child_count()>0 and same(state.node.global_transform,state.base) and same(scene.parallax.current[id],1.0),"natural_layer_keeps_authored_transform_"+id)
    scene.set_parameter("parallax_mode","artistic")
    for id in Settings.LAYER_IDS:
        var info: Dictionary = scene.parallax.projections[id]
        check(info.valid and absf(float(info.result_x)-float(info.expected_x))<.003,"artistic_actual_projection_"+id,info)
    scene.player.position = saved_position
    scene.restore_defaults()

func individual_lights() -> void:
    scene.restore_defaults()
    var catalog: Array = scene.light_catalog()
    check(catalog.size()==14 and catalog.all(func(entry): return scene.lamp_nodes[entry.id] is OmniLight3D),"all_catalog_ids_resolve_actual_Light3D")
    for period in ["day","dusk","night"]:
        scene.apply_time_preset(period)
        check(not scene.test_light.visible and scene.streetlamps.all(func(light): return same(light.light_energy,{"day":.05,"dusk":.8,"night":1.4}[period]) and same(light.omni_range,4.5 if light.name=="streetlamp_dock_south" else 4.0)),"new_streetlamp_actual_preset_"+period)
    scene.restore_defaults()
    check(scene.streetlamps.filter(func(light): return light.shadow_enabled).size()==2,"only_two_default_new_lamps_cast_shadows")
    check(not scene.select_lamp("unknown"),"unknown_selected_light_rejected")
    check(scene.select_lamp("streetlamp_left_back"),"select_actual_single_light")
    var target := {"enabled":false,"color":Color(.9,.55,.3,1),"energy":1.25,"range":6.0,"shadow":true}
    for property in target:
        check(scene.set_selected_lamp(property,target[property]),"single_light_accept_"+property)
        check(same(scene.selected_lamp_values()[property],target[property]),"single_light_actual_"+property)
        scene.console.refresh()
        var control: Control = scene.console.fields["lamp_"+property]
        var displayed = control.color if property=="color" else (control.button_pressed if property in ["enabled","shadow"] else control.value)
        if property in ["energy","range"]:
            displayed = float(scene.console.readouts["lamp_"+property].text.trim_suffix("m"))
        check(same(displayed,target[property]),"single_light_UI_"+property)
    var overrides_before: Dictionary = scene.lamp_overrides.duplicate(true)
    check(not scene.set_selected_lamp("energy",NAN) and not scene.set_selected_lamp("script","injected") and scene.lamp_overrides==overrides_before,"invalid_single_light_keeps_all_overrides")
    var other: Dictionary = scene.lamp_state("streetlamp_right_front")
    check(same(other.energy,scene.values.streetlamp_energy) and other.enabled,"single_override_does_not_modify_other_light")
    scene.set_selected_lamp("enabled",true)
    scene.force_direction("auto")
    scene.player.facing = 2
    scene.player.update_animation()
    var standing_facing: int = scene.player.facing
    var background_before: String = scene.farfield.profile_id
    var original_path: String = scene.settings.path
    scene.settings.path = output.path_join("single-light-settings.cfg")
    var saved: Dictionary = scene.settings.candidate_from_values(scene.values,scene.lamp_overrides)
    var pose_before: Transform3D = scene.camera.global_transform
    scene.isolate_selected_lamp()
    check(not scene.lamp_isolation_snapshot.is_empty() and scene.camera_locked and not scene.player.controls_enabled,"isolation_locks_pose_and_actor")
    check(scene.lamp_nodes.keys().all(func(id): return scene.lamp_nodes[id].visible==(id==scene.selected_lamp_id)) and same(scene.main_light.light_energy,0.0) and not scene.test_light.visible,"isolation_uses_actual_selected_light_only")
    scene.set_selected_lamp("enabled",false)
    check(scene.lamp_nodes.values().all(func(light): return not light.visible),"isolated_selected_light_can_be_disabled")
    scene.set_selected_lamp("enabled",true)
    check(scene.lamp_nodes[scene.selected_lamp_id].visible,"isolated_selected_light_can_be_enabled")
    scene.set_selected_lamp("energy",2.2)
    scene.force_direction("up")
    scene.apply_time_preset("day")
    check(scene.farfield.profile_id==background_before and same(scene.main_light.light_energy,0.0),"isolated_preset_cannot_reenable_main_light_or_change_background")
    check(not scene.set_parameter("streetlamp_energy",3.0) and not scene.set_parameter("main_energy",2.0),"isolated_lighting_group_and_main_controls_are_blocked")
    check(not scene.set_parameter("fixed_animation",false) and not scene.set_parameter("fixed_light",false),"isolated_fixed_state_cannot_be_released")
    check(scene.lamp_nodes.keys().all(func(id): return scene.lamp_nodes[id].visible==(id==scene.selected_lamp_id)),"isolation_guard_preserves_only_selected_visible_light")
    scene.set_parameter("parallax_mode","artistic")
    check(scene.save_settings() and scene.settings.load_settings()==saved,"save_during_isolation_persists_original_complete_candidate")
    scene.restore_lamp_isolation()
    check(scene.lamp_isolation_snapshot.is_empty() and not scene.camera_locked and same(scene.camera.global_transform,pose_before),"isolation_restores_actual_pose")
    check(scene.lamp_overrides==saved.lamp_overrides and scene.parallax.snapshot()==saved.parallax and same(scene.lamp_state("streetlamp_left_back").energy,1.25),"isolation_restores_original_overrides_and_six_layer_profile")
    check(scene.player.direction_override==-1 and scene.player.facing==standing_facing and scene.player.displayed_facing==standing_facing,"isolation_restores_standing_auto_direction")
    check(scene.farfield.profile_id==background_before,"isolation_restores_background_time_preset")
    scene.set_parameter("streetlamp_energy",.6)
    check(not scene.lamp_overrides.get("streetlamp_left_back",{}).has("energy") and scene.streetlamps.all(func(light): return same(light.light_energy,.6)),"group_edit_clears_corresponding_individual_override")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scene.settings.path))
    scene.settings.path = original_path
    scene.restore_defaults()

func animation_bindings() -> void:
    scene.player.set_physics_process(false)
    var position_before: Vector3 = scene.player.position
    var sampled := 0
    for direction_index in 4:
        var direction: String = scene.player.animation.DIRECTIONS[direction_index]
        scene.force_direction(direction)
        for index in 27:
            scene.set_frame(index)
            var definition: Dictionary = scene.player.color_definitions[direction_index]
            var frame: Dictionary = definition.frames[index]
            var atlas: Texture2D = scene.player.color_atlases[direction_index]
            var size: Vector2 = atlas.get_size()
            var area: Array = frame.region
            var expected := Vector4(area[0]/size.x,area[1]/size.y,area[2]/size.x,area[3]/size.y)
            check(scene.player.animation_frame == index and scene.player.displayed_facing == direction_index,"shared_frame_"+direction+"_"+str(index))
            check(shader_value("color_atlas") == atlas,"color_atlas_"+direction+"_"+str(index))
            check(shader_value("normal_atlas") == scene.player.normal_atlases[direction_index] and scene.player.normal_atlases[direction_index].get_size() == atlas.get_size(),"normal_atlas_"+direction+"_"+str(index))
            check(shader_value("silver_atlas") == scene.player.silver_atlases[direction_index] and same(shader_value("atlas_region"),expected),"mask_and_region_"+direction+"_"+str(index))
            check(scene.player.sprite.texture == scene.player.color_frames[direction_index][index],"immutable_frame_texture_"+direction+"_"+str(index))
            check(same(scene.player.position,position_before) and same(scene.player.sprite.offset,Vector2(0,112)),"foot_anchor_"+direction+"_"+str(index))
        scene.set_parameter("animation_pause",false)
        var clip: Dictionary = scene.player.animation.clips[direction_index]
        for cycle in 3:
            var start := 0.0
            for index in 27:
                var end: float = clip.ends[index]
                scene.player.inspection_clock = cycle*float(clip.duration)+(start+end)*.5
                scene.player.update_animation()
                check(scene.player.animation_frame == index,"three_cycles_"+direction+"_"+str(cycle)+"_"+str(index))
                start = end
                sampled += 1
            scene.player.inspection_clock = (cycle+1)*float(clip.duration)+.000001
            scene.player.update_animation()
            check(scene.player.animation_frame == 0,"cycle_seam_"+direction+"_"+str(cycle))
    report.animation = {"explicit_pairs":108,"timed_cycle_samples":sampled,"directions":4,"cycles_each":3,"scope":"real shader atlas bindings and original frame timing; rendered temporal appearance remains a GPU check"}
    scene.restore_defaults()

func presets_and_comparison() -> void:
    scene.set_parameter("camera_distance",27.0)
    scene.set_parameter("camera_fov",42.0)
    scene.set_parameter("dof_near",true)
    scene.set_parameter("dof_far",false)
    for id in ["day","dusk","night"]:
        scene.apply_time_preset(id)
        check(same(actual_value("camera_distance"),27.0) and same(scene.camera.fov,42.0),"preset_preserves_camera_"+id)
        check(scene.attributes.dof_blur_near_enabled and not scene.attributes.dof_blur_far_enabled,"preset_preserves_focus_"+id)
    scene.force_direction("right")
    scene.set_frame(13)
    scene.set_parameter("orbit_light",true)
    var saved: Dictionary = scene.values.duplicate(true)
    var camera_before: Transform3D = scene.camera.global_transform
    var light_before: Vector3 = scene.test_light.position
    var original_path: String = scene.settings.path
    scene.settings.path = output.path_join("comparison-settings.cfg")
    var candidate_before: Dictionary = scene.settings.candidate_from_values(scene.values,scene.lamp_overrides)
    scene.toggle_comparison()
    scene.frozen = false
    scene._process(.25)
    scene.frozen = true
    check(not scene.comparison_snapshot.is_empty() and scene.camera_locked,"comparison_active")
    check(scene.values.normals_enabled != saved.normals_enabled,"comparison_switches_normals")
    check(same(scene.camera.global_transform,camera_before) and same(scene.test_light.position,light_before) and scene.player.animation_frame == 13,"comparison_keeps_camera_frame_light")
    scene.set_parameter("parallax_mode","artistic")
    scene.set_parameter("near_town",.3)
    check(scene.save_settings() and scene.settings.load_settings()==candidate_before,"save_during_comparison_preserves_full_original_profile")
    scene.toggle_comparison()
    check(scene.comparison_snapshot.is_empty() and not scene.camera_locked and scene.values == saved,"comparison_restores_values")
    check(scene.parallax.snapshot()==candidate_before.parallax and scene.rig.lens_profiles_snapshot()==candidate_before.lens_profiles,"comparison_restores_all_controller_profiles")
    scene.force_direction("auto")
    scene.player.facing = 2
    scene.player.update_animation()
    var standing_facing: int = scene.player.facing
    var background_before: String = scene.farfield.profile_id
    scene.toggle_comparison()
    scene.force_direction("up")
    scene.apply_time_preset("day")
    scene.toggle_comparison()
    check(scene.player.direction_override==-1 and scene.player.facing==standing_facing and scene.player.displayed_facing==standing_facing,"comparison_restores_standing_auto_direction")
    check(scene.farfield.profile_id==background_before,"comparison_restores_background_time_preset")
    scene.toggle_comparison()
    scene.restore_defaults()
    check(not scene.camera_locked and scene.comparison_snapshot.is_empty(),"reset_unlocks_comparison_camera")
    scene.console.refresh()
    check(scene.console.state_readout.text.contains("黄昏") and scene.console.state_readout.text.contains("原生"),"reset_actual_readout")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scene.settings.path))
    scene.settings.path = original_path

func key_event(code: Key, pressed: bool, modifier := "", unicode_value := 0, echo := false) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = pressed
    event.echo = echo
    event.unicode = unicode_value
    event.ctrl_pressed = modifier == "ctrl"
    event.alt_pressed = modifier == "alt"
    event.shift_pressed = modifier == "shift"
    event.meta_pressed = modifier == "meta"
    Input.parse_input_event(event)
    await wait_frames(2)

func tap(code: Key, modifier := "", unicode_value := 0) -> void:
    await key_event(code,true,modifier,unicode_value)
    await key_event(code,false,modifier,unicode_value)

func ui_snapshot() -> Dictionary:
    var lamps: Dictionary = {}
    for entry in scene.light_catalog(): lamps[entry.id] = scene.lamp_state(entry.id)
    return {"values":scene.values.duplicate(true),"console":scene.console.visible,"dialogue":scene.dialogue.visible,"exit":scene.exit_confirmation.visible,"route":scene.route_running,"captures":scene.capture_counter,"controls":scene.player.controls_enabled,
        "lens_profiles":scene.rig.lens_profiles_snapshot(),"variant":scene.rig.variant_id,"pose":scene.camera.global_transform,"parallax":scene.parallax.snapshot(),"lamps":lamps,"selected_lamp":scene.selected_lamp_id,"isolated_lamp":scene.isolated_lamp_id}

func wheel_event(button: MouseButton, modifier := "", factor := 1.0) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = button
    event.pressed = true
    event.factor = factor
    event.position = Vector2(4,1060)
    event.global_position = event.position
    event.ctrl_pressed = modifier=="ctrl"
    event.alt_pressed = modifier=="alt"
    event.shift_pressed = modifier=="shift"
    event.meta_pressed = modifier=="meta"
    Input.parse_input_event(event)
    await wait_frames(2)

func reset_ui() -> void:
    scene.cancel_route()
    scene.console.close()
    scene.dialogue.hide()
    scene.exit_confirmation.hide()
    scene.sync_input()
    root.gui_release_focus()
    await wait_frames()

func input_safety() -> void:
    scene.frozen = true
    await reset_ui()
    var before := ui_snapshot()
    for modifier in ["ctrl","alt","shift","meta"]:
        for code in [KEY_M,KEY_E,KEY_T,KEY_G,KEY_K,KEY_ESCAPE]:
            await tap(code,modifier)
            check(ui_snapshot() == before,"modified_shortcut_"+modifier+"_"+OS.get_keycode_string(code))
    for code in [KEY_F8,KEY_F9,KEY_TAB]:
        await tap(code)
        check(ui_snapshot() == before,"reserved_key_"+OS.get_keycode_string(code))
    for modifier in ["ctrl","alt","shift","meta"]:
        await wheel_event(MOUSE_BUTTON_WHEEL_UP,modifier)
        check(ui_snapshot()==before,"modified_wheel_keeps_actual_lens_"+modifier)
    var radius_before: float = scene.rig.lens_snapshot().radius
    await wheel_event(MOUSE_BUTTON_WHEEL_UP)
    check(same(actual_value("camera_distance"),radius_before-.5),"bare_wheel_updates_actual_radius")
    await wheel_event(MOUSE_BUTTON_WHEEL_DOWN)
    check(same(actual_value("camera_distance"),radius_before),"bare_wheel_returns_actual_radius")
    await tap(KEY_M)
    check(scene.console.visible and not scene.player.controls_enabled,"M_opens_and_locks_movement")
    check(scene.player.motion_direction() == Vector3.ZERO,"console_rejects_actual_actor_motion")
    before = ui_snapshot()
    await wheel_event(MOUSE_BUTTON_WHEEL_UP)
    check(ui_snapshot()==before,"visible_console_blocks_world_wheel")
    before = ui_snapshot()
    await key_event(KEY_M,true,"",0,true)
    await key_event(KEY_M,false)
    check(ui_snapshot() == before,"key_echo_and_release_do_not_repeat")
    scene.console.tabs.current_tab = 2
    var edit: LineEdit = scene.console.numeric_spins.camera_fov.get_line_edit()
    edit.grab_focus()
    await wait_frames()
    check(root.gui_get_focus_owner() == edit,"actual_numeric_focus")
    before = ui_snapshot()
    for code in [KEY_M,KEY_E,KEY_T,KEY_G,KEY_K]:
        await tap(code,"",int(code))
        check(ui_snapshot() == before,"typing_does_not_dispatch_"+OS.get_keycode_string(code))
    edit.text = "34"
    edit.select_all()
    await tap(KEY_A,"ctrl",97)
    await tap(KEY_4,"",52)
    await tap(KEY_2,"",50)
    await tap(KEY_ENTER)
    check(same(scene.camera.fov,42.0),"numeric_text_commits_to_camera")
    await tap(KEY_TAB)
    check(scene.console.visible and not scene.player.controls_enabled,"Tab_navigation_keeps_panel")
    await tap(KEY_TAB,"shift")
    check(scene.console.visible and not scene.player.controls_enabled,"Shift_Tab_navigation_keeps_panel")
    root.gui_release_focus()
    scene.console.tabs.current_tab = 1
    var popup: PopupMenu = scene.console.fields.time_preset.get_popup()
    scene.console.fields.time_preset.show_popup()
    await wait_frames()
    check(popup.visible,"embedded_preset_popup_open")
    await tap(KEY_ESCAPE)
    check(not popup.visible and scene.console.visible and not scene.exit_confirmation.visible,"Esc_closes_popup_first")
    scene.console.lamp_selector.show_popup()
    await wait_frames()
    check(scene.console.has_open_popup(),"actual_single_lamp_menu_open")
    await tap(KEY_ESCAPE)
    check(not scene.console.has_open_popup() and scene.console.visible and not scene.exit_confirmation.visible,"Esc_closes_new_lamp_menu_first")
    await tap(KEY_ESCAPE)
    check(not scene.console.visible and scene.player.controls_enabled and not scene.exit_confirmation.visible,"Esc_closes_console")
    scene.dialogue.show()
    scene.sync_input()
    await tap(KEY_ESCAPE)
    check(not scene.dialogue.visible and not scene.exit_confirmation.visible and scene.player.controls_enabled,"Esc_closes_dialogue")
    await tap(KEY_ESCAPE)
    check(scene.exit_confirmation.visible and not scene.player.controls_enabled,"Esc_requests_confirmation")
    check(scene.exit_confirmation.gui_get_focus_owner() == scene.exit_confirmation.get_cancel_button(),"exit_defaults_to_continue")
    scene.exit_confirmation.get_cancel_button().pressed.emit()
    await wait_frames()
    check(not scene.exit_confirmation.visible and scene.player.controls_enabled,"cancel_exit_restores_control")
    await reset_ui()
    scene.start_route()
    scene.set_physics_process(false)
    before = ui_snapshot()
    for code in [KEY_M,KEY_T,KEY_E,KEY_K,KEY_F8,KEY_F9]:
        await tap(code)
        check(ui_snapshot() == before,"route_locks_action_"+OS.get_keycode_string(code))
    await wheel_event(MOUSE_BUTTON_WHEEL_UP)
    check(ui_snapshot()==before,"route_locks_world_wheel")
    await tap(KEY_ESCAPE,"ctrl")
    check(scene.route_running,"modified_Esc_keeps_route")
    await tap(KEY_ESCAPE)
    check(not scene.route_running and scene.route_result.get("cancelled",false) and not scene.player.scripted_input,"Esc_cancels_route_and_releases_script")
    scene.set_physics_process(true)
    await reset_ui()

func settings_round_trip() -> void:
    var original_path: String = scene.settings.path
    var isolated_path := output.path_join("scene-settings-local.cfg")
    scene.settings.path = isolated_path
    scene.select_variant("W")
    scene.set_lens("radius",24.5)
    scene.set_lens("fov",47.0)
    scene.select_variant("F")
    scene.set_lens("radius",32.5)
    scene.set_lens("fov",42.0)
    scene.set_parameter("near_town",.5)
    scene.set_parameter("far_clouds",.4)
    scene.set_parameter("dof_near",true)
    scene.set_parameter("normal_strength",1.2)
    scene.set_parameter("main_color",Color(.8,.6,.4,1))
    scene.select_lamp("streetlamp_left_back")
    scene.set_selected_lamp("energy",1.25)
    scene.set_selected_lamp("color",Color(1,.7,.4,1))
    scene.set_selected_lamp("shadow",true)
    var saved: Dictionary = scene.values.duplicate(true)
    var saved_profiles: Dictionary = scene.rig.lens_profiles_snapshot()
    var saved_parallax: Dictionary = scene.parallax.snapshot()
    var saved_overrides: Dictionary = scene.lamp_overrides.duplicate(true)
    check(scene.save_settings(),"scene_saves_isolated_settings")
    var written := ConfigFile.new()
    written.load(isolated_path)
    check(not written.has_section("lens_O") and written.get_value("camera", "variant") == "F", "scene_explicit_save_contains_only_F_W")
    scene.restore_defaults()
    check(scene.load_settings() and scene.values == saved,"scene_restores_complete_settings")
    check(same(scene.camera.fov,42.0) and scene.attributes.dof_blur_near_enabled and same(shader_value("normal_strength"),1.2) and same(scene.main_light.light_color,Color(.8,.6,.4,1)),"loaded_settings_apply_real_properties")
    check(scene.rig.variant_id=="F" and scene.rig.lens_profiles_snapshot()==saved_profiles and scene.parallax.snapshot()==saved_parallax and scene.lamp_overrides==saved_overrides,"loaded_settings_restore_all_inactive_profiles_and_lamps")
    check(same(scene.lamp_state("streetlamp_left_back").energy,1.25) and same(scene.lamp_state("streetlamp_left_back").color,Color(1,.7,.4,1)) and scene.lamp_state("streetlamp_left_back").shadow,"loaded_single_light_override_applies_actual_node")
    scene.console.refresh()
    check(same(control_value("camera_fov"),42.0) and same(control_value("normal_strength"),1.2),"loaded_settings_refresh_UI")
    var config := ConfigFile.new()
    config.load(isolated_path)
    config.set_value("parameters","main_energy",NAN)
    config.save(isolated_path)
    check(not scene.load_settings() and scene.values == saved,"invalid_saved_settings_do_not_partially_apply")
    check(scene.rig.lens_profiles_snapshot()==saved_profiles and scene.parallax.snapshot()==saved_parallax and scene.lamp_overrides==saved_overrides,"invalid_cfg_preserves_all_authoritative_controllers")
    var old_three := ConfigFile.new()
    old_three.parse(scene.settings.config_for(scene.settings.candidate_from_values(saved, saved_overrides)).encode_to_text())
    old_three.set_value("lens_O", "radius", 29.5)
    old_three.set_value("lens_O", "fov", 38.0)
    old_three.set_value("camera", "variant", "O")
    old_three.save(isolated_path)
    var old_three_hash := FileAccess.get_sha256(isolated_path)
    check(scene.load_settings() and scene.rig.variant_id == "F" and scene.rig.lens_profiles_snapshot() == saved_profiles and scene.values == saved, "scene_maps_valid_saved_O_to_F_and_preserves_F_W_settings")
    check(FileAccess.get_sha256(isolated_path) == old_three_hash, "scene_old_O_load_preserves_file_bytes")
    var camera_before_rejection: Transform3D = scene.camera.global_transform
    old_three.set_value("lens_O", "radius", NAN)
    old_three.save(isolated_path)
    var rejected_old_hash := FileAccess.get_sha256(isolated_path)
    check(not scene.load_settings() and scene.values == saved and scene.rig.lens_profiles_snapshot() == saved_profiles and same(scene.camera.global_transform, camera_before_rejection), "scene_invalid_discarded_O_lens_rejects_atomically")
    check(FileAccess.get_sha256(isolated_path) == rejected_old_hash, "scene_invalid_O_load_does_not_rewrite_file")
    var legacy := ConfigFile.new()
    legacy.set_value("meta","schema",1)
    legacy.set_value("meta","scene","ancient-canal")
    for key in Settings.LEGACY_KEYS:
        var value = saved.get(key,1.0)
        if key=="camera_yaw": value = 10.0
        elif key=="camera_pitch": value = 20.0
        elif key=="camera_follow": value = false
        elif key=="parallax": value = .25
        legacy.set_value("parameters",key,value)
    legacy.save(isolated_path)
    var legacy_hash := FileAccess.get_sha256(isolated_path)
    check(scene.load_settings() and scene.settings.migrated_v1,"actual_scene_accepts_v1_in_memory_migration")
    var pose: Dictionary = scene.rig.pose_diagnostics()
    check(scene.rig.variant_id=="F" and same(pose.orbit_radius,30.0) and same(pose.fov,35.0) and same(pose.pitch_degrees,14.0) and same(pose.yaw_degrees,0.0) and scene.rig.enabled,"v1_actual_scene_resets_all_camera_fields")
    check(same(shader_value("normal_strength"),1.2) and same(scene.main_light.light_color,Color(.8,.6,.4,1)) and scene.attributes.dof_blur_near_enabled,"v1_actual_scene_preserves_valid_noncamera_effects")
    check(scene.parallax.snapshot()==scene.parallax.defaults_snapshot() and scene.lamp_overrides.is_empty(),"v1_actual_scene_resets_new_profile_and_missing_overrides")
    scene.select_variant("W")
    scene.set_lens("radius",26.0)
    check(FileAccess.get_sha256(isolated_path)==legacy_hash,"actual_scene_migration_switch_and_edit_leave_original_cfg_bytes")
    check(scene.save_settings() and FileAccess.get_sha256(isolated_path)!=legacy_hash,"explicit_scene_save_replaces_v1_only_after_user_action")
    config.load(isolated_path)
    check(config.get_value("meta","schema")==2,"explicit_scene_save_writes_schema2")
    for period in ["day","night"]:
        scene.apply_time_preset(period)
        var sky_before: Color = sky_color("sky_top_color")
        check(scene.save_settings(),"preset_settings_saved_"+period)
        scene.apply_time_preset("dusk")
        check(scene.load_settings() and same(sky_color("sky_top_color"),sky_before),"saved_preset_restores_actual_sky_"+period)
    scene.apply_time_preset("night")
    scene.select_lamp("streetlamp_left_back")
    scene.set_selected_lamp("range",5.25)
    var night_sky: Color = sky_color("sky_top_color")
    check(scene.values.time_preset=="custom" and scene.farfield.profile_id=="night","single_light_edit_marks_custom_and_preserves_actual_night_background")
    check(scene.save_settings(),"custom_night_scene_saved_with_explicit_background_metadata")
    scene.restore_defaults()
    check(scene.farfield.profile_id=="dusk","default_reset_changes_background_before_custom_load")
    check(scene.load_settings() and scene.values.time_preset=="custom" and same(sky_color("sky_top_color"),night_sky),"custom_night_load_restores_actual_sky_and_custom_label")
    check(background_palette_matches("night") and same(scene.lamp_state("streetlamp_left_back").range,5.25),"custom_night_load_restores_actual_background_colors_and_single_light")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_path))
    scene.settings.path = original_path
    check(scene.settings.path == "user://settings/ancient-canal.cfg","isolated_settings_leave_default_path")
    scene.restore_defaults()

func place(point: Vector3, settle := 20) -> void:
    scene.player.position = point+Vector3.UP*.15
    scene.player.velocity = Vector3.ZERO
    scene.player.scripted_input = true
    scene.player.scripted_direction = Vector2.ZERO
    scene.player.controls_enabled = true
    await wait_physics(settle)

func interactions() -> void:
    scene.player.set_physics_process(true)
    for entry in scene.layout.npcs+scene.layout.interactions:
        await place(vec(entry.position)+Vector3(0,0,.6))
        var nearest: Dictionary = scene.nearest_interaction()
        check(nearest.get("id","") == entry.id,"nearest_interaction_"+entry.id,{"position":str(scene.player.position)})
        scene.interact()
        check(scene.dialogue.visible and scene.dialogue_text.text.contains(entry.name) and scene.dialogue_text.text.contains(entry.dialogue),"dialogue_"+entry.id)
        check(not scene.player.controls_enabled,"dialogue_locks_movement_"+entry.id)
        check(scene.player.motion_direction() == Vector3.ZERO,"dialogue_rejects_actual_actor_motion_"+entry.id)
        scene.interact()
        check(not scene.dialogue.visible and scene.player.controls_enabled,"dialogue_closes_"+entry.id)
    await place(vec(scene.layout.player_spawn))
    check(scene.nearest_interaction().is_empty(),"outside_interaction_radius")
    scene.interact()
    check(not scene.dialogue.visible,"out_of_range_has_no_dialogue")
    for entry in scene.layout.npcs:
        var npc: Node = scene.get_node_or_null(entry.id)
        check(npc is Sprite3D and npc.texture.get_size() == Vector2(256,256),"npc_visible_sprite_"+entry.id)

func walk_toward(target: Vector3, limit := 900) -> Dictionary:
    var distance := INF
    var stagnant := 0
    var previous: Vector3 = scene.player.position
    var highest: float = scene.player.position.y
    var lowest: float = scene.player.position.y
    for frame in limit:
        var delta: Vector3 = target-scene.player.position
        delta.y = 0
        distance = delta.length()
        if distance < .22:
            scene.player.scripted_direction = Vector2.ZERO
            return {"passed":true,"frames":frame,"highest":highest,"lowest":lowest,"distance":distance}
        scene.player.scripted_direction = Vector2(delta.x,delta.z).normalized()
        await physics_frame
        highest = maxf(highest,scene.player.position.y)
        lowest = minf(lowest,scene.player.position.y)
        if scene.player.position.distance_to(previous)<.001:
            stagnant += 1
        else:
            stagnant = 0
        if stagnant > 120:
            break
        previous = scene.player.position
    scene.player.scripted_direction = Vector2.ZERO
    return {"passed":false,"distance":distance,"position":str(scene.player.position),"highest":highest,"lowest":lowest}

func physics_checks() -> void:
    scene.restore_defaults()
    scene.player.set_physics_process(true)
    scene.frozen = true
    await place(Vector3(1.2,0,7.5))
    check(scene.player.is_on_floor() and absf(scene.player.position.y)<.08,"left_bank_physical_ground")
    var outward := await walk_toward(Vector3(1.2,0,-2.3))
    check(outward.passed,"bridge_left_to_right",outward)
    check(outward.highest > .5 and outward.lowest > -.1,"bridge_raises_feet",outward)
    var inward := await walk_toward(Vector3(1.2,0,7.5))
    check(inward.passed and inward.highest > .5,"bridge_right_to_left",inward)
    var dock_entry := Vector3(scene.layout.dock.center_x,0,scene.layout.dock.approach_z+.2)
    await place(dock_entry)
    var dock := await walk_toward(Vector3(scene.layout.dock.center_x,scene.layout.dock.surface_y,scene.layout.dock.center_z))
    await wait_physics(25)
    check(dock.passed and scene.player.is_on_floor() and absf(scene.player.position.y+.32)<.08,"dock_ramp_descends_to_floor",dock)
    var back := await walk_toward(dock_entry)
    await wait_physics(20)
    check(back.passed and absf(scene.player.position.y)<.08,"dock_ramp_returns_to_bank",back)
    for side in [-1.0,1.0]:
        await place(Vector3(22,0,2.5+side*3.3))
        scene.player.scripted_direction = Vector2(0,-side)
        await wait_physics(100)
        scene.player.scripted_direction = Vector2.ZERO
        check(absf(scene.player.position.z-2.5)>=float(scene.layout.river.half_width) and scene.player.position.y>-.08,"water_guard_side_"+str(side),{"position":str(scene.player.position)})
    var tavern: Dictionary = scene.layout.models.filter(func(x): return x.id=="tavern")[0]
    var face: float = tavern.position[2]+tavern.collision_size[2]/2.0
    await place(Vector3(tavern.position[0],0,face+1.5))
    scene.player.scripted_direction = Vector2(0,-1)
    await wait_physics(90)
    scene.player.scripted_direction = Vector2.ZERO
    check(scene.player.position.z>face+.2 and scene.player.position.z<face+.6,"tavern_collision_blocks_entry",{"position":str(scene.player.position)})
    await place(vec(scene.layout.player_spawn))
    var manual_legs: Array[Dictionary] = []
    for index in scene.layout.route.size():
        var leg := await walk_toward(vec(scene.layout.route[index]))
        leg.index = index
        manual_legs.append(leg)
        check(leg.passed,"actual_route_leg_"+str(index),leg)
        if not leg.passed:
            break
    report.manual_route = manual_legs
    await place(vec(scene.layout.player_spawn))
    scene.start_route()
    var trajectory: Array = []
    for frame in 15500:
        trajectory.append([scene.player.position.x,scene.player.position.y,scene.player.position.z])
        if not scene.route_running:
            break
        await physics_frame
    if scene.route_running:
        scene.cancel_route()
        check(false,"automatic_route_timeout")
    check(scene.route_result.get("passed",false) and not scene.player.scripted_input,"automatic_route_completes",{"frames":scene.route_result.get("frames",0)})
    var extrema := Vector2(INF,-INF)
    for point in trajectory:
        extrema.x = minf(extrema.x,point[1])
        extrema.y = maxf(extrema.y,point[1])
    check(extrema.x<-.24 and extrema.y>.5,"automatic_route_visits_bridge_and_lower_dock",{"lowest_y":extrema.x,"highest_y":extrema.y})
    report.automatic_route = scene.route_result.duplicate(true)
    report.automatic_route.full_trajectory = trajectory
    scene.start_route()
    await wait_physics(15)
    scene.cancel_route()
    check(not scene.route_running and scene.route_result.get("cancelled",false) and not scene.player.scripted_input,"API_route_cancel")
    scene.player.scripted_input = false
    scene.player.scripted_direction = Vector2.ZERO

func cross_process() -> void:
    scene.player.set_physics_process(false)
    scene.frozen = true
    scene.settings.path = CROSS_PROCESS_SETTINGS
    if "--canal-settings-write" in OS.get_cmdline_user_args():
        scene.apply_time_preset("night")
        scene.select_variant("W")
        scene.set_lens("radius",24.5)
        scene.set_lens("fov",47.0)
        scene.select_variant("F")
        scene.set_lens("radius",32.5)
        scene.set_lens("fov",42.0)
        scene.set_parameter("far_clouds",.4)
        scene.set_parameter("dof_near",true)
        scene.set_parameter("normal_strength",1.2)
        scene.set_parameter("main_color",Color(.8,.6,.4,1))
        scene.select_lamp("streetlamp_left_back")
        scene.set_selected_lamp("energy",1.25)
        scene.set_selected_lamp("color",Color(1,.7,.4,1))
        check(scene.save_settings(),"cross_process_settings_written")
        check(scene.settings.load_settings().background_preset=="night" and scene.values.time_preset=="custom","cross_process_writer_records_actual_night_background_independently")
    else:
        check(scene.load_settings(),"cross_process_settings_loaded")
        check(same(scene.camera.fov,42.0) and scene.attributes.dof_blur_near_enabled and same(shader_value("normal_strength"),1.2) and same(scene.main_light.light_color,Color(.8,.6,.4,1)),"cross_process_real_properties_restored")
        check(scene.rig.variant_id=="F" and same(scene.rig.lens_snapshot().radius,32.5) and same(scene.rig.lens_profiles.W.radius,24.5) and same(scene.rig.lens_profiles.W.fov,47.0),"cross_process_all_lens_profiles_restored")
        check(scene.parallax.snapshot().mode=="natural" and same(scene.parallax.snapshot().far_clouds,.4) and same(scene.parallax.effective("far_clouds"),1.0),"cross_process_six_layer_requested_profile_restored")
        check(same(scene.lamp_state("streetlamp_left_back").energy,1.25) and same(scene.lamp_state("streetlamp_left_back").color,Color(1,.7,.4,1)),"cross_process_single_light_actual_override_restored")
        check(scene.values.time_preset=="custom" and background_palette_matches("night"),"cross_process_custom_night_background_applies_actual_layer_colors")
        DirAccess.remove_absolute(ProjectSettings.globalize_path(CROSS_PROCESS_SETTINGS))

func background_palette_matches(period: String) -> bool:
    if scene.farfield.profile_id!=period: return false
    for id in scene.farfield.PALETTES[period]:
        if scene.farfield.layer_materials[id].is_empty(): return false
        for material in scene.farfield.layer_materials[id]:
            if not same(material.albedo_color,Color(scene.farfield.PALETTES[period][id])): return false
    return true

func run() -> void:
    if "--canal-test" not in OS.get_cmdline_user_args() and "--ignore-user-settings" not in OS.get_cmdline_user_args():
        check(false,"refuse_everyday_preferences_without_test_flag")
        finish()
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    var close_connections := root.close_requested.get_connections().size()
    scene = load(ENTRY).instantiate()
    root.add_child(scene)
    await wait_frames(4)
    check(not scene.settings_load_attempted,"ignore_everyday_preferences")
    check(scene.player is CharacterBody3D and scene.world.get_child_count()>20,"real_scene_and_collision_world")
    check(root.close_requested.get_connections().size()==close_connections+1,"one_exit_signal_handler")
    if "--canal-settings-write" in OS.get_cmdline_user_args() or "--canal-settings-read" in OS.get_cmdline_user_args():
        await cross_process()
    else:
        await parameters()
        await camera_profiles_and_layers()
        await individual_lights()
        await animation_bindings()
        await presets_and_comparison()
        await settings_round_trip()
        await input_safety()
        await interactions()
        check(is_equal_approx(Engine.time_scale,1.0) and Engine.physics_ticks_per_second==60,"normal_speed_60Hz_physics")
        report.physics_conditions = {"time_scale":Engine.time_scale,"physics_ticks_per_second":Engine.physics_ticks_per_second}
        await physics_checks()
    scene.queue_free()
    scene = null
    await wait_frames(4)
    check(root.close_requested.get_connections().size()==close_connections,"freed_scene_disconnects_exit_handler")
    finish()

func finish() -> void:
    complete = true
    report.merge({"schema_version":1,"entry":ENTRY,"headless":DisplayServer.get_name()=="headless","passed":failures.is_empty(),"complete":complete,"checks":checks,"failures":failures,"scope":"Actual scene API, effective material/light/camera/environment properties, synthesized GUI input and physical traversal. Does not prove GPU visual quality, actual rendered effects, native window/editor delivery, screenshots, or 1080p performance."})
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(report,"  ")+"\n")
        file.close()
    print("CANAL_VALIDATION_DONE checks=",checks.size()," failures=",failures.size())
    quit(0 if failures.is_empty() else 1)

func sky_color(key: String) -> Color:
    var material: Material = scene.environment.sky.sky_material
    return material.get_shader_parameter(key) if material is ShaderMaterial else material.get(key)
