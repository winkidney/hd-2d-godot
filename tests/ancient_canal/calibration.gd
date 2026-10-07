extends SceneTree
## Real GPU calibration. Force-drawn captures never serve as FPS measurements.
## Launch off screen with --disable-render-loop --position 10000,10000.
var viewport: SubViewport
var camera: Camera3D
var light: DirectionalLight3D
var native_quad: MeshInstance3D
var sphere: MeshInstance3D
var sprite: Sprite3D
var native_material: StandardMaterial3D
var shader_material: ShaderMaterial
var output := "res://build/ancient-canal/normal-calibration"
var failures: Array[String] = []
var report: Dictionary = {}
var runtime_fingerprint := ""
var fixture_albedo_linear := Color(.64,.64,.64,1)

func _initialize() -> void:
    root.set_flag(Window.FLAG_NO_FOCUS,true)
    root.hide()
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--canal-calibration-dir="): output=arg.trim_prefix("--canal-calibration-dir=")
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

func require(condition: bool, description: String) -> void:
    if not condition:
        failures.append(description)
        push_error(description)

func rendered() -> Image:
    await process_frame
    await RenderingServer.frame_post_draw
    var image:=viewport.get_texture().get_image()
    require(not image.is_empty() and image.get_size()==viewport.size,"empty or non-1080p GPU frame")
    return image

func save(image: Image,name: String) -> void:
    require(image.save_png(output.path_join(name))==OK,"cannot save "+name)

func data_texture(color: Color) -> ImageTexture:
    var image:=Image.create(256,256,false,Image.FORMAT_RGBA8)
    image.fill(color)
    return ImageTexture.create_from_image(image)

func calibration_normal() -> ImageTexture:
    var image:=Image.create(256,256,false,Image.FORMAT_RGBA8)
    # Top row is X-/X+, bottom row is Y+/Y-. The four vectors have z=.8.
    var vectors: Array[Vector3]=[Vector3(-.6,0,.8),Vector3(.6,0,.8),Vector3(0,.6,.8),Vector3(0,-.6,.8)]
    for y in range(256):
        for x in range(256):
            var index:=int(x>=128)+2*int(y>=128)
            var n: Vector3=vectors[index]
            image.set_pixel(x,y,Color(n.x*.5+.5,n.y*.5+.5,n.z*.5+.5,1))
    save(image,"authored-four-vector-normal.png")
    return ImageTexture.create_from_image(image)

func base_material() -> StandardMaterial3D:
    var material:=StandardMaterial3D.new()
    # StandardMaterial3D's source_color uniform decodes its UI color from sRGB.
    # The tested spatial shader writes linear ALBEDO=.64 directly, so supply
    # its sRGB encoding to the native material for identical reflectance.
    material.albedo_color=fixture_albedo_linear.linear_to_srgb()
    material.roughness=.91
    material.metallic=0
    material.metallic_specular=.12
    material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
    return material

func setup_world() -> void:
    var world:=Node3D.new()
    viewport.add_child(world)
    camera=Camera3D.new()
    camera.projection=Camera3D.PROJECTION_ORTHOGONAL
    camera.size=5.0
    camera.near=.05
    camera.far=100
    camera.position=Vector3(0,0,8)
    camera.current=true
    world.add_child(camera)
    camera.look_at(Vector3.ZERO)
    var environment:=Environment.new()
    environment.background_mode=Environment.BG_COLOR
    environment.background_color=Color(.015,.015,.015)
    environment.ambient_light_source=Environment.AMBIENT_SOURCE_DISABLED
    environment.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
    environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
    environment.glow_enabled=false
    environment.ssao_enabled=false
    environment.fog_enabled=false
    var env_node:=WorldEnvironment.new()
    env_node.environment=environment
    world.add_child(env_node)
    light=DirectionalLight3D.new()
    light.light_energy=1
    light.light_color=Color.WHITE
    light.shadow_enabled=false
    world.add_child(light)
    sphere=MeshInstance3D.new()
    var sphere_mesh:=SphereMesh.new()
    sphere_mesh.radius=1
    sphere_mesh.height=2
    sphere_mesh.radial_segments=64
    sphere_mesh.rings=32
    sphere.mesh=sphere_mesh
    sphere.material_override=base_material()
    sphere.position=Vector3(-2.7,0,0)
    world.add_child(sphere)
    var quad_mesh:=QuadMesh.new()
    quad_mesh.size=Vector2(2,2)
    native_quad=MeshInstance3D.new()
    native_quad.mesh=quad_mesh
    native_material=base_material()
    native_material.billboard_mode=BaseMaterial3D.BILLBOARD_FIXED_Y
    native_material.normal_enabled=true
    native_material.normal_texture=calibration_normal()
    native_material.normal_scale=1
    native_quad.material_override=native_material
    world.add_child(native_quad)
    sprite=Sprite3D.new()
    sprite.texture=data_texture(Color.WHITE)
    sprite.pixel_size=2.0/256.0
    sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
    sprite.position=Vector3(2.7,0,0)
    sprite.shaded=true
    sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
    shader_material=ShaderMaterial.new()
    shader_material.shader=load("res://shaders/ancient_canal/sprite_native.gdshader")
    shader_material.set_shader_parameter("color_atlas",sprite.texture)
    shader_material.set_shader_parameter("normal_atlas",native_material.normal_texture)
    shader_material.set_shader_parameter("silver_atlas",data_texture(Color.BLACK))
    shader_material.set_shader_parameter("clay_mode",true)
    shader_material.set_shader_parameter("silver_specular",0)
    shader_material.set_shader_parameter("normal_strength",1)
    sprite.material_override=shader_material
    world.add_child(sprite)

