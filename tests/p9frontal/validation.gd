extends Node
## Geometry, physical traversal and GPU evidence are reported separately.
const Route = preload("res://tests/p9frontal/route.gd")
const IDS := ["ridge_near","ridge_mid","ridge_far","clouds_near","clouds_far"]
var scene: Node3D
var output := "res://build/p9-frontal/gpu"
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var report: Dictionary = {}
var real_gpu := false

func check(ok: bool, label: String) -> void:
    checks.append({"name":label,"passed":ok})
    if not ok: failures.append(label)
    print("FRONTAL_", "PASS " if ok else "FAIL ",label)

func wait_frames(count: int) -> void:
    for i in count: await get_tree().physics_frame

func run(value: Node3D) -> void:
    scene = value
    reparent(get_tree().root)
    var args := OS.get_cmdline_user_args()
    var recording := ""
    for arg in args:
        if arg.begins_with("--frontal-output="): output = arg.trim_prefix("--frontal-output=")
        if arg.begins_with("--frontal-record="): recording = arg.trim_prefix("--frontal-record=")
    output = ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(output)
    real_gpu = DisplayServer.get_name() != "headless"
    if real_gpu: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    await wait_frames(30)
    scene.player.scripted_input = true
    scene.tour = false
    scene.clock_frozen = true
    if not recording.is_empty():
        check(real_gpu,"record_requires_real_gpu")
        check(scene.select_variant(recording),"record_variant")
        scene.hud.container.hide()
        report.route = await Route.run(scene,output,true)
        check(report.route.passed,"recorded_physical_route")
        await finish()
        return
    check(not scene.settings_load_attempted,"ignore_user_preferences")
    state_tests()
    report.variants = {}
    for id in ["F","W","O"]:
        check(scene.select_variant(id),"select_"+id)
        scene.reset_variant()
        scene.player.position = Route.vector(scene.layout.player_spawn)
        scene.player.velocity = Vector3.ZERO
        scene.rig.select_variant(id,scene.player.position)
        var entry := {"camera":scene.rig.pose_diagnostics(),"projection":"perspective"}
        if "--frontal-no-route" not in args:
            entry.route = await Route.run(scene,output,false)
            check(entry.route.passed,"physical_route_"+id)
        else: entry.route = {"skipped":true,"reason":"--frontal-no-route; a separate physical record is required."}
        entry.p7 = p7_tests(id)
        if real_gpu:
            entry.images = await images(id)
            if "--frontal-no-fixtures" not in args:
                var directory := output.path_join(id)
                DirAccess.make_dir_recursive_absolute(directory)
                entry.fixtures = await fixtures(directory)
                check(entry.fixtures.passed,"gpu_fixtures_"+id)
            if "--frontal-benchmark" in args and "--frontal-quick" not in args:
                entry.performance = await performance(id)
        report.variants[id] = entry
    await finish()

