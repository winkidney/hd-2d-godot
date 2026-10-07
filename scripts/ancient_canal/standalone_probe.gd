extends RefCounted
## Invoked only by the actual default scene's --canal-standalone-test hook.
## Resource and binding checks work in the exported package without tools.
const ENTRY := "res://scenes/ancient_canal.tscn"
const SIZE := Vector2i(1920,1080)
const FRAME_SIZE := Vector2i(256,256)
const DIRECTIONS := ["down","up","left","right"]
const MODELS := ["bank_wall","boat","bridge","cloth_banner","cloth_stall","dock","food_stall","house","lantern","tavern","willow","wine_jar"]

static func check(report: Dictionary, passed: bool, scope: String, detail: Dictionary = {}) -> void:
    report.checks.append({"passed":passed,"scope":scope,"detail":detail})
    if not passed:
        report.failures.append(scope)
        print("CANAL_STANDALONE_FAIL ",scope," ",detail)

static func texture_at(path: String) -> Texture2D:
    if not ResourceLoader.exists(path,"Texture2D"):
        return null
    var resource = load(path)
    return resource if resource is Texture2D else null

static func sized(texture: Texture2D, size: Vector2i) -> bool:
    return texture!=null and Vector2i(texture.get_size())==size

static func resource_path(path: String) -> String:
    return path if path.begins_with("res://") else "res://"+path

static func same_region(a: Variant,b: Variant) -> bool:
    return a is Array and b is Array and a.size()==4 and b.size()==4 and a==b and int(a[2])==256 and int(a[3])==256

static func numeric_array(a: Variant, expected: Array) -> bool:
    # JSON numbers are floats; exported typed bytecode must compare values,
    # rather than requiring the same internal integer/float Array variants.
    if not a is Array or a.size()!=expected.size(): return false
    for index in range(expected.size()):
        if not (a[index] is int or a[index] is float) or not is_finite(float(a[index])) or not is_equal_approx(float(a[index]),float(expected[index])): return false
    return true

static func absolute_output(path: String, suffix: String) -> bool:
    return not path.is_empty() and path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://") and path.get_extension().to_lower()==suffix

static func mesh_count(node: Node) -> int:
    var count := 0
    if node is MeshInstance3D and node.mesh!=null and node.mesh.get_surface_count()>0:
        count += 1
    for child in node.get_children():
        count += mesh_count(child)
    return count

static func save_report(report: Dictionary, output: String, tree: SceneTree) -> void:
    report.passed = report.failures.is_empty()
    if absolute_output(output,"json"):
        var mkdir_error := DirAccess.make_dir_recursive_absolute(output.get_base_dir())
        check(report,mkdir_error==OK,"report_directory_created")
        var file := FileAccess.open(output,FileAccess.WRITE)
        if file==null:
            check(report,false,"report_file_opened",{"error":FileAccess.get_open_error()})
        else:
            report.passed = report.failures.is_empty()
            file.store_string(JSON.stringify(report,"  ")+"\n")
            file.flush()
            var error := file.get_error()
            file.close()
            if error!=OK:
                check(report,false,"report_file_written",{"error":error})
    report.passed = report.failures.is_empty()
    print("CANAL_STANDALONE_DONE passed=",report.passed," mode=",report.mode," checks=",report.checks.size())
    tree.quit(0 if report.passed else 1)