func average(image: Image,area: Rect2) -> float:
    var bounds:=area.intersection(Rect2(Vector2.ZERO,Vector2(viewport.size)))
    var sum:=0.0
    var count:=0
    for y in range(ceili(bounds.position.y),floori(bounds.end.y)):
        for x in range(ceili(bounds.position.x),floori(bounds.end.x)):
            var color:=image.get_pixel(x,y)
            sum+=(color.r+color.g+color.b)/3.0
            count+=1
    require(count>100,"calibration sample outside image")
    return sum/maxi(1,count)

func standing_basis() -> Basis:
    var front:=Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
    return Basis(Vector3.UP.cross(front).normalized(),Vector3.UP,front)

func projected_area(center: Vector3,upright:=false) -> Rect2:
    var basis:=standing_basis() if upright else camera.global_basis
    var top_left:=camera.unproject_position(center-basis.x+basis.y)
    var bottom_right:=camera.unproject_position(center+basis.x-basis.y)
    return Rect2(top_left,bottom_right-top_left).abs()

func quadrant_values(image: Image,center: Vector3) -> Array[float]:
    var area:=projected_area(center,true)
    var result: Array[float]=[]
    for index in range(4):
        var origin:=area.position+area.size*Vector2(.08+float(index%2)*.5,.08+float(index/2)*.5)
        result.append(average(image,Rect2(origin,area.size*.34)))
    return result

func image_difference(a: Image,b: Image,area: Rect2) -> Dictionary:
    var bounds:=area.intersection(Rect2(Vector2.ZERO,Vector2(viewport.size)))
    var changed:=0
    var total:=0.0
    var count:=0
    for y in range(ceili(bounds.position.y+2),floori(bounds.end.y-2)):
        for x in range(ceili(bounds.position.x+2),floori(bounds.end.x-2)):
            var ca:=a.get_pixel(x,y)
            var cb:=b.get_pixel(x,y)
            var difference: float=(absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b))/3
            if difference>.015:changed+=1
            total+=difference
            count+=1
    return {"changed_pixels":changed,"sample_pixels":count,"mean_absolute_RGB":total/maxi(1,count)}

func check_order(samples: Array[float],label: String,direction: String) -> void:
    match direction:
        "left":require(samples[0]>samples[1]+.08,label+" X-left light illuminates negative X normal")
        "right":require(samples[1]>samples[0]+.08,label+" X-right light illuminates positive X normal")
        "up":require(samples[2]>samples[3]+.08,label+" Y-up light illuminates positive Y normal")
        "down":require(samples[3]>samples[2]+.08,label+" Y-down light illuminates negative Y normal")

