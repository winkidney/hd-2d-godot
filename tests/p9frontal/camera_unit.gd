extends SceneTree
## Offline projection/state checks. Building vertices are read without import.
## godot --headless --path . --script res://tests/p9frontal/camera_unit.gd
const Rig = preload("res://scripts/frontal_canal/camera.gd")
const Parallax = preload("res://scripts/frontal_canal/parallax.gd")
const Preview = preload("res://scripts/frontal_canal/preview.gd")
const VariantPanel = preload("res://scripts/frontal_canal/panel.gd")
var failures: Array[String] = []
var checks := 0

class Backdrop extends Node3D:
    var layers: Dictionary = {}
    var cloud_roots: Dictionary = {}
    var wind_enabled := true
    var wind_speeds := [0.2,0.1]

class Focus extends RefCounted:
    var mode := "protected"
    var manual_depth := 28.0
    var focus_depth := 28.0
    func apply() -> void:
        pass

class PreviewScene extends Node3D:
    var rig: RefCounted
    var camera: Camera3D
    var parallax: RefCounted
    var dof := Focus.new()
    var lighting: Dictionary = {}
    var clock_frozen := false
    var tour := false
    var follow := true
    var route_running := false
    var route_cancelled := false
    var variant_id := "F"
    var notice := ""
    var parallax_panel := preload("res://scripts/parallax_panel.gd").new()
    func select_variant(_id: String) -> bool:
        return true
    func reset_variant() -> void:
        pass
    func run_route() -> Dictionary:
        return {"passed":true}
    func close_tuning() -> void:
        pass

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        print("FRONTAL_UNIT_FAIL ",label)

func building_vertices() -> PackedVector3Array:
    # The checked-in static GLB has flat nodes and float POSITION accessors.
    # Reading vertices avoids loading a scene or touching the shared import cache.
    var bytes := FileAccess.get_file_as_bytes("res://assets/reference-scene/models/palazzo.glb")
    var points := PackedVector3Array()
    if bytes.size()<28:
        check(false,"building GLB available for coverage")
        return points
    var json_size := bytes.decode_u32(12)
    var data: Dictionary = JSON.parse_string(bytes.slice(20,20+json_size).get_string_from_utf8())
    var binary_offset := 28+json_size
    for node in data.nodes:
        if not node.has("mesh"):
            continue
        if node.has("children") or node.has("matrix"):
            check(false,"coverage expects flattened model transforms")
            return PackedVector3Array()
        var q: Array = node.get("rotation",[0,0,0,1])
        var t: Array = node.get("translation",[0,0,0])
        var s: Array = node.get("scale",[1,1,1])
        var transform := Transform3D(Basis(Quaternion(q[0],q[1],q[2],q[3])).scaled(Vector3(s[0],s[1],s[2])),Vector3(t[0],t[1],t[2]))
        for primitive in data.meshes[node.mesh].primitives:
            var accessor: Dictionary = data.accessors[primitive.attributes.POSITION]
            if int(accessor.componentType)!=5126 or accessor.type!="VEC3":
                check(false,"coverage requires float position vertices")
                return PackedVector3Array()
            var view: Dictionary = data.bufferViews[accessor.bufferView]
            var start := binary_offset+int(view.get("byteOffset",0))+int(accessor.get("byteOffset",0))
            var stride := int(view.get("byteStride",12))
            for index in int(accessor.count):
                var offset := start+index*stride
                var point := Vector3(bytes.decode_float(offset),bytes.decode_float(offset+4),bytes.decode_float(offset+8))
                points.append((transform*point)*1.1+Vector3(4,2.8,-10))
    check(not points.is_empty(),"actual building vertices decoded")
    return points

