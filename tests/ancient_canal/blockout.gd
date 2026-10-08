extends SceneTree
var player: CharacterBody3D
var world: Node3D
var layout: Dictionary
var failures: Array[String] = []
var report: Dictionary = {"checks":[],"trajectory":[]}
var npc_distances: Dictionary = {}
var output := "res://build/ancient-canal/blockout.json"

func _initialize() -> void:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--blockout-output="):
            output = argument.trim_prefix("--blockout-output=")
    call_deferred("run")

func check(ok: bool,id: String) -> void:
    report.checks.append({"id":id,"passed":ok})
    if not ok: failures.append(id)

func go(target: Vector3) -> void:
    var start := player.position
    var done := false
    for frame in range(1800):
        var delta := target-player.position
        delta.y = 0
        if delta.length()<.24:
            done = true
            break
        player.scripted_direction = Vector2(delta.x,delta.z).normalized()
        await physics_frame
        for entry in layout.npcs:
            var distance := player.position.distance_to(world.vec(entry.position))
            npc_distances[entry.id] = minf(float(npc_distances.get(entry.id,INF)),distance)
        if frame%20==0: report.trajectory.append([player.position.x,player.position.y,player.position.z])
        if player.position.y < -.6: break
    player.scripted_direction = Vector2.ZERO
    check(done,"waypoint:"+str(target))
    check(player.position.y>-.55,"above_water:"+str(target))
    if not done: print("BLOCKOUT_STUCK ",start," -> ",target," at ",player.position)

func run() -> void:
    layout = JSON.parse_string(FileAccess.get_file_as_string("res://resources/ancient-canal/layout.json"))
    world = preload("res://scripts/ancient_canal/world.gd").new()
    root.add_child(world)
    world.configure(layout,true)
    player = preload("res://scripts/pixel_actor.gd").new()
    player.position = world.vec(layout.player_spawn)
    player.scripted_input = true
    root.add_child(player)
    for i in range(20): await physics_frame
    for waypoint in layout.route: await go(world.vec(waypoint))
    for entry in layout.npcs:
        check(float(npc_distances.get(entry.id,INF))<.8,"npc_reachable:"+entry.id)
    # Try to enter water well away from the bridge and dock.
    player.position = Vector3(22,.2,7)
    player.velocity = Vector3.ZERO
    player.scripted_direction = Vector2(0,-1)
    for i in range(140): await physics_frame
    check(player.position.z > 5.1,"river_blocked")
    check(player.position.y > -.1,"river_block_floor")
    report["passed"] = failures.is_empty()
    report["failures"] = failures
    report["scope"] = "Actual CharacterBody3D collision walking with unchanged actor movement; both banks, parabola bridge, dock ramp and all NPC spots."
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
    var file := FileAccess.open(output,FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  ")+"\n")
    print("BLOCKOUT_DONE passed=",report.passed," checks=",report.checks.size())
    quit(0 if report.passed else 1)
