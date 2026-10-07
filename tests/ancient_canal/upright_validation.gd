extends SceneTree
## Read-only asset/mesh checks. --upright-gpu additionally executes the exact
## production GLSL basis helper on hardware; headless results never claim it.
## GPU runs must be scheduled separately from other capture/benchmark jobs.
const SURFACE := "res://shaders/ancient_canal/sprite_surface.gdshaderinc"
const BASELINE := "res://art_source/ancient-canal/character-reuse.json"
const NORMALS := "res://assets/ancient-canal/character-normals/v1/manifest.json"
var output := "res://build/ancient-canal/upright-validation"
var gpu := false
var runtime_fingerprint := ""
var failures: Array[String] = []
var checks: Array[Dictionary] = []
var report: Dictionary = {}
var scene: Node3D
var viewport: SubViewport

func _initialize() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg == "--upright-gpu": gpu = true
        if arg.begins_with("--upright-output="): output = arg.trim_prefix("--upright-output=")
        if arg.begins_with("--canal-fingerprint="): runtime_fingerprint=arg.trim_prefix("--canal-fingerprint=")
    if gpu:
        root.set_flag(Window.FLAG_NO_FOCUS,true)
        root.hide()
    call_deferred("run")

func _process(_delta: float) -> bool:
    if gpu: RenderingServer.force_draw()
    return false

func check(ok: bool,label: String,detail: Dictionary = {}) -> void:
    checks.append({"name":label,"passed":ok,"detail":detail})
    if not ok:
        failures.append(label)
        push_error(label)

func vector(value: Vector3) -> Array:
    return [value.x,value.y,value.z]

func json(path: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string(path))

func sha(path: String,expected: String) -> void:
    var actual:=FileAccess.get_sha256(path)
    check(actual==expected,"immutable SHA "+path,{"expected":expected,"actual":actual})

func standing_basis(back: Vector3,right_hint: Vector3) -> Basis:
    var front:=Vector3(back.x,0,back.z)
    if front.length_squared()<.000001:
        var right:=Vector3(right_hint.x,0,right_hint.z)
        if right.length_squared()<.000001: right=Vector3.RIGHT
        front=right.normalized().cross(Vector3.UP)
    front=front.normalized()
    return Basis(Vector3.UP.cross(front).normalized(),Vector3.UP,front)

func camera_cases() -> Array[Dictionary]:
    var cases: Array[Dictionary]=[]
    for yaw in [-35.0,0.0,10.0,35.0]:
        for pitch in [14.0,20.0,40.0]:
            var angle:=deg_to_rad(yaw)
            var tilt:=deg_to_rad(pitch)
            cases.append({"name":"yaw-"+str(yaw)+"-pitch-"+str(pitch),"back":Vector3(sin(angle)*cos(tilt),sin(tilt),cos(angle)*cos(tilt)),"right":Vector3(cos(angle),0,-sin(angle))})
    cases.append({"name":"vertical-camera-fallback","back":Vector3.UP,"right":Vector3.RIGHT})
    cases.append({"name":"degenerate-input-fallback","back":Vector3.UP,"right":Vector3.UP})
    return cases

