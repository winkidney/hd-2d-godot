extends SceneTree
## No world import, GPU capture or user-preference writes.
## godot --headless --path . --script res://tests/p9frontal/lens_unit.gd
const Rig = preload("res://scripts/frontal_canal/camera.gd")
const Parallax = preload("res://scripts/frontal_canal/parallax.gd")
const LensSettings = preload("res://scripts/frontal_canal/lens_settings.gd")
const IDS := ["F", "W", "O"]
const LAYOUT_ID := "1111111111111111111111111111111111111111111111111111111111111111"
const DEFAULTS := {"F":{"radius":30.0,"fov":35.0},"W":{"radius":23.0,"fov":45.0},"O":{"radius":30.0,"fov":35.0}}
var checks := 0
var failures: Array[String] = []
var projection_cases := 0
var projection_samples := 0
var maximum_projection_error := 0.0

class Backdrop extends Node3D:
    var layers: Dictionary = {}
    var cloud_roots: Dictionary = {}
    var wind_enabled := true
    var wind_speeds := [0.2,0.1]

func _initialize() -> void:
    call_deferred("run")

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        print("FRONTAL_LENS_FAIL ",label)

func same(a: Variant, b: Variant) -> bool:
    if typeof(a) != typeof(b):
        return false
    if typeof(a) == TYPE_FLOAT:
        return (is_nan(a) and is_nan(b)) or is_equal_approx(a,b)
    if a is Dictionary:
        if a.size() != b.size(): return false
        for key in a:
            if not b.has(key) or not same(a[key],b[key]): return false
        return true
    if a is Array:
        if a.size() != b.size(): return false
        for i in a.size():
            if not same(a[i],b[i]): return false
        return true
    if typeof(a) in [TYPE_VECTOR3,TYPE_BASIS,TYPE_TRANSFORM3D]:
        return a.is_equal_approx(b)
    return a == b

func default_and_boundary_checks(rig: RefCounted, spawn: Vector3) -> void:
    check(Rig.LENS_LIMITS.radius == Vector2(18,45),"distance contract is 18 through 45 metres")
    check(Rig.LENS_LIMITS.fov == Vector2(25,60),"FOV contract is 25 through 60 degrees")
    for id in IDS:
        check(rig.select_variant(id,spawn),id+" selectable")
        check(same(rig.lens_snapshot(),DEFAULTS[id]),id+" documented default lens")
        for key in ["radius","fov"]:
            var limits: Vector2 = Rig.LENS_LIMITS[key]
            for value in [limits.x,limits.y,int(limits.x),int(limits.y)]:
                check(rig.set_lens(key,value),id+" accepts inclusive numeric boundary "+key+" "+str(value))
                check(is_equal_approx(float(rig.lens_snapshot()[key]),float(value)),id+" exposes accepted boundary "+key)
                check(rig.supported_pose(),id+" boundary lens remains supported")
            var invalid: Array = [limits.x-0.001,limits.y+0.001,NAN,INF,-INF,"30",true,false,null,Vector2(30,30),[30],{"value":30}]
            for value in invalid:
                var before: Dictionary = rig.pose_snapshot()
                check(not rig.set_lens(key,value),id+" rejects invalid "+key+" "+str(value))
                check(same(rig.pose_snapshot(),before),id+" invalid lens leaves all pose/profile state unchanged")
        var before_unknown: Dictionary = rig.pose_snapshot()
        check(not rig.set_lens("pitch",14.0),id+" rejects unknown lens key")
        check(same(rig.pose_snapshot(),before_unknown),id+" unknown lens key is atomic")
        rig.reset_lens()
        check(same(rig.lens_snapshot(),DEFAULTS[id]),id+" reset restores own defaults")
        var detached: Dictionary = rig.lens_snapshot()
        detached.radius = 99.0
        check(same(rig.lens_snapshot(),DEFAULTS[id]),id+" returned lens values are detached")
    var before_variant: Dictionary = rig.pose_snapshot()
    check(not rig.select_variant("D",spawn),"old D is not a new frontal variant")
    check(same(rig.pose_snapshot(),before_variant),"invalid variant does not alter profiles or pose")

