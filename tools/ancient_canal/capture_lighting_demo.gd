extends "res://tools/ancient_canal/capture_route.gd"
## Chaptered real-physics demonstration. The inherited recorder owns hardware
## draws, bounded PNG workers, wall timestamps and native no-focus startup.

var chapter := "warming-up"
var chapters: Array[Dictionary] = []
var demo_moves: Array[Dictionary] = []
var normal_pair_states: Array[Dictionary] = []
var caption: Label
var ending_baseline: Dictionary = {}
var demo_route_result: Dictionary = {}
var movement_start := Vector3.ZERO
var total_distance := 0.0
var previous_foot := Vector3.ZERO
var demonstration_elapsed := 0.0
var movement_failed := false
var closeup_enabled := false
var closeup_offset := Vector3(0,1.05,8.0)
var closeup_requested := false
var parameter_recipe_audit: Array[Dictionary] = []
const OCCLUSION_LAYER := 1 << 19
var visual_proxy_count := 0
var visual_triangle_count := 0
var alpha_images: Dictionary = {}
var alpha_ray_samples: Dictionary = {}
var occlusion_checks := 0
var occlusion_blocked := 0
var latest_occlusion: Dictionary = {}

func audit_parameter_recipe() -> void:
    # Check the production schema before recording. Direct assignments in the
    # fixed ending use the same validator as the ordinary console controls.
    for item in [["dof_near",true],["dof_near",false],["dof_far",true],["dof_far",false],["dof_amount",.45],["focus_protection",true],["direction","right"],["animation_frame",13],["animation_pause",true],["fixed_animation",true],["fixed_light",true],["orbit_light",false],["normals_enabled",true],["camera_variant","F"],["camera_variant","W"],["test_light_enabled",true],["test_light_x",5.0],["test_light_y",2.4],["test_light_z",1.0],["test_light_energy",2.4],["test_light_range",6.0],["test_light_color",Color(1,.88,.72)],["test_light_shadow",true]]:
        var key: String = item[0]
        var error: String = scene.settings.field_error(key,item[1])
        parameter_recipe_audit.append({"key":key,"value":item[1],"schema":scene.parameter_spec.parameters[key],"passed":error.is_empty(),"error":error})
        require(error.is_empty(),"demonstration parameter recipe rejected before recording: "+key+" "+error)

func _process(delta: float) -> bool:
    if closeup_enabled and is_instance_valid(scene): update_closeup_camera()
    return super._process(delta)

func update_closeup_camera() -> void:
    var focus: Vector3 = scene.player.global_position+Vector3.UP*1.05
    scene.camera.global_position = scene.player.global_position+closeup_offset
    scene.camera.look_at(focus,Vector3.UP)
    scene.update_focus()

func enter_closeup(warm := false) -> void:
    # Capture-only framing. Production camera profiles and their center remain
    # untouched. Warm movement stays west of the food stall and north of the
    # lantern posts; a southern camera keeps the warm light in front of cloth.
    closeup_offset = Vector3(0,1.05,8.0)
    scene.camera_locked = true
    closeup_enabled = true
    closeup_requested = true
    scene.camera.set_perspective(25.0,scene.camera.near,scene.camera.far)
    update_closeup_camera()

func leave_closeup() -> void:
    closeup_enabled = false
    scene.camera_locked = false
    scene.rig.apply_lens()
    scene.camera_update(0,true)
    scene.update_focus()

func character_projection() -> Dictionary:
    var bounds: Array = scene.player.color_definitions[scene.player.facing].frames[scene.player.animation_frame].visible_bounds
    var feet: Vector3 = scene.player.global_position
    var right: Vector3 = scene.camera.global_basis.x
    right.y = 0.0
    right = right.normalized()
    var corners: Array = []
    var minimum := Vector2(INF,INF)
    var maximum := Vector2(-INF,-INF)
    var all_forward := true
    for pixel in [Vector2(bounds[0],bounds[1]),Vector2(bounds[2],bounds[1]),Vector2(bounds[2],bounds[3]),Vector2(bounds[0],bounds[3])]:
        var position: Vector3 = feet+right*(pixel.x-128.0+scene.player.sprite.offset.x)*scene.player.sprite.pixel_size+Vector3.UP*(128.0-pixel.y+scene.player.sprite.offset.y)*scene.player.sprite.pixel_size
        var screen: Vector2 = scene.camera.unproject_position(position)
        all_forward = all_forward and not scene.camera.is_position_behind(position)
        minimum = minimum.min(screen)
        maximum = maximum.max(screen)
        corners.append([screen.x,screen.y])
    return {"source_visible_bounds":bounds,"projected_visible_corners":corners,"projected_visible_bounds":[minimum.x,minimum.y,maximum.x,maximum.y],"projected_role_height_px":maximum.y-minimum.y,"full_body_in_frame":all_forward and minimum.x>=0 and minimum.y>=0 and maximum.x<=SIZE.x and maximum.y<=SIZE.y,"foot_screen":foot_array(Vector3(scene.camera.unproject_position(feet).x,scene.camera.unproject_position(feet).y,0)),"method":"current immutable frame alpha bounds projected through actual GPU camera using the production world-UP billboard basis; no resize or crop"}

