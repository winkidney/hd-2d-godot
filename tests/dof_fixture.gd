extends RefCounted
## Temporary image-quality fixture. No filesystem changes outside the output folder.
static func run(scene, output: String) -> Dictionary:
    var holder := Node3D.new()
    scene.add_child(holder)
    scene.get_node("World").hide()
    scene.background.hide()
    scene.player.hide()
    scene.get_node("Waykeeper").hide()
    scene.lighting.set_effects(false)
    scene.lighting.environment.background_mode = Environment.BG_COLOR
    scene.lighting.environment.background_color = Color(0.1,0.1,0.1)
    scene.dof.master_enabled = true
    scene.dof.mode = "manual"
    scene.dof.manual_depth = 42.0
    scene.dof.focus_depth = 42.0
    scene.dof.select_profile("standard")
    var image := Image.create(128,128,false,Image.FORMAT_RGB8)
    for y in range(128):
        for x in range(128):
            image.set_pixel(x,y,Color(0.85,0.85,0.85) if ((x>>3)+(y>>3))%2 == 0 else Color(0.12,0.12,0.12))
    var texture := ImageTexture.create_from_image(image)
    var size: Vector2 = scene.get_viewport().get_visible_rect().size
    var focal: float = size.y*.5/tan(deg_to_rad(scene.camera.fov)*.5)
    var rois: Array[Dictionary] = []
    var depths := [20.0,42.0,100.0]
    for i in range(3):
        var depth: float = depths[i]
        var cx: float = size.x * [0.25,0.5,0.75][i]
        var card := MeshInstance3D.new()
        var mesh := QuadMesh.new()
        mesh.size = Vector2.ONE * 180.0*depth/focal
        card.mesh = mesh
        var material := StandardMaterial3D.new()
        material.albedo_texture = texture
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
        card.material_override = material
        holder.add_child(card)
        var point: Vector3 = scene.camera.get_camera_transform() * Vector3((cx-size.x*.5)*depth/focal,0,-depth)
        card.global_transform = Transform3D(scene.camera.global_basis,point)
        rois.append({"name":["near","focus","far"][i],"box":[int(cx)-64,int(size.y*.5)-64,int(cx)+64,int(size.y*.5)+64],"depth_m":depth})
    var success := true
    var states := {"off":[false,false],"near":[true,false],"far":[false,true],"both":[true,true]}
    scene.dof.enabled = true
    for id in states:
        scene.dof.near_enabled = states[id][0]
        scene.dof.far_enabled = states[id][1]
        scene.dof.apply()
        for frame in range(16): await RenderingServer.frame_post_draw
        var saved: bool = await scene.capture(output.path_join("fixture-"+id+".png"))
        success = success and saved
    holder.queue_free()
    scene.get_node("World").show()
    scene.background.show()
    scene.player.show()
    scene.get_node("Waykeeper").show()
    scene.lighting.environment.background_mode = Environment.BG_SKY
    scene.lighting.set_effects(true)
    scene.dof.near_enabled = true
    scene.dof.far_enabled = true
    scene.dof.mode = "protected"
    scene.dof.focus_depth = scene.dof.depth(scene.player.position+Vector3.UP)
    scene.dof.apply()
    return {"capture_success":success,"rois":rois,"scope":"Three equal-screen-size checkerboards, native near/focus/far DOF; image metrics are evaluated separately"}