func state_tests() -> void:
    var position: Vector3 = scene.player.position
    var collisions: Array = scene.get_node("World").find_children("*","CollisionShape3D",true,false)
    var transforms: Dictionary = {}
    for shape in collisions: transforms[shape.get_instance_id()] = shape.global_transform
    scene.lighting.apply_preset("night")
    scene.dof.near_enabled = false
    scene.dof.far_enabled = true
    scene.dof.apply()
    check(not scene.select_variant("invalid"),"reject_unknown_variant")
    for id in ["F","W","O"]:
        check(scene.select_variant(id),"switch_"+id)
        check(scene.camera.projection == Camera3D.PROJECTION_PERSPECTIVE,"true_perspective_"+id)
        check(scene.player.position == position and scene.lighting.preset_id == "night" and not scene.dof.near_enabled and scene.dof.far_enabled,"switch_preserves_player_time_dof_"+id)
        check(scene.preferences_path.ends_with("-"+id+".cfg"),"independent_preference_path_"+id)
        var unchanged := true
        for shape in collisions: unchanged = unchanged and shape.global_transform == transforms[shape.get_instance_id()]
        check(unchanged,"collision_transforms_unchanged_"+id)
        scene.parallax.change("global_strength",.4+.2*["F","W","O"].find(id))
    for id in ["F","W","O"]:
        scene.select_variant(id)
        check(is_equal_approx(scene.parallax.profile.global_strength,.4+.2*["F","W","O"].find(id)),"independent_memory_settings_"+id)
        scene.reset_variant()
        check(scene.rig.supported_pose(),"reset_supported_pose_"+id)
        var initial_fov: float = scene.camera.fov
        scene.player.scripted_input = false
        scene.player.controls_enabled = true
        for yaw in [-4.0,0.0,4.0]:
            scene.rig.set_test_yaw(yaw)
            check(absf(scene.rig.yaw_degrees) <= (4.001 if id == "O" else .001),"yaw_limit_"+id+"_"+str(yaw))
            check(is_equal_approx(scene.camera.fov,initial_fov),"fixed_fov_"+id+"_"+str(yaw))
            for action in ["move_left","move_right","move_up","move_down"]:
                Input.action_press(action)
                var direction: Vector3 = scene.player.motion_direction()
                Input.action_release(action)
                var delta: Vector2 = scene.camera.unproject_position(position+direction)-scene.camera.unproject_position(position)
                var ok: bool = delta.x < 0 if action == "move_left" else (delta.x > 0 if action == "move_right" else (delta.y < 0 if action == "move_up" else delta.y > 0))
                check(ok,"screen_controls_"+id+"_"+action+"_"+str(yaw))
        scene.player.scripted_input = true
        scene.rig.clear_test_yaw()
        for i in 300: scene.rig.update(1.0/60.0,position,false,0)
        check(scene.rig.follow_offset.distance_to(scene.rig.desired_offset(position)) < .001 and absf(scene.rig.yaw_degrees-scene.rig.desired_yaw(position)) < .001,"camera_converges_"+id)
        var pose: Dictionary = scene.rig.pose_snapshot()
        var focus: float = scene.dof.focus_depth
        var old_clock: bool = scene.clock_frozen
        check(scene.parallax_preview.start(scene),"preview_start_"+id)
        scene.parallax_preview.update(.75)
        scene.parallax_preview.stop()
        var restored: Dictionary = scene.rig.pose_snapshot()
        check(restored.transform.is_equal_approx(pose.transform) and restored.follow_offset.is_equal_approx(pose.follow_offset) and is_equal_approx(restored.yaw_degrees,pose.yaw_degrees) and is_equal_approx(restored.target_yaw_degrees,pose.target_yaw_degrees),"preview_restores_internal_pose_"+id)
        check(scene.player.position == position and scene.clock_frozen == old_clock and is_equal_approx(scene.dof.focus_depth,focus),"preview_restores_player_clock_focus_"+id)
        scene.reset_variant()
    var amounts: Array[float] = []
    for id in ["soft","standard","strong"]:
        scene.dof.select_profile(id)
        amounts.append(scene.dof.attributes.dof_blur_amount)
        check(scene.dof.profile.valid(),"P6_profile_"+id)
    check(amounts[0] < amounts[1] and amounts[1] < amounts[2],"P6_profile_amounts_increase")
    scene.dof.select_profile("standard")
    scene.dof.near_enabled = true
    scene.dof.apply()
    scene.lighting.apply_preset("dusk")
    scene.route_running = true
    check(not scene.select_variant("F"),"route_prevents_variant_switch")
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.pressed = true
    scene._input(event)
    check(scene.route_cancelled,"route_escape_requests_cancel")
    scene.route_running = false
    scene.route_cancelled = false