func add_visual_ray_proxies(node: Node) -> void:
    if node is MeshInstance3D and node.mesh!=null and node.is_visible_in_tree():
        var faces: PackedVector3Array = node.mesh.get_faces()
        if not faces.is_empty():
            # Exact visual triangles get a query-only collision layer. The
            # actor mask remains unchanged, so these cannot block movement.
            var body := StaticBody3D.new()
            body.collision_layer = OCCLUSION_LAYER
            body.collision_mask = 0
            body.set_meta("visual_source",str(scene.get_path_to(node)))
            scene.add_child(body)
            body.global_transform = node.global_transform
            var shape := ConcavePolygonShape3D.new()
            shape.backface_collision = true
            shape.set_faces(faces)
            var collision := CollisionShape3D.new()
            collision.shape = shape
            body.add_child(collision)
            visual_proxy_count += 1
            visual_triangle_count += int(faces.size()/3)
    # Proxies are attached to the scene, outside the authored world subtree.
    for child in node.get_children(): add_visual_ray_proxies(child)

func setup_visual_rays() -> void:
    add_visual_ray_proxies(scene.world)
    add_visual_ray_proxies(scene.farfield)
    require(visual_proxy_count>20 and visual_triangle_count>1000,"visual triangle ray proxies were not populated")

func image_for_texture(texture: Texture2D,key: String) -> Image:
    if not alpha_images.has(key):
        var pixels := texture.get_image()
        if pixels.is_compressed(): pixels.decompress()
        alpha_images[key] = pixels
    return alpha_images[key]

func character_alpha_samples() -> Array:
    var key := str(scene.player.facing)+"-"+str(scene.player.animation_frame)
    if alpha_ray_samples.has(key): return alpha_ray_samples[key]
    var texture: Texture2D = scene.player.color_frames[scene.player.facing][scene.player.animation_frame]
    var pixels := image_for_texture(texture,key)
    var bounds: Array = scene.player.color_definitions[scene.player.facing].frames[scene.player.animation_frame].visible_bounds
    var samples: Array = []
    for y in range(int(bounds[1])+3,int(bounds[3])-3,12):
        for x in range(int(bounds[0])+3,int(bounds[2])-3,12):
            if pixels.get_pixel(x,y).a>=.5: samples.append(Vector2(x,y))
    alpha_ray_samples[key] = samples
    return samples

func npc_blocks_segment(start: Vector3,end: Vector3) -> Array:
    var blocked: Array = []
    var facing: Vector3 = scene.camera.global_basis.z
    facing.y = 0
    facing = facing.normalized()
    var right := Vector3.UP.cross(facing).normalized()
    var segment := end-start
    var denominator := segment.dot(facing)
    if absf(denominator)<.00001: return blocked
    for npc in scene.get_children():
        if not npc is Sprite3D or not npc.visible: continue
        var fraction: float = (npc.global_position-start).dot(facing)/denominator
        if fraction<=.0001 or fraction>=.9999: continue
        var local: Vector3 = start+segment*fraction-npc.global_position
        var x: float = 128.0+local.dot(right)/npc.pixel_size-npc.offset.x
        var y: float = 128.0+npc.offset.y-local.y/npc.pixel_size
        if x<0 or y<0 or x>=256 or y>=256: continue
        var pixels := image_for_texture(npc.texture,"npc-"+str(npc.name))
        if pixels.get_pixel(int(x),int(y)).a>=.5: blocked.append(str(npc.name))
    return blocked

func closeup_occlusion() -> Dictionary:
    if not closeup_enabled or visual_proxy_count==0: return {}
    var samples := character_alpha_samples()
    var right: Vector3 = scene.camera.global_basis.x
    right.y = 0
    right = right.normalized()
    var origin: Vector3 = scene.camera.global_position
    var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
    var blockers: Dictionary = {}
    var blocked_samples := 0
    for pixel in samples:
        var target: Vector3 = scene.player.global_position+right*(pixel.x-128.0+scene.player.sprite.offset.x)*scene.player.sprite.pixel_size+Vector3.UP*(128.0-pixel.y+scene.player.sprite.offset.y)*scene.player.sprite.pixel_size
        var query := PhysicsRayQueryParameters3D.create(origin,target,OCCLUSION_LAYER)
        var hit := space.intersect_ray(query)
        var names := npc_blocks_segment(origin,target)
        if not hit.is_empty() and origin.distance_to(hit.position)<origin.distance_to(target)-.01:
            names.append(str(hit.collider.get_meta("visual_source","unknown")))
        if not names.is_empty():
            blocked_samples += 1
            for name in names: blockers[name] = int(blockers.get(name,0))+1
    return {"sampled_actual_alpha_points":samples.size(),"blocked_alpha_points":blocked_samples,"blocked_fraction":float(blocked_samples)/maxi(1,samples.size()),"blockers":blockers,"clear":blocked_samples==0,"scope":"actual visible MeshInstance3D triangles plus NPC immutable alpha planes, sampled through the actual capture camera; pixel review remains required"}

