extends SceneTree
## Run with a real GPU after rebuilding/importing the P9 model.
## godot --path . --script res://tools/p9/capture_impostors.gd -- --p9-impostors
const Impostor = preload("res://scripts/reference_scene/impostor.gd")
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var lighting: Node3D

func _initialize() -> void:
    call_deferred("capture_all")

func capture_all() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("Impostor generation needs an actual GPU viewport.")
        quit(2)
        return
    viewport = SubViewport.new()
    viewport.size = Vector2i(512, 512)
    viewport.own_world_3d = true
    viewport.transparent_bg = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    stage = Node3D.new()
    viewport.add_child(stage)
    var world := preload("res://scripts/reference_scene/world_builder.gd").new()
    world.name = "CaptureWorld"
    stage.add_child(world)
    var model := world.model("palazzo", Vector3.ZERO)
    var dummy_water := MeshInstance3D.new()
    dummy_water.name = "WaterSurface"
    dummy_water.mesh = PlaneMesh.new()
    dummy_water.hide()
    dummy_water.material_override = ShaderMaterial.new()
    dummy_water.material_override.shader = preload("res://scripts/reference_scene/water.gdshader")
    world.add_child(dummy_water)
    camera = Camera3D.new()
    stage.add_child(camera)
    camera.current = true
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = Impostor.WORLD_SPAN
    camera.near = 0.1
    camera.far = 100.0
    lighting = preload("res://scripts/reference_scene/lighting.gd").new()
    stage.add_child(lighting)
    lighting.configure(camera, world, {"lamps":[], "buildings":[{"position":[0,0,0],"scale":1.0}]})
    var output := ProjectSettings.globalize_path(Impostor.FOLDER)
    if DirAccess.make_dir_recursive_absolute(output) != OK:
        push_error("Cannot create impostor output directory.")
        quit(2)
        return
    var records: Array = []
    var pitch := atan2(19.0, sqrt(16.0 * 16.0 + 31.0 * 31.0))
    for period in Impostor.PERIODS:
        lighting.apply_preset(period)
        # Preserve alpha and bake only local lighting, not scene fog or DOF.
        lighting.environment.background_mode = Environment.BG_COLOR
        lighting.environment.background_color = Color(0, 0, 0, 0)
        lighting.environment.volumetric_fog_enabled = false
        lighting.environment.glow_enabled = false
        var atlas := Image.create(3584, 512, false, Image.FORMAT_RGBA8)
        atlas.fill(Color(0, 0, 0, 0))
        for index in Impostor.ANGLES.size():
            var angle := deg_to_rad(Impostor.ANGLES[index])
            var direction := Vector3(sin(angle) * cos(pitch), sin(pitch), cos(angle) * cos(pitch))
            camera.position = direction * 28.0
            camera.look_at(Vector3.ZERO)
            var screen_center := camera.global_basis.y * ((Impostor.ANCHOR_V - 0.5) * Impostor.WORLD_SPAN)
            camera.position = screen_center + direction * 28.0
            camera.look_at(screen_center)
            for frame in range(4): await process_frame
            await RenderingServer.frame_post_draw
            var capture := viewport.get_texture().get_image()
            capture.convert(Image.FORMAT_RGBA8)
            atlas.blit_rect(capture, Rect2i(0, 0, 512, 512), Vector2i(index * 512, 0))
        var path: String = output.path_join("palazzo-" + period + ".png")
        if atlas.save_png(path) != OK:
            push_error("Could not save " + path)
            quit(2)
            return
        records.append({"period":period, "path":"assets/reference-scene/impostors/" + path.get_file(), "sha256":FileAccess.get_sha256(path)})
        print("P9_IMPOSTOR_ATLAS ", period)
    var manifest := {"schema":1, "source_model":"assets/reference-scene/models/palazzo.glb",
        "source_model_sha256":FileAccess.get_sha256("res://assets/reference-scene/models/palazzo.glb"),
        "generator":"tools/p9/capture_impostors.gd", "engine":Engine.get_version_info().string,
        "renderer":RenderingServer.get_current_rendering_method(), "angles_degrees":Impostor.ANGLES,
        "capture_projection":"orthographic", "pitch_degrees":rad_to_deg(pitch), "world_span":Impostor.WORLD_SPAN,
        "frame_size":[512,512], "atlas_size":[3584,512], "feet_anchor_uv":[0.5,Impostor.ANCHOR_V],
        "transparent":true, "lighting":"reference-scene preset; no fog, DOF or glow", "outputs":records}
    var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
    if file == null:
        push_error("Cannot save impostor manifest.")
        quit(2)
        return
    file.store_string(JSON.stringify(manifest, "  ") + "\n")
    file.close()
    print("P9_IMPOSTORS_COMPLETE 21 frames")
    quit(0)
