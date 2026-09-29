extends RefCounted
## Real GPU fixtures. Capture success is separate from measured image acceptance.
const IDS := ["ridge_near", "ridge_mid", "ridge_far", "clouds_near", "clouds_far"]

static func run(scene, output: String) -> Dictionary:
    if DisplayServer.get_name() == "headless":
        return {"passed":false, "capture_success":false, "reason":"A real GPU is required."}
    var previous_process: bool = scene.is_processing()
    var previous_physics: bool = scene.player.is_physics_processing()
    scene.parallax_preview.stop()
    var pose: Dictionary = scene.rig.pose_snapshot()
    var settings: Dictionary = scene.parallax.snapshot()
    var dof_state := {"enabled":scene.dof.enabled, "near_enabled":scene.dof.near_enabled,
        "far_enabled":scene.dof.far_enabled, "master_enabled":scene.dof.master_enabled,
        "mode":scene.dof.mode, "focus_depth":scene.dof.focus_depth,
        "manual_depth":scene.dof.manual_depth, "profile":scene.dof.profile}
    var old_effects: bool = scene.lighting.effects_enabled
    var env: Environment = scene.lighting.environment
    var env_state: Dictionary = {}
    for key in ["background_mode", "background_color", "tonemap_mode", "glow_enabled", "ssao_enabled", "volumetric_fog_enabled"]:
        env_state[key] = env.get(key)
    var visibility: Array[Dictionary] = []
    for node in [scene.get_node("World"), scene.player, scene.impostor, scene.hud.container]:
        visibility.append({"node":node, "visible":node.visible})
        node.hide()
    for node in scene.get_children():
        if node is Sprite3D:
            visibility.append({"node":node, "visible":node.visible})
            node.hide()
    var background_visible: bool = scene.background.visible
    scene.background.show()
    for node in scene.background.find_children("*", "GeometryInstance3D", true, false):
        visibility.append({"node":node, "visible":node.visible})
        node.hide()
    scene.set_process(false)
    scene.player.set_physics_process(false)
    scene.lighting.set_effects(false)
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color.BLACK
    env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    scene.background.wind_enabled = false
    scene.rig.set_test_yaw(0.0)
    scene.rig.set_offset(Vector3.ZERO)
    scene.parallax.profile.mode = "natural"
    scene.parallax.update(0.0, true)
    var dof_result: Dictionary = await checkerboards(scene, output)
    scene.dof.enabled = false
    scene.dof.apply()
    var marker_result: Dictionary = await markers(scene, output)
    for key in settings: scene.parallax.change(key, settings[key])
    scene.rig.restore_pose(pose)
    scene.parallax.update(0.0, true)
    scene.lighting.set_effects(old_effects)
    for key in env_state: env.set(key, env_state[key])
    for key in dof_state: scene.dof.set(key, dof_state[key])
    scene.dof.apply()
    for entry in visibility:
        if is_instance_valid(entry.node): entry.node.visible = entry.visible
    scene.background.visible = background_visible
    scene.set_process(previous_process)
    scene.player.set_physics_process(previous_physics)
    return {"passed":bool(dof_result.capture_success) and bool(marker_result.capture_success),
        "capture_success":bool(dof_result.capture_success) and bool(marker_result.capture_success),
        "image_subdir":output.get_file(),
        "variant":scene.experiment_id,
        "projection":"orthographic" if scene.camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective",
        "dof":dof_result, "markers":marker_result,
        "scope":"GPU checkerboards and temporary layer representative markers. Image metrics decide acceptance; captures alone do not prove orthographic DOF support."}