func _initialize() -> void:
    output = "res://build/ancient-canal/tavern-lighting-20261007/demo-render"
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--lighting-demo-output="):
            output = argument.trim_prefix("--lighting-demo-output=")
    super._initialize()

func rgba(color: Color) -> Array:
    return [color.r,color.g,color.b,color.a]

func light_snapshot() -> Dictionary:
    var result: Dictionary = {}
    for id in scene.lamp_nodes:
        var lamp: OmniLight3D = scene.lamp_nodes[id]
        result[id] = {"position":foot_array(lamp.global_position),"enabled":lamp.visible,"color":rgba(lamp.light_color),"energy":lamp.light_energy,"range":lamp.omni_range,"shadow":lamp.shadow_enabled}
    result["main"] = {"rotation":foot_array(scene.main_light.rotation),"color":rgba(scene.main_light.light_color),"energy":scene.main_light.light_energy,"shadow":scene.main_light.shadow_enabled}
    result["test"] = {"position":foot_array(scene.test_light.global_position),"enabled":scene.test_light.visible,"color":rgba(scene.test_light.light_color),"energy":scene.test_light.light_energy,"range":scene.test_light.omni_range,"shadow":scene.test_light.shadow_enabled}
    return result

func state_snapshot() -> Dictionary:
    var zones: Array[String] = []
    for entry in scene.layout.broad_lights:
        var horizontal := Vector2(scene.player.position.x-float(entry.position[0]),scene.player.position.z-float(entry.position[2])).length()
        if horizontal<scene.lamp_nodes[entry.id].omni_range: zones.append(entry.id)
    var result := {"chapter":chapter,"shot":"character-closeup" if closeup_enabled else "environment-production-camera","period":scene.values.time_preset,"camera_variant":scene.values.camera_variant,"normals_enabled":scene.player.surface.get_shader_parameter("use_normals"),"scene_normals_enabled":scene.values.normals_enabled,"normal_control_scope":"character_only_shader_override" if scene.frozen else "ordinary_scene_parameter","normal_strength":scene.values.normal_strength,"dof_near":scene.values.dof_near,"dof_far":scene.values.dof_far,"dof_amount":scene.values.dof_amount,"focus_protection":scene.values.focus_protection,"focus_distance":scene.values.focus_distance,"actual_focus_near_distance":scene.attributes.dof_blur_near_distance,"actual_focus_far_distance":scene.attributes.dof_blur_far_distance,"actual_dof_near_enabled":scene.attributes.dof_blur_near_enabled,"actual_dof_far_enabled":scene.attributes.dof_blur_far_enabled,"world_foot":foot_array(scene.player.global_position),"animation_frame":scene.player.animation_frame,"direction":scene.player.animation.DIRECTIONS[scene.player.facing],"walking":scene.player.walking,"velocity":foot_array(scene.player.get_real_velocity()),"camera_position":foot_array(scene.camera.global_position),"camera_rotation":foot_array(scene.camera.global_rotation),"camera_fov":scene.camera.fov,"camera_supported":scene.rig.supported_pose(),"camera_locked":scene.camera_locked,"animation_pause":scene.player.paused,"scene_frozen":scene.frozen,"scene_clock":scene.elapsed,"water_clock":scene.water_clock,"lighting":light_snapshot(),"ambient_energy":scene.environment.ambient_light_energy,"ambient_color":rgba(scene.environment.ambient_light_color),"broad_light_zones":zones}
    result.merge(character_projection(),true)
    result["occlusion"] = latest_occlusion
    return result

func observe_physics(delta: float) -> void:
    if not tracking or not is_instance_valid(scene): return
    var tick := Engine.get_physics_frames()
    if tick==last_observed_tick: return
    last_observed_tick = tick
    simulation_elapsed += delta
    if closeup_enabled:
        update_closeup_camera()
        latest_occlusion = closeup_occlusion()
        occlusion_checks += 1
        occlusion_blocked += int(latest_occlusion.blocked_alpha_points)
    else: latest_occlusion = {}
    var foot: Vector3 = scene.player.global_position
    total_distance += foot.distance_to(previous_foot)
    previous_foot = foot
    latest_physics = state_snapshot()
    latest_physics.merge({"physics_index":tick,"physics_elapsed_frames":tick-start_tick,"simulation_elapsed_ms":simulation_elapsed*1000.0,"physics_delta_ms":delta*1000.0,"wall_elapsed_ms":float(Time.get_ticks_usec()-start_usec)/1000.0,"route_index":scene.route_index,"route_running":scene.route_running,"phase":chapter,"scripted_input":scene.player.scripted_input,"controls_enabled":scene.player.controls_enabled},true)
    trajectory.append(latest_physics.duplicate(true))