func check_assets() -> void:
    var baseline:=json(BASELINE)
    var normals:=json(NORMALS)
    var definition:=json("res://"+baseline.source_definition)
    sha("res://"+baseline.source_definition,baseline.source_definition_sha256)
    sha(BASELINE,normals.baseline_sha256)
    var count:=0
    for entry in baseline.directions:
        sha("res://"+entry.manifest,entry.manifest_sha256)
        var colors:=json("res://"+entry.manifest)
        var paired: Dictionary=normals.directions[entry.direction]
        var folder: String=("res://"+entry.manifest).get_base_dir()
        sha(folder.path_join(colors.atlas),entry.atlas_sha256)
        sha("res://"+paired.atlas,paired.atlas_sha256)
        sha("res://"+paired.mask_atlas,paired.mask_atlas_sha256)
        check(colors.pivot==entry.pivot and paired.pivot==entry.pivot,"unchanged foot pivot "+entry.direction)
        check(paired.idle_frame==definition.directions[entry.direction].idle_frame,"unchanged idle "+entry.direction)
        check(colors.frames.size()==27 and paired.frames.size()==27,"27 paired frames "+entry.direction)
        for index in range(27):
            var source: Dictionary=entry.frames[index]
            var color: Dictionary=colors.frames[index]
            var normal: Dictionary=paired.frames[index]
            sha("res://"+source.path,source.sha256)
            sha("res://"+normal.path,normal.sha256)
            sha("res://"+normal.mask_path,normal.mask_sha256)
            check(source.sha256==normal.source_sha256 and source.path==normal.source_path and source.region==color.region and source.region==normal.region and source.duration_ms==color.duration_ms and source.duration_ms==normal.duration_ms,"unchanged pairing/timing "+entry.direction+"/"+str(index))
            count+=1
    for npc in json("res://art_source/ancient-canal/npcs/manifest.json").characters:
        for asset in npc.outputs: sha("res://"+asset.path,asset.sha256)
    check(count==108,"108 immutable color/normal/silver triples")
    report["asset_scope"]={"character_frames":count,"directions":4,"npc_triples":3,"policy":"No assets written; full PNG SHA guarantees unchanged alpha/vector bytes as well as color."}

func check_sprite_mesh(sprite: Sprite3D,label: String,foot: Vector3) -> void:
    var mesh:=sprite.generate_triangle_mesh()
    check(mesh!=null,label+" actual sprite triangle mesh exists")
    if mesh==null: return
    var points:=mesh.get_faces()
    var minimum:=Vector3(INF,INF,INF)
    var maximum:=Vector3(-INF,-INF,-INF)
    for point in points:
        minimum=minimum.min(point)
        maximum=maximum.max(point)
    var local_foot:=Vector3(sprite.offset.x*sprite.pixel_size,(sprite.offset.y+128-240)*sprite.pixel_size,0)
    var local_top:=Vector3(local_foot.x,maximum.y,0)
    check(points.size()==6 and absf(maximum.y-minimum.y-256*sprite.pixel_size)<.00001,label+" unchanged 256px actual mesh extent",{"minimum":vector(minimum),"maximum":vector(maximum)})
    check(sprite.global_position.distance_to(foot)<.00001 and local_foot.length()<.00001,label+" unchanged foot anchor",{"sprite_origin":vector(sprite.global_position),"world_foot":vector(foot),"local_foot":vector(local_foot)})
    for item in camera_cases():
        var basis:=standing_basis(item.back,item.right)
        var world_foot: Vector3=sprite.global_position+basis*local_foot
        var world_top: Vector3=sprite.global_position+basis*local_top
        var delta:=world_top-world_foot
        check(basis.y.is_equal_approx(Vector3.UP) and absf(delta.x)<.00001 and absf(delta.z)<.00001 and delta.y>2,label+" top-to-foot is world UP "+item.name,{"world_delta":vector(delta),"basis_determinant":basis.determinant()})
        check(absf(basis.x.dot(basis.y))<.00001 and absf(basis.z.y)<.00001 and absf(basis.determinant()-1)<.00001,label+" orthonormal horizontal billboard "+item.name)
    check(sprite.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,label+" real geometry shadow retained")

