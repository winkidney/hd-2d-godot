extends SceneTree
## Record the actual automatic route at time_scale 1, rather than advancing a
## pose timeline for the camera. PNG writes run on independent, bounded workers.
## Render/readback cost is included in the wall clock; missing samples are kept.

const SIZE := Vector2i(1920, 1080)
const PHYSICS_HZ := 60
const SAMPLE_EVERY_PHYSICS_FRAMES := 2
const WRITER_COUNT := 4
const QUEUE_LIMIT := 96
const CHOICE_KEYS := ["camera_fov", "camera_distance", "camera_variant", "camera_follow", "dof_near", "dof_far", "dof_amount", "focus_protection", "focus_distance"]

class PhysicsObserver:
    extends Node
    var recorder
    func _physics_process(delta: float) -> void:
        recorder.observe_physics(delta)

var viewport: SubViewport
var scene
var observer: PhysicsObserver
var output := "res://build/ancient-canal/route-render"
var evidence_prefix := "route-render"
var fingerprint := ""
var timeout_seconds := 240.0
var frames: Array[Dictionary] = []
var trajectory: Array[Dictionary] = []
var transitions: Array[Dictionary] = []
var failures: Array[String] = []
var writer_threads: Array[Thread] = []
var writer_queue: Array[Dictionary] = []
var writer_results: Array[Dictionary] = []
var queue_mutex := Mutex.new()
var queue_signal := Semaphore.new()
var writers_stopping := false
var writers_active := 0
var queue_high_water := 0
var backpressure_events := 0
var backpressure_skips := 0
var render_gap_skips := 0
var attempted_samples := 0
var readback_failures := 0
var start_tick := 0
var start_usec := 0
var next_sample_tick := 0
var last_observed_tick := -1
var first_route_start := Vector3.ZERO
var recording := false
var tracking := false
var phase := "warming-up"
var stage := 0
var simulation_elapsed := 0.0
var period_thresholds := [0, 0]
var camera_choices: Dictionary = {}
var route_result: Dictionary = {}
var cancel_result: Dictionary = {}
var latest_physics: Dictionary = {}
var process_intervals_ms: Array[float] = []
var previous_process_usec := 0
var no_fixed_fps := true
var ignore_preferences := false
var disabled_render_loop := false
var output_allowed := false
var launch_state: Dictionary = {}

func actual_launch_state() -> Dictionary:
    # Startup consumes these options before OS.get_cmdline_args can see them.
    # Only retain verified state and counts, never host paths or raw argv.
    var evidence := {"process_args_read":false,"process_cmdline_complete":false,"process_cmdline_argc":0,"fixed_fps_flag_present":null,"engine_render_loop_query_available":ClassDB.class_has_method("RenderingServer","is_render_loop_enabled"),"engine_render_loop_enabled":null}
    if evidence.engine_render_loop_query_available:
        var enabled = RenderingServer.call("is_render_loop_enabled")
        evidence.engine_render_loop_query_available = enabled is bool
        if enabled is bool: evidence.engine_render_loop_enabled = enabled
    var file := FileAccess.open("/proc/self/cmdline",FileAccess.READ)
    if file==null:
        return evidence
    # proc's size is zero even while its direct read has a complete NUL list.
    var bytes := file.get_buffer(65536)
    file.close()
    if bytes.is_empty() or bytes.size()>=65536 or bytes[-1]!=0:
        return evidence
    var current := PackedByteArray()
    var fixed := false
    for byte in bytes:
        if byte==0:
            var argument := current.get_string_from_utf8()
            fixed = fixed or argument=="--fixed-fps" or argument.begins_with("--fixed-fps=")
            evidence.process_cmdline_argc += 1
            current.clear()
        else:
            current.append(byte)
    evidence.process_args_read = true
    evidence.process_cmdline_complete = true
    evidence.fixed_fps_flag_present = fixed
    return evidence