func capture_due_frame(now: int) -> void:
    if not latest_physics.is_empty():
        # Camera follow and water update on the render process after physics.
        # These values describe the image actually being read, not a prior tick.
        latest_physics.merge(state_snapshot(),true)
    super.capture_due_frame(now)

func begin_chapter(id: String,title: String) -> void:
    chapter = id
    caption.text = title
    chapters.append({"id":id,"title":title,"first_physics_index":Engine.get_physics_frames(),"first_wall_ms":float(Time.get_ticks_usec()-start_usec)/1000.0,"state_at_start":state_snapshot()})

func hold(seconds: float) -> void:
    scene.player.scripted_direction = Vector2.ZERO
    await wait_physics(roundi(seconds*PHYSICS_HZ))

func move_to(point: Vector3,speed_scale := 1.0) -> void:
    var before: Vector3 = scene.player.global_position
    var tick := Engine.get_physics_frames()
    var wall := Time.get_ticks_usec()
    var permitted_seconds := maxf(8.0,Vector2(point.x-before.x,point.z-before.z).length()/(3.2*speed_scale)*3.0+3.0)
    scene.player.scripted_input = true
    scene.player.controls_enabled = true
    while Vector2(scene.player.position.x-point.x,scene.player.position.z-point.z).length()>.075:
        var offset := Vector2(point.x-scene.player.position.x,point.z-scene.player.position.z)
        scene.player.scripted_direction = offset.normalized()*speed_scale
        await wait_physics(1)
        if float(Time.get_ticks_usec()-wall)/1000000.0>permitted_seconds or float(Time.get_ticks_usec()-start_usec)/1000000.0>240.0:
            movement_failed = true
            require(false,"physical chapter path could not reach waypoint: "+chapter)
            break
    scene.player.scripted_direction = Vector2.ZERO
    var after: Vector3 = scene.player.global_position
    var error := Vector2(after.x-point.x,after.z-point.z).length()
    demo_moves.append({"chapter":chapter,"before":foot_array(before),"target":foot_array(point),"after":foot_array(after),"horizontal_error":error,"physical_frames":Engine.get_physics_frames()-tick,"wall_ms":float(Time.get_ticks_usec()-wall)/1000.0,"input_scale":speed_scale,"teleport_used":false,"passed":error<=.1})
    require(error<=.1,"physical movement did not reach its chapter waypoint")

func four_direction_square(prefix: String,origin: Vector2,span: float,scale: float) -> void:
    enter_closeup(prefix=="warm")
    begin_chapter(prefix+"-approach","沿街走入"+("冷色" if prefix=="cool" else "暖色")+"灯区")
    await move_to(Vector3(origin.x,0,origin.y+span))
    var corners := [Vector3(origin.x,0,origin.y),Vector3(origin.x+span,0,origin.y),Vector3(origin.x+span,0,origin.y+span),Vector3(origin.x,0,origin.y+span)]
    var ids := ["up","right","down","left"]
    var titles := ["向后行走","向右行走","向前行走","向左行走"]
    for i in range(corners.size()):
        begin_chapter(prefix+"-"+ids[i],("冷色光 · " if prefix=="cool" else "暖色光 · ")+titles[i])
        await move_to(corners[i],scale)
        await hold(.25)

func make_caption() -> void:
    var layer := CanvasLayer.new()
    viewport.add_child(layer)
    var background := ColorRect.new()
    background.position = Vector2(30,30)
    background.size = Vector2(990,64)
    background.color = Color(.025,.035,.065,.84)
    layer.add_child(background)
    caption = Label.new()
    caption.position = Vector2(50,40)
    caption.add_theme_font_override("font",load(scene.FONT_PATH))
    caption.add_theme_font_size_override("font_size",29)
    caption.add_theme_color_override("font_color",Color(.96,.93,.86))
    layer.add_child(caption)

func side_diagnostics() -> Dictionary:
    var tavern: Vector3 = scene.vec(scene.layout.models[0].position)
    var offset: Vector3 = scene.camera.global_position-tavern
    var degrees := rad_to_deg(atan2(absf(offset.x),absf(offset.z)))
    return {"camera_variant":scene.values.camera_variant,"camera_supported":scene.rig.supported_pose(),"target_model":"tavern","model_position":foot_array(tavern),"camera_position":foot_array(scene.camera.global_position),"side_view_angle_degrees":degrees,"side_view_nonzero":degrees>8.0,"scope":"real perspective view relative to the authored building axes; pixel visibility requires separate visual review"}

func ending_state() -> Dictionary:
    var data := state_snapshot()
    data.erase("chapter")
    data.erase("normals_enabled")
    # Only the character shader flag changes. NPC and world materials remain.
    return data

