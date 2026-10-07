extends SceneTree
## Capture actual 1080p character material draws without desktop focus.
## Force-drawn PNG sequences are visual evidence, not a performance benchmark.
var viewport: SubViewport
var output := "res://build/ancient-canal/character-normal-render"
var failures: Array[String] = []
var report: Dictionary = {}
var scene
var normal_manifest: Dictionary
var runtime_fingerprint := ""

func _initialize() -> void:
    root.set_flag(Window.FLAG_NO_FOCUS,true)
    root.hide()
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--canal-normal-capture-dir="): output=arg.trim_prefix("--canal-normal-capture-dir=")
        if arg.begins_with("--canal-fingerprint="): runtime_fingerprint=arg.trim_prefix("--canal-fingerprint=")
    output=ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(output)
    viewport=SubViewport.new()
    viewport.size=Vector2i(1920,1080)
    viewport.own_world_3d=true
    viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    call_deferred("run")

func _process(_delta: float) -> bool:
    RenderingServer.force_draw()
    return false

func require(condition: bool,description: String) -> void:
    if not condition:
        failures.append(description)
        push_error(description)

func rendered() -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    var image:=viewport.get_texture().get_image()
    require(not image.is_empty() and image.get_size()==viewport.size,"empty/non-1080p GPU frame")
    return image

func save(image: Image,path: String) -> void:
    require(image.save_png(output.path_join(path))==OK,"cannot save "+path)

func standing_basis() -> Basis:
    var back: Vector3=scene.camera.global_basis.z
    var front:=Vector3(back.x,0,back.z)
    if front.length_squared()<.000001:
        var right: Vector3=scene.camera.global_basis.x
        right.y=0
        if right.length_squared()<.000001: right=Vector3.RIGHT
        front=right.normalized().cross(Vector3.UP)
    front=front.normalized()
    return Basis(Vector3.UP.cross(front).normalized(),Vector3.UP,front)

func actor_area() -> Rect2:
    var sprite: Sprite3D=scene.player.sprite
    var basis:=standing_basis()
    var first:=Vector2(INF,INF)
    var last:=Vector2(-INF,-INF)
    # Perspective makes the top and bottom widths differ. Project every real
    # mesh vertex instead of assuming a screen-parallel camera billboard.
    for point in sprite.generate_triangle_mesh().get_faces():
        var screen: Vector2=scene.camera.unproject_position(sprite.global_position+basis*point)
        first=first.min(screen)
        last=last.max(screen)
    return Rect2(first,last-first).intersection(Rect2(Vector2.ZERO,Vector2(viewport.size)))

func difference(a: Image,b: Image,area: Rect2) -> Dictionary:
    var bounds:=area.intersection(Rect2(Vector2.ZERO,Vector2(viewport.size)))
    var changed:=0
    var sum:=0.0
    var count:=0
    for y in range(ceili(bounds.position.y),floori(bounds.end.y)):
        for x in range(ceili(bounds.position.x),floori(bounds.end.x)):
            var ca:=a.get_pixel(x,y)
            var cb:=b.get_pixel(x,y)
            var delta: float=(absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b))/3.0
            if delta>.02: changed+=1
            sum+=delta
            count+=1
    return {"changed_pixels":changed,"sample_pixels":count,"mean_absolute_RGB":sum/maxi(1,count)}

func validate_binding(direction: int,index: int) -> Dictionary:
    var actor=scene.player
    var name: String=actor.animation.DIRECTIONS[direction]
    var expected: Dictionary=normal_manifest.directions[name].frames[index]
    var region: Array=expected.region
    var size: Vector2=actor.color_atlases[direction].get_size()
    var wanted:=Vector4(region[0]/size.x,region[1]/size.y,region[2]/size.x,region[3]/size.y)
    var actual: Vector4=actor.surface.get_shader_parameter("atlas_region")
    var color_texture: Texture2D=actor.surface.get_shader_parameter("color_atlas")
    var normal_texture: Texture2D=actor.surface.get_shader_parameter("normal_atlas")
    var silver_texture: Texture2D=actor.surface.get_shader_parameter("silver_atlas")
    require(actor.animation_frame==index and actor.displayed_facing==direction,"frame/direction mismatch "+name+" "+str(index))
    require(actual.is_equal_approx(wanted),"atlas region mismatch "+name+" "+str(index))
    require(color_texture==actor.color_atlases[direction],"color atlas binding mismatch")
    require(normal_texture==actor.normal_atlases[direction],"normal atlas binding mismatch")
    require(silver_texture==actor.silver_atlases[direction],"silver atlas binding mismatch")
    require(color_texture.resource_path=="res://"+normal_manifest.directions[name].source_atlas,"color source resource changed")
    require(normal_texture.resource_path=="res://"+normal_manifest.directions[name].atlas,"normal source resource mismatch")
    require(silver_texture.resource_path=="res://"+normal_manifest.directions[name].mask_atlas,"silver source resource mismatch")
    require(actor.sprite.texture.resource_path=="res://"+expected.source_path,"sprite mesh source frame mismatch")
    return {"direction":name,"frame":index,"source_index":expected.source_index,"duration_ms":expected.duration_ms,"region":region,"uniform":[actual.x,actual.y,actual.z,actual.w],"color":color_texture.resource_path.trim_prefix("res://"),"normal":normal_texture.resource_path.trim_prefix("res://"),"silver":silver_texture.resource_path.trim_prefix("res://"),"sprite_color":actor.sprite.texture.resource_path.trim_prefix("res://")}