func run() -> void:
    root.size = Vector2i(1920,1080)
    var camera := Camera3D.new()
    root.add_child(camera)
    camera.current = true
    var rig := Rig.new()
    var spawn := Vector3(4,1.2,6)
    rig.configure(camera,{"target":[4.0,4.0,1.0],"far":1400},spawn)
    var background := Backdrop.new()
    root.add_child(background)
    var n := 0
    for id in Parallax.Profile.IDS:
        var layer := Node3D.new()
        background.add_child(layer)
        var mesh := MeshInstance3D.new()
        mesh.mesh = BoxMesh.new()
        layer.add_child(mesh)
        mesh.position = Vector3(-8+n*5,-3-n*2,-30-n*25)
        if id.begins_with("clouds_"):
            background.cloud_roots[id] = layer
        else:
            background.layers[id] = layer
        n += 1
    var parallax := Parallax.new()
    parallax.configure(camera,rig,background,"frontal-unit-v1")
    var calibration: Dictionary = {}
    var geometry := building_vertices()
    for variant in ["F","W","O"]:
        parallax.select_variant(variant)
        rig.select_variant(variant,spawn)
        check(camera.projection==Camera3D.PROJECTION_PERSPECTIVE,variant+" true perspective")
        check(camera.global_basis.x.is_equal_approx(Vector3.RIGHT),variant+" centre faces straight -Z")
        check(camera.global_basis.z.x==0.0,variant+" no isometric yaw")
        check(float(Rig.VARIANTS[variant].fov)*.5-float(Rig.VARIANTS[variant].pitch)>=3.0,variant+" upper view includes sky above horizon")
        var center := spawn+Vector3.UP*.04+camera.global_basis.y*1.05
        var height := camera.unproject_position(center+camera.global_basis.y*1.12).distance_to(camera.unproject_position(center-camera.global_basis.y*1.12))
        check(absf(height-rig.actor_screen_height(spawn))<.001,variant+" exact billboard height")
        calibration[variant] = {"pose":rig.pose_diagnostics(),"actor_height_px":height,
            "actor_feet_px":camera.unproject_position(spawn),"building_roof_px":camera.unproject_position(Vector3(4,12.7,-10)),"side_coverage":[]}
        for x in [-16.0,17.0]:
            var position := Vector3(x,1.2,3)
            rig.select_variant(variant,position)
            var relative := camera.global_position-Vector3(4,4,-10)
            var angle := rad_to_deg(atan2(relative.x,relative.z))
            check(angle < -10.0 if x<4.0 else angle>10.0,variant+" crosses main building "+str(x))
            var pixel := camera.unproject_position(position)
            check(pixel.x>100 and pixel.x<1820 and pixel.y>100 and pixel.y<1010,variant+" actor stays visible "+str(x))
            var minimum := Vector2(INF,INF)
            var maximum := Vector2(-INF,-INF)
            for vertex in geometry:
                var projected := camera.unproject_position(vertex)
                minimum = minimum.min(projected)
                maximum = maximum.max(projected)
            check(not geometry.is_empty() and minimum.x>=0.0 and maximum.x<=1920.0 and minimum.y>=0.0 and maximum.y<=1080.0,variant+" full building viewport coverage "+str(x))
            calibration[variant].side_coverage.append({"player_x":x,"view_angle":angle,"bounds":[minimum.x,minimum.y,maximum.x,maximum.y]})
        for yaw in [-4.0,0.0,4.0]:
            rig.set_test_yaw(yaw)
            for ratio in [0.0,.5,1.0,1.5,2.0]:
                parallax.change("mode","artistic")
                parallax.change("global_strength",ratio)
                for dx in [-22.0,-8.0,0.0,8.0,22.0]:
                    rig.set_offset(Vector3.RIGHT*dx)
                    parallax.update(0,true)
                    check(parallax.compatible,variant+" supported pose")
                    check(absf(camera.global_position.distance_to(rig.target+rig.follow_offset)-float(Rig.VARIANTS[variant].radius))<.0001,variant+" radius invariant")
                    check(absf(rad_to_deg(asin(camera.global_basis.z.y))-float(Rig.VARIANTS[variant].pitch))<.0001,variant+" pitch invariant")
                    for layer in Parallax.Profile.IDS:
                        var expected_x: float=parallax.projections[layer].expected_x+960.0
                        var actual_x := camera.unproject_position(parallax.layer_point(layer)).x
                        check(absf(actual_x-expected_x)<.1,variant+" engine projection "+layer)
                        if is_zero_approx(dx):
                            check(parallax.states[layer].node.global_transform.is_equal_approx(parallax.states[layer].base),variant+" pure orbit does not translate "+layer)
        rig.clear_test_yaw()
        rig.select_variant(variant,spawn)
        for distance in [-20.0,-13.0,-7.0,-1.0,0.0,1.0,7.0,13.0,20.0]:
            var expected := signf(distance)*clampf((absf(distance)-1.0)/12.0,0,1)*4.0 if variant=="O" else 0.0
            check(is_equal_approx(rig.desired_yaw(spawn+Vector3.RIGHT*distance),expected),variant+" orbit dead zone/ramp")
        rig.update(.4,spawn+Vector3.RIGHT*20,false,0.0)
        check(is_equal_approx(rig.yaw_degrees,4.0*(1.0-exp(-1.0)) if variant=="O" else 0.0),variant+" orbit smoothing")
        check(rig.horizontal_right().is_equal_approx(Vector3.RIGHT),variant+" fixed follow axis")
    check(parallax.variant_settings.keys().size()==3 and not parallax.variant_settings.has("A") and not parallax.variant_settings.has("D"),"no previous scene profile state")
    check(parallax.change("horizontal_follow_gain",.9).is_empty(),"new follow gain accepted")
    check(parallax.change("horizontal_max_offset",22.0).is_empty(),"new follow extent accepted")
    check(not parallax.change("horizontal_follow_gain",1.3).is_empty(),"follow gain limit enforced")
    check(not parallax.change("horizontal_max_offset",27.0).is_empty(),"follow extent limit enforced")
    parallax.select_variant("F")
    parallax.change("horizontal_follow_gain",.8)
    parallax.select_variant("W")
    parallax.change("horizontal_follow_gain",1.1)
    parallax.select_variant("F")
    check(is_equal_approx(rig.horizontal_gain,.8),"independent variant settings")
    parallax.reset_all()
    check(is_equal_approx(rig.horizontal_gain,.7) and is_equal_approx(rig.max_offset.x,22.0),"frontal reset defaults")
    var scene := PreviewScene.new()
    root.add_child(scene)
    scene.camera=camera;scene.rig=rig;scene.parallax=parallax
    var shader := Shader.new()
    shader.code="shader_type spatial; uniform float motion = 1.0;"
    var water := ShaderMaterial.new()
    water.shader=shader
    water.set_shader_parameter("motion",1.0)
    scene.lighting={"water":water}
    scene.add_child(scene.parallax_panel)
    scene.parallax_panel.configure(scene)
    var panel := VariantPanel.new()
    scene.add_child(panel)
    panel.configure(scene)
    check(is_equal_approx(scene.parallax_panel.fields.horizontal_follow_gain.max_value,1.2),"P gain range extended locally")
    check(is_equal_approx(scene.parallax_panel.fields.horizontal_follow_gain.value,.7),"P actual gain not clamped")
    check(is_equal_approx(scene.parallax_panel.fields.horizontal_max_offset.max_value,26.0),"P extent range extended locally")
    check(is_equal_approx(scene.parallax_panel.fields.horizontal_max_offset.value,22.0),"P actual extent not clamped")
    var preview := Preview.new()
    for variant in ["F","W","O"]:
        parallax.select_variant(variant)
        rig.select_variant(variant,spawn+Vector3.RIGHT*6)
        var before := rig.pose_snapshot()
        check(preview.start(scene),variant+" preview starts")
        preview.update(.5)
        check(not camera.global_transform.is_equal_approx(before.transform),variant+" preview moves camera")
        preview.stop()
        check(camera.global_transform.is_equal_approx(before.transform) and rig.follow_offset==before.follow_offset and rig.yaw_degrees==before.yaw_degrees and rig.reference_basis==before.reference_basis,variant+" preview restores full pose")
        check(not rig.frozen and not scene.clock_frozen and scene.dof.mode=="protected" and water.get_shader_parameter("motion")==1.0,variant+" preview restores clock focus water")
    print("FRONTAL_CALIBRATION ",JSON.stringify(calibration))
    print("FRONTAL_CAMERA_UNIT checks=",checks," failures=",failures.size())
    scene.free();background.free();camera.free()
    quit(0 if failures.is_empty() else 1)
