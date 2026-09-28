extends RefCounted
## Coverage calculations are separate from the actual GPU extreme-state captures.
static func screen_bounds(camera: Camera3D, mesh: MeshInstance3D) -> Rect2:
    var bounds := mesh.get_aabb()
    var result := Rect2(camera.unproject_position(mesh.to_global(bounds.get_endpoint(0))),Vector2.ZERO)
    for i in range(1,8): result = result.expand(camera.unproject_position(mesh.to_global(bounds.get_endpoint(i))))
    return result

static func run(scene, runner) -> Dictionary:
    var c = scene.parallax
    var frames: Array[Dictionary] = []
    var width: float = scene.get_viewport().get_visible_rect().size.x
    var original: Transform3D = scene.camera.global_transform
    scene.rig.frozen = true
    scene.clock_frozen = true
    scene.background.wind_enabled = false
    for mode in ["zero","maximum","inverted"]:
        c.reset_all()
        c.change("mode","artistic")
        c.change("global_strength",0.0 if mode == "zero" else 2.0)
        if mode == "inverted": c.change("ridge_near",0.0)
        for side in [-1,1]:
            scene.rig.set_offset(c.right*7.5*side)
            c.update(0.0,true)
            var case := {"mode":mode,"side":side,"bounds":{}}
            for id in ["ridge_near","ridge_mid","ridge_far"]:
                var mesh: MeshInstance3D = c.states[id].node.find_children("*","MeshInstance3D",true,false)[0]
                var rect := screen_bounds(scene.camera,mesh)
                runner.check(rect.position.x < -32 and rect.end.x > width+32,"coverage_%s_%s_%d"%[mode,id,side])
                case.bounds[id] = [rect.position.x,rect.end.x]
            frames.append(case)
            if runner.real_gpu:
                scene.hud.container.hide()
                await runner.snap(scene,"extreme-%s-%d"%[mode,side])
    c.reset_all()
    scene.rig.set_offset(Vector3.ZERO)
    c.update(0,true)
    for layer in range(2):
        var span := 585.0 if layer == 0 else 1620.0
        for side in [-1,1]:
            scene.rig.set_offset(c.right*7.5*side)
            c.update(0,true)
            var mesh: MeshInstance3D = scene.background.clouds[layer*int(scene.background.config.cloud_count_per_layer)].node
            var old := mesh.position
            for edge in [-1,1]:
                mesh.position.x = span*0.5*edge
                var rect := screen_bounds(scene.camera,mesh)
                runner.check(rect.end.x < -32 or rect.position.x > width+32,"cloud_wrap_offscreen_%d_%d_%d"%[layer,side,edge])
            mesh.position = old
    scene.camera.global_transform = original
    c.reset_all()
    c.update(0,true)
    return {"cases":frames,"scope":"AABB screen coverage and cloud-wrap edge checks; GPU extreme captures reviewed separately."}