func check_scene() -> void:
    var packed: PackedScene=load("res://scenes/ancient_canal.tscn")
    check(packed!=null,"real Ancient scene loads")
    if packed==null: return
    scene=packed.instantiate()
    check(scene.get_script()!=null and scene.has_method("camera_update"),"real Ancient runtime script parses")
    if scene.get_script()==null or not scene.has_method("camera_update"):
        scene.free()
        return
    root.add_child(scene)
    scene.frozen=true
    scene.player.set_physics_process(false)
    scene.player.controls_enabled=false
    var body_transform: Transform3D=scene.player.global_transform
    check_sprite_mesh(scene.player.sprite,"player",scene.player.global_position)
    for npc in scene.layout.npcs:
        var node: Sprite3D=scene.get_node(npc.id)
        check_sprite_mesh(node,npc.id,Vector3(npc.position[0],npc.position[1],npc.position[2]))
        check(node.material_override.shader.resource_path=="res://shaders/ancient_canal/sprite_native.gdshader",npc.id+" uses shared upright surface")
    scene.player.paused=true
    var bindings:=0
    for direction in range(4):
        scene.player.direction_override=direction
        for index in range(27):
            scene.player.frame_override=index
            scene.player.update_animation()
            var color: Texture2D=scene.player.surface.get_shader_parameter("color_atlas")
            var normal: Texture2D=scene.player.surface.get_shader_parameter("normal_atlas")
            var silver: Texture2D=scene.player.surface.get_shader_parameter("silver_atlas")
            var frame: Dictionary=scene.player.color_definitions[direction].frames[index]
            var size:=Vector2(color.get_size())
            var r: Array=frame.region
            var region:=Vector4(r[0]/size.x,r[1]/size.y,r[2]/size.x,r[3]/size.y)
            check(scene.player.animation_frame==index and scene.player.displayed_facing==direction and scene.player.sprite.texture==scene.player.color_frames[direction][index] and normal==scene.player.normal_atlases[direction] and silver==scene.player.silver_atlases[direction] and scene.player.surface.get_shader_parameter("atlas_region")==region,"synchronized actual color/normal/silver binding "+str(direction)+"/"+str(index))
            check(scene.player.global_transform.is_equal_approx(body_transform) and scene.player.sprite.offset==Vector2(0,112),"unchanged body/pivot "+str(direction)+"/"+str(index))
            bindings+=1
        check(scene.player.animation.frame_at(direction,0,false)==(11 if direction==3 else 10),"existing balanced idle "+str(direction))
    report["scene_scope"]={"actual_sprite_meshes":4,"synchronized_material_frames":bindings,"camera_cases_per_mesh":camera_cases().size(),"facing_selection":"Existing pixel_actor physics facing logic unchanged; tests exercise all explicit direction/frame bindings."}
    scene.queue_free()
    await process_frame