func images(id: String) -> Array:
    var entries: Array = []
    var saved := {"position":scene.player.global_position,"velocity":scene.player.velocity,"frozen":scene.rig.frozen,
        "hud":scene.hud.container.visible,"wind":scene.background.wind_enabled,"motion":scene.lighting.water.get_shader_parameter("motion"),
        "dof":scene.dof.enabled,"mode":scene.dof.mode,"focus":scene.dof.focus_depth,"manual":scene.dof.manual_depth,"period":scene.lighting.preset_id,"pose":scene.rig.pose_snapshot()}
    scene.rig.frozen = true
    scene.hud.container.hide()
    scene.background.wind_enabled = false
    scene.lighting.water.set_shader_parameter("motion",0.0)
    for place in ["left","center","right"]:
        scene.player.position = Route.vector(scene.layout.view_anchors[place])+Vector3.UP*.15
        scene.player.velocity = Vector3.ZERO
        await wait_frames(25)
        scene.rig.select_variant(id,scene.player.global_position)
        scene.parallax.update(0.0,true)
        var observed := Route.observation(scene)
        check(observed.actor_in_viewport,"actor_in_view_"+id+"_"+place)
        check(observed.actor_sightline_clear,"actor_sightline_"+id+"_"+place)
        if place != "center": check(observed.visible_side == place and observed.side_large_enough,"actual_building_side_"+id+"_"+place)
        for period in ["day","dusk","night"]:
            scene.lighting.apply_preset(period)
            scene.dof.mode = "manual"
            scene.dof.focus_depth = scene.dof.depth(scene.player.position+Vector3.UP)
            scene.dof.manual_depth = scene.dof.focus_depth
            for enabled in [false,true]:
                scene.dof.enabled = enabled
                scene.dof.apply()
                for frame in 8: await RenderingServer.frame_post_draw
                var name := "%s-%s-%s-dof-%s.png" % [id,period,place,"on" if enabled else "off"]
                check(await scene.capture(output.path_join(name)),"capture_"+name)
                entries.append({"file":name,"place":place,"period":period,"dof":enabled,"observation":observed,
                    "scope":"Static comparison pose, not physical route evidence. Human visual review is separate."})
    scene.player.global_position = saved.position
    scene.player.velocity = saved.velocity
    scene.rig.frozen = saved.frozen
    scene.rig.restore_pose(saved.pose)
    scene.parallax.update(0.0,true)
    scene.hud.container.visible = saved.hud
    scene.background.wind_enabled = saved.wind
    scene.lighting.water.set_shader_parameter("motion",saved.motion)
    scene.lighting.apply_preset(saved.period)
    scene.dof.enabled = saved.dof
    scene.dof.mode = saved.mode
    scene.dof.focus_depth = saved.focus
    scene.dof.manual_depth = saved.manual
    scene.dof.apply()
    return entries

func cloud_visibility() -> Dictionary:
    var result := {}
    var viewport: Rect2 = scene.get_viewport().get_visible_rect()
    for layer in [0,1]:
        var name: String = "clouds_near" if layer == 0 else "clouds_far"
        var corners_in_view := 0
        var cards_in_view := 0
        var near_depth := INF
        var far_depth := -INF
        for cloud in scene.background.clouds:
            if int(cloud.layer) != layer: continue
            var card: MeshInstance3D = cloud.node
            var bounds := card.get_aabb()
            var visible_corners := 0
            for corner in 8:
                var point: Vector3 = card.global_transform*bounds.get_endpoint(corner)
                var depth: float = scene.dof.depth(point)
                near_depth = minf(near_depth,depth)
                far_depth = maxf(far_depth,depth)
                if card.is_visible_in_tree() and depth >= scene.camera.near and depth <= scene.camera.far and viewport.has_point(scene.camera.unproject_position(point)):
                    visible_corners += 1
            corners_in_view += visible_corners
            if visible_corners > 0: cards_in_view += 1
        result[name] = {"corners_in_view":corners_in_view,"cards_in_view":cards_in_view,"min_depth_m":near_depth,"max_depth_m":far_depth,
            "camera_near":scene.camera.near,"camera_far":scene.camera.far,"passed":cards_in_view > 0}
    return result