func freeze_scene() -> void:
    scene.frozen=true
    scene.camera_locked=true
    scene.player.controls_enabled=false
    scene.player.set_physics_process(false)
    scene.set_physics_process(false)
    scene.overlay.hide()
    scene.values.dof_near=false
    scene.values.dof_far=false
    scene.values.camera_follow=false
    scene.values.orbit_light=false
    scene.values.animation_pause=true
    scene.values.fixed_animation=true
    scene.values.fixed_light=true
    scene.values.normals_enabled=true
    scene.values.normal_strength=.8
    scene.values.normal_flip_y=false
    scene.values.shading_mode="native"
    scene.values.normal_debug=false
    scene.values.fog=0
    scene.values.bloom=0
    scene.values.water_flow=0
    scene.apply_parameters()
    # Evidence close-up. Real geometry, native material and scene shadowing stay.
    var target: Vector3=scene.player.global_position+Vector3.UP*1.05
    var forward: Vector3=scene.camera.global_basis.z
    scene.camera.global_position=target+forward*4.6
    scene.camera.look_at(target)
    scene.camera.fov=35
    scene.update_focus()

func set_pose(direction: int,index: int) -> void:
    scene.player.direction_override=direction
    scene.player.facing=direction
    scene.player.paused=true
    scene.player.frame_override=index
    scene.player.update_animation()

func sweep_position(phase: float) -> Vector3:
    var center: Vector3=scene.player.global_position+Vector3.UP*1.05
    # Horizontal camera right/front and world UP match the upright shader.
    # A front offset lights the visible hemisphere throughout all four tests.
    var basis:=standing_basis()
    return center+basis.x*cos(phase)*2.8+basis.y*sin(phase)*1.5+basis.z*2.2