func gpu_probe() -> void:
    root.set_flag(Window.FLAG_NO_FOCUS,true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    var adapter:=RenderingServer.get_video_adapter_name()
    check(DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="forward_plus" and not adapter.is_empty() and not adapter.to_lower().contains("llvmpipe") and not adapter.to_lower().contains("lavapipe"),"real hardware Forward+ basis probe")
    check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED and root.get_flag(Window.FLAG_NO_FOCUS),"GPU probe minimized/no-focus contract")
    if not failures.is_empty(): return
    viewport=SubViewport.new()
    viewport.size=Vector2i(64,64)
    viewport.own_world_3d=true
    viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var camera:=Camera3D.new()
    camera.projection=Camera3D.PROJECTION_ORTHOGONAL
    camera.size=2
    camera.position=Vector3(0,0,4)
    camera.current=true
    viewport.add_child(camera)
    var env:=WorldEnvironment.new()
    env.environment=Environment.new()
    env.environment.background_mode=Environment.BG_COLOR
    env.environment.background_color=Color.BLACK
    env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
    viewport.add_child(env)
    var production:=FileAccess.get_file_as_string(SURFACE)
    var begin:=production.find("mat3 upright_billboard_basis(")
    var end:=production.find("void vertex()",begin)
    check(begin>=0 and end>begin,"production helper can be compiled for pixel probe")
    if begin<0 or end<=begin: return
    # Execute this exact production helper; the assertion depends on GPU pixels,
    # not the presence of text or a Sprite3D billboard enum.
    var helper:=production.substr(begin,end-begin)
    var shader:=Shader.new()
    shader.code="shader_type spatial;\nrender_mode unshaded;\nuniform vec3 probe_camera_back;\nuniform vec3 probe_camera_right;\nuniform int axis;\nvarying vec3 actual_axis;\n"+helper+"\nvoid vertex(){mat3 b=upright_billboard_basis(probe_camera_back,probe_camera_right); actual_axis=axis<3?b[axis]:(b*vec3(0.0,2.16,0.0)-b*vec3(0.0,0.0,0.0))/2.16;}\nvoid fragment(){ALBEDO=actual_axis*0.5+0.5;}\n"
    var material:=ShaderMaterial.new()
    material.shader=shader
    var quad:=MeshInstance3D.new()
    var mesh:=QuadMesh.new()
    mesh.size=Vector2(2,2)
    quad.mesh=mesh
    quad.material_override=material
    viewport.add_child(quad)
    for warmup in range(8): await process_frame
    var samples: Array[Dictionary]=[]
    for item in camera_cases():
        material.set_shader_parameter("probe_camera_back",item.back)
        material.set_shader_parameter("probe_camera_right",item.right)
        var expected:=standing_basis(item.back,item.right)
        for axis in range(4):
            material.set_shader_parameter("axis",axis)
            await process_frame
            await RenderingServer.frame_post_draw
            var image:=viewport.get_texture().get_image()
            var sample:=image.get_pixel(32,32).srgb_to_linear()
            var actual:=Vector3(sample.r,sample.g,sample.b)*2-Vector3.ONE
            var wanted: Vector3=expected[axis] if axis<3 else Vector3.UP
            var name: String=item.name+"-axis-"+str(axis)+".png"
            check(image.save_png(output.path_join(name))==OK,"save real basis probe "+name)
            check(actual.distance_to(wanted)<.018,"GPU production helper "+item.name+" axis "+str(axis),{"expected":vector(wanted),"actual_gpu":vector(actual)})
            samples.append({"case":item.name,"axis":axis,"expected":vector(wanted),"raw_srgb":[image.get_pixel(32,32).r,image.get_pixel(32,32).g,image.get_pixel(32,32).b],"actual_gpu":vector(actual),"png":name,"sha256":FileAccess.get_sha256(output.path_join(name))})
    report["gpu"]={"adapter":adapter,"renderer":RenderingServer.get_current_rendering_method(),"main_window_minimized":DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED,"no_focus_flag":root.get_flag(Window.FLAG_NO_FOCUS),"production_helper_sha256":helper.sha256_text(),"samples":samples,"scope":"Exact production GLSL helper executed in vertex stage; sampled RGB encodes right/up/front and world top-to-foot direction. Native/material brightness and real geometry shadows require separate calibration/captures."}
    report["gpu_basis_executed"]=true

func run() -> void:
    if gpu:
        root.set_flag(Window.FLAG_NO_FOCUS,true)
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    output=ProjectSettings.globalize_path(output)
    DirAccess.make_dir_recursive_absolute(output)
    report={"runtime_fingerprint":runtime_fingerprint,"mode":"hardware GPU plus read-only CPU" if gpu else "headless read-only CPU","surface_sha256":FileAccess.get_sha256(SURFACE),"gpu_basis_executed":false,"limitations":["Production helper pixel probe does not itself prove real scene silhouette, lighting or shadows; these require separate hardware calibration/captures."] if gpu else ["Headless has no render device: mesh/world-vector expectations are checked, but shader execution, lighting and shadow pixels need separate hardware acceptance."]}
    check_assets()
    await check_scene()
    if gpu: await gpu_probe()
    report["checks"]=checks
    report["failures"]=failures
    report["passed"]=failures.is_empty()
    var file:=FileAccess.open(output.path_join("upright-report.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  ")+"\n")
    print("ANCIENT_UPRIGHT_VALIDATION_DONE passed=",report.passed," gpu=",gpu," checks=",checks.size())
    quit(0 if failures.is_empty() else 1)