func p7_tests(id: String) -> Dictionary:
    var period: String = scene.lighting.preset_id
    var entries := {}
    var sky_colors: Array[String] = []
    var cloud_colors: Array[String] = []
    var valid := true
    for time in ["day","dusk","night"]:
        scene.lighting.apply_preset(time)
        var sky_ok: bool = scene.background.profile_id == time and scene.lighting.environment.background_mode == Environment.BG_SKY and scene.lighting.environment.sky.sky_material == scene.background.sky_material
        var zenith: Color = scene.background.sky_material.get_shader_parameter("zenith")
        var horizon: Color = scene.background.sky_material.get_shader_parameter("horizon")
        var night: float = scene.background.sky_material.get_shader_parameter("night")
        sky_ok = sky_ok and is_equal_approx(night,1.0 if time == "night" else 0.0)
        var cloud: Color = scene.background.clouds[0].node.material_override.albedo_color
        sky_colors.append(zenith.to_html()+horizon.to_html())
        cloud_colors.append(cloud.to_html())
        var layers := cloud_visibility()
        check(sky_ok,"P7_sky_preset_"+id+"_"+time)
        for key in layers:
            check(layers[key].passed,"P7_visible_"+key+"_"+id+"_"+time)
            valid = valid and layers[key].passed
        entries[time] = {"sky_preset":sky_ok,"zenith":zenith.to_html(),"horizon":horizon.to_html(),"cloud_tint":cloud.to_html(),"layers":layers}
        valid = valid and sky_ok
    var palettes_distinct: bool = sky_colors[0] != sky_colors[1] and sky_colors[1] != sky_colors[2] and sky_colors[0] != sky_colors[2] and cloud_colors[0] != cloud_colors[1] and cloud_colors[1] != cloud_colors[2] and cloud_colors[0] != cloud_colors[2]
    check(palettes_distinct,"P7_three_distinct_sky_cloud_palettes_"+id)
    scene.lighting.apply_preset(period)
    return {"passed":valid and palettes_distinct,"presets":entries,"scope":"Each near/far cloud layer must have an actual mesh corner inside camera clip depths and viewport. Geometry and preset checks do not assert cloud pixels are unobstructed by every other object."}