func _initialize() -> void:
    launch_state = actual_launch_state()
    no_fixed_fps = launch_state.process_args_read and launch_state.fixed_fps_flag_present==false
    disabled_render_loop = launch_state.engine_render_loop_query_available and launch_state.engine_render_loop_enabled==false
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--canal-route-dir="):
            output = argument.trim_prefix("--canal-route-dir=")
        elif argument.begins_with("--canal-fingerprint="):
            fingerprint = argument.trim_prefix("--canal-fingerprint=")
        elif argument.begins_with("--canal-route-timeout="):
            timeout_seconds = maxf(10.0, argument.trim_prefix("--canal-route-timeout=").to_float())
    ignore_preferences = "--ignore-user-settings" in OS.get_cmdline_user_args()
    output = ProjectSettings.globalize_path(output).simplify_path()
    var evidence_root := ProjectSettings.globalize_path("res://build/ancient-canal").simplify_path()
    if output.begins_with(evidence_root + "/"):
        output_allowed = true
        evidence_prefix = output.trim_prefix(evidence_root + "/")
    else:
        require(false, "route output must be inside build/ancient-canal")
    if not fingerprint.is_empty():
        var pattern := RegEx.new()
        pattern.compile("^[0-9a-fA-F]{64}$")
        require(pattern.search(fingerprint) != null, "runtime fingerprint must be 64 hexadecimal characters or omitted")
    require(launch_state.process_args_read, "cannot verify actual Linux process command line")
    require(no_fixed_fps, "route recording refuses an actual --fixed-fps process flag; use real wall-clock simulation")
    require(launch_state.engine_render_loop_query_available, "cannot verify actual engine render-loop state")
    require(disabled_render_loop, "disable the actual engine render loop before route recording")
    require(ignore_preferences, "launch route recording with --ignore-user-settings")
    # A hidden root can suspend its independent SubViewport on some backends.
    # Keep a black root present and minimize it after native startup instead.
    root.set_flag(Window.FLAG_NO_FOCUS, true)
    root.transparent_bg = false
    root.gui_embed_subwindows = true
    RenderingServer.set_default_clear_color(Color.BLACK)
    Engine.time_scale = 1.0
    Engine.physics_ticks_per_second = PHYSICS_HZ
    Engine.max_fps = 60
    OS.low_processor_usage_mode = false
    viewport = SubViewport.new()
    viewport.size = SIZE
    viewport.own_world_3d = true
    viewport.gui_embed_subwindows = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    call_deferred("run")

func _process(_delta: float) -> bool:
    # The caller disables the ordinary render loop. Draws here are genuine GPU
    # scene draws with real physics; they do not claim renderer throughput.
    if DisplayServer.get_name() == "headless":
        return false
    RenderingServer.force_draw()
    var now := Time.get_ticks_usec()
    if recording:
        if previous_process_usec > 0:
            process_intervals_ms.append(float(now - previous_process_usec) / 1000.0)
        previous_process_usec = now
        capture_due_frame(now)
    return false

func require(condition: bool, description: String) -> void:
    if not condition and description not in failures:
        failures.append(description)
        push_error(description)

func foot_array(position: Vector3) -> Array:
    return [position.x, position.y, position.z]

func choices() -> Dictionary:
    var result: Dictionary = {}
    for key in CHOICE_KEYS:
        result[key] = scene.values[key]
    return result