func isolation_and_state_checks(rig: RefCounted, spawn: Vector3) -> void:
    var custom := {"F":{"radius":41.0,"fov":52.0},"W":{"radius":25.0,"fov":49.0},"O":{"radius":35.0,"fov":32.0}}
    for id in IDS:
        rig.select_variant(id,spawn)
        check(same(rig.lens_snapshot(),DEFAULTS[id]),id+" untouched by other variant edits")
        check(rig.set_lens("radius",custom[id].radius) and rig.set_lens("fov",custom[id].fov),id+" independent edits accepted")
    for id in ["W","O","F","O","W","F"]:
        rig.select_variant(id,spawn)
        check(same(rig.lens_snapshot(),custom[id]),id+" edits survive switching")
    rig.select_variant("W",spawn)
    rig.reset_lens()
    check(same(rig.lens_snapshot(),DEFAULTS.W),"W resets to 23m and 45 degrees")
    check(same(rig.lens_profiles.F,custom.F) and same(rig.lens_profiles.O,custom.O),"W reset preserves F and O")
    rig.select_variant("O",spawn)
    rig.update(0.15,spawn+Vector3(15,0,-7),false,0.0)
    var moving: Dictionary = rig.pose_snapshot()
    check(moving.yaw_degrees > 0.0 and moving.yaw_degrees < moving.target_yaw_degrees,"fixture has unfinished yaw smoothing")
    check(moving.follow_offset.length() > 0.1,"fixture has unfinished translation smoothing")
    for edit in [["radius",44.0],["fov",59.0]]:
        check(rig.set_lens(edit[0],edit[1]),"live lens edit accepted "+str(edit[0]))
        var after: Dictionary = rig.pose_snapshot()
        for field in ["follow_offset","horizontal_follow","yaw_degrees","target_yaw_degrees","test_yaw"]:
            check(same(after[field],moving[field]),"live lens edit preserves "+field)
        check(rig.supported_pose(),"edited moving lens has supported pose")
    var remaining := absf(rig.target_yaw_degrees-rig.yaw_degrees)
    rig.update(0.15,spawn+Vector3(15,0,-7),false,0.0)
    check(absf(rig.target_yaw_degrees-rig.yaw_degrees)<remaining,"yaw continues converging after lens edit")
    for saved_test_yaw in [false,true]:
        rig.select_variant("O",spawn+Vector3(7,0,-2))
        if saved_test_yaw: rig.set_test_yaw(-2.0)
        else:
            rig.clear_test_yaw()
            rig.update(0.1,spawn+Vector3(16,0,-3),false,0.0)
        var saved: Dictionary = rig.pose_snapshot()
        for id in IDS:
            rig.select_variant(id,spawn)
            rig.set_lens("radius",18.0)
            rig.set_lens("fov",25.0)
            rig.set_test_yaw(4.0)
            rig.set_offset(Vector3(20,0,3))
        check(same(saved.lens_profiles.O,rig.lens_profiles.O)==false,"snapshot owns a deep profile copy")
        rig.restore_pose(saved)
        check(same(rig.pose_snapshot(),saved),"snapshot restores every declared pose field including lens profiles and yaw override")
        check(rig.supported_pose(),"restored lens is supported")
        rig.set_lens("radius",19.0)
        check(not same(rig.lens_profiles,saved.lens_profiles),"restored profiles do not alias the snapshot")
        rig.restore_pose(saved)
    for id in IDS:
        rig.select_variant(id,spawn)
        rig.reset_lens()

