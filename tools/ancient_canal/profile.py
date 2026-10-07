"""Generate isolated probes from the current benchmark; never edit runtime code.

Run from the project root. Output must be a fresh project-local build directory.
GPU tests use the existing minimized, no-focus, real-time benchmark contract.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from project import engine, desktop_environment
from feature_fingerprint import fingerprint

CASES = ["baseline", "no_ssr", "no_ssao", "no_dof", "no_glow", "no_shadows",
         "no_local_shadows", "no_main_shadow", "no_broad_shadows", "no_near_town",
         "no_far_town", "no_normals", "no_msaa", "scale_075", "no_post", "static_natural", "dof_low"]

def replace_once(source, before, after):
    if source.count(before) != 1:
        raise RuntimeError("Probe source changed; review insertion: " + before[:80])
    return source.replace(before, after, 1)

def instrument(source, methods):
    source += "\nvar profile_timings: Dictionary = {}\n"
    source += "func profile_record(key: String, started: int) -> void:\n    if not profile_timings.has(key): profile_timings[key] = []\n    profile_timings[key].append(float(Time.get_ticks_usec()-started)/1000.0)\n"
    for name, signature, args, result in methods:
        source = replace_once(source, "func " + name + "(", "func profile_original_" + name + "(")
        call = "profile_original_" + name + "(" + args + ")"
        source += "\nfunc " + name + "(" + signature + ") -> " + result + ":\n    var started := Time.get_ticks_usec()\n"
        source += "    var result = " + call + "\n" if result != "void" else "    " + call + "\n"
        source += '    profile_record("' + name + '",started)\n'
        if result != "void": source += "    return result\n"
    return source

MUTATIONS = '''
    var case_id := period.split("/")[0]
    scene.farfield.layers.near_town.show()
    scene.farfield.layers.far_town.show()
    scene.parallax.profile_skip_natural = case_id=="static_natural"
    var jitter: bool = ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_use_jitter",false)
    var quality: int = ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_bokeh_quality",2)
    RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_LOW if case_id=="dof_low" else quality,jitter)
    match case_id:
        "no_ssr": scene.environment.ssr_enabled = false
        "no_ssao": scene.environment.ssao_enabled = false
        "no_dof": scene.attributes.dof_blur_near_enabled = false; scene.attributes.dof_blur_far_enabled = false
        "no_glow": scene.environment.glow_enabled = false
        "no_shadows":
            scene.main_light.shadow_enabled = false
            for lamp in scene.lamp_nodes.values(): lamp.shadow_enabled = false
        "no_local_shadows":
            for lamp in scene.lamp_nodes.values(): lamp.shadow_enabled = false
        "no_main_shadow": scene.main_light.shadow_enabled = false
        "no_broad_shadows":
            for lamp in scene.broad_lights: lamp.shadow_enabled = false
        "no_near_town": scene.farfield.layers.near_town.hide()
        "no_far_town": scene.farfield.layers.far_town.hide()
        "no_normals": scene.values.normals_enabled = false; scene.apply_parameters()
        "no_msaa": viewport.msaa_3d = Viewport.MSAA_DISABLED
        "scale_075": viewport.scaling_3d_scale = .75
        "no_post":
            scene.environment.ssr_enabled = false
            scene.environment.ssao_enabled = false
            scene.environment.glow_enabled = false
            scene.attributes.dof_blur_near_enabled = false
            scene.attributes.dof_blur_far_enabled = false
    # The live scene updates DOF every frame; change the owning values as well.
    if case_id in ["no_dof","no_post"]:
        scene.values.dof_near = false
        scene.values.dof_far = false
    viewport.msaa_3d = Viewport.MSAA_DISABLED if case_id=="no_msaa" else Viewport.MSAA_2X
    viewport.scaling_3d_scale = .75 if case_id=="scale_075" else 1.0
    var inventory := {"mesh_instances":0,"surfaces":0,"triangles":0,"unique_meshes":{},"unique_materials":{},"shadow_lights":0}
    for mesh in scene.find_children("*","MeshInstance3D",true,false):
        inventory.mesh_instances += 1
        inventory.unique_meshes[str(mesh.mesh.get_instance_id())] = true
        for surface in mesh.mesh.get_surface_count():
            inventory.surfaces += 1
            var arrays: Array = mesh.mesh.surface_get_arrays(surface)
            inventory.triangles += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size())/3
            var mat: Material = mesh.get_active_material(surface)
            if mat!=null: inventory.unique_materials[str(mat.get_instance_id())] = true
    inventory.unique_meshes = inventory.unique_meshes.size()
    inventory.unique_materials = inventory.unique_materials.size()
    for lamp in scene.lamp_nodes.values():
        if lamp.visible and lamp.shadow_enabled: inventory.shadow_lights += 1
    inventory.main_shadow = scene.main_light.shadow_enabled
    inventory.msaa_3d = viewport.msaa_3d
    inventory.scaling_3d_scale = viewport.scaling_3d_scale
    inventory.background_sleep_usec = OS.low_processor_usage_mode_sleep_usec
    inventory.dof_quality = RenderingServer.DOF_BLUR_QUALITY_LOW if case_id=="dof_low" else quality
    inventory.dof_jitter = jitter
    inventory.ssao = scene.environment.ssao_enabled
    inventory.ssr = scene.environment.ssr_enabled
    inventory.dof = scene.attributes.dof_blur_far_enabled
'''

COLLECT = '''
        setup_times.append(RenderingServer.get_frame_setup_time_cpu())
        if intervals.size()%10==0:
            render_counts.append({"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"objects":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME),"primitives":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow_draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
            var rd := RenderingServer.get_rendering_device()
            var timestamp_frame := rd.get_captured_timestamps_frame()
            if timestamp_frame!=last_timestamp_frame:
                last_timestamp_frame = timestamp_frame
                var markers: Array = []
                for i in rd.get_captured_timestamps_count():
                    # Vulkan backend returns nanoseconds, despite older class docs.
                    # Keep large timestamps as strings to preserve integer precision.
                    markers.append({"name":rd.get_captured_timestamp_name(i),"gpu_ns":str(rd.get_captured_timestamp_gpu_time(i)),"cpu_us":rd.get_captured_timestamp_cpu_time(i)})
                timestamp_frames.append({"frame":timestamp_frame,"markers":markers})
'''

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--cases", default=",".join(CASES))
    parser.add_argument("--period", choices=["day","dusk","night"], default="dusk")
    parser.add_argument("--seconds", type=float, default=10)
    parser.add_argument("--warmup", type=float, default=3)
    parser.add_argument("--gpu-profile", action="store_true")
    parser.add_argument("--instrument-cpu", action="store_true")
    args = parser.parse_args()
    out = (ROOT/args.output).resolve()
    if not out.is_relative_to(ROOT/"build/ancient-canal") or out.exists():
        parser.error("Output must be a fresh directory below build/ancient-canal")
    cases = args.cases.split(",")
    if any(c not in CASES for c in cases) or len(cases)!=len(set(cases)) or args.seconds<=0 or args.warmup<=0:
        parser.error("Invalid cases or duration")
    out.mkdir(parents=True)
    uri = "res://"+out.relative_to(ROOT).as_posix()
    source = (ROOT/"tools/ancient_canal/benchmark.gd").read_text()
    # Minimization itself triggers OS::add_frame_delay even when low-usage mode
    # is false. Remove that delay locally; otherwise wall FPS measures a sleep.
    source = replace_once(source,"    OS.low_processor_usage_mode = false","    OS.low_processor_usage_mode = false\n    OS.low_processor_usage_mode_sleep_usec = 0")
    source = replace_once(source,"const WARMUP_SECONDS := 5.0",f"const WARMUP_SECONDS := {args.warmup}")
    source = replace_once(source,"const SAMPLE_SECONDS := 30.0",f"const SAMPLE_SECONDS := {args.seconds}")
    source = replace_once(source,'const PERIODS := ["day","dusk","night"]',"const PERIODS := "+json.dumps([c+"/"+args.period for c in cases]))
    source = source.replace("report.presets.size()==3", f"report.presets.size()=={len(cases)}")
    source = replace_once(source,"    if failures.is_empty():\n        for period in PERIODS:","    report[\"default_subviewport_msaa_3d\"] = viewport.msaa_3d\n    report[\"root_msaa_3d\"] = root.msaa_3d\n    report[\"background_sleep_usec\"] = OS.low_processor_usage_mode_sleep_usec\n    if failures.is_empty():\n        for period in PERIODS:")
    source = replace_once(source,"scene.apply_time_preset(period)",'scene.apply_time_preset(period.split("/")[1])')
    source = replace_once(source,"    completed_routes = 0",MUTATIONS+"\n    completed_routes = 0")
    source = replace_once(source,"    var intervals: Array[float] = []","    var setup_times: Array[float] = []\n    var render_counts: Array = []\n    var timestamp_frames: Array = []\n    var last_timestamp_frame := -1\n    var intervals: Array[float] = []")
    source = replace_once(source,"        previous = now",COLLECT+"\n        previous = now")
    source = replace_once(source,'    var samples_path := output.path_join(period+"-samples.json")','    var samples_path := output.path_join(period.replace("/","-")+"-samples.json")')
    source = replace_once(source,"    var saved := save_json(samples_path,raw)",'    raw.merge({"inventory":inventory,"frame_setup_cpu_ms":setup_times,"render_counts":render_counts,"timestamp_frames":timestamp_frames})\n    var saved := save_json(samples_path,raw)')
    source = replace_once(source,'    print("CANAL_BENCHMARK_PERIOD "','    result["inventory"] = inventory\n    result["frame_setup_cpu"] = summarize(setup_times)\n    print("CANAL_BENCHMARK_PERIOD "')
    # A diagnostic-only fast path tests whether redundant natural transforms
    # invalidate static shadows. The ordinary scene and all assets stay intact.
    parallax_code = (ROOT/"scripts/ancient_canal/parallax.gd").read_text()
    parallax_code = replace_once(parallax_code,"    if camera == null: return","    if camera == null: return\n    if profile_skip_natural and profile.mode==\"natural\" and not immediate: return")
    parallax_code += "\nvar profile_skip_natural := false\n"
    (out/"parallax.gd").write_text(parallax_code)
    scene_code = (ROOT/"scripts/ancient_canal/scene.gd").read_text().replace("res://scripts/ancient_canal/parallax.gd",uri+"/parallax.gd")
    (out/"scene.gd").write_text(scene_code)
    source = replace_once(source,"scene = load(ENTRY).instantiate()",f'scene = load("{uri}/scene.gd").new()')
    if args.instrument_cpu:
        specs = {
            "actor": [("_physics_process","delta: float","delta","void"),("update_animation","","","void"),("bind_frame","direction: int,index: int","direction,index","void")],
            "background": [("advance","delta: float","delta","void")],
            "parallax": [("update","delta: float,immediate := false","delta,immediate","void")],
            "camera": [("update","delta: float,player_position: Vector3,tour: bool,elapsed: float","delta,player_position,tour,elapsed","void")],
            "scene": [("_process","delta: float","delta","void"),("_physics_process","delta: float","delta","void"),("camera_update","delta: float,immediate := false","delta,immediate","void"),("update_focus","","","void"),("nearest_interaction","","","Dictionary"),("sync_input","","","void")]
        }
        for name, methods in specs.items():
            code = (ROOT/f"scripts/ancient_canal/{name}.gd").read_text()
            if name=="parallax": code = parallax_code
            if name=="scene":
                for dep in ["actor","background","parallax","camera"]: code = code.replace(f'res://scripts/ancient_canal/{dep}.gd',f'{uri}/{dep}.gd')
            (out/f"{name}.gd").write_text(instrument(code,methods))
        source = replace_once(source,"    var sample_start := Time.get_ticks_usec()","    scene.profile_timings.clear()\n    scene.player.profile_timings.clear()\n    scene.farfield.profile_timings.clear()\n    scene.parallax.profile_timings.clear()\n    scene.rig.profile_timings.clear()\n    var sample_start := Time.get_ticks_usec()")
        source = replace_once(source,"    var saved := save_json(samples_path,raw)",'    raw["instrumented_cpu"] = {"scene":scene.profile_timings,"actor":scene.player.profile_timings,"background":scene.farfield.profile_timings,"parallax":scene.parallax.profile_timings,"camera":scene.rig.profile_timings}\n    var saved := save_json(samples_path,raw)')
    (out/"probe.gd").write_text(source)
    current = fingerprint(ROOT)
    manifest = {"runtime_fingerprint":current,"parameters":vars(args),"benchmark_sha256":hashlib.sha256((ROOT/"tools/ancient_canal/benchmark.gd").read_bytes()).hexdigest(),"probe_sha256":hashlib.sha256(source.encode()).hexdigest(),"generated_sha256":{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.glob("*.gd")},"background_sleep_usec":0,"msaa_3d_baseline":"2x, explicitly matches project.godot; old SubViewport benchmark left this at its disabled default","policy":"One intervention per case, equal repeating physical route start and warmup. Separate CPU instrumentation and GPU profiling runs. No screenshots during samples."}
    (out/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    env = desktop_environment()
    for key,name in [("XDG_DATA_HOME","user-data"),("XDG_CONFIG_HOME","config"),("XDG_CACHE_HOME","cache")]: env[key] = str(out/name)
    command = [engine(),"--path",str(ROOT),"--display-driver","x11","--position","10000,10000","--audio-driver","Dummy","--disable-render-loop"]
    if args.gpu_profile: command.append("--gpu-profile")
    command += ["--script",uri+"/probe.gd","--","--ignore-user-settings","--canal-fingerprint="+current["sha256"],"--canal-output="+uri]
    with (out/"run.log").open("w") as stream:
        child = subprocess.Popen(command,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT)
        print("Started isolated profiler",flush=True)
        try:
            code = child.wait(timeout=60+len(cases)*(args.seconds+args.warmup)*2)
        except BaseException:
            child.terminate()
            try: child.wait(timeout=15)
            except subprocess.TimeoutExpired: child.kill();child.wait()
            raise
    log = (out/"run.log").read_text()
    print(log[-3500:])
    if code or "ERROR:" in log or "SCRIPT ERROR" in log: raise SystemExit(code or 1)

if __name__=="__main__": main()