func record_demo() -> void:
    begin_chapter("opening","江南河街 · 黄昏与逐帧受光")
    await hold(2.0)
    await four_direction_square("cool",Vector2(-7.2,1.65),3.3,.5)
    begin_chapter("night","夜晚 · 冷色大灯与街灯")
    scene.apply_time_preset("night")
    await move_to(Vector3(-6.7,0,2.0),.7)
    await hold(4.0)
    begin_chapter("day","晴昼 · 保留同一街区与人物比例")
    scene.apply_time_preset("day")
    await hold(5.0)
    leave_closeup()
    scene.apply_time_preset("dusk")
    require(scene.set_parameter("dof_near",true),"near DOF rejected")
    require(scene.set_parameter("dof_far",false),"far DOF disable rejected")
    require(scene.set_parameter("dof_amount",.45),"DOF amount rejected")
    require(scene.set_parameter("focus_protection",true),"focus protection rejected")
    begin_chapter("near-dof","近景景深 · 前景虚化，人物焦点保护")
    await hold(6.0)
    require(scene.set_parameter("dof_near",false),"near DOF disable rejected")
    require(scene.set_parameter("dof_far",true),"far DOF rejected")
    begin_chapter("far-dof","远景景深 · 远镇与山云虚化")
    await hold(6.0)
    require(scene.set_parameter("dof_far",false),"far DOF restore rejected")
    require(scene.select_variant("W"),"supported W perspective rejected")
    begin_chapter("building-side-approach","W 透视 · 沿左岸观察酒肆侧墙")
    await move_to(Vector3(-6.7,0,-1.0))
    begin_chapter("building-side","真实三维酒肆 · 侧墙与屋顶几何")
    var sides := side_diagnostics()
    chapters[-1]["side_geometry"] = sides
    require(sides.side_view_nonzero and sides.camera_supported,"supported W view has insufficient building side angle")
    await hold(6.0)
    require(scene.select_variant("F"),"supported F perspective restore rejected")
    begin_chapter("full-route","完整自动路线 · 两岸灯区、拱桥与码头")
    scene.player.scripted_input = false
    scene.player.scripted_direction = Vector2.ZERO
    scene.start_route()
    var deadline := Time.get_ticks_usec()+100000000
    while scene.route_running and Time.get_ticks_usec()<deadline:
        await wait_physics(1)
    demo_route_result = scene.route_result.duplicate(true)
    require(not scene.route_running and demo_route_result.get("passed",false),"full automatic route failed to complete")
    scene.cancel_route()
    begin_chapter("warm-approach","跨过石拱桥 · 走向酒肆暖光")
    await move_to(Vector3(-4.5,0,-1.0))
    await move_to(Vector3(4.5,0,-1.0))
    await move_to(Vector3(6.2,0,-1.6))
    scene.apply_time_preset("night")
    await four_direction_square("warm",Vector2(5.95,-1.9),.4,.06)
    begin_chapter("normal-pair-approach","回到暖灯下 · 准备固定机位法线比较")
    await move_to(Vector3(6.2,0,-1.6),.7)
    # Existing, adjustable production test light provides a fixed front-oblique
    # key for this capture. It is reported as custom, never relabeled as night.
    for item in [["test_light_enabled",true],["test_light_x",5.0],["test_light_y",2.4],["test_light_z",1.0],["test_light_energy",2.4],["test_light_range",6.0],["test_light_color",Color(1,.88,.72)],["test_light_shadow",true]]:
        require(scene.set_parameter(item[0],item[1]),"fixed comparison key light rejected: "+str(item[0]))
    scene.player.scripted_input = false
    scene.player.scripted_direction = Vector2.ZERO
    scene.values.direction = "right"
    scene.values.animation_frame = 13
    scene.values.animation_pause = true
    scene.values.fixed_animation = true
    scene.values.fixed_light = true
    scene.values.orbit_light = false
    scene.values.dof_near = false
    scene.values.dof_far = false
    scene.values.normals_enabled = true
    scene.apply_parameters()
    await wait_physics(2)
    scene.camera_locked = true
    scene.frozen = true
    scene.player.controls_enabled = false
    scene.player.set_physics_process(false)
    ending_baseline = ending_state()
    for item in [["normal-on","法线开启 · 角色、机位、灯位固定",true],["normal-off","法线关闭 · 只切换法线受光",false],["normal-on-restored","法线恢复 · 同一姿态与照明",true]]:
        scene.player.surface.set_shader_parameter("use_normals",item[2])
        begin_chapter(item[0],item[1])
        var current := ending_state()
        require(current==ending_baseline,"normal-only comparison changed pose, lights, depth of field or clocks")
        normal_pair_states.append({"chapter":item[0],"normals_enabled":item[2],"fixed_state":current,"matches_baseline":current==ending_baseline})
        await hold(4.0)

func write_report(result: Dictionary) -> void:
    result["failures"] = failures
    var destination := FileAccess.open(output.path_join("lighting-demo-report.json"),FileAccess.WRITE)
    if destination==null:
        push_error("cannot write lighting demonstration report")
        quit(1)
        return
    destination.store_string(JSON.stringify(result,"  ")+"\n")
    destination.close()
    print("ANCIENT_LIGHTING_DEMO_DONE passed=",result.get("passed",false)," frames=",frames.size()," chapters=",chapters.size()," failures=",failures.size())
    quit(0 if result.get("passed",false) else 1)