func run() -> void:
    # Engine startup can replace flags set during _initialize(). Reapply to
    # both the Window object and the actual native window before every draw.
    root.set_flag(Window.FLAG_NO_FOCUS,true)
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    # Native WM acknowledgement arrives after the minimize request.
    for startup in 5: await process_frame
    var adapter:=RenderingServer.get_video_adapter_name()
    report={"runtime_fingerprint":runtime_fingerprint,"renderer":RenderingServer.get_current_rendering_method(),"adapter":adapter,"hardware_gpu":not adapter.is_empty() and not adapter.to_lower().contains("llvmpipe") and not adapter.to_lower().contains("lavapipe"),"size":[1920,1080],"capture_mode":"minimized no-focus window, independent offscreen SubViewport","main_window_minimized":DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED,"no_focus_flag":root.get_flag(Window.FLAG_NO_FOCUS),"scope":"pixel brightness assertions on native geometry sphere, StandardMaterial3D normal quad, and actual character spatial shader billboard; no source-code-presence assertions","samples":[]}
    require(DisplayServer.get_name()!="headless","calibration requires an actual hardware render device")
    require(report.hardware_gpu and report.renderer=="forward_plus","calibration is not hardware Forward+")
    require(report.main_window_minimized and report.no_focus_flag,"window visibility/focus contract violated")
    setup_world()
    report["billboard_fixture"]={"native_mode":"BILLBOARD_FIXED_Y","custom_mode":"production upright_billboard_basis","world_up":[0,1,0],"main_camera_for_shadow_pass":true,"color_normal_resources_regenerated":false}
    var native_ui:=native_material.albedo_color
    var native_linear:=native_ui.srgb_to_linear()
    report["albedo_fixture"]={"native_ui_srgb":[native_ui.r,native_ui.g,native_ui.b],"native_decoded_linear":[native_linear.r,native_linear.g,native_linear.b],"shader_linear":[fixture_albedo_linear.r,fixture_albedo_linear.g,fixture_albedo_linear.b],"conversion":"native source_color receives linear_to_srgb(.64), matching shader linear ALBEDO=.64"}
    require(absf(native_linear.r-fixture_albedo_linear.r)<.00001 and absf(native_linear.g-fixture_albedo_linear.g)<.00001 and absf(native_linear.b-fixture_albedo_linear.b)<.00001,"native/shader fixture reflectance mismatch")
    for i in range(12):await process_frame
    for camera_index in range(2):
        if camera_index==1:
            camera.position=Vector3(2.8,1.8,8)
            camera.look_at(Vector3.ZERO)
        for name in ["left","right","up","down"]:
            var xy:=Vector2(-1,0) if name=="left" else (Vector2(1,0) if name=="right" else (Vector2(0,1) if name=="up" else Vector2(0,-1)))
            var upright:=standing_basis()
            light.position=(upright.x*xy.x+upright.y*xy.y+upright.z)*5
            light.look_at(Vector3.ZERO)
            shader_material.set_shader_parameter("use_normals",true)
            shader_material.set_shader_parameter("normal_strength",1)
            shader_material.set_shader_parameter("flip_y",false)
            var image:=await rendered()
            save(image,"camera-%d-light-%s.png"%[camera_index,name])
            var native:=quadrant_values(image,native_quad.global_position)
            var custom:=quadrant_values(image,sprite.global_position)
            check_order(native,"native camera "+str(camera_index),name)
            check_order(custom,"shader billboard camera "+str(camera_index),name)
            var sphere_area:=projected_area(sphere.global_position)
            var bright_area:=Rect2(sphere_area.position+sphere_area.size*Vector2(.10,.28),sphere_area.size*Vector2(.3,.44))
            var dim_area:=Rect2(sphere_area.position+sphere_area.size*Vector2(.60,.28),sphere_area.size*Vector2(.3,.44))
            if name=="up" or name=="down":
                bright_area=Rect2(sphere_area.position+sphere_area.size*Vector2(.28,.10),sphere_area.size*Vector2(.44,.3))
                dim_area=Rect2(sphere_area.position+sphere_area.size*Vector2(.28,.60),sphere_area.size*Vector2(.44,.3))
            var first:=average(image,bright_area)
            var second:=average(image,dim_area)
            require(first>second+.03 if name=="left" or name=="up" else second>first+.03,"native geometric sphere responds to "+name+" light")
            var native_shader_error:=0.0
            for q in range(4):native_shader_error+=absf(native[q]-custom[q])/4
            require(native_shader_error<.08,"native/shader tangent basis mismatch "+name+" camera "+str(camera_index))
            var entry: Dictionary={"camera":camera_index,"light":name,"native_quadrants":native,"shader_quadrants":custom,"native_shader_mean_error":native_shader_error,"sphere_first":first,"sphere_second":second,"billboard_right":[upright.x.x,upright.x.y,upright.x.z],"billboard_up":[upright.y.x,upright.y.y,upright.y.z],"billboard_front":[upright.z.x,upright.z.y,upright.z.z],"screenshot":"camera-%d-light-%s.png"%[camera_index,name]}
            if camera_index==0 and name=="up":
                shader_material.set_shader_parameter("flip_y",true)
                var flipped:=await rendered()
                save(flipped,"flip-y-up.png")
                var flip_values:=quadrant_values(flipped,sprite.global_position)
                require(flip_values[3]>flip_values[2]+.08,"flip_y does not reverse actual Y illumination")
                entry["flip_y_quadrants"]=flip_values
                shader_material.set_shader_parameter("flip_y",false)
            if camera_index==0 and name=="left":
                shader_material.set_shader_parameter("normal_strength",0)
                var zero:=await rendered()
                save(zero,"normal-strength-zero.png")
                shader_material.set_shader_parameter("use_normals",false)
                var disabled:=await rendered()
                save(disabled,"normal-disabled.png")
                var zero_difference:=image_difference(zero,disabled,projected_area(sprite.global_position,true))
                var enabled_difference:=image_difference(image,disabled,projected_area(sprite.global_position,true))
                require(zero_difference.mean_absolute_RGB<.006,"strength zero differs from disabled flat normal")
                require(enabled_difference.changed_pixels>2000 and enabled_difference.mean_absolute_RGB>.04,"normal enabled does not change actual GPU pixels")
                entry["strength_zero_vs_disabled"]=zero_difference
                entry["enabled_vs_disabled"]=enabled_difference
            report.samples.append(entry)
    report["failures"]=failures
    report["passed"]=failures.is_empty() and report.samples.size()==8
    var file:=FileAccess.open(output.path_join("calibration-report.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  ")+"\n")
    print("ANCIENT_NORMAL_CALIBRATION_DONE hardware=",report.hardware_gpu," passed=",report.passed)
    quit(0 if report.passed else 1)
