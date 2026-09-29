extends SceneTree
## Quantify the documented whole-layer approximation without a GPU fixture.
func _initialize() -> void:
    call_deferred("sample")

func sample() -> void:
    var scene = load("res://scenes/reference_scene.tscn").instantiate()
    root.add_child(scene)
    scene.set_process(false)
    scene.player.set_physics_process(false)
    var rows: Array=[]
    for variant in ["A","B","C","D"]:
        scene.select_experiment(variant)
        for yaw in ([-6.0,0.0,6.0] if variant in ["B","C"] else [0.0]):
            scene.rig.set_test_yaw(yaw)
            for gain in [0.0,.5,1.0,1.5,2.0]:
                scene.parallax.change("mode","artistic")
                scene.parallax.change("global_strength",gain)
                for layer in scene.parallax.Profile.IDS: scene.parallax.change(layer,1.0)
                for dx in [-7.0,-2.0,0.0,2.0,7.0]:
                    scene.rig.set_offset(scene.rig.initial_right*dx)
                    scene.parallax.update(0,true)
                    for layer in scene.parallax.Profile.IDS:
                        rows.append({"variant":variant,"yaw":yaw,"gain":gain,"dx":dx,"layer":layer,"samples":scene.parallax.layer_sample_errors(layer),"visible_samples":visible_errors(scene,layer)})
    var output := ProjectSettings.globalize_path("res://build/p9-experiments/layer-approximation.json")
    var file:=FileAccess.open(output,FileAccess.WRITE)
    file.store_string(JSON.stringify({"scope":"Actual layer mesh bounds in the current scene. Representative X is exact; this records other mesh points. Ratios here are total gain, not D default per-layer gains.","samples":rows},"  ")+"\n")
    file.close()
    print("P9_LAYER_SAMPLES ",rows.size())
    scene.queue_free()
    for i in range(5):await process_frame
    quit(0)

func visible_errors(scene, id: String) -> Dictionary:
    var state: Dictionary=scene.parallax.states[id]
    var node: Node3D=state.node
    var inverse: Transform3D=scene.camera.get_camera_transform().affine_inverse()
    var virtual_transform: Transform3D=scene.camera.get_camera_transform()
    virtual_transform.origin-=scene.rig.horizontal_follow
    var virtual_inverse:=virtual_transform.affine_inverse()
    var focal: float=scene.camera.get_camera_projection().x.x*scene.get_viewport().get_visible_rect().size.x*.5
    var perspective: bool=scene.camera.projection==Camera3D.PROJECTION_PERSPECTIVE
    var maximum:=0.0
    var count:=0
    for mesh in node.find_children("*","MeshInstance3D",true,false):
        var bounds: AABB=mesh.get_aabb()
        for tx in [0.0,.5,1.0]:
            for tz in [0.0,.5,1.0]:
                var world: Vector3=mesh.to_global(bounds.position+bounds.size*Vector3(tx,.5,tz))
                if not scene.camera.is_position_in_frustum(world):continue
                var original: Vector3=state.base*node.to_local(world)
                var a: Vector3=inverse*original
                var v: Vector3=virtual_inverse*original
                if -a.z<=scene.camera.near or -v.z<=scene.camera.near:continue
                var nx: float=scene.parallax.projected_x(a,focal,perspective)
                var vx: float=scene.parallax.projected_x(v,focal,perspective)
                var expected: float=vx+scene.parallax.current[id]*(nx-vx)
                var actual: float=scene.parallax.projected_x(inverse*world,focal,perspective)
                maximum=maxf(maximum,absf(actual-expected))
                count+=1
    return {"count":count,"max_error_px":maximum,"scope":"Only current camera-frustum-visible actual mesh bound sample points; full unfiltered bounds remain in samples."}