func projection_checks(rig: RefCounted, camera: Camera3D, virtual_camera: Camera3D, parallax: RefCounted, anchors: Dictionary, spawn: Vector3) -> void:
    for id in IDS:
        parallax.select_variant(id)
        rig.select_variant(id,spawn)
        parallax.change("mode","artistic")
        for radius in [18.0,30.0,45.0]:
            for fov in [25.0,35.0,60.0]:
                check(rig.set_lens("radius",radius) and rig.set_lens("fov",fov),id+" matrix lens accepted")
                for yaw in [-4.0,0.0,4.0]:
                    rig.set_test_yaw(yaw)
                    check(is_equal_approx(rig.yaw_degrees,yaw if id=="O" else 0.0),id+" yaw request follows its variant contract")
                    for ratio in [0.0,0.5,1.0,1.5,2.0]:
                        parallax.change("global_strength",ratio)
                        for dx in [-22.0,0.0,22.0]:
                            rig.set_offset(Vector3(dx,0,-1.5))
                            parallax.update(0.0,true)
                            var label := "%s radius=%.0f fov=%.0f yaw=%.0f ratio=%.1f dx=%.0f" % [id,radius,fov,yaw,ratio,dx]
                            projection_cases += 1
                            check(rig.supported_pose() and parallax.compatible,label+" supported")
                            check(is_equal_approx(camera.global_position.distance_to(rig.target+rig.follow_offset),radius),label+" measured distance")
                            check(is_equal_approx(camera.fov,fov),label+" measured FOV")
                            virtual_camera.set_perspective(fov,camera.near,camera.far)
                            virtual_camera.global_transform = camera.global_transform
                            virtual_camera.global_position -= Vector3.RIGHT*dx
                            # Two actual Camera3D projections independently define the
                            # requested screen-X ratio; do not read controller expected_x.
                            for layer in Parallax.Profile.IDS:
                                var point: Vector3 = anchors[layer]
                                var no_follow := virtual_camera.unproject_position(point).x
                                var natural := camera.unproject_position(point).x
                                var expected: float = no_follow+float(ratio)*(natural-no_follow)
                                var actual := camera.unproject_position(parallax.layer_point(layer)).x
                                var error := absf(actual-expected)
                                projection_samples += 1
                                maximum_projection_error = maxf(maximum_projection_error,error)
                                check(error<0.1,label+" representative "+layer+" error="+str(error))
        rig.clear_test_yaw()
        rig.select_variant(id,spawn)
        rig.reset_lens()
        var supported: Dictionary = rig.pose_snapshot()
        camera.fov += 1.0
        check(not rig.supported_pose(),id+" detects external FOV mutation")
        parallax.update(0.0,true)
        check(not parallax.compatible,id+" external FOV cannot silently claim compensation")
        rig.restore_pose(supported)
        camera.global_position += Vector3(0.2,0,0)
        check(not rig.supported_pose(),id+" detects external translation")
        rig.restore_pose(supported)
        camera.rotate_y(deg_to_rad(1.0))
        check(not rig.supported_pose(),id+" detects external rotation")
        rig.restore_pose(supported)
        camera.set_orthogonal(20.0,camera.near,camera.far)
        check(not rig.supported_pose(),id+" detects external projection")
        rig.restore_pose(supported)
        parallax.update(0.0,true)
        check(rig.supported_pose() and parallax.compatible,id+" restores supported compensation after invalid pose")

func make_config(id: String, radius: Variant = 38.0, fov: Variant = 47.0) -> ConfigFile:
    var config := ConfigFile.new()
    config.set_value("meta","schema",1)
    config.set_value("meta","variant",id)
    config.set_value("meta","layout_id",LAYOUT_ID)
    config.set_value("lens","radius",radius)
    config.set_value("lens","fov",fov)
    return config

func rejected_config(settings: RefCounted, rig: RefCounted, config: ConfigFile, label: String) -> void:
    var before: Dictionary = rig.pose_snapshot()
    check(not settings.apply_config(config,rig,LAYOUT_ID),label+" rejected")
    check(same(rig.pose_snapshot(),before),label+" leaves every variant and pose unchanged")