static func checkerboards(scene, output: String) -> Dictionary:
    var holder := Node3D.new()
    scene.add_child(holder)
    var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
    for y in range(128):
        for x in range(128):
            image.set_pixel(x, y, Color(0.85,0.85,0.85) if ((x >> 3) + (y >> 3)) % 2 == 0 else Color(0.12,0.12,0.12))
    var material := StandardMaterial3D.new()
    material.albedo_texture = ImageTexture.create_from_image(image)
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    material.disable_fog = true
    var size: Vector2 = scene.get_viewport().get_visible_rect().size
    var rois: Array[Dictionary] = []
    var depths := [20.0, 42.0, 100.0]
    for index in range(3):
        var depth: float = depths[index]
        var center := Vector2(size.x * [0.25, 0.5, 0.75][index], size.y * 0.5)
        var point: Vector3 = scene.camera.project_position(center, depth)
        var left: Vector3 = scene.camera.project_position(center - Vector2(90,0), depth)
        var right: Vector3 = scene.camera.project_position(center + Vector2(90,0), depth)
        var top: Vector3 = scene.camera.project_position(center - Vector2(0,90), depth)
        var bottom: Vector3 = scene.camera.project_position(center + Vector2(0,90), depth)
        var mesh := QuadMesh.new()
        mesh.size = Vector2(left.distance_to(right), top.distance_to(bottom))
        var card := MeshInstance3D.new()
        card.mesh = mesh
        card.material_override = material
        card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        holder.add_child(card)
        card.global_transform = Transform3D(scene.camera.global_basis, point)
        rois.append({"name":["near","focus","far"][index], "box":[int(center.x)-64,int(center.y)-64,int(center.x)+64,int(center.y)+64], "depth_m":depth})
    scene.dof.master_enabled = true
    scene.dof.enabled = true
    scene.dof.mode = "manual"
    scene.dof.manual_depth = 42.0
    scene.dof.focus_depth = 42.0
    scene.dof.select_profile("standard")
    var success := true
    var images: Dictionary = {}
    var modes := {"off":[false,false], "near":[true,false], "far":[false,true], "both":[true,true]}
    for id in modes:
        scene.dof.near_enabled = modes[id][0]
        scene.dof.far_enabled = modes[id][1]
        scene.dof.apply()
        for frame in range(8): await RenderingServer.frame_post_draw
        var name: String = "dof-fixture-" + id + ".png"
        var ok: bool = await scene.capture(output.path_join(name))
        images[id] = name
        success = success and ok
    holder.free()
    return {"capture_success":success, "images":images, "rois":rois,
        "requested_near_and_far":true,
        "scope":"Equal 180-pixel checkerboards placed by Camera3D.project_position at 20, 42 and 100m. Native blur is measured, including possible orthographic limitations."}

