extends RefCounted
## Shared physical route. Only the initial reset and final restoration teleport.

static func vector(value: Array) -> Vector3:
    return Vector3(value[0], value[1], value[2])

static func array3(value: Vector3) -> Array:
    return [value.x, value.y, value.z]

static func polygon_area(points: PackedVector2Array) -> float:
    var area := 0.0
    for i in points.size():
        area += points[i].cross(points[(i + 1) % points.size()])
    return absf(area) * 0.5

static func face_metrics(camera: Camera3D, corners: Array[Vector3]) -> Dictionary:
    var polygon := PackedVector2Array()
    for point in corners:
        if camera.is_position_behind(point): return {"area_px":0.0,"visible_area_px":0.0,"width_px":0.0}
        polygon.append(camera.unproject_position(point))
    var size := camera.get_viewport().get_visible_rect().size
    var rectangle := PackedVector2Array([Vector2.ZERO, Vector2(size.x,0), size, Vector2(0,size.y)])
    var clipped := Geometry2D.intersect_polygons(polygon, rectangle)
    var visible_area := 0.0
    var width := 0.0
    for part in clipped:
        visible_area += polygon_area(part)
        var low := INF
        var high := -INF
        for point in part:
            low = minf(low, point.x)
            high = maxf(high, point.x)
        width = maxf(width, high-low)
    return {"area_px":polygon_area(polygon),"visible_area_px":visible_area,"width_px":width,
        "corners":Array(polygon)}

static func observation(scene) -> Dictionary:
    var entry: Dictionary = {}
    for building in scene.layout.buildings:
        if building.id == scene.layout.view_anchors.building_id: entry = building
    if entry.is_empty(): return {"passed":false,"reason":"Missing main building anchor"}
    var origin := vector(entry.position)
    var scale_value := float(entry.scale)
    var half_x := 3.5 * scale_value
    var half_z := 2.5 * scale_value
    var top := origin.y + 6.8 * scale_value
    var left := origin.x-half_x
    var right := origin.x+half_x
    var back := origin.z-half_z
    var front := origin.z+half_z
    var left_face := face_metrics(scene.camera, [Vector3(left,origin.y,back),Vector3(left,origin.y,front),Vector3(left,top,front),Vector3(left,top,back)])
    var right_face := face_metrics(scene.camera, [Vector3(right,origin.y,front),Vector3(right,origin.y,back),Vector3(right,top,back),Vector3(right,top,front)])
    var front_face := face_metrics(scene.camera, [Vector3(left,origin.y,front),Vector3(right,origin.y,front),Vector3(right,top,front),Vector3(left,top,front)])
    var camera_position: Vector3 = scene.camera.global_position
    var side := "left" if camera_position.x < left else ("right" if camera_position.x > right else "front_only")
    var side_metrics: Dictionary = left_face if side == "left" else right_face
    var viewport: Rect2 = scene.get_viewport().get_visible_rect()
    var foot: Vector2 = scene.camera.unproject_position(scene.player.global_position)
    var sprite: Sprite3D = scene.player.sprite
    var height := float(sprite.texture.get_height()) / sprite.vframes
    var width := float(sprite.texture.get_width()) / sprite.hframes
    var center: Vector3 = sprite.global_position + scene.camera.global_basis.y * sprite.offset.y * sprite.pixel_size
    var actor_visible := true
    for x in [-0.5,0.5]:
        for y in [-0.5,0.5]:
            var point: Vector3 = center + scene.camera.global_basis.x * width * sprite.pixel_size * x + scene.camera.global_basis.y * height * sprite.pixel_size * y
            actor_visible = actor_visible and not scene.camera.is_position_behind(point) and viewport.has_point(scene.camera.unproject_position(point))
    var exclusions: Array[RID] = [scene.player.get_rid()]
    for node in scene.get_tree().get_nodes_in_group("movement_only_barrier"):
        if node is CollisionObject3D: exclusions.append(node.get_rid())
    var rays: Array[Dictionary] = []
    for y in [0.9,1.7]:
        var query := PhysicsRayQueryParameters3D.create(camera_position,scene.player.global_position+Vector3.UP*y,1,exclusions)
        var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(query)
        rays.append({"height":y,"clear":hit.is_empty(),"occluder":"" if hit.is_empty() else str(hit.collider.name)})
    var sight_clear: bool = rays[0].clear or rays[1].clear
    return {"camera":scene.rig.pose_diagnostics(),"player":array3(scene.player.global_position),
        "foot_pixel":[foot.x,foot.y],"actor_in_viewport":actor_visible,"actor_sightline_clear":sight_clear,"actor_rays":rays,
        "camera_x":camera_position.x,"left_wall_x":left,"right_wall_x":right,"visible_side":side,
        "geometric_angle_degrees":rad_to_deg(atan2(camera_position.x-origin.x,camera_position.z-origin.z)),
        "left":left_face,"right":right_face,"front":front_face,
        "side_large_enough":side != "front_only" and side_metrics.visible_area_px >= 1500.0 and side_metrics.width_px >= 16.0,
        "scope":"Projected body-wall polygons are clipped to the viewport. Sightlines test physical colliders, excluding invisible movement barriers; rendered visual occlusion still requires image review."}