static func inspect_character(scene: Node3D,report: Dictionary) -> void:
    var player = scene.player
    var normal: Dictionary = player.normal_definition
    check(report,normal.get("frame_count",0)==108 and numeric_array(normal.get("size",[]),[256,256]) and numeric_array(normal.get("pivot",[]),[128,240]),"normal_manifest_count_size_pivot")
    var arrays_complete: bool = player.color_definitions.size()==4 and player.color_frames.size()==4 and player.color_atlases.size()==4 and player.normal_atlases.size()==4 and player.silver_atlases.size()==4 and player.animation.clips.size()==4
    check(report,arrays_complete,"four_loaded_direction_adapters")
    check(report,player.animation.DIRECTIONS==DIRECTIONS,"direction_order_matches_original")
    check(report,arrays_complete and player.sprite.texture is Texture2D and sized(player.sprite.texture,FRAME_SIZE) and player.animation_frame>=0 and player.animation_frame<27 and player.sprite.texture==player.color_frames[player.facing][player.animation_frame],"default_current_color_frame_loaded")
    check(report,player.sprite.offset==Vector2(0,112) and is_zero_approx(player.sprite.position.y) and is_equal_approx(player.sprite.pixel_size,.009),"actual_sprite_foot_pivot_and_scale")
    check(report,player.sprite.billboard==BaseMaterial3D.BILLBOARD_ENABLED and player.sprite.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST and player.sprite.alpha_cut==SpriteBase3D.ALPHA_CUT_DISCARD and player.sprite.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"billboard_pixel_sampling_cutout_and_shadow")
    if not arrays_complete:
        return
    for direction_index in range(DIRECTIONS.size()):
        var id: String = DIRECTIONS[direction_index]
        var color: Dictionary = player.color_definitions[direction_index]
        var normal_direction: Dictionary = normal.get("directions",{}).get(id,{})
        var color_entries: Array = color.get("frames",[])
        var normal_entries: Array = normal_direction.get("frames",[])
        var clip: Dictionary = player.animation.clips[direction_index]
        var count_ok: bool = color_entries.size()==27 and normal_entries.size()==27 and player.color_frames[direction_index].size()==27 and clip.ends.size()==27
        check(report,count_ok,"direction_frame_count_"+id)
        var atlas_size: Vector2i = player.color_atlases[direction_index].get_size()
        check(report,sized(player.normal_atlases[direction_index],atlas_size) and sized(player.silver_atlases[direction_index],atlas_size) and atlas_size.x>256 and atlas_size.y>256,"direction_atlas_dimensions_"+id)
        check(report,numeric_array(color.get("pivot",[]),[128,240]) and numeric_array(normal_direction.get("pivot",[]),[128,240]) and clip.pivot==Vector2(128,240) and color.get("loop",false)==normal_direction.get("loop",false),"direction_pivot_loop_"+id)
        if not count_ok:
            continue
        report.resources.directions += 1
        var duration_ms := 0
        for frame_index in range(27):
            var frame: Dictionary = color_entries[frame_index]
            var mapped: Dictionary = normal_entries[frame_index]
            var color_texture: Texture2D = player.color_frames[direction_index][frame_index]
            var normal_texture := texture_at(resource_path(str(mapped.get("path",""))))
            var mask_texture := texture_at(resource_path(str(mapped.get("mask_path",""))))
            var color_ok := sized(color_texture,FRAME_SIZE)
            var normal_ok := sized(normal_texture,FRAME_SIZE)
            var mask_ok := sized(mask_texture,FRAME_SIZE)
            report.resources.color_frames += int(color_ok)
            report.resources.normal_frames += int(normal_ok)
            report.resources.mask_frames += int(mask_ok)
            var metadata_ok: bool = same_region(frame.get("region"),mapped.get("region")) and int(frame.get("duration_ms",0))>0 and int(frame.duration_ms)==int(mapped.get("duration_ms",-1)) and frame.get("sha256","")==mapped.get("source_sha256","invalid")
            duration_ms += int(frame.get("duration_ms",0))
            metadata_ok = metadata_ok and is_equal_approx(float(clip.ends[frame_index]),float(duration_ms)/1000.0)
            check(report,color_ok and normal_ok and mask_ok and metadata_ok,"loaded_color_normal_mask_pair_"+id+"_"+str(frame_index),{"size":[256,256],"color":color_ok,"normal":normal_ok,"mask":mask_ok,"metadata":metadata_ok})
            player.direction_override = direction_index
            player.frame_override = frame_index
            player.paused = true
            player.update_animation()
            var region: Array = frame.region
            var expected := Vector4(region[0]/float(atlas_size.x),region[1]/float(atlas_size.y),region[2]/float(atlas_size.x),region[3]/float(atlas_size.y))
            var binding_ok: bool = player.animation_frame==frame_index and player.displayed_facing==direction_index and player.sprite.texture==color_texture and player.surface.get_shader_parameter("color_atlas")==player.color_atlases[direction_index] and player.surface.get_shader_parameter("normal_atlas")==player.normal_atlases[direction_index] and player.surface.get_shader_parameter("silver_atlas")==player.silver_atlases[direction_index] and player.surface.get_shader_parameter("atlas_region")==expected
            check(report,binding_ok,"actual_albedo_normal_mask_region_binding_"+id+"_"+str(frame_index))
        check(report,is_equal_approx(float(clip.duration),float(duration_ms)/1000.0) and int(normal_direction.get("duration_ms",0))==duration_ms,"direction_original_timeline_"+id)
    check(report,report.resources.color_frames==108 and report.resources.normal_frames==108 and report.resources.mask_frames==108 and report.resources.directions==4,"all_108_loaded_color_normal_mask_pairs")
    scene.restore_defaults()