func set_period(id: String) -> void:
    var before := choices()
    scene.apply_time_preset(id)
    var after := choices()
    var preserved := before == after and after == camera_choices
    require(preserved, "time preset changed camera or DOF selections: " + id)
    require(scene.values.time_preset == id, "time preset did not become active: " + id)
    transitions.append({"period": id, "physics_index": Engine.get_physics_frames(), "wall_elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0, "route_index": scene.route_index, "camera_dof_choices_before": before, "camera_dof_choices_after": after, "choices_preserved": preserved, "main_energy": scene.main_light.light_energy, "ambient_energy": scene.environment.ambient_light_energy, "lantern_energy": scene.values.lantern_energy})

func observe_physics(delta: float) -> void:
    if not tracking or not is_instance_valid(scene):
        return
    var tick := Engine.get_physics_frames()
    if tick == last_observed_tick:
        return
    last_observed_tick = tick
    simulation_elapsed += delta
    if phase == "automatic-route" and scene.route_running:
        if stage == 0 and scene.route_index >= period_thresholds[0]:
            set_period("night")
            stage = 1
        if stage == 1 and scene.route_index >= period_thresholds[1]:
            set_period("day")
            stage = 2
    latest_physics = {"physics_index": tick, "physics_elapsed_frames": tick - start_tick, "simulation_elapsed_ms": simulation_elapsed * 1000.0, "physics_delta_ms": delta * 1000.0, "wall_elapsed_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0, "route_index": scene.route_index, "route_running": scene.route_running, "world_foot": foot_array(scene.player.global_position), "period": scene.values.time_preset, "phase": phase, "animation_frame": scene.player.animation_frame, "direction": scene.player.animation.DIRECTIONS[scene.player.facing], "scripted_input": scene.player.scripted_input, "controls_enabled": scene.player.controls_enabled}
    trajectory.append(latest_physics.duplicate(true))

func capture_due_frame(now: int) -> void:
    if latest_physics.is_empty():
        return
    var tick := int(latest_physics.physics_index)
    if tick < next_sample_tick:
        return
    var slots_due := 1 + int((tick - next_sample_tick) / SAMPLE_EVERY_PHYSICS_FRAMES)
    var requested_tick := next_sample_tick
    next_sample_tick += slots_due * SAMPLE_EVERY_PHYSICS_FRAMES
    attempted_samples += slots_due
    queue_mutex.lock()
    var pending := writer_queue.size()
    queue_mutex.unlock()
    if pending >= QUEUE_LIMIT:
        backpressure_events += 1
        backpressure_skips += slots_due
        return
    render_gap_skips += slots_due - 1
    var readback_start := Time.get_ticks_usec()
    var image := viewport.get_texture().get_image()
    if image.is_empty() or image.get_size() != SIZE:
        readback_failures += 1
        require(false, "GPU readback was empty or not 1920x1080")
        return
    var relative_file := evidence_prefix + "/frames/frame-%06d.png" % frames.size()
    var metadata := latest_physics.duplicate(true)
    metadata["file"] = relative_file
    metadata["sequence_index"] = frames.size()
    metadata["wall_elapsed_ms"] = float(now - start_usec) / 1000.0
    metadata["readback_finished_wall_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
    metadata["readback_ms"] = float(Time.get_ticks_usec() - readback_start) / 1000.0
    metadata["requested_physics_index"] = requested_tick
    metadata["rendered_physics_index"] = Engine.get_physics_frames()
    metadata["missed_sampling_slots_before"] = slots_due - 1
    metadata["queue_depth_before"] = pending
    metadata["camera_world_position"] = foot_array(scene.camera.global_position)
    metadata["camera_fov"] = scene.camera.fov
    frames.append(metadata)
    # get_image creates a unique snapshot. Its pixels are never changed or read
    # again on the main thread while this independent writer owns the image.
    var job := {"image": image, "name": "frame-%06d.png" % int(metadata.sequence_index), "sequence_index": metadata.sequence_index, "queued_usec": Time.get_ticks_usec()}
    queue_mutex.lock()
    writer_queue.append(job)
    queue_high_water = maxi(queue_high_water, writer_queue.size())
    queue_mutex.unlock()
    queue_signal.post()

func writer_loop(worker_id: int) -> void:
    while true:
        queue_signal.wait()
        queue_mutex.lock()
        if writer_queue.is_empty():
            var stop := writers_stopping
            queue_mutex.unlock()
            if stop:
                return
            continue
        var job: Dictionary = writer_queue.pop_front()
        writers_active += 1
        queue_mutex.unlock()
        var save_start := Time.get_ticks_usec()
        var snapshot: Image = job.image
        var error := snapshot.save_png(output.path_join("frames").path_join(job.name))
        var result := {"sequence_index": job.sequence_index, "worker_id": worker_id, "save_error": error, "save_ms": float(Time.get_ticks_usec() - save_start) / 1000.0, "queue_wait_ms": float(save_start - int(job.queued_usec)) / 1000.0}
        queue_mutex.lock()
        writer_results.append(result)
        writers_active -= 1
        queue_mutex.unlock()

func start_writers() -> void:
    for worker_id in range(WRITER_COUNT):
        var worker := Thread.new()
        var error := worker.start(writer_loop.bind(worker_id))
        require(error == OK, "cannot start PNG writer " + str(worker_id))
        if error == OK:
            writer_threads.append(worker)

func stop_writers() -> void:
    recording = false
    queue_mutex.lock()
    writers_stopping = true
    queue_mutex.unlock()
    for worker in writer_threads:
        queue_signal.post()
    for worker in writer_threads:
        worker.wait_to_finish()

func wait_physics(count: int) -> void:
    # Count actual ticks. Never change a step, use --fixed-fps or teleport along
    # the route for recording. Observation priority is after the actual actor.
    var target := Engine.get_physics_frames() + count
    while Engine.get_physics_frames() < target:
        await process_frame

func write_report(result: Dictionary) -> void:
    result["failures"] = failures
    var destination := FileAccess.open(output.path_join("route-render-report.json"), FileAccess.WRITE)
    if destination == null:
        push_error("cannot write route recording report")
        quit(1)
        return
    destination.store_string(JSON.stringify(result, "  ") + "\n")
    destination.close()
    print("ANCIENT_ROUTE_RENDER_DONE passed=", result.get("passed", false), " frames=", frames.size(), " failures=", failures.size())
    quit(0 if result.get("passed", false) else 1)

func run() -> void:
    if not output_allowed:
        # Invalid destinations must not create directories or write even a
        # failure report outside the independent evidence tree.
        print("ANCIENT_ROUTE_RENDER_REFUSED invalid evidence directory")
        quit(1)
        return
    var adapter := RenderingServer.get_video_adapter_name()
    var hardware := not adapter.is_empty() and not adapter.to_lower().contains("llvmpipe") and not adapter.to_lower().contains("lavapipe") and not adapter.to_lower().contains("swiftshader")
    var report := {"schema_version": 1, "runtime_fingerprint": fingerprint, "adapter": adapter, "hardware_gpu": hardware, "renderer": RenderingServer.get_current_rendering_method(), "display_driver": DisplayServer.get_name(), "size": [SIZE.x, SIZE.y], "capture_mode": "independent 1080p SubViewport; native root black, minimized and no focus; real physics and wall clock", "viewport_own_world_3d": viewport.own_world_3d, "viewport_update_always": viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "root_hidden": not root.visible, "preferences_ignored": false, "time_scale": Engine.time_scale, "physics_ticks_per_second": Engine.physics_ticks_per_second, "no_fixed_fps": no_fixed_fps, "disabled_render_loop": disabled_render_loop, "render_cap_fps": Engine.max_fps, "low_processor_usage_mode": OS.low_processor_usage_mode, "frame_pattern": evidence_prefix + "/frames/frame-%06d.png", "target_fps": float(PHYSICS_HZ) / SAMPLE_EVERY_PHYSICS_FRAMES, "timing_policy": "use measured wall timestamps for observed real-time VFR; physics-index resampling must hold existing images across missing slots and disclose the chosen clock; do not simply concatenate at target_fps; capture is not a performance benchmark", "passed": false}
    report.merge(launch_state,true)
    require(DisplayServer.get_name() != "headless", "route recording requires a real GPU display backend; headless is not visual evidence")
    require(hardware and report.renderer == "forward_plus", "route recording requires hardware Forward+")
    if DisplayServer.get_name() != "headless":
        # Initialization flags can be overwritten by native window startup.
        root.set_flag(Window.FLAG_NO_FOCUS, true)
        DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    for startup_frame in range(5): await process_frame
    report["main_window_minimized"] = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED if DisplayServer.get_name() != "headless" else false
    report["no_focus_flag"] = root.get_flag(Window.FLAG_NO_FOCUS)
    report["vsync_disabled"] = DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED if DisplayServer.get_name() != "headless" else false
    require(report.main_window_minimized and report.no_focus_flag and not report.root_hidden, "native window minimize/no-focus/present contract failed")
    require(report.vsync_disabled, "route recorder VSync disable did not apply")
    var directory_error := DirAccess.make_dir_recursive_absolute(output)
    require(directory_error == OK, "cannot create route output directory")
    if FileAccess.file_exists(output.path_join("route-render-report.json")) or FileAccess.file_exists(output.path_join("frames/frame-000000.png")):
        require(false, "route output already contains evidence; choose a fresh --canal-route-dir")
        # Preserve earlier recordings, including their report, on a refused run.
        print("ANCIENT_ROUTE_RENDER_REFUSED existing evidence directory")
        quit(1)
        return
    if not failures.is_empty():
        write_report(report)
        return
    require(DirAccess.make_dir_recursive_absolute(output.path_join("frames")) == OK, "cannot create route frame directory")
    scene = load("res://scenes/ancient_canal.tscn").instantiate()
    viewport.add_child(scene)
    await wait_physics(30)
    report.preferences_ignored = not scene.settings_load_attempted
    require(report.preferences_ignored, "route scene loaded everyday user preferences")
    require(scene.player.position.distance_to(scene.vec(scene.layout.player_spawn)) < 0.25, "route did not start at the actual spawn")
    camera_choices = choices()
    report["camera_dof_choices"] = camera_choices
    scene.console.close()
    scene.dialogue.hide()
    scene.exit_confirmation.hide()
    # Keep normal player movement, camera follow, animation and world updates.
    scene.overlay.hide()
    scene.apply_time_preset("dusk")
    observer = PhysicsObserver.new()
    observer.recorder = self
    observer.process_physics_priority = 1000
    viewport.add_child(observer)
    start_writers()
    if not failures.is_empty():
        stop_writers()
        write_report(report)
        return
    start_tick = Engine.get_physics_frames()
    start_usec = Time.get_ticks_usec()
    next_sample_tick = start_tick + SAMPLE_EVERY_PHYSICS_FRAMES
    first_route_start = scene.player.global_position
    report["start_foot"] = foot_array(first_route_start)
    tracking = true
    recording = true
    phase = "automatic-route"
    scene.start_route()
    period_thresholds = [maxi(1, floori(float(scene.route_points.size() - 1) / 3.0)), maxi(2, floori(float(scene.route_points.size() - 1) * 2.0 / 3.0))]
    set_period("dusk")
    report["route_points"] = scene.route_points.duplicate(true)
    report["period_switch_route_indices"] = period_thresholds
    while scene.route_running and float(Time.get_ticks_usec() - start_usec) / 1000000.0 < timeout_seconds:
        await process_frame
    if scene.route_running:
        require(false, "automatic route exceeded real wall-clock timeout")
        scene.cancel_route()
    route_result = scene.route_result.duplicate(true)
    var completed_foot: Vector3 = scene.player.global_position
    route_result["start_foot"] = foot_array(first_route_start)
    route_result["end_foot"] = foot_array(completed_foot)
    route_result["return_horizontal_error_metres"] = Vector2(completed_foot.x - first_route_start.x, completed_foot.z - first_route_start.z).length()
    route_result["wall_duration_ms"] = float(Time.get_ticks_usec() - start_usec) / 1000.0
    route_result["physics_elapsed_frames"] = Engine.get_physics_frames() - start_tick
    require(route_result.get("passed", false) and not route_result.get("cancelled", false), "actual automatic route did not complete")
    require(float(route_result.return_horizontal_error_metres) < 0.5, "completed route did not return to its spawn")
    phase = "route-settle"
    await wait_physics(60)
    # A separate brief automatic route demonstrates API cancellation and leaves
    # ordinary manual controls available, without injecting a fake key press.
    phase = "cancel-probe"
    scene.start_route()
    var cancel_start: Vector3 = scene.player.global_position
    await wait_physics(30)
    var before_cancel: Vector3 = scene.player.global_position
    var active_before: bool = scene.route_running and scene.player.scripted_input
    scene.cancel_route()
    phase = "cancel-settle"
    await wait_physics(60)
    var after_cancel: Vector3 = scene.player.global_position
    var cancel_motion := Vector2(before_cancel.x - cancel_start.x, before_cancel.z - cancel_start.z).length()
    var stop_error := Vector2(after_cancel.x - before_cancel.x, after_cancel.z - before_cancel.z).length()
    cancel_result = {"api": "cancel_route", "route_was_active": active_before, "movement_before_cancel_metres": cancel_motion, "cancelled": scene.route_result.get("cancelled", false), "route_running_after": scene.route_running, "scripted_input_after": scene.player.scripted_input, "scripted_direction_after": [scene.player.scripted_direction.x, scene.player.scripted_direction.y], "controls_restored": scene.player.controls_enabled, "before_foot": foot_array(before_cancel), "after_settle_foot": foot_array(after_cancel), "horizontal_stop_error_metres": stop_error, "settle_physics_frames": 60}
    cancel_result["passed"] = active_before and cancel_motion > 0.1 and cancel_result.cancelled and not scene.route_running and not scene.player.scripted_input and scene.player.scripted_direction == Vector2.ZERO and scene.player.controls_enabled and stop_error < 0.01
    require(cancel_result.passed, "API route cancellation did not stop the feet and restore controls")
    tracking = false
    recording = false
    var total_wall_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
    stop_writers()
    # Join all writers before hashing or inspecting their PNG outputs.
    var periods: Dictionary = {}
    var output_valid := writer_results.size() == frames.size()
    for result in writer_results:
        var entry: Dictionary = frames[int(result.sequence_index)]
        entry.merge(result, true)
        var name: String = entry.file.get_file()
        var path := output.path_join("frames").path_join(name)
        var valid: bool = result.save_error == OK and FileAccess.file_exists(path)
        var sha := FileAccess.get_sha256(path) if valid else ""
        var png := FileAccess.open(path, FileAccess.READ) if valid else null
        if png != null:
            var header := png.get_buffer(24)
            valid = header.size() == 24 and header.slice(0, 8) == PackedByteArray([137,80,78,71,13,10,26,10])
            if valid:
                var width := int(header[16]) * 16777216 + int(header[17]) * 65536 + int(header[18]) * 256 + int(header[19])
                var height := int(header[20]) * 16777216 + int(header[21]) * 65536 + int(header[22]) * 256 + int(header[23])
                valid = width == SIZE.x and height == SIZE.y
            png.close()
        else:
            valid = false
        entry["sha256"] = sha
        entry["png_valid_1080p"] = valid and sha.length() == 64
        output_valid = output_valid and entry.png_valid_1080p
        periods[entry.period] = int(periods.get(entry.period, 0)) + 1
    require(output_valid and not frames.is_empty(), "PNG worker output failed save, size or checksum validation")
    require(transitions.size() == 3 and stage == 2 and periods.has("dusk") and periods.has("night") and periods.has("day"), "route did not render all three real lighting periods")
    require(choices() == camera_choices, "camera/DOF selections changed during route recording")
    var sampling_complete := render_gap_skips == 0 and backpressure_skips == 0 and readback_failures == 0 and frames.size() == attempted_samples
    var max_physics_gap := 0
    var previous_physics_index := start_tick
    for entry in frames:
        max_physics_gap = maxi(max_physics_gap, int(entry.physics_index) - previous_physics_index)
        previous_physics_index = int(entry.physics_index)
    report["route_result"] = route_result
    report["cancel_result"] = cancel_result
    report["trajectory"] = trajectory
    report["frames"] = frames
    report["period_transitions"] = transitions
    report["recorded_period_frame_counts"] = periods
    report["wall_duration_ms"] = total_wall_ms
    report["simulation_duration_ms"] = simulation_elapsed * 1000.0
    report["wall_duration_s"] = total_wall_ms / 1000.0
    report["simulation_s"] = simulation_elapsed
    report["physics_elapsed_frames"] = Engine.get_physics_frames() - start_tick
    report["render_frame_wall_intervals_ms"] = process_intervals_ms
    report["sampling"] = {"complete": sampling_complete, "every_physics_frames": SAMPLE_EVERY_PHYSICS_FRAMES, "attempted_slots": attempted_samples, "captured_frames": frames.size(), "simulation_s": simulation_elapsed, "max_physics_gap": max_physics_gap, "capture_fps_over_simulation": float(frames.size()) / maxf(0.001, simulation_elapsed), "capture_fps_over_wall_clock": float(frames.size()) / maxf(0.001, total_wall_ms / 1000.0), "render_gap_skipped_slots": render_gap_skips, "queue_backpressure_events": backpressure_events, "queue_backpressure_skipped_slots": backpressure_skips, "readback_failures": readback_failures, "timestamp_scope": "physics observer after actor movement; render/readback on main thread; wall timestamps are monotonic and not a synthetic 30fps timeline", "status": "all intended samples recorded" if sampling_complete else "sampling gaps retained; encode real wall timestamps, not an assumed 30fps clock"}
    report["writer"] = {"threads_started": writer_threads.size(), "queue_capacity": QUEUE_LIMIT, "queue_high_water": queue_high_water, "completed_jobs": writer_results.size(), "output_valid": output_valid, "joined_before_checksums": true}
    report["main_window_minimized"] = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
    report["no_focus_flag"] = root.get_flag(Window.FLAG_NO_FOCUS)
    report["preferences_ignored"] = not scene.settings_load_attempted
    require(report.main_window_minimized and report.no_focus_flag, "window minimize/no-focus contract changed during route")
    require(Engine.time_scale == 1.0 and Engine.physics_ticks_per_second == PHYSICS_HZ, "real-time simulation contract changed during route")
    report["passed_scope"] = "actual route completion and return, three rendered periods with camera/DOF choices preserved, valid independent PNG files, and a separate cancellation/controls check; sampling completeness is reported independently"
    report["passed"] = failures.is_empty() and output_valid and route_result.get("passed", false) and cancel_result.passed
    write_report(report)
