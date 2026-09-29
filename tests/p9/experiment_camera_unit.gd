extends SceneTree
## Offline camera/parallax math and state regression; no scene/model import.
## Run: godot --headless --path . --script res://tests/p9/experiment_camera_unit.gd
const CameraRig = preload("res://scripts/reference_scene/experiment_camera.gd")
const Controller = preload("res://scripts/reference_scene/experiment_parallax.gd")
const Preview = preload("res://scripts/reference_scene/experiment_preview.gd")
const Multiview = preload("res://scripts/reference_scene/impostor.gd")
var failures: Array[String] = []
var checks := 0
class Backdrop extends Node3D:
    var layers: Dictionary = {}
    var cloud_roots: Dictionary = {}
    var wind_enabled := true
    var wind_speeds := [0.2, 0.1]

class Focus extends RefCounted:
    var mode := "auto"
    var manual_depth := 25.0
    var focus_depth := 30.0
    func apply() -> void:
        pass

class PreviewScene extends Node3D:
    var rig: RefCounted
    var camera: Camera3D
    var parallax: RefCounted
    var clock_frozen := false
    var tour := false
    var follow := true
    var dof := Focus.new()
    var lighting: Dictionary = {}
    var impostor: Node3D

func _initialize() -> void:
    call_deferred("run")

func check(value: bool, label: String) -> void:
    checks += 1
    if not value:
        failures.append(label)
        print("FAIL ", label)

