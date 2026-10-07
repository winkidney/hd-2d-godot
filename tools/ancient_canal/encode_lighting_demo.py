#!/usr/bin/env python3
"""Encode and audit a chaptered hardware-GPU demonstration at observed wall PTS.

Never renders or edits captures, resizes video, inserts frames, or measures FPS.
Decoded contacts are derived inspection aids; visual approval is separate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from feature_fingerprint import fingerprint
from encode_evidence import OUT, SIZE, check_report, encode_clip, load, need, packet_probe, png_from_report, portable, save, scoped_file, sha

DEFAULT = OUT / "tavern-lighting-20261007"
STEM = "jiangnan-lighting-closeup"
MAX_MAE, MIN_PSNR = 4.0, 32.0
CAPTION = (30, 30, 1030, 110)
NORMAL_PIXEL_MARGIN = 32  # Include local bloom around the character silhouette.


def receipt(path):
    return {"path": portable(path), "sha256": sha(path)}


def presentation(rows):
    times = [float(r["wall_elapsed_ms"]) for r in rows]
    need(len(times) > 20 and all(math.isfinite(t) for t in times), "Incomplete or nonfinite captured wall timeline")
    need(all(b > a for a, b in zip(times, times[1:])), "Captured wall timestamps repeat or go backward")
    pts = [round(t - times[0]) for t in times]
    need(all(b > a for a, b in zip(pts, pts[1:])), "Wall timestamps collide at the 1ms video time base")
    observed = [b - a for a, b in zip(pts, pts[1:])]
    hold = max(1, round(statistics.median(observed)))
    return times, pts, observed + [hold]


def producer(path, current):
    data = check_report(path, current)
    need(data.get("failures") == [] and data.get("no_fixed_fps") is True and data.get("time_scale") == 1.0 and data.get("physics_ticks_per_second") == 60, "Producer failed or used synthetic simulation timing")
    need(data.get("automatic_route_result", {}).get("passed") is True and data.get("physical_movement_metres", 0) > 40, "Full physical demonstration route did not complete")
    rows = data["frames"]
    times, pts, durations = presentation(rows)
    diagnostics = data.get("occlusion_diagnostics", {})
    need(diagnostics.get("visual_mesh_proxies", 0) > 20 and diagnostics.get("visual_triangles", 0) > 1000 and diagnostics.get("closeup_physics_checks", 0) > 100 and diagnostics.get("models_hidden") is False, "Actual visible-mesh/NPC-alpha occlusion diagnostics missing")
    need(diagnostics.get("query_only_layer", 0) > 0 and diagnostics["query_only_layer"] & diagnostics["player_collision_mask"] == 0, "Diagnostic ray proxies alter the player collision mask")
    need(all(r["sequence_index"] == i and r.get("png_valid_1080p") is True and r.get("full_body_in_frame") is True for i, r in enumerate(rows)), "Source images missing, reordered or character silhouette cropped")
    critical_closeups = {temperature + "-" + direction for temperature in ("cool", "warm") for direction in ("up", "right", "down", "left")} | {"day", "night", "normal-on", "normal-off", "normal-on-restored"}
    for row in rows:
        if row["chapter"] in critical_closeups:
            occlusion = row.get("occlusion", {})
            need(occlusion.get("sampled_actual_alpha_points", 0) > 0 and occlusion.get("blocked_alpha_points") == 0 and occlusion.get("clear") is True, "Critical character close-up blocked by real mesh/NPC alpha rays")
    paths = [png_from_report(path, r["file"], r["sha256"]) for r in rows]
    chapters = []
    owners = []
    for row in rows:
        candidates = [i for i, c in enumerate(data["chapters"]) if c["id"] == row["chapter"] and c["first_wall_ms"] <= row["wall_elapsed_ms"] + .001]
        need(bool(candidates), "Frame lacks a preceding matching chapter start")
        owners.append(candidates[-1])
    for i, c in enumerate(data["chapters"]):
        packets = [j for j, owner in enumerate(owners) if owner == i]
        need(bool(packets), "Chapter instance has no actual GPU frame")
        chapters.append({**c, "chapter_index": i, "first_packet": packets[0], "last_packet": packets[-1], "captured_frames": len(packets), "video_start_ms": pts[packets[0]], "video_end_ms": pts[packets[-1]] + durations[packets[-1]]})
    by_id = {name: [i for i, r in enumerate(rows) if r["chapter"] == name] for name in data["chapter_frame_counts"]}
    for temperature in ("cool", "warm"):
        for direction in ("up", "right", "down", "left"):
            matches = [rows[i] for i in by_id[temperature + "-" + direction] if rows[i]["walking"] and rows[i]["direction"] == direction]
            need(len(matches) >= 5, "Missing actual cold/warm walking direction close-up")
            need(all(r["shot"] == "character-closeup" and r["projected_role_height_px"] >= 480 and r["normals_enabled"] is True for r in matches), "Walking close-up lacks native size or actual normals")
    for name, near, far in [("near-dof", True, False), ("far-dof", False, True)]:
        need(all(rows[i]["actual_dof_near_enabled"] is near and rows[i]["actual_dof_far_enabled"] is far and 0 < rows[i]["dof_amount"] <= .5 for i in by_id[name]), "Actual separate near/far DOF differs from chapter")
    side = [c for c in chapters if c["id"] == "building-side"]
    need(len(side) == 1 and side[0]["side_geometry"]["side_view_angle_degrees"] > 8 and side[0]["side_geometry"]["camera_supported"] is True, "Building side lacks supported actual perspective")
    periods = {r["period"] for r in rows}
    need({"day", "dusk", "night"}.issubset(periods) and periods.issubset({"day", "dusk", "night", "custom"}), "Three real periods missing or unknown period captured")
    need(all(r["chapter"] in ("normal-pair-approach", "normal-on", "normal-off", "normal-on-restored") for r in rows if r["period"] == "custom"), "Custom normal-test lighting used outside final preparation/comparison chapters")
    triples = data["normal_only_comparison"]
    need([s["normals_enabled"] for s in triples] == [True, False, True] and all(s["matches_baseline"] is True for s in triples), "Normal ON/OFF/ON report triple incomplete")
    baseline = triples[0]["fixed_state"]
    need(all(s["fixed_state"] == baseline for s in triples), "Normal comparison changed frozen state")
    for name, flag in [("normal-on", True), ("normal-off", False), ("normal-on-restored", True)]:
        need(all(rows[i]["normals_enabled"] is flag and all(rows[i].get(k) == v for k, v in baseline.items()) for i in by_id[name]), "Actual per-image normal shader flag or fixed state differs")
    framing = data["framing"]
    heights = [float(r["projected_role_height_px"]) for r in rows if r["shot"] == "character-closeup"]
    need(min(heights) >= 480 and framing["character_cropped_frames"] == 0 and framing["source_frames_resized"] is False, "Native character close-up framing failed")
    need(abs(min(heights) - framing["minimum_visible_height_px"]) < 1e-8 and abs(max(heights) - framing["maximum_visible_height_px"]) < 1e-8, "Framing extrema differ from source rows")
    return data, paths, times, pts, durations, chapters, owners, by_id


def encode(args):
    current = fingerprint(ROOT)["sha256"]
    report_path = scoped_file(Path(args.producer).resolve())
    initial_sha = sha(report_path)
    data, paths, times, pts, durations, chapters, owners, _ = producer(report_path, current)
    folder = Path(args.output_dir).resolve()
    portable(folder)
    need(not folder.exists(), "Use a fresh scoped video output directory; previous evidence is preserved")
    frames = []
    for i, (row, path, duration) in enumerate(zip(data["frames"], paths, durations)):
        metadata = {k: v for k, v in row.items() if k not in ("file", "sha256")}
        metadata.update(producer_png_sha256=row["sha256"], chapter_index=owners[i], wall_time_rounding_error_ms=pts[i] - (times[i] - times[0]))
        frames.append({"path": path, "duration_ms": duration, "source_metadata": metadata})
    metadata = {"timing_source": "actual monotonic GPU capture wall time rounded once to nearest ms; sample gaps retained as VFR", "first_wall_elapsed_ms": times[0], "last_wall_elapsed_ms": times[-1], "terminal_duration_ms": durations[-1], "terminal_duration_inferred": True, "terminal_duration_method": "median observed adjacent presentation interval; inference applies only to terminal still", "chapters": chapters, "sampling": data["sampling"], "framing": data["framing"], "occlusion_diagnostics": data["occlusion_diagnostics"], "normal_only_comparison": data["normal_only_comparison"], "critical_closeup_occlusion": {"source":"actual per-frame visible mesh triangle and NPC alpha ray metadata; all cold/warm directions, day/night and normal triple sampled clear", "passed":True}, "scope": "Original native GPU captures and real CharacterBody3D motion. Capture/readback gaps are preserved; no smooth30fps or performance claim."}
    video = encode_clip(STEM, frames, folder, "Full Jiangnan demonstration with native character close-ups, cold/warm four-direction walking, three periods, near/far DOF, building-side geometry, full route and fixed normal ON/OFF/ON", [c["id"] for c in chapters], report_path, metadata)
    need(sha(report_path) == initial_sha and fingerprint(ROOT)["sha256"] == current, "Producer or runtime changed while encoding")
    result = {"schema_version": 1, "passed": True, "runtime_fingerprint": current, "scope": "Provenance and exact observed-wall VFR encoding only; decoded quality and visual review are separate", "videos": [video], "source_reports": [receipt(report_path)], "chapters": chapters, "sampling": data["sampling"], "framing": data["framing"], "occlusion_diagnostics": data["occlusion_diagnostics"], "source_pngs_unmodified": True, "interpolated_frames": 0, "resized_frames": 0, "duplicated_frames": 0, "visual_review_passed": None, "ffmpeg_version": subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0]}
    save(folder / "video-report.json", result)
    print("LIGHTING_DEMO_ENCODED", len(frames), sum(durations), "ms", flush=True)


def read_frame(pipe, size):
    data = bytearray()
    while len(data) < size:
        part = pipe.read(size - len(data))
        if not part:
            break
        data.extend(part)
    return bytes(data)


def audit(args):
    import numpy as np
    current = fingerprint(ROOT)["sha256"]
    folder = Path(args.output_dir).resolve()
    report_path = scoped_file(folder / "video-report.json")
    report_sha = sha(report_path)
    report = load(report_path)
    need(report["passed"] is True and report["runtime_fingerprint"] == current and len(report["videos"]) == 1, "Missing current complete encoded demo")
    record = report["videos"][0]
    artifacts = {}
    for key in ("path", "timing_report", "concat_source", "source_report"):
        path = scoped_file(OUT / record[key])
        digest_key = "sha256" if key == "path" else key + "_sha256"
        need(sha(path) == record[digest_key], "Video artifact SHA mismatch: " + key)
        artifacts[key] = path
    source, paths, times, pts, durations, chapters, owners, by_id = producer(artifacts["source_report"], current)
    need(report["chapters"] == chapters and report["source_reports"] == [receipt(artifacts["source_report"])], "Aggregate chapter or producer chain differs")
    need(all(report[k] == source[k] for k in ("framing", "sampling", "occlusion_diagnostics")), "Aggregate framing, sampling or occlusion metadata differs from producer")
    need(report["source_pngs_unmodified"] is True and all(report[k] == 0 for k in ("interpolated_frames", "resized_frames", "duplicated_frames")), "Video report claims changed/synthesized source images")
    timing = load(artifacts["timing_report"])
    need(timing["passed"] is True and len(timing["frames"]) == len(paths) and timing["metadata"]["chapters"] == chapters, "Timing source/chapter count differs")
    need(all(timing["metadata"][k] == source[k] for k in ("framing", "sampling", "occlusion_diagnostics", "normal_only_comparison")), "Timing state summaries differ from real GPU producer")
    need(timing["source_report_sha256"] == record["source_report_sha256"] and timing["duration_ms"] == sum(durations), "Timing producer or total differs")
    lines = artifacts["concat_source"].read_text().splitlines()
    need(len(lines) == 1 + 3 * len(paths) and lines[0] == "ffconcat version 1.0", "Concat has extra/missing entries")
    for i, (row, path, t, duration) in enumerate(zip(source["frames"], paths, timing["frames"], durations)):
        need(t["packet"] == i and t["source_png"] == portable(path) and t["source_png_sha256"] == row["sha256"] and t["producer_png_sha256"] == row["sha256"] and t["pts_ms"] == pts[i] and t["duration_ms"] == duration, "Source frame/packet identity or observed timing differs")
        need(t["chapter_index"] == owners[i] and all(t.get(k) == v for k, v in row.items() if k not in ("file", "sha256")), "Encoded state metadata differs from actual source PNG state")
        relative = os.path.relpath(path, artifacts["concat_source"].parent).replace(os.sep, "/").replace("'", "'\\''")
        need(lines[1 + 3*i:4 + 3*i] == ["file '" + relative + "'", "option framerate 1000", f"duration {duration/1000:.6f}"], "Reproducible concat source differs")
    probe = packet_probe(artifacts["path"])
    need(len(probe["packets"]) == len(paths) and len(probe["streams"]) == 1 and (probe["streams"][0]["width"], probe["streams"][0]["height"]) == SIZE, "Actual MP4 packets or native size differ")
    for i, packet in enumerate(probe["packets"]):
        need(abs(float(packet["pts_time"])*1000-pts[i]) < .0001 and abs(float(packet["dts_time"])*1000-pts[i]) < .0001 and abs(float(packet["duration_time"])*1000-durations[i]) < .0001, "Fresh ffprobe PTS/DTS/duration differs from observed source wall time")
        stored = timing["packets"][i]
        need(stored["packet"] == i and abs(stored["pts_ms"]-pts[i]) < .0001 and abs(stored["duration_ms"]-durations[i]) < .0001, "Stored packet timing differs from fresh independent ffprobe")
    need(abs(float(probe["format"]["duration"])*1000-sum(durations)) < .0001, "Actual MP4 duration differs")
    need(record["frame_count"] == len(paths) and abs(record["duration_s"]*1000-sum(durations)) < .0001 and record["viewport"] == list(SIZE) and record["time_base"] == probe["streams"][0]["time_base"], "Top video count/duration/native-size/timebase differs from actual encoded stream")
    selected = {}
    for c in chapters:
        candidates = list(range(c["first_packet"], c["last_packet"]+1))
        moving = [i for i in candidates if source["frames"][i]["walking"] and source["frames"][i]["chapter"] == c["id"]]
        if c["id"].startswith(("cool-", "warm-")) and c["id"].split("-")[-1] in ("up", "right", "down", "left"):
            moving = [i for i in moving if source["frames"][i]["direction"] == c["id"].split("-")[-1]]
            need(bool(moving), "Decoded selected walking chapter has no actual matching direction")
        candidates = moving or candidates
        selected.setdefault(candidates[len(candidates)//2], []).append({"chapter_index": c["chapter_index"], "chapter": c["id"], "title": c["title"]})
    review = folder / "decoded-review"
    need(not review.exists(), "Decoded review already exists; use a fresh encoded output folder")
    review.mkdir(parents=True)
    metrics, samples = [], []
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-threads", "1", "-noautorotate", "-i", str(artifacts["path"]), "-map", "0:v:0", "-an", "-sn", "-dn", "-fps_mode", "passthrough", "-threads", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
    with (review / "decoder.txt").open("wb") as log:
        decoder = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=log)
        try:
            for i, (path, row) in enumerate(zip(paths, source["frames"])):
                raw = read_frame(decoder.stdout, SIZE[0]*SIZE[1]*3)
                need(len(raw) == SIZE[0]*SIZE[1]*3, "Missing native decoded frame")
                need(sha(path) == row["sha256"], "Source PNG changed during actual decode")
                rgb = np.frombuffer(raw, dtype=np.uint8).reshape(SIZE[1], SIZE[0], 3)
                with Image.open(path) as image:
                    original = np.asarray(image.convert("RGB"))
                difference = rgb.astype(np.int16) - original.astype(np.int16)
                mae = float(np.abs(difference).mean())
                mse = float(np.square(difference, dtype=np.float32).mean(dtype=np.float64))
                psnr = 10*math.log10(255*255/mse) if mse else None
                need(mae <= MAX_MAE and (psnr is None or psnr >= MIN_PSNR), "Decoded quality failed fixed MAE/PSNR policy")
                digest = hashlib.sha256(raw).hexdigest()
                metrics.append({"packet": i, "source_png": portable(path), "source_png_sha256": row["sha256"], "decoded_RGB_sha256": digest, "RGB_MAE_8bit": mae, "PSNR_dB": psnr})
                if i in selected:
                    destination = review / "full" / f"packet-{i:06}.png"
                    destination.parent.mkdir(exist_ok=True)
                    Image.fromarray(rgb).save(destination)
                    samples.append({**receipt(destination), "packet": i, "chapters": selected[i], "pts_ms": pts[i], "source_png": portable(path), "source_png_sha256": row["sha256"], "decoded_RGB_sha256": digest, "actual_state": row, "scope": "Native1920x1080 decoded MP4 sample, derived from actual GPU capture; no new rendering"})
                if (i+1) % 100 == 0:
                    print("LIGHTING_DEMO_DECODE_PROGRESS", i+1, "of", len(paths), flush=True)
            need(decoder.stdout.read(1) == b"" and decoder.wait(timeout=30) == 0, "Extra decoded frame or decoder failure")
        finally:
            if decoder.poll() is None:
                decoder.kill(); decoder.wait(timeout=10)
            decoder.stdout.close()
    # Source PNG equality localizes the normal toggle, independently of H.264.
    normal_indices = [by_id[n][len(by_id[n])//2] for n in ("normal-on", "normal-off", "normal-on-restored")]
    source_images = [np.asarray(Image.open(paths[i]).convert("RGB")) for i in normal_indices]
    mask = np.ones((SIZE[1], SIZE[0]), dtype=bool)
    mask[CAPTION[1]:CAPTION[3], CAPTION[0]:CAPTION[2]] = False
    restored_diff = np.abs(source_images[0].astype(np.int16)-source_images[2].astype(np.int16))
    need(int(restored_diff[mask].max()) == 0, "Normal restored image differs outside chapter caption")
    bounds = source["frames"][normal_indices[0]]["projected_visible_bounds"]
    x1, y1, x2, y2 = math.floor(bounds[0])-NORMAL_PIXEL_MARGIN, math.floor(bounds[1])-NORMAL_PIXEL_MARGIN, math.ceil(bounds[2])+NORMAL_PIXEL_MARGIN, math.ceil(bounds[3])+NORMAL_PIXEL_MARGIN
    outside = mask.copy(); outside[max(0,y1):min(SIZE[1],y2), max(0,x1):min(SIZE[0],x2)] = False
    toggle_diff = np.abs(source_images[0].astype(np.int16)-source_images[1].astype(np.int16))
    toggle_changed = int(np.any(toggle_diff>1, axis=2)[mask].sum())
    need(toggle_changed > 100 and int(toggle_diff[outside].max()) <= 1 and float(toggle_diff[outside].mean()) < .0001, "Normal toggle changed world pixels beyond character or had no measurable character response")
    normal_check = {"passed": True, "packets": normal_indices, "source_pngs": [receipt(paths[i]) for i in normal_indices], "caption_rectangle": list(CAPTION), "character_alpha_bound_with_local_bloom_margin": [x1,y1,x2,y2], "local_bloom_margin_px": NORMAL_PIXEL_MARGIN, "restored_pixels_changed_outside_caption": 0, "on_off_character_response_pixels_over_1LSB": toggle_changed, "on_off_outside_character_max_RGB_change": int(toggle_diff[outside].max()), "on_off_outside_character_RGB_MAE": float(toggle_diff[outside].mean()), "actual_shader_flags": [True,False,True], "fixed_pose_lights_camera_environment_state_equal": True, "scope": "Fresh original PNG ON/OFF/ON pixels. Restored scene is identical outside captions; off response confined to projected character and a predeclared local bloom margin apart from <=1LSB rounding."}
    contacts = []
    for start in range(0,len(samples),8):
        batch = samples[start:start+8]
        board = Image.new("RGB", (1920, math.ceil(len(batch)/4)*310), (24,31,38)); draw = ImageDraw.Draw(board)
        for j, s in enumerate(batch):
            tile = Image.open(OUT/s["path"]).resize((480,270),Image.Resampling.NEAREST)
            x,y = (j%4)*480,(j//4)*310
            board.paste(tile,(x,y+40)); draw.text((x+4,y+3),s["chapters"][0]["chapter"]+f" #{s['packet']}",fill="white"); draw.text((x+4,y+20),f"{s['pts_ms']}ms height={s['actual_state']['projected_role_height_px']:.1f}px",fill="white")
        destination = review / f"chapter-contact-{start//8:02}.png"; board.save(destination)
        contacts.append({**receipt(destination), "scope": "Derived nearest-neighbour decoded inspection contact; not native GPU evidence or resized video", "packets": [s["packet"] for s in batch], "sources": [{k:s[k] for k in ("path","sha256","decoded_RGB_sha256","source_png","source_png_sha256")} for s in batch]})
    need(fingerprint(ROOT)["sha256"] == current and sha(report_path) == report_sha, "Runtime or encoded report changed during audit")
    for key,path in artifacts.items():
        need(sha(path) == record["sha256" if key == "path" else key+"_sha256"], "Source artifact changed during audit")
    finite = [m["PSNR_dB"] for m in metrics if m["PSNR_dB"] is not None]
    result = {"schema_version": 1, "passed": True, "runtime_fingerprint": current, "source_video_report": receipt(report_path), "video": record, "audit_script": Path(__file__).relative_to(ROOT).as_posix(), "audit_script_sha256": sha(Path(__file__)), "chapter_count": len(chapters), "chapters": chapters, "source_state_metadata_exact": True, "native_size": list(SIZE), "all_packet_pts_dts_durations_exact_ms": True, "concat_source_exact": True, "source_png_provenance_exact": True, "decoded_frames": len(metrics), "duration_ms": sum(durations), "maximum_hold_ms": max(durations), "terminal_hold_ms": durations[-1], "terminal_hold_inferred_median": True, "sampling": source["sampling"], "quality_policy": {"fixed_before_current_decode": True,"maximum_RGB_MAE_8bit":MAX_MAE,"minimum_PSNR_dB":MIN_PSNR}, "maximum_RGB_MAE_8bit": max(m["RGB_MAE_8bit"] for m in metrics), "minimum_PSNR_dB": min(finite) if finite else None, "frames": metrics, "normal_only_original_png_check": normal_check, "full_native_decoded_samples": samples, "decoded_contacts": contacts, "visual_review_passed": None, "scope": "Fresh ffprobe time/source state and all native RGB decoded frames compared with producer-SHA-verified PNGs; selected native samples cover every chapter. Visual acceptance requires actual viewing; no benchmark or assumed30fps claim."}
    save(folder / "video-decode-audit.json", result)
    print("LIGHTING_DEMO_AUDIT_COMPLETE",len(metrics),"native decoded frames",len(samples),"samples",len(contacts),"contacts awaiting view",flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("encode","audit","all","check-only"), default="all")
    parser.add_argument("--producer", default=DEFAULT/"demo-render-final/lighting-demo-report.json")
    parser.add_argument("--output-dir", default=DEFAULT/"demo-video")
    args = parser.parse_args()
    if args.mode == "check-only":
        print(json.dumps({"native_size":SIZE,"clock":"observed wall VFR at1ms, terminal median hold only","full_decode":True,"quality_policy":{"max_MAE":MAX_MAE,"min_PSNR":MIN_PSNR},"scope":"Contract only; no frames read, encoded or audited"}))
    else:
        if args.mode in ("encode","all"):encode(args)
        if args.mode in ("audit","all"):audit(args)