func run_layout_probe() -> void:
    require(DisplayServer.get_name()=="headless","layout probe must be headless, not a GPU recording")
    require(DirAccess.make_dir_recursive_absolute(output)==OK,"cannot create independent layout-probe output")
    scene = load("res://scenes/ancient_canal.tscn").instantiate()
    viewport.add_child(scene)
    await wait_physics(30)
    audit_parameter_recipe()
    setup_visual_rays()
    await wait_physics(2)
    make_caption()
    start_tick = Engine.get_physics_frames()
    start_usec = Time.get_ticks_usec()
    # A static negative-control pose reproduces the first capture's blocked
    # sightline. It is not included in the subsequent real-motion trajectory.
    var spawn: Vector3 = scene.player.global_position
    scene.player.position = Vector3(7.429749,.000461,-1.669031)
    scene.player.facing = 3
    scene.player.update_animation()
    enter_closeup(true)
    closeup_offset = Vector3(-5,1.05,6.5)
    update_closeup_camera()
    var negative_control := closeup_occlusion()
    require(negative_control.blocked_alpha_points>0,"visual ray negative control failed to detect the former lamp-post occlusion")
    leave_closeup()
    scene.player.position = spawn
    scene.player.velocity = Vector3.ZERO
    await wait_physics(2)
    observer = PhysicsObserver.new()
    observer.recorder = self
    observer.process_physics_priority = 1000
    viewport.add_child(observer)
    previous_foot = scene.player.global_position
    tracking = true
    await four_direction_square("cool",Vector2(-7.2,1.65),3.3,.5)
    leave_closeup()
    begin_chapter("probe-warm-approach","headless geometry/physical route probe")
    await move_to(Vector3(-4.5,0,-1))
    await move_to(Vector3(4.5,0,-1))
    await move_to(Vector3(6.2,0,-1.6))
    await four_direction_square("warm",Vector2(5.95,-1.9),.4,.06)
    await move_to(Vector3(6.2,0,-1.6),.7)
    await hold(.5)
    tracking = false
    require(occlusion_blocked==0 and occlusion_checks>100,"new warm sightlines include an occluder")
    var result := {"passed":failures.is_empty(),"scope":"headless actual physical movement and sampled actual visible-mesh/NPC-alpha rays only, no GPU pixels or visual acceptance","negative_control":negative_control,"visual_mesh_proxies":visual_proxy_count,"visual_triangles":visual_triangle_count,"query_layer":OCCLUSION_LAYER,"player_collision_mask":scene.player.collision_mask,"occlusion_physics_checks":occlusion_checks,"blocked_alpha_points":occlusion_blocked,"movements":demo_moves,"trajectory":trajectory,"parameter_recipe_audit":parameter_recipe_audit,"failures":failures}
    var file := FileAccess.open(output.path_join("lighting-layout-probe.json"),FileAccess.WRITE)
    if file==null: quit(1); return
    file.store_string(JSON.stringify(result,"  ")+"\n")
    file.close()
    print("ANCIENT_LIGHTING_LAYOUT_PROBE passed=",result.passed," rays=",occlusion_checks," blocked=",occlusion_blocked)
    quit(0 if result.passed else 1)

