extends RefCounted
## One deterministic, physical route used by the panel, tests and movie capture.
const STOPS := [
    ["bridge_approach",Vector3(3,1.2,3.5)], ["bridge",Vector3(-7,1.2,3.5)],
    ["west",Vector3(-20,1.2,3.5)], ["bridge_return",Vector3(3,1.2,3.5)],
    ["east",Vector3(22,1.2,3.5)], ["central_bottom",Vector3(2,1.2,.3)],
    ["central_up",Vector3(2,4,-5.8)], ["upper_npc",Vector3(5.4,4,-6.8)],
    ["central_return",Vector3(2,4,-5.8)], ["central_down",Vector3(2,1.2,.3)],
    ["market_bottom",Vector3(17.5,1.2,3.2)], ["market_up",Vector3(17.5,4,-3)],
    ["market_down",Vector3(17.5,1.2,3.2)], ["merchant",Vector3(8,1.2,.8)],
    ["dock_approach",Vector3(0,1.2,9.5)], ["dock_stair",Vector3(0,1.2,12)],
    ["dock_down",Vector3(-5.3,-.3,12)], ["dock_up",Vector3(0,1.2,12)],
    ["return",Vector3(3,1.2,6.7)]]

static func run(scene, capture_dir := "", record := false) -> Dictionary:
    var prior_scripted: bool = scene.player.scripted_input
    var prior_clock: bool = scene.clock_frozen
    var prior_time: String = scene.lighting.preset_id
    var prior_follow: bool = scene.follow
    var prior_tour: bool = scene.tour
    var prior_frozen: bool = scene.rig.frozen
    scene.experiment_route_cancelled = false
    scene.close_tuning()
    scene.hud.close_dialogue()
    scene.player.position = scene.to_vector(scene.layout.player_spawn)
    scene.player.velocity = Vector3.ZERO
    scene.player.scripted_input = true
    scene.player.scripted_direction = Vector2.ZERO
    scene.follow = true
    scene.tour = false
    scene.rig.frozen = false
    scene.clock_frozen = true
    scene.rig.select_variant(scene.experiment_id, scene.player.position)
    var original_recoveries: int = scene.recovery_count
    for frame in range(30): await scene.get_tree().physics_frame
    var result := {"passed":true,"steps":[],"frames":0,"recoveries":0,"speed_m_s":scene.player.SPEED,"teleports":"Initial spawn reset only; all stops reached through CharacterBody3D physics.","trajectory":[]}
    for step_index in STOPS.size():
        var step: Array = STOPS[step_index]
        if record and step_index in [0,5,14]:
            scene.lighting.apply_preset({0:"dusk",5:"day",14:"night"}[step_index])
        var reached := false
        for frame in range(1800):
            if scene.experiment_route_cancelled:
                result["reason"]="Cancelled with Escape."
                break
            var delta: Vector3 = step[1] - scene.player.position
            delta.y = 0
            if delta.length() < .16:
                reached = true
                break
            scene.player.scripted_direction = Vector2(delta.x,delta.z).normalized()
            await scene.get_tree().physics_frame
            result.frames += 1
            if result.frames % 30 == 0:
                var pos: Vector3 = scene.player.position
                var screen: Vector2 = scene.camera.unproject_position(pos+Vector3.UP)
                result.trajectory.append({"frame":result.frames,"position":[pos.x,pos.y,pos.z],"screen":[screen.x,screen.y],"yaw":scene.rig.yaw_degrees,"camera":scene.rig.pose_diagnostics(),"impostor":scene.impostor.diagnostics()})
        scene.player.scripted_direction = Vector2.ZERO
        for frame in range(12): await scene.get_tree().physics_frame
        var pos: Vector3 = scene.player.position
        var ok: bool = reached and absf(pos.y-step[1].y)<.36
        var item := {"name":step[0],"passed":ok,"actual":[pos.x,pos.y,pos.z],"target":[step[1].x,step[1].y,step[1].z]}
        if step[0] in ["upper_npc","merchant"]:
            scene.interact()
            item["interaction"] = scene.hud.dialogue.visible and not scene.player.controls_enabled
            ok = ok and item.interaction
            if scene.hud.dialogue.visible: scene.interact()
        result.steps.append(item)
        result.passed = result.passed and ok
        print("P9_ROUTE ",scene.experiment_id," ",step[0]," ",ok," ",pos)
        if not reached: break
    result.recoveries = scene.recovery_count-original_recoveries
    result.passed = result.passed and result.recoveries == 0 and scene.player.is_on_floor()
    scene.player.scripted_direction = Vector2.ZERO
    scene.player.scripted_input = prior_scripted
    scene.clock_frozen = prior_clock
    scene.follow = prior_follow
    scene.tour = prior_tour
    scene.rig.frozen = prior_frozen
    if not record: scene.lighting.apply_preset(prior_time)
    if not capture_dir.is_empty():
        var file := FileAccess.open(capture_dir.path_join("route-"+scene.experiment_id+".json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(result,"  ")+"\n")
    return result
