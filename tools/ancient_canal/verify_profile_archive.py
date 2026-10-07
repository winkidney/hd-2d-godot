"""Verify archived profiling bytes and recompute results without Godot or a GPU."""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import math
import statistics

ROOT = Path(__file__).resolve().parents[2]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def stats(values):
    require(bool(values), "Empty sample series")
    require(all(math.isfinite(v) and v >= 0 for v in values), "Invalid sample series")
    ordered = sorted(values)

    def quantile(fraction):
        position = (len(ordered) - 1) * fraction
        lo, hi = math.floor(position), math.ceil(position)
        return ordered[lo] + (ordered[hi] - ordered[lo]) * (position - lo)

    return {
        "sample_count": len(values),
        "mean_ms": statistics.mean(values),
        "p50_ms": quantile(.5),
        "p95_ms": quantile(.95),
        "p99_ms": quantile(.99),
    }


def verify(archive):
    manifest = json.loads((archive / "archive-manifest.json").read_text())
    files = {}
    stored_bytes = original_bytes = 0
    for record in manifest["records"]:
        path = archive / record["path"]
        require(path.resolve().is_relative_to(archive.resolve()), "Archive path escapes directory")
        stored = path.read_bytes()
        require(len(stored) == record["stored_bytes"], "Stored size mismatch: " + record["path"])
        require(hashlib.sha256(stored).hexdigest() == record["stored_sha256"], "Stored checksum mismatch: " + record["path"])
        require(record["encoding"] in ["gzip", "identity"], "Unknown encoding")
        original = gzip.decompress(stored) if record["encoding"] == "gzip" else stored
        require(len(original) == record["original_bytes"], "Original size mismatch: " + record["path"])
        require(hashlib.sha256(original).hexdigest() == record["original_sha256"], "Original checksum mismatch: " + record["path"])
        require(record["source"] not in files, "Duplicate original path")
        files[record["source"]] = original
        stored_bytes += len(stored)
        original_bytes += len(original)

    prefix = manifest["original_output_root"]
    cases = []
    cpu_functions = {}
    report_count = 0
    for name, content in sorted(files.items()):
        if not name.endswith("/performance-report.json"):
            continue
        report_count += 1
        report = json.loads(content)
        require(report["passed"] and not report["failures"], "Failed measurement report")
        require(report["hardware_gpu"] and report["renderer"] == "forward_plus", "Wrong renderer")
        require(report["preferences_ignored"] and report["main_window_minimized"] and report["no_focus"], "Isolation contract failed")
        require(report["readback_count"] == 0 and not report["fixed_fps"], "Invalid benchmark conditions")
        run = Path(name).parent.name
        for case_name, result in report["presets"].items():
            source = Path(name).parent / (case_name.replace("/", "-") + "-samples.json")
            content = files[source.as_posix()]
            require(hashlib.sha256(content).hexdigest() == result["sha256"], "Report/sample checksum mismatch")
            raw = json.loads(content)
            require(raw["draw_counters"]["passed"], "Draw counters failed")
            require(all(raw["draw_counters"]["checks"].values()), "Draw counter check failed")
            require(raw["readback_count"] == 0 and not raw["fixed_fps"], "Raw sample conditions failed")
            require(len(raw["frame_intervals_ms"]) == result["sample_count"], "Wrong sample count")
            require(all(v > 0 for v in raw["frame_intervals_ms"]), "Nonpositive frame interval")
            require(raw["runtime_fingerprint"] == report["runtime_fingerprint"], "Runtime fingerprint mismatch")
            metrics = {}
            for label, field in [("wall", "frame_intervals_ms"), ("gpu", "gpu_timings_ms"), ("render_cpu", "cpu_timings_ms")]:
                metrics[label] = stats(raw[field])
                expected = result if label == "wall" else result["gpu" if label == "gpu" else "cpu"]
                for key in ["mean_ms", "p50_ms", "p95_ms", "p99_ms"]:
                    require(abs(metrics[label][key] - expected[key]) < 1e-6, "Recomputed metric differs: " + run + "/" + case_name + "/" + key)
            cases.append({"run": run, "case": case_name, "source": source.as_posix(), "metrics": metrics, "completed_routes": result["completed_routes"], "inventory": raw.get("inventory")})
            if "instrumented_cpu" in raw:
                cpu_functions[case_name] = {
                    group: {function: stats(values) for function, values in items.items()}
                    for group, items in raw["instrumented_cpu"].items()
                }

    stage_source = json.loads(files[prefix + "/gpu-stages-corrected/baseline-dusk-samples.json"])
    stage_values = {}
    for frame in stage_source["timestamp_frames"]:
        totals = {}
        for begin, end in zip(frame["markers"], frame["markers"][1:]):
            name = begin["name"]
            if name.startswith((">", "<", "vp_")):
                continue
            gpu = (int(end["gpu_ns"]) - int(begin["gpu_ns"])) / 1e6
            cpu = (end["cpu_us"] - begin["cpu_us"]) / 1000
            totals.setdefault(name, [0., 0.])
            totals[name][0] += gpu
            totals[name][1] += cpu
        for name, values in totals.items():
            stage_values.setdefault(name, []).append(values)
    stages = [
        {"name": name, "samples": len(values), "mean_gpu_ms": statistics.mean(v[0] for v in values), "mean_cpu_ms": statistics.mean(v[1] for v in values)}
        for name, values in stage_values.items()
    ]
    stages.sort(key=lambda v: v["mean_gpu_ms"], reverse=True)
    recorded_stages = json.loads(files[prefix + "/gpu-stage-summary-corrected.json"])
    require(stages == recorded_stages, "Stage summary differs from raw timestamps")

    verification = json.loads(files[prefix + "/verification-summary.json"])
    require(verification["all_passed"] and verification["runtime_unchanged"], "Original verification failed")
    require(len(cases) == sum(len(v["samples"]) for v in verification["checks"]), "Missing original cases")
    for name, content in files.items():
        if name.endswith("/manifest.json"):
            launch = json.loads(content)
            benchmark = files["tools/ancient_canal/benchmark.gd"]
            require(hashlib.sha256(benchmark).hexdigest() == launch["benchmark_sha256"], "Benchmark source mismatch")
            parent = Path(name).parent
            require(hashlib.sha256(files[(parent / "probe.gd").as_posix()]).hexdigest() == launch["probe_sha256"], "Generated probe mismatch")
            for source, checksum in launch.get("generated_sha256", {}).items():
                require(hashlib.sha256(files[(parent / source).as_posix()]).hexdigest() == checksum, "Generated script mismatch")

    by_case = {(case["run"], case["case"]): case for case in cases}
    baseline = by_case[("ablation-b", "baseline/dusk")]["metrics"]
    comparisons = []
    for case in cases:
        if case["run"] != "ablation-b":
            continue
        comparisons.append({"case": case["case"], **case["metrics"], "gpu_reduction_percent": 100 * (1 - case["metrics"]["gpu"]["mean_ms"] / baseline["gpu"]["mean_ms"]), "render_cpu_reduction_percent": 100 * (1 - case["metrics"]["render_cpu"]["mean_ms"] / baseline["render_cpu"]["mean_ms"])})
    confirm = by_case[("confirm", "baseline/dusk")]["metrics"]
    low = by_case[("confirm", "dof_low/dusk")]["metrics"]
    return {
        "schema_version": 1,
        "verified": True,
        "measurement_count": len(cases),
        "report_count": report_count,
        "archived_records": len(files),
        "original_bytes": original_bytes,
        "stored_bytes": stored_bytes,
        "source_commit": manifest["source_commit"],
        "runtime_fingerprint": verification["runtime_fingerprint_before"],
        "conditions": verification["conditions"],
        "baseline_corrected_dusk": baseline,
        "dof_low_gpu_reduction_percent": 100 * (1 - low["gpu"]["mean_ms"] / confirm["gpu"]["mean_ms"]),
        "normal_comparison_scope": "Shared normal switch affects actor/NPC shader branches and building normal_scale; not an isolated character texture cost. Difference is within small measurement variability.",
        "scope": "Offscreen rendering only; CPU function timings include instrumentation; nested function times cannot be added; interventions are diagnostic and gains cannot be summed.",
        "gpu_stages": stages,
        "cpu_functions": cpu_functions,
        "comparisons": comparisons,
        "all_cases": cases,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=ROOT / "docs/ancient-canal/profiling/20261008")
    parser.add_argument("--write-summary", action="store_true")
    args = parser.parse_args()
    archive = args.archive.resolve()
    summary = verify(archive)
    output = archive / "summary.json"
    if args.write_summary:
        output.write_text(json.dumps(summary, indent=2) + "\n")
    else:
        require(json.loads(output.read_text()) == summary, "Saved summary differs from recomputed data")
    print(f'PASS: {summary["measurement_count"]} measurements, {summary["report_count"]} reports, {summary["archived_records"]} byte-verified records; summary recomputed from raw data')


if __name__ == "__main__":
    main()
