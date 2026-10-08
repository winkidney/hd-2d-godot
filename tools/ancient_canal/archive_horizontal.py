"""Archive and independently recompute the horizontal canal acceptance evidence."""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from feature_fingerprint import fingerprint
from verify_profile_archive import require, stats

BUILD = ROOT / "build/ancient-canal/horizontal-night-20261008"
ARCHIVE = ROOT / "docs/ancient-canal/horizontal-night-20261008"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n")


def archive():
    order = json.loads((BUILD / "measurements/run-order.json").read_text())
    require(len(order["runs"]) == 21 and all(r["passed"] for r in order["runs"]), "Incomplete measurements")
    records = []

    def add(source, target, compress=False):
        content = source.read_bytes()
        stored = gzip.compress(content, mtime=0) if compress else content
        path = ARCHIVE / target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(stored)
        records.append({"source": source.relative_to(ROOT).as_posix(), "path": target,
                        "encoding": "gzip" if compress else "identity",
                        "original_bytes": len(content), "stored_bytes": len(stored),
                        "original_sha256": digest(content), "stored_sha256": digest(stored)})

    add(BUILD / "measurements/run-order.json", "data/run-order.json")
    for run in order["runs"]:
        directory = ROOT / run["path"]
        for source in sorted(directory.glob("*.json")):
            compressed = source.name.endswith("-samples.json")
            add(source, "data/" + run["id"] + "/" + source.name + (".gz" if compressed else ""), compressed)
        for source in sorted(directory.glob("*.gd")):
            add(source, "probes/" + run["id"] + "/" + source.name + ".txt.gz", True)
    for directory in ["validation", "validation-camera", "validation-regression", "make-test-complete"]:
        for source in sorted((BUILD / directory).rglob("*.json")):
            add(source, "validation/" + directory + "/" + source.relative_to(BUILD / directory).as_posix())
    for source in sorted((BUILD / "original/build/ancient-canal/baseline-route-proof").glob("*.json")):
        add(source, "validation/original-route/" + source.name)
    render = BUILD / "accepted-render-v2"
    capture = json.loads((render / "horizontal-capture.json").read_text())
    add(render / "horizontal-capture.json", "render/horizontal-capture.json")
    for shot in capture["screenshots"]:
        source = render / Path(shot["path"]).name
        require(digest(source.read_bytes()) == shot["sha256"], "Capture checksum mismatch")
        add(source, "render/" + source.name)
    for name in ["dock-stability-summary.json", "route.mp4", "night.mp4", "route-video.json", "night-video.json", "visual-review.json",
                 "route-contact.png", "night-contact.png", "npc-contact.png"]:
        add(render / name, "render/" + name)
    for name in ["profile.py", "benchmark.gd", "measure_horizontal.py", "capture_horizontal.gd", "archive_horizontal.py",
                 "build_scenery.py", "build_low_bridge.py", "build_extra_npcs.py", "review_horizontal.py"]:
        source = ROOT / "tools/ancient_canal" / name
        add(source, "sources/" + name + (".txt" if name.endswith(".gd") else ""))
    for name in ["profile.py", "benchmark.gd"]:
        add(BUILD / "original/tools/ancient_canal" / name, "sources/original/" + name + (".txt" if name.endswith(".gd") else ""))
    for name in ["resources/ancient-canal/layout.json", "scripts/ancient_canal/night_sky.gd", "scripts/ancient_canal/sky_focus.gd",
                 "shaders/ancient_canal/night_sky.gdshader", "art_source/ancient-canal/scenery/recipe.json",
                 "art_source/ancient-canal/blender/low-bridge/recipe.json"]:
        source = ROOT / name
        add(source, "sources/" + name + (".txt" if source.suffix in [".gd", ".gdshader"] else ""))
    current = fingerprint(ROOT)
    require(current["sha256"] == order["current"], "Runtime changed since measurements")
    write_json(ARCHIVE / "source-fingerprint.json", current)
    add(ARCHIVE / "source-fingerprint.json", "source-fingerprint.json")
    write_json(ARCHIVE / "archive-manifest.json", {
        "schema_version": 1, "original_commit": "b80ed88a2b644ca9e3c4b0246cfd9db1d17f795d",
        "runtime_fingerprint": order["current"], "original_runtime_fingerprint": order["original"], "records": records,
        "policy": "Original bytes and stored bytes are checked independently. Runtime caches, preferences and local process logs are excluded. PNG sequences remain ignored; frame hashes, timestamps and encoded videos are retained."})