func run() -> void:
    if not output_allowed:
        print("ANCIENT_LIGHTING_DEMO_REFUSED invalid evidence directory")
        quit(1)
        return
    if DirAccess.dir_exists_absolute(output):
        require(false,"demonstration output directory already exists; choose a fresh --lighting-demo-output")
        print("ANCIENT_LIGHTING_DEMO_REFUSED existing evidence directory")
        quit(1)
        return
    if "--lighting-demo-layout-probe" in OS.get_cmdline_user_args():
        await run_layout_probe()
        return
    var adapter := RenderingServer.get_video_adapter_name()
    var hardware := not adapter.is_empty() and not adapter.to_lower().contains("llvmpipe") and not adapter.to_lower().contains("lavapipe") and not adapter.to_lower().contains("swiftshader")
    var report := {"schema_version":1,"runtime_fingerprint":fingerprint,"adapter":adapter,"hardware_gpu":hardware,"renderer":RenderingServer.get_current_rendering_method(),"display_driver":DisplayServer.get_name(),"size":[SIZE.x,SIZE.y],"capture_mode":"independent 1080p SubViewport, real 60Hz physics/time_scale1, measured-wall VFR; native root black, minimized and no focus","target_fps":float(PHYSICS_HZ)/SAMPLE_EVERY_PHYSICS_FRAMES,"time_scale":Engine.time_scale,"physics_ticks_per_second":Engine.physics_ticks_per_second,"no_fixed_fps":no_fixed_fps,"disabled_render_loop":disabled_render_loop,"frame_pattern":evidence_prefix+"/frames/frame-%06d.png","passed":false}
    report.merge(launch_state,true)
    require(DisplayServer.get_name()!="headless","lighting demonstration requires actual GPU; headless is not visual evidence")
    require(hardware and report.renderer=="forward_plus","lighting demonstration requires hardware Forward+")
    if DisplayServer.get_name()!="headless":
        root.set_flag(Window.FLAG_NO_FOCUS,true)
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    for startup_frame in range(5): await process_frame
    require(DirAccess.make_dir_recursive_absolute(output)==OK,"cannot create lighting demo output directory")
    report["main_window_minimized"] = DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED if DisplayServer.get_name()!="headless" else false
    report["no_focus_flag"] = root.get_flag(Window.FLAG_NO_FOCUS)
    report["vsync_disabled"] = DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED if DisplayServer.get_name()!="headless" else false
    require(report.main_window_minimized and report.no_focus_flag and root.visible and report.vsync_disabled,"native minimized/no-focus/vsync contract failed")
    if not failures.is_empty():
        write_report(report)
        return
    require(DirAccess.make_dir_recursive_absolute(output.path_join("frames"))==OK,"cannot create lighting demo frame directory")
    scene = load("res://scenes/ancient_canal.tscn").instantiate()
    viewport.add_child(scene)
    await wait_physics(30)
    require(not scene.settings_load_attempted,"demonstration loaded everyday preferences")
    require(scene.player.position.distance_to(scene.vec(scene.layout.player_spawn))<.25,"demonstration did not begin at actual spawn")
    scene.console.close()
    scene.dialogue.hide()
    scene.exit_confirmation.hide()
    scene.overlay.hide()
    scene.apply_time_preset("dusk")
    audit_parameter_recipe()
    setup_visual_rays()
    await wait_physics(2)
    report["parameter_recipe_audit"] = parameter_recipe_audit
    if not failures.is_empty():
        write_report(report)
        return
    make_caption()
    observer = PhysicsObserver.new()
    observer.recorder = self
    observer.process_physics_priority = 1000
    viewport.add_child(observer)
    start_writers()
    start_tick = Engine.get_physics_frames()
    start_usec = Time.get_ticks_usec()
    next_sample_tick = start_tick+SAMPLE_EVERY_PHYSICS_FRAMES
    movement_start = scene.player.global_position
    previous_foot = movement_start
    tracking = true
    recording = true
    await record_demo()
    tracking = false
    recording = false
    var total_wall_ms := float(Time.get_ticks_usec()-start_usec)/1000.0
    stop_writers()
    var output_valid := writer_results.size()==frames.size()
    var coverage: Dictionary = {}
    var periods: Dictionary = {}
    var walking_directions: Dictionary = {}
    var zones: Dictionary = {}
    var closeup_heights: Array[float] = []
    var framing_failures := 0
    var closeup_chapters: Dictionary = {}
    for result in writer_results:
        var entry: Dictionary = frames[int(result.sequence_index)]
        entry.merge(result,true)
        var path := output.path_join("frames").path_join(str(entry.file).get_file())
        var valid: bool = result.save_error==OK and FileAccess.file_exists(path)
        var sha := FileAccess.get_sha256(path) if valid else ""
        var png := FileAccess.open(path,FileAccess.READ) if valid else null
        if png!=null:
            var header := png.get_buffer(24)
            valid = header.size()==24 and header.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10])
            if valid:
                var width := int(header[16])*16777216+int(header[17])*65536+int(header[18])*256+int(header[19])
                var height := int(header[20])*16777216+int(header[21])*65536+int(header[22])*256+int(header[23])
                valid = width==SIZE.x and height==SIZE.y
            png.close()
        else: valid = false
        entry["sha256"] = sha
        entry["png_valid_1080p"] = valid and sha.length()==64
        output_valid = output_valid and entry.png_valid_1080p
        coverage[entry.chapter] = int(coverage.get(entry.chapter,0))+1
        periods[entry.period] = int(periods.get(entry.period,0))+1
        if entry.walking:
            walking_directions[entry.direction] = int(walking_directions.get(entry.direction,0))+1
        for id in entry.broad_light_zones: zones[id] = int(zones.get(id,0))+1
        if not entry.full_body_in_frame: framing_failures += 1
        if entry.shot=="character-closeup":
            closeup_heights.append(float(entry.projected_role_height_px))
            closeup_chapters[entry.chapter] = int(closeup_chapters.get(entry.chapter,0))+1
            require(float(entry.projected_role_height_px)>=480.0,"character close-up is below 480px visible height")
            require(not entry.occlusion.is_empty() and entry.occlusion.clear,"actual close-up ray sampling found a foreground mesh or NPC blocker: "+str(entry.occlusion.get("blockers",{})))
    require(output_valid and not frames.is_empty(),"demonstration PNG save, dimensions or checksums invalid")
    for entry in chapters: require(int(coverage.get(entry.id,0))>0,"chapter has no captured GPU image: "+entry.id)
    for id in ["up","down","left","right"]: require(int(walking_directions.get(id,0))>=10,"actual walking direction lacks images: "+id)
    for id in ["day","dusk","night"]: require(int(periods.get(id,0))>0,"actual lighting period lacks images: "+id)
    for entry in scene.layout.broad_lights: require(int(zones.get(entry.id,0))>=10,"wide light zone lacks rendered player frames")
    require(total_distance>40.0 and not movement_failed,"demonstration lacks real route movement")
    require(framing_failures==0,"a chapter cropped the character alpha silhouette")
    for id in ["cool-up","cool-right","cool-down","cool-left","warm-up","warm-right","warm-down","warm-left","day","night","normal-on","normal-off","normal-on-restored"]:
        require(int(closeup_chapters.get(id,0))>0,"required chapter lacks actual GPU close-up: "+id)
    require(normal_pair_states.size()==3 and normal_pair_states[0].matches_baseline and normal_pair_states[1].matches_baseline and normal_pair_states[2].matches_baseline,"normal-only fixed-state triple incomplete")
    var sampling_complete := render_gap_skips==0 and backpressure_skips==0 and readback_failures==0 and frames.size()==attempted_samples
    var max_physics_gap := 0
    var previous_tick := start_tick
    for entry in frames:
        max_physics_gap = maxi(max_physics_gap,int(entry.physics_index)-previous_tick)
        previous_tick = int(entry.physics_index)
    report.merge({"chapters":chapters,"chapter_frame_counts":coverage,"period_frame_counts":periods,"walking_direction_frame_counts":walking_directions,"broad_light_zone_frame_counts":zones,"physical_movement_metres":total_distance,"movements":demo_moves,"automatic_route_result":demo_route_result,"normal_only_comparison":normal_pair_states,"frames":frames,"trajectory":trajectory,"wall_duration_ms":total_wall_ms,"wall_duration_s":total_wall_ms/1000.0,"simulation_duration_ms":simulation_elapsed*1000.0,"physics_elapsed_frames":Engine.get_physics_frames()-start_tick,"preferences_ignored":not scene.settings_load_attempted,"render_frame_wall_intervals_ms":process_intervals_ms,"timing_policy":"observed monotonic wall timestamps, preserve sample gaps as VFR; capture is not a benchmark","sampling":{"complete":sampling_complete,"every_physics_frames":SAMPLE_EVERY_PHYSICS_FRAMES,"attempted_slots":attempted_samples,"captured_frames":frames.size(),"max_physics_gap":max_physics_gap,"render_gap_skipped_slots":render_gap_skips,"queue_backpressure_events":backpressure_events,"queue_backpressure_skipped_slots":backpressure_skips,"readback_failures":readback_failures,"status":"complete intended samples" if sampling_complete else "sampling gaps retained in measured VFR"},"writer":{"threads_started":writer_threads.size(),"queue_capacity":QUEUE_LIMIT,"queue_high_water":queue_high_water,"completed_jobs":writer_results.size(),"output_valid":output_valid,"joined_before_checksums":true}},true)
    closeup_heights.sort()
    report["framing"] = {"actual_gpu_camera_closeup":closeup_requested,"target_minimum_visible_height_px":480.0,"minimum_visible_height_px":closeup_heights[0] if not closeup_heights.is_empty() else 0,"maximum_visible_height_px":closeup_heights[-1] if not closeup_heights.is_empty() else 0,"closeup_frame_count":closeup_heights.size(),"closeup_chapter_frame_counts":closeup_chapters,"character_cropped_frames":framing_failures,"full_body_required_in_all_chapters":true,"source_frames_resized":false,"capture_only_lens":true,"production_profiles_changed":false,"scope":"actual immutable-alpha geometry projected by the capture camera; actual pixel occlusion requires separate visual review"}
    report["occlusion_diagnostics"] = {"visual_mesh_proxies":visual_proxy_count,"visual_triangles":visual_triangle_count,"query_only_layer":OCCLUSION_LAYER,"player_collision_mask":scene.player.collision_mask,"closeup_physics_checks":occlusion_checks,"blocked_alpha_points":occlusion_blocked,"models_hidden":false,"scope":"production visible triangle proxies and NPC immutable-alpha ray sampling; proxies are not drawn and cannot affect actor movement; actual GPU pixel review remains necessary"}
    report.main_window_minimized = DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED
    report.no_focus_flag = root.get_flag(Window.FLAG_NO_FOCUS)
    require(report.main_window_minimized and report.no_focus_flag,"window minimize/no-focus state changed")
    require(Engine.time_scale==1.0 and Engine.physics_ticks_per_second==PHYSICS_HZ,"real-time physics contract changed")
    report["passed_scope"] = "actual movement and automatic route; four walking directions inside both broad-light zones; day/dusk/night; separate near/far DOF; supported geometric building-side angle; fixed-state normal ON/OFF/ON; valid native1080 GPU PNG and honest sampling gaps. Visual quality and video encoding require separate review."
    report.passed = failures.is_empty() and output_valid
    write_report(report)