static func inspect_world(scene: Node3D,report: Dictionary) -> void:
    for id in MODELS:
        var path: String = "res://assets/ancient-canal/models/"+id+".glb"
        var valid := ResourceLoader.exists(path,"PackedScene")
        var meshes := 0
        if valid:
            var resource = load(path)
            valid = resource is PackedScene
            if valid:
                var instance: Node = resource.instantiate()
                valid = instance!=null
                if valid:
                    meshes = mesh_count(instance)
                    valid = meshes>0
                    instance.free()
        report.resources.models += int(valid)
        check(report,valid,"packed_model_instantiated_"+id,{"meshes":meshes})
    check(report,scene.geometry_ready and mesh_count(scene.world)>12,"actual_scene_model_geometry_loaded")
    check(report,scene.npc_materials.size()==3 and scene.layout.npcs.size()==3,"three_runtime_npc_materials")
    for entry in scene.layout.npcs:
        var npc := scene.get_node_or_null(NodePath(str(entry.id)))
        var valid := npc is Sprite3D
        if valid:
            var mat = npc.material_override
            valid = mat is ShaderMaterial and sized(npc.texture,FRAME_SIZE) and sized(mat.get_shader_parameter("normal_atlas"),FRAME_SIZE) and sized(mat.get_shader_parameter("silver_atlas"),FRAME_SIZE) and mat.get_shader_parameter("color_atlas")==npc.texture and npc.offset==Vector2(0,112) and is_equal_approx(npc.pixel_size,.009)
        report.resources.npcs += int(valid)
        check(report,valid,"runtime_npc_color_normal_mask_"+str(entry.id))
    var font = scene.console.get_theme_default_font()
    report.resources.font_loaded = font is FontFile and font.resource_path==scene.FONT_PATH
    check(report,report.resources.font_loaded,"packaged_chinese_font_loaded")
    report.resources.ui_pages = scene.console.tabs.get_tab_count()
    check(report,report.resources.ui_pages==4 and scene.console.fields.size()==scene.parameter_spec.parameters.size()+scene.parameter_spec.lamp_parameters.size(),"four_console_pages_and_all_effective_fields")
    check(report,not scene.console.visible and not scene.dialogue.visible and not scene.exit_confirmation.visible and scene.player.controls_enabled,"console_closed_and_controls_available")