static func markers(scene, output: String) -> Dictionary:
    var original_points: Dictionary = {}
    var original_depths: Dictionary = {}
    for id in IDS:
        original_points[id] = scene.parallax.states[id].point
        original_depths[id] = maxf(15.0, scene.dof.depth(scene.parallax.layer_point(id)))
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.disable_fog = true
    material.albedo_color = Color.WHITE
    var cases: Array[Dictionary] = []
    var success := true
    var size: Vector2 = scene.get_viewport().get_visible_rect().size
    var yaw_values: Array = [-6.0, 0.0, 6.0] if scene.experiment_id in ["B", "C"] else [0.0]
    for yaw in yaw_values:
        scene.rig.set_test_yaw(float(yaw))
        scene.rig.set_offset(Vector3.ZERO)
        scene.parallax.profile.mode = "natural"
        scene.parallax.update(0.0, true)
        var items: Array[MeshInstance3D] = []
        var base_points: Dictionary = {}
        var baseline_pixels: Dictionary = {}
        for index in IDS.size():
            var id: String = IDS[index]
            var center := Vector2(size.x * (0.12 + index * 0.19), size.y * 0.5)
            var depth: float = original_depths[id]
            var point: Vector3 = scene.camera.project_position(center, depth)
            var left: Vector3 = scene.camera.project_position(center - Vector2(11.5,0), depth)
            var right: Vector3 = scene.camera.project_position(center + Vector2(11.5,0), depth)
            var top: Vector3 = scene.camera.project_position(center - Vector2(0,15.5), depth)
            var bottom: Vector3 = scene.camera.project_position(center + Vector2(0,15.5), depth)
            var marker := MeshInstance3D.new()
            var mesh := QuadMesh.new()
            mesh.size = Vector2(left.distance_to(right), top.distance_to(bottom))
            marker.mesh = mesh
            marker.material_override = material
            marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            var layer: Node3D = scene.parallax.states[id].node
            layer.add_child(marker)
            marker.global_transform = Transform3D(scene.camera.global_basis, point)
            scene.parallax.states[id].point = layer.to_local(point)
            base_points[id] = point
            baseline_pixels[id] = center
            items.append(marker)
        for frame in range(3): await RenderingServer.frame_post_draw
        var base_name := "markers-yaw%d-base.png" % int(yaw)
        var base_ok: bool = await scene.capture(output.path_join(base_name))
        success = success and base_ok
        for gain in [0.0, 0.5, 1.0, 1.5, 2.0]:
            scene.parallax.profile.mode = "artistic"
            scene.parallax.profile.global_strength = gain
            for id in IDS: scene.parallax.profile.layer_gains[id] = 1.0
            for dx in [-2.0, 2.0]:
                scene.rig.set_offset(scene.rig.initial_right * dx)
                var expected: Array[Dictionary] = []
                var actual_inverse: Transform3D = scene.camera.get_camera_transform().affine_inverse()
                var virtual_transform: Transform3D = scene.camera.get_camera_transform()
                virtual_transform.origin -= scene.rig.horizontal_follow
                var virtual_inverse := virtual_transform.affine_inverse()
                var focal: float = scene.camera.get_camera_projection().x.x * size.x * 0.5
                var perspective: bool = scene.camera.projection == Camera3D.PROJECTION_PERSPECTIVE
                for id in IDS:
                    var point: Vector3 = base_points[id]
                    var actual: Vector3 = actual_inverse * point
                    var virtual: Vector3 = virtual_inverse * point
                    var natural_x: float = focal * actual.x / -actual.z if perspective else focal * actual.x
                    var virtual_x: float = focal * virtual.x / -virtual.z if perspective else focal * virtual.x
                    var requested_x: float = virtual_x + gain * (natural_x - virtual_x)
                    var metres_per_pixel: float = -actual.z / focal if perspective else 1.0 / focal
                    var desired_point: Vector3 = point + scene.camera.global_basis.x * (requested_x - natural_x) * metres_per_pixel
                    var projected: Vector2 = scene.camera.unproject_position(desired_point)
                    var baseline: Vector2 = baseline_pixels[id]
                    expected.append({"layer":id, "base_pixel":[baseline.x,baseline.y],
                        "expected_pixel":[projected.x,projected.y], "depth":-actual.z,
                        "natural_x":natural_x+size.x*0.5, "virtual_x":virtual_x+size.x*0.5,
                        "representative_x":requested_x+size.x*0.5})
                scene.parallax.update(0.0, true)
                for frame in range(3): await RenderingServer.frame_post_draw
                var name := "markers-yaw%d-k%d-dx%d.png" % [int(yaw), int(gain*100), int(dx)]
                var ok: bool = await scene.capture(output.path_join(name))
                success = success and ok
                cases.append({"image":name, "base_image":base_name, "yaw":yaw,
                    "gain":gain, "dx":dx, "markers":expected})
        for marker in items: marker.free()
        for id in IDS: scene.parallax.states[id].point = original_points[id]
    return {"capture_success":success, "cases":cases, "tolerance_px":0.8,
        "scope":"Opaque white markers temporarily become each layer's representative point, at its natural depth. Expected pixels are computed independently from the same-orientation virtual camera without horizontal follow; actual GPU centroids are measured externally."}