static func run(scene, capture_dir := "", record := false) -> Dictionary:
    scene.parallax_preview.stop()
    var saved := {"position":scene.player.global_transform,"velocity":scene.player.velocity,
        "scripted":scene.player.scripted_input,"direction":scene.player.scripted_direction,"controls":scene.player.controls_enabled,
        "animation":scene.player.animation_clock,"facing":scene.player.facing,"walking":scene.player.walking,"frame":scene.player.sprite.frame,
        "clock":scene.clock_frozen,"elapsed":scene.elapsed,"period":scene.lighting.preset_id,
        "wind_enabled":scene.background.wind_enabled,"wind_phases":scene.background.wind_phases.duplicate(),"cloud_time":scene.background.cloud_time,
        "follow":scene.follow,"tour":scene.tour,"frozen":scene.rig.frozen,"rig_enabled":scene.rig.enabled,
        "pose":scene.rig.pose_snapshot(),"running":scene.route_running,"cancelled":scene.route_cancelled,
        "hud":scene.hud.container.visible,"panel":scene.variant_panel.visible,
        "dof_panel":scene.dof_panel.visible,"parallax_panel":scene.parallax_panel.visible,
        "dialogue":scene.hud.dialogue.visible,"nearest":scene.nearest.duplicate(true),
        "focus":scene.dof.focus_depth,"manual":scene.dof.manual_depth,"focus_mode":scene.dof.mode}
    scene.close_tuning()
    scene.hud.close_dialogue()
    scene.route_running = true
    scene.route_cancelled = false
    scene.player.global_position = vector(scene.layout.player_spawn)
    scene.player.velocity = Vector3.ZERO
    scene.player.scripted_input = true
    scene.player.scripted_direction = Vector2.ZERO
    scene.follow = true
    scene.tour = false
    scene.rig.frozen = false
    scene.rig.enabled = true
    scene.clock_frozen = not record
    if record: scene.lighting.apply_preset("dusk")
    scene.sync_input_lock()
    # Shared comparisons always use the original lens, then restore user tuning.
    scene.rig.reset_lens()
    scene.rig.select_variant(scene.variant_id, scene.player.global_position)
    var recoveries: int = scene.recovery_count
    var result := {"passed":true,"steps":[],"trajectory":[],"side_observations":{},"period_changes":[],"frames":0,"recoveries":0,"cancelled":false,
        "variant":scene.variant_id,"recording":record,"speed_m_s":scene.player.SPEED,
        "teleports":"Initial spawn reset and final state restoration only. Every route stop is reached with CharacterBody3D.move_and_slide."}
    if record: result.period_changes.append({"stop":"spawn","period":"dusk","frame":0})
    if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
    for i in range(30): await scene.get_tree().physics_frame
    for stop in scene.layout.route_stops:
        var target := vector(stop.position)
        var reached := false
        var stalled := 0
        var previous: Vector3 = scene.player.global_position
        for frame in range(1800):
            if scene.route_cancelled: break
            var delta: Vector3 = target-scene.player.global_position
            delta.y = 0
            if delta.length() < 0.16:
                reached = true
                break
            scene.player.scripted_direction = Vector2(delta.x,delta.z).normalized()
            await scene.get_tree().physics_frame
            result.frames += 1
            if scene.player.global_position.distance_to(previous) < .0001: stalled += 1
            else: stalled = 0
            previous = scene.player.global_position
            if result.frames % 30 == 0:
                var pixel: Vector2 = scene.camera.unproject_position(previous+Vector3.UP)
                result.trajectory.append({"frame":result.frames,"stop":stop.id,"position":array3(previous),"screen":[pixel.x,pixel.y],"camera":scene.rig.pose_diagnostics(),"period":scene.lighting.preset_id,"cloud_time":scene.background.cloud_time})
            if stalled > 240: break
        scene.player.scripted_direction = Vector2.ZERO
        for i in range(90 if str(stop.kind).begins_with("view_") else 12):
            if scene.route_cancelled: break
            await scene.get_tree().physics_frame
        var actual: Vector3 = scene.player.global_position
        var ok: bool = reached and absf(actual.y-target.y) < .36 and not scene.route_cancelled
        var item := {"id":stop.id,"kind":stop.kind,"target":array3(target),"actual":array3(actual),"on_floor":scene.player.is_on_floor()}
        if record and reached and stop.id in ["stair_top","dock_sign_read"]:
            var next_period: String = "day" if stop.id == "stair_top" else "night"
            scene.lighting.apply_preset(next_period)
            result.period_changes.append({"stop":stop.id,"period":next_period,"frame":result.frames})
        item["period"] = scene.lighting.preset_id
        if stop.kind == "interaction" and ok:
            var nearest: Dictionary = scene.nearest_interaction()
            item["nearest_id"] = nearest.get("id","")
            scene.interact()
            item["interaction"] = item.nearest_id == stop.interaction_id and scene.hud.dialogue.visible and not scene.player.controls_enabled
            ok = ok and item.interaction
            if scene.hud.dialogue.visible: scene.interact()
        if str(stop.kind).begins_with("view_"):
            var observed := observation(scene)
            result.side_observations[stop.kind] = observed
            ok = ok and observed.actor_in_viewport and observed.actor_sightline_clear
            if stop.kind in ["view_left","view_right"]:
                ok = ok and observed.visible_side == str(stop.kind).trim_prefix("view_") and observed.side_large_enough
            if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
                var name: String = "route-%s-%s.png" % [scene.variant_id,stop.id]
                item["image"] = name
                ok = bool(await scene.capture(capture_dir.path_join(name))) and ok
        item["passed"] = ok
        result.steps.append(item)
        result.passed = result.passed and ok
        print("FRONTAL_ROUTE ",scene.variant_id," ",stop.id," ",ok," ",actual)
        if not reached or scene.route_cancelled: break
    result.cancelled = scene.route_cancelled
    result.recoveries = scene.recovery_count-recoveries
    result.passed = result.passed and result.recoveries == 0 and not result.cancelled and result.steps.size() == scene.layout.route_stops.size() and scene.player.is_on_floor()
    if result.cancelled: result["reason"] = "Cancelled with Escape; previous state restored."
    scene.player.global_transform = saved.position
    scene.player.velocity = saved.velocity
    scene.player.scripted_input = saved.scripted
    scene.player.scripted_direction = saved.direction
    scene.player.animation_clock = saved.animation
    scene.player.facing = saved.facing
    scene.player.walking = saved.walking
    scene.player.update_animation()
    scene.clock_frozen = saved.clock
    scene.elapsed = saved.elapsed
    scene.background.wind_enabled = saved.wind_enabled
    scene.background.wind_phases.assign(saved.wind_phases)
    scene.background.cloud_time = saved.cloud_time
    scene.background.advance(0.0)
    scene.follow = saved.follow
    scene.tour = saved.tour
    scene.rig.frozen = saved.frozen
    scene.rig.enabled = saved.rig_enabled
    scene.lighting.apply_preset(saved.period)
    scene.rig.restore_pose(saved.pose)
    scene.parallax.update(0.0,true)
    scene.dof.focus_depth = saved.focus
    scene.dof.manual_depth = saved.manual
    scene.dof.mode = saved.focus_mode
    scene.dof.apply()
    scene.route_running = saved.running
    scene.route_cancelled = saved.cancelled
    scene.hud.container.visible = saved.hud
    scene.variant_panel.visible = saved.panel
    scene.dof_panel.visible = saved.dof_panel
    scene.parallax_panel.visible = saved.parallax_panel
    scene.nearest = saved.nearest
    if saved.dialogue and not saved.nearest.is_empty(): scene.hud.show_dialogue(saved.nearest)
    scene.player.controls_enabled = saved.controls
    if not capture_dir.is_empty():
        var file := FileAccess.open(capture_dir.path_join("route-"+scene.variant_id+".json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(result,"  ")+"\n")
    return result