static func run(scene: Node3D) -> void:
    var tree := scene.get_tree()
    var root := tree.root
    var gpu := "--canal-test-gpu" in OS.get_cmdline_user_args()
    var output := ""
    var screenshot := ""
    var fingerprint := ""
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--canal-test-output="): output = argument.trim_prefix("--canal-test-output=")
        elif argument.begins_with("--canal-test-screenshot="): screenshot = argument.trim_prefix("--canal-test-screenshot=")
        elif argument.begins_with("--canal-fingerprint="): fingerprint = argument.trim_prefix("--canal-fingerprint=")
    var report := {"schema_version":1,"passed":false,"runtime_fingerprint":fingerprint,"scene":scene.scene_file_path,"mode":"gpu" if gpu else "headless","checks":[],"failures":[],"resources":{"color_frames":0,"normal_frames":0,"mask_frames":0,"directions":0,"models":0,"npcs":0,"frame_size":[256,256],"pivot":[128,240],"font_loaded":false,"ui_pages":0},"viewport":[SIZE.x,SIZE.y],"screenshot_saved":false,"scope":"Self-check from the package's actual default scene, without an explicit scene or external script argument. Resource loading and real frame/material bindings; optional native hardware offscreen screenshot is separate from visual approval and performance."}
    var explicit_entry := false
    for argument in OS.get_cmdline_args():
        if argument in ["--script","-s"] or argument.begins_with("--script=") or argument.ends_with(".tscn") or argument.ends_with(".gd"):
            explicit_entry = true
    check(report,scene.scene_file_path==ENTRY and tree.current_scene==scene and not explicit_entry,"actual_default_scene_startup")
    check(report,absolute_output(output,"json"),"absolute_json_output_argument")
    var pattern := RegEx.new()
    pattern.compile("^[0-9a-fA-F]{64}$")
    check(report,pattern.search(fingerprint)!=null,"frozen_runtime_fingerprint_argument")
    check(report,"--ignore-user-settings" in OS.get_cmdline_user_args() and not scene.settings_load_attempted,"everyday_settings_ignored")
    check(report,is_equal_approx(Engine.time_scale,1.0) and Engine.physics_ticks_per_second==60,"original_time_scale_and_60hz")
    var viewport: SubViewport
    if gpu:
        check(report,DisplayServer.get_name()!="headless","real_gpu_display_driver")
        root.set_flag(Window.FLAG_NO_FOCUS,true)
        if DisplayServer.get_name()!="headless":
            DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
        root.transparent_bg = false
        RenderingServer.set_default_clear_color(Color.BLACK)
        viewport = SubViewport.new()
        viewport.size = SIZE
        viewport.own_world_3d = true
        viewport.gui_embed_subwindows = true
        viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        root.add_child(viewport)
        scene.reparent(viewport)
        scene.camera.current = true
    else:
        check(report,DisplayServer.get_name()=="headless","headless_display_driver")
        root.size = SIZE
        root.content_scale_size = SIZE
    for index in range(10):
        await tree.physics_frame
    if scene.player==null or scene.player.surface==null or scene.console==null:
        check(report,false,"actual_runtime_components_present")
        save_report(report,output,tree)
        return
    scene.console.close()
    scene.dialogue.hide()
    scene.exit_confirmation.hide()
    scene.sync_input()
    inspect_character(scene,report)
    inspect_world(scene,report)
    if gpu:
        var adapter := RenderingServer.get_video_adapter_name()
        var hardware := not adapter.is_empty() and not adapter.to_lower().contains("llvmpipe") and not adapter.to_lower().contains("lavapipe") and not adapter.to_lower().contains("swiftshader")
        report.hardware_gpu = adapter
        report.renderer = RenderingServer.get_current_rendering_method()
        report.main_window_minimized = DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED
        report.no_focus = root.get_flag(Window.FLAG_NO_FOCUS)
        check(report,hardware and report.renderer=="forward_plus","hardware_forward_plus_rendering")
        check(report,report.main_window_minimized and report.no_focus and root.visible,"minimized_no_focus_present_native_window")
        check(report,absolute_output(screenshot,"png"),"absolute_png_output_argument")
        scene.frozen = true
        scene.player.set_physics_process(false)
        # Preserve the feet position settled by the real physics ticks above.
        # The spawn has a small clearance for entry; resetting its Y here would
        # photograph a suspended character instead of the actual floor contact.
        scene.player.velocity = Vector3.ZERO
        scene.camera_update(0,true)
        scene.update_focus()
        scene.overlay.hide()
        if hardware and DisplayServer.get_name()!="headless" and absolute_output(screenshot,"png"):
            for index in range(6):
                await tree.process_frame
                RenderingServer.force_draw()
            var image := viewport.get_texture().get_image()
            check(report,not image.is_empty() and image.get_size()==SIZE,"actual_1080p_viewport_readback")
            if not image.is_empty() and image.get_size()==SIZE:
                var error := DirAccess.make_dir_recursive_absolute(screenshot.get_base_dir())
                if error==OK: error = image.save_png(screenshot)
                report.screenshot_saved = error==OK and FileAccess.file_exists(screenshot)
                check(report,report.screenshot_saved,"actual_screenshot_png_saved",{"error":error})
                if report.screenshot_saved: report.screenshot_sha256 = FileAccess.get_sha256(screenshot)
    else:
        check(report,root.size==SIZE,"headless_1080p_viewport_size")
    save_report(report,output,tree)
