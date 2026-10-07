#!/usr/bin/env python3
"""Assemble acceptance only from independently completed, current reports."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

from run import ROOT, OUT
sys.path.insert(0, str(ROOT / "tools"))
from feature_fingerprint import fingerprint

# ROOT/tools also has an unrelated package.py. Resolve this scene's API by
# its exact sibling path, independent of the CLI's sys.path search order.
package_spec = importlib.util.spec_from_file_location(
    "ancient_canal_evidence_package", Path(__file__).resolve().with_name("package.py")
)
if package_spec is None or package_spec.loader is None:
    raise ImportError("Cannot load the Jiangnan evidence packaging API")
package_api = importlib.util.module_from_spec(package_spec)
sys.modules[package_spec.name] = package_api
package_spec.loader.exec_module(package_api)
audit_source_inventory = package_api.audit_source_inventory
audit_settings_chain = package_api.audit_settings_chain
audit_review_links = package_api.audit_review_links
audit_revision_history = package_api.audit_revision_history
linked_record = package_api.linked_record
evidence_path = package_api.evidence_path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(name):
    return json.loads((OUT / name).read_text())


def write(name, data):
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def current_report(name, current):
    data = read(name)
    if not data.get("passed") or data.get("runtime_fingerprint") != current:
        raise RuntimeError("Incomplete or stale evidence: " + name)
    return data


def record(name):
    path = evidence_path(name)
    return {"path": name, "sha256": sha(path)}


def main():
    from PIL import Image
    current = fingerprint(ROOT)["sha256"]
    _, _, source_review = audit_source_inventory(current)
    names = {
        "sources": "source-check.json", "headless": "headless/report.json",
        "input_regression": "input-regression-report.json", "video": "video-report.json",
        "performance": "performance/performance-report.json", "settings": "settings-report.json",
        "standalone": "standalone-report.json",
    }
    reports = {key: current_report(name, current) for key, name in names.items()}
    for name in ["blockout.json", "freeze-report.json", "final-headless-suite.json", "export-report.json"]:
        current_report(name, current)
    settings_raw = audit_settings_chain(reports["settings"], current)
    for item in reports["input_regression"].get("artifacts", []):
        linked_record(item, "input regression")
    manual_names = ["visual-review.json", "route-visual-review.json", "video-review.json", "scene-comparison.json", "video-chain-audit.json", "video-decode-audit.json", "standalone-visual-review.json"]
    review_artifact_names = set()
    for name in manual_names:
        reviewed = current_report(name, current)
        audit_review_links(reviewed, current)
        review_artifact_names.update(item.get("path", item.get("file")) for item in reviewed.get("review_artifacts", []))
    # Decoded contacts document the review; they are derived montage pixels,
    # separate from the native 1080p GPU screenshot collection below.
    review_artifact_names.update(path.relative_to(OUT).as_posix() for path in (OUT / "video-review").rglob("*") if path.is_file() and path.suffix.lower() in {".png", ".json"})
    dock = current_report("dock-stability/dock-stability-report.json", current)
    upright = current_report("upright-validation-gpu/upright-report.json", current)
    if dock.get("visual_review_passed") is not True:
        raise RuntimeError("Actual moving dock contacts are not independently visually reviewed")
    if not upright.get("gpu_basis_executed"):
        raise RuntimeError("Upright shader helper has not executed on hardware GPU")
    quick = current_report("render/quick-report.json", current)
    calibration = current_report("normal-calibration/calibration-report.json", current)
    normal = current_report("character-normal-render/normal-render-report.json", current)
    route = current_report("route-render/route-render-report.json", current)
    if not all(data.get("hardware_gpu") for data in [calibration, normal, route]):
        raise RuntimeError("GPU scopes must have actual hardware evidence")
    if not reports["performance"].get("all_periods_60fps_p95_met"):
        raise RuntimeError("Real-time performance target remains unmet")
    if not all(item.get("draw_counters", {}).get("passed") for item in reports["performance"]["presets"].values()):
        raise RuntimeError("Independent completed-draw counters remain unproven")
    if len(normal["bindings"]) != 108 or normal["recorded_frames"] != 648:
        raise RuntimeError("Incomplete character capture")
    screenshots = []

    def screenshot(name, scope, producer_sha=None):
        item = record(name)
        if producer_sha is not None and item["sha256"] != producer_sha:
            raise RuntimeError("Capture changed: " + name)
        if Image.open(OUT / name).size != (1920, 1080):
            raise RuntimeError("Wrong actual viewport: " + name)
        screenshots.append({**item, "scope": scope})

    for item in quick["screenshots"]:
        screenshot(item["path"], item["scope"], item["sha256"])
    for path in sorted((OUT / "normal-calibration").glob("*.png")):
        if Image.open(path).size == (1920, 1080):
            screenshot(path.relative_to(OUT).as_posix(), "Actual native sphere, native normal quad and spatial shader calibration")
    for clip in normal["clips"]:
        for frame in clip["frames"]:
            if frame["cycle"] == 0 and frame["frame"] in (0, 6, 13, 20, 26):
                screenshot("character-normal-render/" + frame["file"], "Actual character key pose: " + clip["direction"], frame["sha256"])
    dock_producer = current_report(dock["source_report"], current)
    for item in dock_producer["frames"]:
        screenshot(item["file"], "Actual dock camera stability and physical ramp traversal", item["sha256"])
    for item in dock.get("review_artifacts", []):
        review_artifact_names.add(item.get("path", item.get("file")))
    reviewed_route = read("route-visual-review.json")
    for item in reviewed_route.get("viewed_actual_gpu_frames", []):
        name = item.get("path", item.get("file"))
        if name:
            screenshot(name, "Actual physical route representative frame", item.get("sha256"))
    gpu = {
        "schema_version": 1, "passed": True, "runtime_fingerprint": current,
        "gpu": True, "adapter": calibration["adapter"], "renderer": calibration["renderer"],
        "viewport": [1920, 1080], "screenshots": screenshots,
        "capture_mode": "Minimized, no-focus native window and independent real hardware GPU SubViewport",
        "reports": [record(n) for n in ["render/quick-report.json", "normal-calibration/calibration-report.json", "character-normal-render/normal-render-report.json", "route-render/route-render-report.json", "dock-stability/dock-stability-report.json", "dock-stability/dock-visual-review.json", "upright-validation-gpu/upright-report.json", *manual_names]],
        "review_artifacts": [{**record(name), "origin": "mp4-decoding" if name.startswith("video-review/") else "gpu-source-review", "scope": "Derived MP4 decode contact; not a native 1080p GPU screenshot" if name.startswith("video-review/") else "Derived original-GPU frame contact; not a native 1080p GPU screenshot"} for name in sorted(review_artifact_names)],
        "review_artifact_counts": {"decoded_video_contacts": sum(name.startswith("video-review/") and name.endswith(".png") for name in review_artifact_names), "source_frame_contacts": sum(name.startswith("visual-review/") and name.endswith(".png") for name in review_artifact_names)},
        "scope": "Actual scene pixels, native material calibration, all 108 pose bindings, three loops per direction, clay cardinal sweeps and physical route. Performance is measured separately; no foreground presentation claim.",
    }
    write("gpu-report.json", gpu)
    names["gpu"] = "gpu-report.json"
    requirements = [{**entry, "evidence": list(entry["evidence"])} for entry in source_review["requirements"]]
    extra = [
        ("calibration", "Actual native sphere/normal quad and spatial billboard brightness under eight cardinal/camera tests, zero strength and Y calibration.", ["normal-calibration/calibration-report.json"]),
        ("visual_loops", "All four original directions: three complete 27-pose loops each, two internal seams, original 41/42ms durations, shared color/normal/mask index; actual encoded clips reviewed.", ["character-normal-render/normal-render-report.json", "visual-review.json", "video-report.json", "video-review.json"]),
        ("light_sweeps", "Actual clay orbit-light and four cardinal directions, editable anatomical normals follow hair, braids, cloth, skirt and silver. Gray test lamp shadows disabled only for form isolation; scene geometry shadows retained separately.", ["normal-calibration/calibration-report.json", "character-normal-render/normal-render-report.json", "visual-review.json", "video-report.json", "video-review.json"]),
        ("scene_comparison", "Selected A composition adapted to walkable 3D coordinates: central canal and arch, right tavern/food stall, left cloth stall, dock/boat, coherent palette, identifiable original hero and actual projected shadows.", ["scene-comparison.json", "route-visual-review.json", "render/quick-report.json"]),
        ("interaction", "Actual collision-world traversal of both banks, bridge slopes, dock ramp and return; NPC/sign interaction, water blocking, real automatic route and cancellation with controls restored.", ["headless/report.json", "blockout.json", "route-render/route-render-report.json"]),
        ("input_safety", "Synthesized real GUI dispatch: text focus, popup/Tab/Escape priority, modifiers/repeats, editor F8/F9 safety, route cancellation and cleanup.", ["headless/report.json", "input-regression-report.json", "regression/input-dispatch.json"]),
        ("parameters", "All 68 scene fields plus five selected-lamp fields across four Chinese console pages, actual material/light/environment/camera changes and readbacks, presets preserve camera/DOF, fixed comparison and defaults.", ["headless/report.json", "render/quick-report.json"]),
        ("settings", "Independent settings schema, restore defaults, invalid input rejection and separate actual save/load scene processes; material/light/camera/DOF values restored.", ["headless/report.json", "settings-report.json"]),
        ("old_regression", "Existing character/camera/lens/P9 scene/input tests passed; source project entry preserved. No foreground editor shortcut delivery claim.", ["input-regression-report.json", "regression/transcript.txt", "regression/input-dispatch.json", "export-report.json"]),
        ("gpu_performance", "Each day/dusk/night preset: at least 5 seconds warmup and 30 real-time seconds with moving physics/HUD, actual 1920x1080 GPU draws, no capture readback, raw intervals and linear quantiles; P95 within 16.667ms. Offscreen throughput only.", ["performance/performance-report.json", "performance/day-samples.json", "performance/dusk-samples.json", "performance/night-samples.json"]),
        ("standalone", "Current ELF alone in empty CWD with fresh user directories boots the new scene without an explicit scene argument; actual headless resources and separate actual GPU pixels verified.", ["standalone-report.json", "export-report.json"]),
    ]
    extra.extend([
        ("camera_profiles", "Ancient fixed Frontal-derived controller: independent F/W radius/FOV, stable actor center, per-axis outer-map follow limits and lens bounds; schema 1 and complete legacy F/W/O migrations preserve valid settings, do not write until explicit save.", ["headless/report.json", "settings-report.json", "final-headless-suite.json", "render/quick-report.json"]),
        ("upright_sprites", "Original hero and all three NPC meshes stand in world UP; production GLSL basis executed on GPU, tangent normal and shadow passes share horizontal facing, frame/foot assets unchanged.", ["upright-validation-gpu/upright-report.json", "normal-calibration/calibration-report.json", "visual-review.json", "scene-comparison.json"]),
        ("distant_scenery", "Six physical-depth layers, eight additional houses, continuous cloud movement and projection-based artistic compensation; fixed paths/collisions preserved. Default and both banks visually checked without fog.", ["final-headless-suite.json", "headless/report.json", "scene-comparison.json", "render/quick-report.json"]),
        ("streetlights", "Six wood-post lights at 2.6m, four-meter range, period intensities 0.05/0.8/1.4; two default shadows, independent groups and actual per-lamp properties, collision, isolated fixed lamp and exact restore, persistent overrides.", ["headless/report.json", "final-headless-suite.json", "settings-report.json", "scene-comparison.json"]),
        ("dock_stability", "Formal dock helper draws nothing while its collision remains; old-angle and fixed F/W tiny-camera GPU regression plus actual moving, stopping and ramp traversal preserve plank surface without stone/wood alternation.", ["dock-stability/dock-stability-report.json", "route-visual-review.json", "route-render/route-render-report.json", "headless/report.json"]),
    ])
    requirements.extend({"id": key, "passed": True, "scope": scope, "evidence": evidence} for key, scope, evidence in extra)
    # Include subordinate raw evidence and review contacts without host logs/caches.
    supplements = ["source-hashes.json", "source-review.json", "final-headless-suite.json", "freeze-report.json", "launch-selfcheck-introspection.json", "benchmark-count-review.json"]
    history_record = None
    if (OUT / "revision-history.json").is_file():
        historical_paths = audit_revision_history(read("revision-history.json"))
        supplements.extend(path.relative_to(OUT).as_posix() for path in historical_paths)
        supplements.append("revision-history.json")
        history_record = {**record("revision-history.json"), "scope": "Retained historical revisions and failures; not current passing GPU or runtime evidence"}
    supplements.extend(item["path"] for item in reports["input_regression"].get("artifacts", []))
    supplements.extend(item["path"] for item in reports["settings"].get("artifacts", []))
    supplements.extend(item["path"] for item in reports["settings"].get("source_reports", []))
    supplements.extend(path.relative_to(OUT).as_posix() for path in settings_raw)
    supplements.extend(item["file"] for item in read("visual-review.json").get("review_artifacts", []))
    supplements.extend(sorted(review_artifact_names))
    supplements.extend(["video-chain-audit.json", "video-decode-audit.json"])
    # Preserve supplemental native GPU comparisons and exact upright basis
    # probe pixels; the tiny probe PNGs are data samples, not 1080p screenshots.
    character_review = read("visual-review.json")
    for item in character_review.get("additional_comparison_pngs", []):
        name = item.get("path", item.get("file"))
        linked_record({"path": name, "sha256": item["sha256"]}, "supplemental normal comparison")
        supplements.append(name)
    for folder in ["character-normal-render", "upright-validation-gpu"]:
        supplements.extend(path.relative_to(OUT).as_posix() for path in (OUT / folder).glob("*.png"))
    for name in ["route-review/contacts.json", "visual-review/contacts.json"]:
        if (OUT / name).is_file():
            supplements.append(name)
    source_requirement = next(entry for entry in requirements if entry["id"] == "sources")
    source_requirement["evidence"].extend(name for name in dict.fromkeys(supplements) if name not in source_requirement["evidence"])
    for requirement in requirements:
        for name in requirement["evidence"]:
            record(name)
    final = {
        "schema_version": 1, "passed": True, "status": "accepted", "runtime_fingerprint": current,
        "evidence": {key: record(name) for key, name in names.items()}, "requirements": requirements,
        "limitations": [
            "Performance measures real 1080p GPU offscreen rendering throughput on the recorded RTX 4070 SUPER; foreground presentation, compositor/display synchronization, native focus and input latency were not tested.",
            "Route video preserves actual observed wall-clock VFR and discloses skipped capture slots from PNG writer backpressure. It is not a performance recording; final still hold is explicitly inferred and recorded.",
            "Gray sweep test lamp projection is disabled to isolate form; ordinary scene geometry occlusion and adjustable shadows remain enabled and are checked separately.",
            "Three NPCs are stationary. Height-map self-shadowing is outside the first version. Technical visual acceptance does not replace personal art preference.",
        ],
        "committed": False, "pushed": False, "published": False,
    }
    if history_record is not None:
        final["revision_history"] = history_record
    if fingerprint(ROOT)["sha256"] != current:
        raise RuntimeError("Runtime changed while assembling acceptance")
    write("final-report.json", final)
    print("ANCIENT_CANAL_FINAL_EVIDENCE", len(requirements), "scopes", len(screenshots), "GPU screenshots")


if __name__ == "__main__":
    main()
