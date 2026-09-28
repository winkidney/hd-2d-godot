extends RefCounted
## White markers ride actual layer roots; image centroids are measured externally.
static func run(scene, folder: String) -> Dictionary:
    var saved: Array[Dictionary] = []
    for node in scene.background.find_children("*","GeometryInstance3D",true,false):
        saved.append({"node":node,"visible":node.visible})
        node.hide()
    for node in [scene.get_node("World"),scene.player,scene.get_node("Waykeeper")]:
        saved.append({"node":node,"visible":node.visible})
        node.hide()
    var env: Environment = scene.lighting.environment
    var old_env := {"background_mode":env.background_mode,"background_color":env.background_color,"tonemap_mode":env.tonemap_mode}
    var effects: bool = scene.lighting.effects_enabled
    scene.lighting.set_effects(false)
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color.BLACK
    env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    scene.rig.set_offset(Vector3.ZERO)
    scene.parallax.reset_all()
    scene.background.wind_enabled = false
    scene.parallax.update(0,true)
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.disable_fog = true
    material.albedo_color = Color.WHITE
    var markers: Array[MeshInstance3D] = []
    var metadata: Array[Dictionary] = []
    var viewport_size: Vector2 = scene.get_viewport().get_visible_rect().size
    var focal: float = scene.camera.get_camera_projection().x.x*viewport_size.x*0.5
    var fy: float = scene.camera.get_camera_projection().y.y*viewport_size.y*0.5
    var index := 0
    for id in scene.parallax.Profile.IDS:
        var depth: float = scene.dof.depth(scene.parallax.layer_point(id))
        var x := 240.0 + index*340.0
        var y := viewport_size.y*0.5
        var view_point := Vector3((x-viewport_size.x*0.5)*depth/focal,0,-depth)
        var marker := MeshInstance3D.new()
        var mesh := QuadMesh.new()
        mesh.size = Vector2(23.0*depth/focal,31.0*depth/fy)
        marker.mesh = mesh
        marker.material_override = material
        marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        scene.parallax.states[id].node.add_child(marker)
        marker.global_transform = Transform3D(scene.camera.global_basis,scene.camera.get_camera_transform()*view_point)
        markers.append(marker)
        metadata.append({"layer":id,"x":x,"y":y,"depth":depth,"focal":focal})
        index += 1
    for i in range(6): await RenderingServer.frame_post_draw
    var success: bool = await scene.capture(folder.path_join("markers-base.png"))
    var cases: Array[Dictionary] = []
    scene.parallax.profile.mode = "artistic"
    for k in [0.0,0.5,1.0,1.5,2.0]:
        scene.parallax.profile.global_strength = k
        for dx in [-2.0,2.0]:
            scene.rig.set_offset(scene.parallax.right*dx)
            scene.parallax.update(0,true)
            for i in range(3): await RenderingServer.frame_post_draw
            var name := "markers-k%d-dx%d.png"%[int(k*100),int(dx)]
            var ok: bool = await scene.capture(folder.path_join(name))
            success = success and ok
            cases.append({"image":name,"k":k,"dx":dx})
    for marker in markers: marker.queue_free()
    for entry in saved: entry.node.visible = entry.visible
    for key in old_env: env.set(key,old_env[key])
    scene.lighting.set_effects(effects)
    scene.parallax.reset_all()
    scene.rig.set_offset(Vector3.ZERO)
    scene.parallax.update(0,true)
    for i in range(6): await scene.get_tree().process_frame
    var result := {"passed":success,"markers":metadata,"cases":cases,"scope":"Actual layer-root motion with isolated opaque GPU markers; separate from scene beauty captures."}
    var file := FileAccess.open(folder.path_join("markers.json"),FileAccess.WRITE)
    file.store_string(JSON.stringify(result))
    file.close()
    return result