func performance(id: String) -> Dictionary:
    var results := {}
    scene.player.position = Route.vector(scene.layout.player_spawn)
    scene.player.velocity = Vector3.ZERO
    scene.rig.select_variant(id,scene.player.position)
    scene.dof.enabled = true
    scene.dof.near_enabled = true
    scene.dof.far_enabled = true
    scene.dof.apply()
    scene.clock_frozen = false
    for period in ["day","dusk","night"]:
        scene.lighting.apply_preset(period)
        var result: Dictionary = await preload("res://tests/feature_benchmark.gd").measure(scene.get_viewport())
        result["rendering_video_memory_bytes"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
        results[period] = result
        check(result.duration_s >= 30 and result.gpu.nonzero_samples > 0,"measured_30_seconds_"+id+"_"+period)
        check(result.target_60fps_p95_met,"performance_budget_"+id+"_"+period)
    scene.clock_frozen = true
    return results

func fixtures(directory: String) -> Dictionary:
    scene.parallax_preview.stop()
    var processing: bool = scene.is_processing()
    var physics: bool = scene.player.is_physics_processing()
    var pose: Dictionary = scene.rig.pose_snapshot()
    var clip_planes := Vector2(scene.camera.near,scene.camera.far)
    var settings: Dictionary = scene.parallax.snapshot()
    var dof_state := {}
    for key in ["enabled","near_enabled","far_enabled","master_enabled","mode","focus_depth","manual_depth","profile"]:
        dof_state[key] = scene.dof.get(key)
    var effects: bool = scene.lighting.effects_enabled
    var wind: bool = scene.background.wind_enabled
    var environment: Environment = scene.lighting.environment
    var environment_state := {}
    for key in ["background_mode","background_color","tonemap_mode","glow_enabled","ssao_enabled","volumetric_fog_enabled"]:
        environment_state[key] = environment.get(key)
    var visibility: Array[Dictionary] = []
    for node in [scene.get_node("World"),scene.player,scene.hud.container]:
        visibility.append({"node":node,"visible":node.visible})
        node.hide()
    for node in scene.get_children():
        if node is Sprite3D:
            visibility.append({"node":node,"visible":node.visible})
            node.hide()
    var background_visible: bool = scene.background.visible
    scene.background.show()
    for node in scene.background.find_children("*","GeometryInstance3D",true,false):
        visibility.append({"node":node,"visible":node.visible})
        node.hide()
    scene.set_process(false)
    scene.player.set_physics_process(false)
    scene.lighting.set_effects(false)
    scene.background.wind_enabled = false
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color.BLACK
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    scene.rig.set_test_yaw(0.0)
    scene.rig.set_offset(Vector3.ZERO)
    scene.parallax.profile.mode = "natural"
    scene.parallax.update(0.0,true)
    var dof_result := await checkerboards(directory)
    scene.dof.enabled = false
    scene.dof.apply()
    var marker_result := await markers(directory)
    for key in settings: scene.parallax.change(key,settings[key])
    scene.rig.restore_pose(pose)
    scene.parallax.update(0.0,true)
    scene.lighting.set_effects(effects)
    for key in environment_state: environment.set(key,environment_state[key])
    for key in dof_state: scene.dof.set(key,dof_state[key])
    scene.dof.apply()
    for entry in visibility:
        if is_instance_valid(entry.node): entry.node.visible = entry.visible
    scene.background.visible = background_visible
    scene.background.wind_enabled = wind
    scene.set_process(processing)
    scene.player.set_physics_process(physics)
    var restored: bool = is_equal_approx(scene.camera.near,clip_planes.x) and is_equal_approx(scene.camera.far,clip_planes.y) and scene.camera.global_transform.is_equal_approx(pose.transform) and scene.background.visible == background_visible and scene.background.wind_enabled == wind
    for entry in visibility:
        if is_instance_valid(entry.node): restored = restored and entry.node.visible == entry.visible
    for key in environment_state: restored = restored and environment.get(key) == environment_state[key]
    check(restored,"fixtures_restore_camera_background_environment_"+scene.variant_id)
    return {"passed":dof_result.passed and marker_result.passed and restored,"restored":restored,"image_subdir":directory.get_file(),
        "dof":dof_result,"markers":marker_result,
        "scope":"Real perspective GPU checkerboard blur and representative-point centroids; independent fixtures, not scene-art acceptance. No impostor is used."}

func gpu_image(path: String, settle := 4) -> Image:
    for frame in settle: await RenderingServer.frame_post_draw
    var image: Image = get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        check(false,"nonempty_gpu_image_"+path.get_file())
        return null
    check(image.save_png(path) == OK,"save_gpu_image_"+path.get_file())
    return image

func luminance(image: Image, x: int, y: int) -> float:
    var color := image.get_pixel(x,y)
    return color.r*.2126+color.g*.7152+color.b*.0722

func edge_energy(image: Image, box: Rect2i) -> float:
    var energy := 0.0
    for y in range(box.position.y+1,box.end.y-1):
        for x in range(box.position.x+1,box.end.x-1):
            energy += absf(4*luminance(image,x,y)-luminance(image,x-1,y)-luminance(image,x+1,y)-luminance(image,x,y-1)-luminance(image,x,y+1))
    return energy / ((box.size.x-2)*(box.size.y-2))

func mean_difference(first: Image, second: Image, box: Rect2i) -> float:
    var difference := 0.0
    for y in range(box.position.y,box.end.y):
        for x in range(box.position.x,box.end.x):
            difference += absf(luminance(first,x,y)-luminance(second,x,y))
    return difference / (box.size.x*box.size.y)

func checkerboards(directory: String) -> Dictionary:
    var holder := Node3D.new()
    scene.add_child(holder)
    var texture := Image.create(128,128,false,Image.FORMAT_RGB8)
    for y in 128:
        for x in 128:
            texture.set_pixel(x,y,Color(.85,.85,.85) if ((x>>3)+(y>>3))%2 == 0 else Color(.12,.12,.12))
    var material := StandardMaterial3D.new()
    material.albedo_texture = ImageTexture.create_from_image(texture)
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    material.disable_fog = true
    var size: Vector2 = get_viewport().get_visible_rect().size
    var rois: Array[Dictionary] = []
    for index in 3:
        var depth: float = [20.0,42.0,100.0][index]
        var center := Vector2(size.x*[.25,.5,.75][index],size.y*.5)
        var mesh := QuadMesh.new()
        mesh.size = Vector2(scene.camera.project_position(center-Vector2(90,0),depth).distance_to(scene.camera.project_position(center+Vector2(90,0),depth)),
            scene.camera.project_position(center-Vector2(0,90),depth).distance_to(scene.camera.project_position(center+Vector2(0,90),depth)))
        var card := MeshInstance3D.new()
        card.mesh = mesh
        card.material_override = material
        card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        holder.add_child(card)
        card.global_transform = Transform3D(scene.camera.global_basis,scene.camera.project_position(center,depth))
        rois.append({"name":["near","focus","far"][index],"box":[int(center.x)-64,int(center.y)-64,int(center.x)+64,int(center.y)+64],"depth_m":depth})
    scene.dof.master_enabled = true
    scene.dof.enabled = true
    scene.dof.mode = "manual"
    scene.dof.manual_depth = 42.0
    scene.dof.focus_depth = 42.0
    scene.dof.select_profile("standard")
    var images := {}
    var filenames := {}
    var modes := {"off":[false,false],"near":[true,false],"far":[false,true],"both":[true,true]}
    for id in modes:
        scene.dof.near_enabled = modes[id][0]
        scene.dof.far_enabled = modes[id][1]
        scene.dof.apply()
        var name: String = "dof-fixture-"+id+".png"
        images[id] = await gpu_image(directory.path_join(name),8)
        filenames[id] = name
    for profile in ["soft","strong"]:
        scene.dof.select_profile(profile)
        var name: String = "dof-fixture-profile-"+profile+".png"
        images[profile] = await gpu_image(directory.path_join(name),8)
        filenames[profile] = name
    var valid := true
    for image in images.values(): valid = valid and image != null
    var metrics := {}
    if valid:
        for roi in rois:
            var box := Rect2i(roi.box[0],roi.box[1],roi.box[2]-roi.box[0],roi.box[3]-roi.box[1])
            var values := {}
            for id in images:
                values[id] = {"edge":edge_energy(images[id],box),"difference_from_off":mean_difference(images.off,images[id],box)}
            metrics[roi.name] = values
        var near: Dictionary = metrics.near
        var far: Dictionary = metrics.far
        var focus: Dictionary = metrics.focus
        var near_ok: bool = near.off.edge > .02 and near.near.edge < near.off.edge*.90 and near.near.difference_from_off > .008 and near.both.edge < near.off.edge*.90 and near.far.difference_from_off < .005
        var far_ok: bool = far.off.edge > .02 and far.far.edge < far.off.edge*.90 and far.far.difference_from_off > .008 and far.both.edge < far.off.edge*.90 and far.near.difference_from_off < .005
        var focus_ok := true
        for id in ["near","far","both","soft","strong"]: focus_ok = focus_ok and focus[id].difference_from_off < .005
        check(near_ok,"native_near_blur_"+scene.variant_id)
        check(far_ok,"native_far_blur_"+scene.variant_id)
        check(focus_ok,"native_focus_plane_stays_sharp_"+scene.variant_id)
        valid = near_ok and far_ok and focus_ok
    holder.free()
    return {"passed":valid,"images":filenames,"rois":rois,"metrics":metrics,
        "scope":"Native near-only/far-only/both/off at fixed 42 m focus, 20/42/100 m checkerboards each 180 screen pixels. Soft and strong profiles also captured. Pass requires measured blur, unchanged opposite end, and a sharp focus plane."}

func centroid(image: Image, expected: Vector2) -> Dictionary:
    var box := Rect2i(int(expected.x)-40,int(expected.y)-45,80,90).intersection(Rect2i(0,0,image.get_width(),image.get_height()))
    var total := 0.0
    var position := Vector2.ZERO
    var count := 0
    for y in range(box.position.y,box.end.y):
        for x in range(box.position.x,box.end.x):
            var color := image.get_pixel(x,y)
            var value := minf(color.r,minf(color.g,color.b))
            if value > .1:
                total += value
                position += Vector2(x+.5,y+.5)*value
                count += 1
    if total <= 0: return {"found":false,"count":count,"error_px":100000.0}
    position /= total
    return {"found":count >= 100,"count":count,"pixel":[position.x,position.y],"error_px":position.distance_to(expected)}

func markers(directory: String) -> Dictionary:
    var original_points := {}
    var original_depths := {}
    for id in IDS:
        original_points[id] = scene.parallax.states[id].point
        original_depths[id] = maxf(15.0,scene.dof.depth(scene.parallax.layer_point(id)))
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.disable_fog = true
    material.albedo_color = Color.WHITE
    var size: Vector2 = get_viewport().get_visible_rect().size
    var cases: Array[Dictionary] = []
    var passed := true
    var maximum_error := 0.0
    var yaws: Array = [-4.0,0.0,4.0] if scene.variant_id == "O" else [0.0]
    for yaw in yaws:
        scene.rig.set_test_yaw(float(yaw))
        scene.rig.set_offset(Vector3.ZERO)
        scene.parallax.profile.mode = "natural"
        scene.parallax.update(0.0,true)
        var nodes: Array[MeshInstance3D] = []
        var base_points := {}
        var baseline_pixels := {}
        for index in IDS.size():
            var id: String = IDS[index]
            var center := Vector2(size.x*(.12+index*.19),size.y*.5)
            var depth: float = original_depths[id]
            var point: Vector3 = scene.camera.project_position(center,depth)
            var mesh := QuadMesh.new()
            mesh.size = Vector2(scene.camera.project_position(center-Vector2(11.5,0),depth).distance_to(scene.camera.project_position(center+Vector2(11.5,0),depth)),
                scene.camera.project_position(center-Vector2(0,15.5),depth).distance_to(scene.camera.project_position(center+Vector2(0,15.5),depth)))
            var node := MeshInstance3D.new()
            node.mesh = mesh
            node.material_override = material
            node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            var layer: Node3D = scene.parallax.states[id].node
            layer.add_child(node)
            node.global_transform = Transform3D(scene.camera.global_basis,point)
            scene.parallax.states[id].point = layer.to_local(point)
            base_points[id] = point
            baseline_pixels[id] = center
            nodes.append(node)
        var base_name := "markers-yaw%d-base.png" % int(yaw)
        var base_image := await gpu_image(directory.path_join(base_name))
        var baseline := {}
        if base_image != null:
            for id in IDS: baseline[id] = centroid(base_image,baseline_pixels[id])
        for gain in [0.0,.5,1.0,1.5,2.0]:
            scene.parallax.profile.mode = "artistic"
            scene.parallax.profile.global_strength = gain
            for id in IDS: scene.parallax.profile.layer_gains[id] = 1.0
            for dx in [-2.0,2.0]:
                scene.rig.set_offset(Vector3.RIGHT*dx)
                var expected: Array[Dictionary] = []
                var actual_inverse: Transform3D = scene.camera.get_camera_transform().affine_inverse()
                var virtual_transform: Transform3D = scene.camera.get_camera_transform()
                virtual_transform.origin -= scene.rig.horizontal_follow
                var virtual_inverse := virtual_transform.affine_inverse()
                var focal: float = scene.camera.get_camera_projection().x.x*size.x*.5
                for id in IDS:
                    var point: Vector3 = base_points[id]
                    var actual: Vector3 = actual_inverse*point
                    var virtual: Vector3 = virtual_inverse*point
                    var natural_x := focal*actual.x/-actual.z
                    var virtual_x := focal*virtual.x/-virtual.z
                    var requested_x: float = virtual_x+gain*(natural_x-virtual_x)
                    var shifted: Vector3 = point+scene.camera.global_basis.x*(requested_x-natural_x)*(-actual.z/focal)
                    var pixel: Vector2 = scene.camera.unproject_position(shifted)
                    expected.append({"layer":id,"expected_pixel":[pixel.x,pixel.y],"base_pixel":[baseline_pixels[id].x,baseline_pixels[id].y],
                        "natural_x":natural_x+size.x*.5,"virtual_x":virtual_x+size.x*.5,"depth_m":-actual.z})
                scene.parallax.update(0.0,true)
                var name := "markers-yaw%d-k%d-dx%d.png" % [int(yaw),int(gain*100),int(dx)]
                var image := await gpu_image(directory.path_join(name))
                var case_ok := image != null and base_image != null
                if case_ok:
                    for item in expected:
                        var requested := Vector2(item.expected_pixel[0],item.expected_pixel[1])
                        var measured := centroid(image,requested)
                        item["measured"] = measured
                        var base: Dictionary = baseline[item.layer]
                        var valid: bool = measured.found and base.found and measured.error_px <= .8
                        if measured.found and base.found:
                            var measured_delta := Vector2(measured.pixel[0]-base.pixel[0],measured.pixel[1]-base.pixel[1])
                            var expected_delta := requested-Vector2(item.base_pixel[0],item.base_pixel[1])
                            item["delta_error_px"] = measured_delta.distance_to(expected_delta)
                            valid = valid and item.delta_error_px <= .8
                            maximum_error = maxf(maximum_error,maxf(measured.error_px,item.delta_error_px))
                        case_ok = case_ok and valid
                check(case_ok,"gpu_centroids_"+scene.variant_id+"_"+name)
                passed = passed and case_ok
                cases.append({"image":name,"base_image":base_name,"yaw":yaw,"gain":gain,"dx":dx,"passed":case_ok,"markers":expected})
        for node in nodes: node.free()
        for id in IDS: scene.parallax.states[id].point = original_points[id]
    return {"passed":passed,"cases":cases,"tolerance_px":.8,"max_error_px":maximum_error,
        "scope":"Five layer representative markers. Expected X uses a same-orientation virtual camera with horizontal follow removed; GPU centroids independently measure absolute and displacement errors. Gain zero removes translation at each representative point, not orbit or every point of a depth-varying layer."}

func finish() -> void:
    report.merge({"schema":2,"scene_id":scene.layout.scene_id,"real_gpu":real_gpu,
        "engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),
        "gpu":RenderingServer.get_video_adapter_name() if real_gpu else "none","viewport":[get_viewport().size.x,get_viewport().size.y],
        "checks":checks,"failures":failures,"passed":failures.is_empty(),"visual_review_pending":true,
        "scope":"Automated geometry, state, physics and GPU fixture results. Artistic match and transparent/visual occlusion need a separate image review.",
        "utc":Time.get_datetime_string_from_system(true)})
    var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
    if file: file.store_string(JSON.stringify(report,"  ")+"\n"); file.close()
    print("FRONTAL_DONE checks=",checks.size()," failures=",failures)
    scene.queue_free()
    for i in 5: await get_tree().process_frame
    get_tree().quit(0 if failures.is_empty() else 1)