func settings_checks(rig: RefCounted, spawn: Vector3) -> void:
    var settings := LensSettings.new()
    for id in IDS:
        rig.select_variant(id,spawn+Vector3(5,0,-2))
        var others: Dictionary = rig.lens_profiles.duplicate(true)
        var before: Dictionary = rig.pose_snapshot()
        check(settings.apply_config(make_config(id),rig,LAYOUT_ID),id+" valid lens config loads")
        check(same(rig.lens_snapshot(),{"radius":38.0,"fov":47.0}),id+" loads both fields")
        check(rig.follow_offset.is_equal_approx(before.follow_offset) and is_equal_approx(rig.yaw_degrees,before.yaw_degrees),id+" loading preserves pose smoothing")
        for other in IDS:
            if other!=id: check(same(rig.lens_profiles[other],others[other]),id+" config does not modify "+other)
        check(settings.apply_config(make_config(id,18,60),rig,LAYOUT_ID),id+" integer endpoint config accepted")
        for schema in [0,2,1.0,"1",true]:
            var config := make_config(id)
            config.set_value("meta","schema",schema)
            rejected_config(settings,rig,config,id+" bad schema "+str(schema))
        for variant in ["A","D","",15,false,"W" if id!="W" else "F"]:
            var config := make_config(id)
            config.set_value("meta","variant",variant)
            rejected_config(settings,rig,config,id+" bad variant "+str(variant))
        for layout in ["","wrong-layout","0000000000000000000000000000000000000000000000000000000000000000",12,false]:
            var config := make_config(id)
            config.set_value("meta","layout_id",layout)
            rejected_config(settings,rig,config,id+" mismatched layout "+str(layout))
        for section in ["meta","lens"]:
            var extra := make_config(id)
            extra.set_value(section,"unexpected",1)
            rejected_config(settings,rig,extra,id+" unknown "+section+" field")
            var missing_section := make_config(id)
            missing_section.erase_section(section)
            rejected_config(settings,rig,missing_section,id+" missing "+section+" section")
        var extra_section := make_config(id)
        extra_section.set_value("other","value",1)
        rejected_config(settings,rig,extra_section,id+" unknown section")
        for key in ["schema","variant","layout_id"]:
            var config := make_config(id)
            config.erase_section_key("meta",key)
            rejected_config(settings,rig,config,id+" missing meta "+key)
        for key in ["radius","fov"]:
            var missing := make_config(id)
            missing.erase_section_key("lens",key)
            rejected_config(settings,rig,missing,id+" missing lens "+key)
            var substituted := make_config(id)
            substituted.erase_section_key("lens",key)
            substituted.set_value("lens","unknown",30)
            rejected_config(settings,rig,substituted,id+" unknown replaces required "+key)
            var limits: Vector2 = Rig.LENS_LIMITS[key]
            for value in [limits.x-0.01,limits.y+0.01,NAN,INF,-INF,"35",true,Vector2(30,30),[30],{"value":30}]:
                var config := make_config(id,41.0,52.0)
                config.set_value("lens",key,value)
                rejected_config(settings,rig,config,id+" invalid lens field "+key+" "+str(value))
    check(settings.path_for("F")!=settings.path_for("W") and settings.path_for("W")!=settings.path_for("O"),"variants have separate lens settings paths")

func run() -> void:
    root.size = Vector2i(1920,1080)
    var camera := Camera3D.new()
    root.add_child(camera)
    camera.current = true
    var virtual_camera := Camera3D.new()
    root.add_child(virtual_camera)
    var rig := Rig.new()
    var spawn := Vector3(4,1.2,5.8)
    rig.configure(camera,{"target":[4.0,4.0,1.0],"far":1400},spawn)
    default_and_boundary_checks(rig,spawn)
    isolation_and_state_checks(rig,spawn)
    var background := Backdrop.new()
    root.add_child(background)
    var anchors: Dictionary = {}
    var index := 0
    for id in Parallax.Profile.IDS:
        var layer := Node3D.new()
        background.add_child(layer)
        var mesh := MeshInstance3D.new()
        mesh.mesh = BoxMesh.new()
        layer.add_child(mesh)
        mesh.position = Vector3(-8+index*5,-3-index*2,-30-index*25)
        anchors[id] = mesh.global_position
        if id.begins_with("clouds_"): background.cloud_roots[id] = layer
        else: background.layers[id] = layer
        index += 1
    var parallax := Parallax.new()
    parallax.configure(camera,rig,background,"frontal-lens-unit")
    projection_checks(rig,camera,virtual_camera,parallax,anchors,spawn)
    settings_checks(rig,spawn)
    print("FRONTAL_LENS_UNIT checks=",checks," failures=",failures.size()," projection_cases=",projection_cases," projection_samples=",projection_samples," max_error_px=",maximum_projection_error)
    background.free()
    virtual_camera.free()
    camera.free()
    quit(0 if failures.is_empty() else 1)