func run() -> void:
    # Engine startup can replace flags set during _initialize(). Reapply to
    # both the Window object and the actual native window before every draw.
    root.set_flag(Window.FLAG_NO_FOCUS,true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    # Native WM acknowledgement arrives after the minimize request.
    for startup in 5: await process_frame
    var adapter:=RenderingServer.get_video_adapter_name()
    report={"runtime_fingerprint":runtime_fingerprint,"renderer":RenderingServer.get_current_rendering_method(),"adapter":adapter,"hardware_gpu":not adapter.is_empty() and not adapter.to_lower().contains("llvmpipe") and not adapter.to_lower().contains("lavapipe"),"size":[1920,1080],"capture_mode":"minimized no-focus window, independent offscreen SubViewport","main_window_minimized":DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED,"no_focus_flag":root.get_flag(Window.FLAG_NO_FOCUS),"preferences_ignored":false,"scope":"all original 108 source frames, 3 complete cycles in each direction, native color and gray material sweep; pose is fixed by one shared frame index; performance measured separately","clips":[],"bindings":[],"normal_comparisons":[],"light_samples":[]}
    require(DisplayServer.get_name()!="headless","normal capture requires real GPU graphics")
    require(report.hardware_gpu and report.renderer=="forward_plus","capture is not hardware Forward+")
    require(report.main_window_minimized and report.no_focus_flag,"native window focus/minimize contract violated")
    normal_manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/ancient-canal/character-normals/v1/manifest.json"))
    scene=load("res://scenes/ancient_canal.tscn").instantiate()
    viewport.add_child(scene)
    for i in range(30):await physics_frame
    freeze_scene()
    report.preferences_ignored=not scene.settings_load_attempted
    require(report.preferences_ignored,"capture loaded everyday user settings; launch with --ignore-user-settings")
    report["foot_anchor_world"]=[scene.player.position.x,scene.player.position.y,scene.player.position.z]
    var anchor: Vector2=scene.camera.unproject_position(scene.player.global_position)
    report["foot_anchor_screen"]=[anchor.x,anchor.y]
    report["projected_sprite_rect"]=[actor_area().position.x,actor_area().position.y,actor_area().size.x,actor_area().size.y]
    var upright:=standing_basis()
    report["billboard_basis"]={"right":[upright.x.x,upright.x.y,upright.x.z],"up":[upright.y.x,upright.y.y,upright.y.z],"front":[upright.z.x,upright.z.y,upright.z.z],"convention":"horizontal MAIN camera right/front, world UP; same visible/normal/shadow basis","rect_method":"all actual Sprite3D triangle vertices projected with upright basis"}
    var total:=0
    for mode in ["color","clay-sweep"]:
        scene.values.clay=mode=="clay-sweep"
        if mode=="clay-sweep":
            scene.values.main_energy=0
            scene.values.lantern_energy=0
            scene.values.lantern_enabled=false
            scene.values.streetlamp_energy=0
            scene.values.streetlamp_enabled=false
            scene.values.broad_energy=0
            scene.values.broad_enabled=false
            scene.values.ambient=.06
            scene.values.ambient_color=Color.WHITE
            scene.values.test_light_enabled=true
            scene.values.test_light_color=Color.WHITE
            scene.values.test_light_energy=3.5
            scene.values.test_light_range=9.0
            scene.values.silver_specular=.75
        scene.apply_parameters()
        if mode=="clay-sweep":
            # Shape inspection isolates vector-normal lighting from geometry
            # obstruction. Color evidence retains real scene cast shadows.
            scene.test_light.shadow_enabled=false
            # Explicitly isolate the actual nodes too: no per-lamp override or
            # isolate selection may accidentally add a second gray-sweep light.
            for lamp in scene.lamp_nodes.values():
                lamp.visible=false
                lamp.light_energy=0
            var environment_lamps: Dictionary={}
            var disabled_environment_count: int=0
            for id in scene.lamp_nodes:
                var lamp: OmniLight3D=scene.lamp_nodes[id]
                var disabled: bool=not lamp.visible and is_zero_approx(lamp.light_energy)
                if disabled: disabled_environment_count+=1
                environment_lamps[id]={"group":scene.lamp_metadata[id].group,"enabled":lamp.visible,"energy":lamp.light_energy,"disabled":disabled}
            var actual_environment: Environment=scene.environment
            var actual_test: OmniLight3D=scene.test_light
            var only_test_and_ambient: bool=disabled_environment_count==scene.lamp_nodes.size() and is_zero_approx(scene.main_light.light_energy) and actual_test.visible and actual_test.light_energy>0 and actual_test.light_color.is_equal_approx(Color.WHITE) and not actual_test.shadow_enabled and is_equal_approx(actual_environment.ambient_light_energy,.06) and actual_environment.ambient_light_color.is_equal_approx(Color.WHITE)
            require(only_test_and_ambient,"gray sweep did not isolate all actual environment lights from the white test lamp and .06 white ambient")
            report["clay_sweep_lighting"]={"test_light_cast_shadows":actual_test.shadow_enabled,"intent":"form inspection; only the test lamp and .06 white ambient illuminate the gray actor, test lamp cast-shadow is disabled, color clips retain all scene geometric lighting/shadows","basis":"horizontal camera right/front with world UP","right":[upright.x.x,upright.x.y,upright.x.z],"up":[0,1,0],"front":[upright.z.x,upright.z.y,upright.z.z],"horizontal_radius":2.8,"vertical_radius":1.5,"front_offset":2.2,"scene_main_cast_shadows":scene.main_light.shadow_enabled,"scene_main_energy":scene.main_light.light_energy,"lantern_count_disabled":scene.lanterns.size(),"streetlamp_count_disabled":scene.streetlamps.size(),"broad_count_disabled":scene.broad_lights.size(),"environment_catalog_count":scene.lamp_nodes.size(),"actual_environment_lights_disabled":disabled_environment_count,"environment_lights":environment_lamps,"only_test_lamp_and_white_ambient":only_test_and_ambient,"test_light_enabled":actual_test.visible,"test_light_energy":actual_test.light_energy,"test_light_color":[actual_test.light_color.r,actual_test.light_color.g,actual_test.light_color.b,actual_test.light_color.a],"ambient_energy":actual_environment.ambient_light_energy,"ambient_color":[actual_environment.ambient_light_color.r,actual_environment.ambient_light_color.g,actual_environment.ambient_light_color.b,actual_environment.ambient_light_color.a]}
        for direction in range(4):
            var name: String=scene.player.animation.DIRECTIONS[direction]
            var folder: String=mode+"/"+name
            DirAccess.make_dir_recursive_absolute(output.path_join(folder))
            var seen: Array[int]=[]
            var timed_frames: Array[Dictionary]=[]
            var loop_difference: Dictionary={}
            var first_cycle: Image
            var last_cycle: Image
            for cycle in range(3):
                for index in range(27):
                    set_pose(direction,index)
                    if mode=="clay-sweep":
                        var phase:=TAU*(float(cycle)+float(index)/27.0)/3.0
                        scene.test_light.position=sweep_position(phase)
                        if index in [0,6,13,20,26]:
                            report.light_samples.append({"direction":name,"cycle":cycle,"frame":index,"phase":phase,"position":[scene.test_light.position.x,scene.test_light.position.y,scene.test_light.position.z]})
                    var image:=await rendered()
                    var filename: String=folder+"/%05d.png"%(cycle*27+index)
                    save(image,filename)
                    var producer_sha256:=FileAccess.get_sha256(output.path_join(filename))
                    require(producer_sha256.length()==64,"cannot hash captured PNG "+filename)
                    if mode=="color" and cycle==0:
                        report.bindings.append(validate_binding(direction,index))
                        seen.append(index)
                    if cycle==0 and index==0:first_cycle=image
                    if cycle==2 and index==26:last_cycle=image
                    if cycle==0 and index in [0,6,13,20,26]:save(image,mode+"-"+name+"-key-%02d.png"%index)
                    timed_frames.append({"file":filename,"sha256":producer_sha256,"frame":index,"cycle":cycle,"duration_ms":normal_manifest.directions[name].frames[index].duration_ms})
                    total+=1
            if mode=="color":loop_difference=difference(first_cycle,last_cycle,actor_area())
            report.clips.append({"mode":mode,"direction":name,"frames_per_loop":27,"cycles_rendered":3,"recorded_frames":81,"duration_ms_per_loop":normal_manifest.directions[name].duration_ms,"seen_original_indices":seen,"first_last_pose_difference":loop_difference,"frames":timed_frames})
            print("ANCIENT_NORMAL_CLIP ",mode," ",name," 81 actual GPU frames")
    # Same pose, same camera and same real lamp for on/off evidence. Limit the
    # numerical comparison to the actor rectangle, rather than changing scenery.
    for direction in range(4):
        var name: String=scene.player.animation.DIRECTIONS[direction]
        set_pose(direction,int(normal_manifest.directions[name].idle_frame))
        scene.test_light.position=sweep_position(PI*.75)
        scene.player.surface.set_shader_parameter("use_normals",true)
        var enabled:=await rendered()
        save(enabled,name+"-normal-enabled.png")
        scene.player.surface.set_shader_parameter("use_normals",false)
        var disabled:=await rendered()
        save(disabled,name+"-normal-disabled.png")
        var comparison:=difference(enabled,disabled,actor_area())
        require(comparison.changed_pixels>500 and comparison.mean_absolute_RGB>.006,"normal toggle produces insufficient actual pixel difference "+name)
        comparison["direction"]=name
        comparison["frame"]=normal_manifest.directions[name].idle_frame
        report.normal_comparisons.append(comparison)
        scene.player.surface.set_shader_parameter("use_normals",true)
    report["recorded_frames"]=total
    report["main_window_minimized"]=DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED
    report["failures"]=failures
    report["passed"]=failures.is_empty() and total==648 and report.bindings.size()==108 and report.normal_comparisons.size()==4 and report.preferences_ignored
    var file:=FileAccess.open(output.path_join("normal-render-report.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  ")+"\n")
    scene.queue_free()
    for i in range(4):await process_frame
    print("ANCIENT_NORMAL_RENDER_DONE hardware=",report.hardware_gpu," passed=",report.passed," frames=",total)
    quit(0 if report.passed else 1)