def stages(frames):
    series = {}
    for frame in frames:
        totals = {}
        for begin, end in zip(frame["markers"], frame["markers"][1:]):
            name = begin["name"]
            if name.startswith((">", "<", "vp_")):
                continue
            gpu = (int(end["gpu_ns"]) - int(begin["gpu_ns"])) / 1e6
            cpu = (end["cpu_us"] - begin["cpu_us"]) / 1000
            require(gpu >= 0 and cpu >= 0, "Nonmonotonic timestamp")
            totals.setdefault(name, [0., 0.])
            totals[name][0] += gpu
            totals[name][1] += cpu
        for name, pair in totals.items():
            series.setdefault(name, []).append(pair)
    return sorted([{"name": name, "samples": len(values), "max_gpu_ms": max(p[0] for p in values), "max_cpu_ms": max(p[1] for p in values), "gpu": stats([p[0] for p in values]),
                    "cpu": stats([p[1] for p in values])} for name, values in series.items()],
                  key=lambda v: v["gpu"]["mean_ms"], reverse=True)


def verify():
    manifest = json.loads((ARCHIVE / "archive-manifest.json").read_text())
    files = {}
    for record in manifest["records"]:
        path = ARCHIVE / record["path"]
        require(path.resolve().is_relative_to(ARCHIVE.resolve()), "Escaping archive path")
        stored = path.read_bytes()
        require(len(stored) == record["stored_bytes"] and digest(stored) == record["stored_sha256"], "Stored bytes mismatch: " + record["path"])
        require(record["encoding"] in ["gzip", "identity"], "Invalid encoding")
        content = gzip.decompress(stored) if record["encoding"] == "gzip" else stored
        require(len(content) == record["original_bytes"] and digest(content) == record["original_sha256"], "Source bytes mismatch")
        require(record["source"] not in files, "Duplicate source")
        files[record["source"]] = content
    prefix = BUILD.relative_to(ROOT).as_posix()
    order = json.loads(files[prefix + "/measurements/run-order.json"])
    require(len(order["runs"]) == 21, "Missing run")
    cases = []
    raw_by_key = {}
    cpu = []
    transitions = []
    for run in order["runs"]:
        require(run["passed"], "Run failed")
        base = run["path"]
        report = json.loads(files[base + "/performance-report.json"])
        launch = json.loads(files[base + "/manifest.json"])
        require(report["passed"] and not report["failures"] and report["hardware_gpu"], "GPU measurement failed")
        require(report["renderer"] == "forward_plus" and report["viewport"] == [1920, 1080], "Wrong rendering conditions")
        require(report["background_sleep_usec"] == 0 and report["preferences_ignored"] and not report["low_processor_usage_mode"], "Background throttling/preferences")
        require(report["readback_count"] == 0 and not report["fixed_fps"] and report["main_window_minimized"] and report["no_focus"], "Measurement/capture isolation failed")
        require(launch["parameters"]["warmup"] == 5 and launch["parameters"]["seconds"] == 30, "Wrong duration")
        source_base = prefix + "/original/" if run["original"] else ""
        require(digest(files[source_base + "tools/ancient_canal/benchmark.gd"]) == launch["benchmark_sha256"], "Benchmark source mismatch")
        require(digest(files[base + "/probe.gd"]) == launch["probe_sha256"], "Probe source mismatch")
        for name, checksum in launch["generated_sha256"].items():
            require(digest(files[base + "/" + name]) == checksum, "Generated source mismatch")
        for case, result in report["presets"].items():
            content = files[base + "/" + case.replace("/", "-") + "-samples.json"]
            require(digest(content) == result["sha256"], "Raw sample checksum mismatch")
            raw = json.loads(content)
            require(raw["runtime_fingerprint"] == run["source_fingerprint"] == report["runtime_fingerprint"], "Runtime identity mismatch")
            require(raw["draw_counters"]["passed"] and all(raw["draw_counters"]["checks"].values()), "Draw completion mismatch")
            require(raw["inventory"]["msaa_3d"] == 1 and raw["inventory"]["workload_phase_reset"], "MSAA/workload mismatch")
            require(raw["warmup_elapsed_s"] >= 5 and raw["elapsed_s"] >= 30 and raw["readback_count"] == 0, "Sampling duration/readback mismatch")
            metrics = {}
            for label, field in [("wall", "frame_intervals_ms"), ("gpu", "gpu_timings_ms"), ("render_cpu", "cpu_timings_ms")]:
                metrics[label] = stats(raw[field])
                saved = result if label == "wall" else result["gpu" if label == "gpu" else "cpu"]
                for key in ["mean_ms", "p50_ms", "p95_ms", "p99_ms"]:
                    require(abs(metrics[label][key] - saved[key]) < 1e-6, "Recomputed statistic mismatch")
            positions = [point["foot"] for point in raw["render_counts"]]
            extent = [[min(p[i] for p in positions), max(p[i] for p in positions)] for i in range(3)]
            require(extent[0][1] - extent[0][0] > 10 and extent[2][1] - extent[2][0] > 4, "Route was not exploring")
            entry = {"run": run["id"], "case": case, "metrics": metrics, "completed_routes": result["completed_routes"],
                     "route_extent_xyz_m": extent, "inventory": raw["inventory"], "gpu_stages": stages(raw["timestamp_frames"])}
            cases.append(entry)
            raw_by_key[(run["id"], case)] = raw
            if run["instrumented_cpu"]:
                functions = raw["instrumented_cpu"]
                selected = [("night_sky", "update"), ("sky_focus", "_render_callback"), ("scene", "update_focus")]
                conservative = sum(sum(functions[group][name]) for group, name in selected) / raw["post_draw_sample_count"]
                cpu.append({"run": run["id"], "completed_draws": raw["post_draw_sample_count"],
                            "conservative_sky_and_entire_existing_focus_ms_per_draw": conservative,
                            "functions": {group: {name: stats(values) for name, values in items.items()} for group, items in functions.items()}})
            if not run["original"] and run["period"] == "night" and not run["instrumented_cpu"]:
                initial = stages(raw["transition_frames"])
                sky = next((s for s in initial if s["name"] == "Setup Sky"), None)
                transitions.append({"run": run["id"], "case": case, "apply_preset_cpu_ms": raw["transition_apply_cpu_ms"],
                                    "first_120_completed_draws_gpu": stats([f["gpu_ms"] for f in raw["transition_frames"]]),
                                    "initial_max_viewport_gpu_ms": max(f["gpu_ms"] for f in raw["transition_frames"]),
                                    "initial_window_s": max(f["elapsed_s"] for f in raw["transition_frames"]),
                                    "initial_gpu_stages": initial, "setup_sky": sky})
    require(len(cases) == 24 and len(cpu) == 3, "Wrong case count")
    validation_sources = {
        "ancient": "validation/final-headless-suite.json", "camera": "validation-camera/camera-suite.json",
        "regression": "validation-regression/regression-suite.json", "make_test": "make-test-complete/report.json"}
    validation = {}
    for label, name in validation_sources.items():
        result = json.loads(files[prefix + "/" + name])
        require(result["passed"] and result["runtime_unchanged"], "Validation failed/changed runtime")
        require(result["runtime_fingerprint_before"] == order["current"], "Validation source differs")
        validation[label] = {"passed": True, "runtime_unchanged": True}
    by_key = {(c["run"], c["case"]): c for c in cases}
    comparisons = []
    for period in ["day", "dusk", "night"]:
        row = {"period": period}
        for kind in ["old", "new"]:
            samples = [by_key[(f"{kind}-{period}-r{r}", "baseline/" + period)] for r in [1, 2, 3]]
            row[kind] = {metric: {key: statistics.mean(c["metrics"][metric][key] for c in samples)
                                 for key in ["mean_ms", "p95_ms"]} for metric in ["gpu", "render_cpu", "wall"]}
        row["gpu_mean_change_percent"] = 100 * (row["new"]["gpu"]["mean_ms"] / row["old"]["gpu"]["mean_ms"] - 1)
        comparisons.append(row)
    deltas = []
    for r in [1, 2, 3]:
        on = by_key[(f"new-night-r{r}", "baseline/night")]["metrics"]
        off = by_key[(f"new-night-r{r}", "plain_sky/night")]["metrics"]
        deltas.append({"round": r, "gpu_mean_delta_ms": on["gpu"]["mean_ms"] - off["gpu"]["mean_ms"],
                       "gpu_p95_delta_ms": on["gpu"]["p95_ms"] - off["gpu"]["p95_ms"]})
    budget = {"gpu_mean_delta_ms": statistics.mean(d["gpu_mean_delta_ms"] for d in deltas),
              "gpu_p95_delta_ms": statistics.mean(d["gpu_p95_delta_ms"] for d in deltas),
              "cpu_mean_ms_per_draw": statistics.mean(c["conservative_sky_and_entire_existing_focus_ms_per_draw"] for c in cpu),
              "texture_mipmap_upper_bound_mib": 4096 * 2048 * 4 * 4 / 3 / 1024**2,
              "limits": {"gpu_mean_delta_ms": .15, "gpu_p95_delta_ms": .20, "cpu_mean_ms_per_draw": .03, "texture_mipmap_upper_bound_mib": 48},
              "rounds": deltas}
    budget["passed"] = all(budget[name] <= limit for name, limit in budget["limits"].items())
    budget["every_gpu_round_passed"] = all(d["gpu_mean_delta_ms"] <= .15 and d["gpu_p95_delta_ms"] <= .20 for d in deltas)
    budget["every_cpu_round_passed"] = all(c["conservative_sky_and_entire_existing_focus_ms_per_draw"] <= .03 for c in cpu)
    capture = json.loads(files[prefix + "/accepted-render-v2/horizontal-capture.json"])
    require(capture["passed"] and capture["route_passed"] and not capture["write_failures"], "Capture/route failed")
    require(capture["runtime_fingerprint"] == order["current"], "Capture source mismatch")
    for label in ["route_frames", "night_frames"]:
        frames = capture[label]
        require(all(len(f["sha256"]) == 64 for f in frames), "Missing captured frame checksum")
        require(all(b["time_s"] > a["time_s"] for a, b in zip(frames, frames[1:])), "Nonmonotonic video timestamps")
    for shot in capture["screenshots"]:
        require(digest(files[prefix + "/accepted-render-v2/" + Path(shot["path"]).name]) == shot["sha256"], "Screenshot checksum mismatch")
    require(files[prefix + "/accepted-render-v2/night-still-a.png"] == files[prefix + "/accepted-render-v2/night-still-b.png"], "Stationary sky unstable")
    visual = json.loads(files[prefix + "/accepted-render-v2/visual-review.json"])
    require(visual["passed"] and all(v["returncode"] == 0 for v in visual["video_decodes"]), "Visual/video QA failed")
    return {"schema_version": 1, "verified": True, "runtime_fingerprint": order["current"],
            "original_runtime_fingerprint": order["original"], "measurement_count": len(cases), "process_count": 21,
            "archived_records": len(manifest["records"]), "conditions": {"viewport": [1920,1080], "renderer": "Forward+",
                "gpu": "NVIDIA GeForce RTX 4070 SUPER", "msaa": "2x", "warmup_s": 5, "sample_s": 30,
                "rounds": 3, "background_sleep_usec": 0, "readback_during_sampling": False},
            "aggregation": "Equal-weight mean of three per-round means/P95 values; P95 is not pooled. GPU and render CPU timings overlap. Instrumented CPU samples are separate.",
            "scope": "Real offscreen GPU rendering with moving physical exploration. Native window presentation/input latency is not measured. Old and new route geometry/duration differ, so the layout comparison does not isolate any single asset optimization. Night sky A/B uses the same new layout/route.",
            "layout_comparison": comparisons, "night_budget": budget, "cpu_instrumentation": cpu, "night_transitions": transitions,
            "all_cases": cases, "validation": validation, "render": {"screenshots": len(capture["screenshots"]), "route_frames": len(capture["route_frames"]),
                "night_frames": len(capture["night_frames"]), "route_physics_frames": capture["route_result"]["frames"],
                "route_wall_seconds": capture["route_elapsed_s"], "stationary_night_byte_identical": True}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", action="store_true", help="Copy completed local measurements and captures")
    parser.add_argument("--write-summary", action="store_true")
    args = parser.parse_args()
    if args.archive:
        archive()
    summary = verify()
    if args.write_summary:
        write_json(ARCHIVE / "summary.json", summary)
    else:
        require(json.loads((ARCHIVE / "summary.json").read_text()) == summary, "Summary differs from original samples")
    print(json.dumps({"verified": True, "measurements": summary["measurement_count"], "records": summary["archived_records"],
                      "night_budget": summary["night_budget"]}, indent=2))


if __name__ == "__main__":
    main()