func run() -> void:
    root.size = Vector2i(1920,1080)
    var cam := Camera3D.new()
    root.add_child(cam)
    cam.current = true
    var rig := CameraRig.new()
    var spawn := Vector3(3,1.5,6.7)
    rig.configure(cam,{"position":[16,21,32],"target":[0,2,1],"follow_gain":0.45,"dead_zone":0.8,"smoothing":4.0,"follow_max":[7.5,4.5],"fov":35.0,"far":1400.0},spawn)
    var background := Backdrop.new()
    root.add_child(background)
    var n := 0
    for id in Controller.Profile.IDS:
        var layer := Node3D.new()
        background.add_child(layer)
        var mesh := MeshInstance3D.new()
        mesh.mesh = BoxMesh.new()
        layer.add_child(mesh)
        mesh.position = Vector3(-5+n*4, -4-n*3, -24-n*20)
        if id.begins_with("clouds_"):
            background.cloud_roots[id] = layer
        else:
            background.layers[id] = layer
        n += 1
    var controller := Controller.new()
    controller.configure(cam, rig, background, "isolated-fixture")
    var center := spawn + Vector3.UP*.04 + cam.global_basis.y*(30.0*.035)
    var basis_y := cam.global_basis.y
    var reference_height := absf(cam.unproject_position(center + basis_y*1.12).y - cam.unproject_position(center - basis_y*1.12).y)
    var original_radius := (rig.home-rig.target).length()
    var original_pitch := cam.global_basis.z.y
    for variant in ["A","B","C","D"]:
        controller.select_variant(variant)
        rig.select_variant(variant)
        controller.update(0,true)
        check(rig.supported_pose(),variant+" supported")
        center = spawn + Vector3.UP*.04 + cam.global_basis.y*(30.0*.035)
        var match_height := absf(cam.unproject_position(center + cam.global_basis.y*1.12).y-cam.unproject_position(center-cam.global_basis.y*1.12).y)
        check(absf(match_height/reference_height-1.0)<0.02,variant+" actor_scale "+str(match_height/reference_height))
        check(absf(rig.actor_screen_height(spawn)-match_height)<.001,variant+" billboard endpoint measurement")
        for yaw in [-6.0,0.0,6.0]:
            rig.set_test_yaw(yaw)
            for ratio in [0.0,0.5,1.0,1.5,2.0]:
                controller.change("mode","artistic")
                controller.change("global_strength",ratio)
                for dx in [-7.0,-2.0,0.0,2.0,7.0]:
                    rig.set_offset(rig.horizontal_right()*dx)
                    controller.update(0,true)
                    check(controller.compatible, "%s compatible %s %s %s"%[variant,yaw,ratio,dx])
                    check(absf(cam.global_position.distance_to(rig.target+rig.follow_offset)-original_radius)<.0001,variant+" radius")
                    check(absf(cam.global_basis.z.y-original_pitch)<.0001,variant+" pitch")
                    for id in Controller.Profile.IDS:
                        var info: Dictionary=controller.diagnostics()[id]
                        check(info.valid and info.representative_error_px<.1,"%s %s yaw%s k%s dx%s error%s"%[variant,id,yaw,ratio,dx,info.representative_error_px])
                        var engine_pixel_x := cam.unproject_position(controller.layer_point(id)).x
                        var expected_pixel_x: float = controller.projections[id].expected_x+960.0
                        check(absf(engine_pixel_x-expected_pixel_x)<.1,"engine projection %s %s yaw%s k%s dx%s error%s"%[variant,id,yaw,ratio,dx,absf(engine_pixel_x-expected_pixel_x)])
                        if is_zero_approx(dx):
                            check(controller.states[id].node.global_transform.is_equal_approx(controller.states[id].base),variant+" pure_yaw_natural "+id)
                    var snap := rig.pose_snapshot()
                    rig.set_offset(Vector3.ONE)
                    rig.set_test_yaw(-3)
                    rig.restore_pose(snap)
                    check(cam.global_transform.is_equal_approx(snap.transform) and rig.follow_offset==snap.follow_offset and rig.yaw_degrees==snap.yaw_degrees,variant+" restore")
        rig.clear_test_yaw()
        rig.set_offset(Vector3.ZERO)
        rig.select_variant(variant,spawn)
        var fixed_right := rig.horizontal_right()
        for distance in [-21.0,-11.0,-6.0,-1.0,0.0,1.0,6.0,11.0,21.0]:
            var expected_yaw := signf(distance)*minf(maxf(absf(distance)-1.0,0.0)/10.0,1.0)*6.0 if variant in ["B","C"] else 0.0
            check(is_equal_approx(rig.desired_yaw(spawn+fixed_right*distance),expected_yaw),variant+" orbit dead zone/ramp "+str(distance))
        rig.update(.4,spawn+fixed_right*21.0,false,0.0)
        var expected_after_step := 6.0*(1.0-exp(-2.5*.4)) if variant in ["B","C"] else 0.0
        check(is_equal_approx(rig.yaw_degrees,expected_after_step),variant+" orbit independent smoothing")
        check(rig.horizontal_right().is_equal_approx(fixed_right),variant+" orbit does not rotate follow axis")
        rig.select_variant(variant,spawn)
    controller.select_variant("A")
    controller.change("horizontal_follow_gain",.2)
    controller.select_variant("B")
    controller.change("horizontal_follow_gain",.65)
    controller.select_variant("A")
    check(is_equal_approx(rig.horizontal_gain,.2),"independent variant settings")
    controller.reset_all()
    check(is_equal_approx(rig.horizontal_gain,.45),"variant reset")
    var fake := PreviewScene.new()
    root.add_child(fake)
    fake.rig = rig
    fake.camera = cam
    fake.parallax = controller
    var shader := Shader.new()
    shader.code = "shader_type spatial; uniform float motion = 1.0;"
    var water := ShaderMaterial.new()
    water.shader = shader
    water.set_shader_parameter("motion",1.0)
    fake.lighting = {"water": water}
    fake.impostor = Multiview.new()
    fake.add_child(fake.impostor)
    fake.impostor.camera = cam
    fake.impostor.source_visual = Node3D.new()
    fake.impostor.add_child(fake.impostor.source_visual)
    fake.impostor.source_visual.position = Vector3(13,4,-10.5)
    fake.impostor.add_child(fake.impostor.card)
    fake.impostor.material.shader = preload("res://scripts/reference_scene/impostor.gdshader")
    fake.impostor.available = true
    var preview := Preview.new()
    for variant in ["A","B","C","D"]:
        controller.select_variant(variant)
        rig.select_variant(variant)
        rig.set_test_yaw(6.0)
        rig.set_offset(rig.horizontal_right()*3.0)
        fake.impostor.active = variant == "D"
        fake.impostor.update_view(0,true)
        var before_multiview: Dictionary = fake.impostor.pose_snapshot()
        var before := rig.pose_snapshot()
        var snapshot := {"clock": fake.clock_frozen, "focus": fake.dof.mode, "water": water.get_shader_parameter("motion")}
        check(preview.start(fake),variant+" preview started")
        preview.update(.4)
        fake.impostor.update_view(.4)
        check(not cam.global_transform.is_equal_approx(before.transform),variant+" preview moved")
        preview.stop()
        var after_multiview: Dictionary = fake.impostor.pose_snapshot()
        check(before_multiview.angle_degrees==after_multiview.angle_degrees and before_multiview.target_angle_degrees==after_multiview.target_angle_degrees and before_multiview.frame_position==after_multiview.frame_position and before_multiview.card_transform==after_multiview.card_transform, variant+" preview restores multiview internal state")
        if variant == "D":
            check(is_equal_approx(float(fake.impostor.material.get_shader_parameter("frame_position")), float(before_multiview.frame_position)), "D preview restores displayed atlas frame")
        check(cam.global_transform.is_equal_approx(before.transform) and rig.follow_offset==before.follow_offset and rig.yaw_degrees==before.yaw_degrees,variant+" preview restored all pose")
        check(fake.clock_frozen==snapshot.clock and fake.dof.mode==snapshot.focus and water.get_shader_parameter("motion")==snapshot.water,variant+" preview restored clock/focus/water")
        check(controller.compatible,variant+" preview restored compatible")
        for id in Controller.Profile.IDS:
            var errors := controller.layer_sample_errors(id)
            check(errors.count>0,variant+" wholelayer samples "+id)
    print("P9_CAMERA_UNIT checks=",checks," failures=",failures.size())
    fake.free()
    cam.free()
    background.free()
    quit(0 if failures.is_empty() else 1)
