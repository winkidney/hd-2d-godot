#!/usr/bin/env python3
"""Independently audit nine encoded GPU clips, then create pending-view contacts.

Never renders or writes source PNGs. Every native decoded RGB frame is compared
with its captured PNG. Numeric fidelity and timestamp checks do not constitute
visual approval. --self-test uses only tiny in-memory arrays, not GPU evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/ancient-canal"
sys.path.insert(0, str(ROOT / "tools"))
from feature_fingerprint import fingerprint

SIZE = (1920, 1080)
DIRECTIONS = ("down", "up", "left", "right")
MAX_MAE = 4.0
MIN_PSNR = 32.0
KEYS = (0, 6, 13, 20, 26)
SEAMS = (25, 26, 27, 28, 52, 53, 54, 55)


def need(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text())


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n")


def scoped(name):
    part = Path(name)
    need(not part.is_absolute() and ".." not in part.parts, "Unscoped evidence path")
    path = OUT / part
    need(not path.is_symlink(), "Evidence is a symlink")
    path = path.resolve()
    need(path.is_relative_to(OUT.resolve()) and path.is_file(), "Missing evidence: " + name)
    return path


def portable(path):
    return path.resolve().relative_to(OUT.resolve()).as_posix()


def output_location(name):
    part = Path(name)
    need(not part.is_absolute() and ".." not in part.parts, "Unscoped audit output path")
    path = OUT / part
    need(not path.is_symlink() and path.resolve().is_relative_to(OUT.resolve()), "Audit output leaves evidence boundary")
    return path


def receipt(path):
    return {"path": portable(path), "sha256": sha(path)}


def verified(name, digest):
    path = scoped(name)
    need(isinstance(digest, str) and sha(path) == digest, "Artifact SHA changed: " + name)
    return path


def captured_png(report_path, name):
    part = Path(name)
    need(not part.is_absolute() and ".." not in part.parts, "Unscoped captured PNG")
    candidates = list(dict.fromkeys(p.resolve() for p in (report_path.parent / part, OUT / part) if p.is_file()))
    need(len(candidates) == 1, "Missing or ambiguous captured PNG: " + name)
    return scoped(portable(candidates[0]))


def probe(path):
    return json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_packets", "-show_streams",
        "-show_format", "-show_entries", "packet=pts_time,dts_time,duration_time:stream=codec_name,width,height,nb_frames,time_base:format=duration",
        "-of", "json", str(path)], text=True))


def assert_source(source, current):
    need(source.get("passed") is True and source.get("runtime_fingerprint") == current, "Stale or failed GPU producer")
    need(source.get("hardware_gpu") is True and source.get("renderer") == "forward_plus", "No real hardware Forward+ producer")
    need(source.get("size", source.get("viewport")) == list(SIZE), "Producer is not native 1080p")
    need(source.get("preferences_ignored") is True, "Ordinary settings affected capture")
    need(source.get("main_window_minimized") is True and source.get("no_focus_flag", source.get("no_focus")) is True,
         "Producer violates minimized/no-focus policy")


def timeline(rows, route, manifest=None, direction=None):
    if route:
        times = [float(r["wall_elapsed_ms"]) for r in rows]
        need(all(math.isfinite(t) for t in times) and all(b > a for a, b in zip(times, times[1:])), "Invalid observed route wall times")
        pts = [round(t - times[0]) for t in times]
        gaps = [b - a for a, b in zip(pts, pts[1:])]
        need(gaps and all(g > 0 for g in gaps), "Route cannot preserve millisecond VFR")
        return pts, gaps + [max(1, round(statistics.median(gaps)))], times
    need(len(rows) == 81, "Character video is not three original 27-pose cycles")
    durations = []
    for i, row in enumerate(rows):
        expected = manifest["directions"][direction]["frames"][i % 27]
        need(row["cycle"] == i // 27 and row["frame"] == i % 27, "Captured poses are reordered")
        duration = expected["duration_ms"]
        need(type(duration) is int and duration in (41, 42) and row["duration_ms"] == duration,
             "Original pose duration changed")
        durations.append(duration)
    pts = [0]
    for duration in durations[:-1]:
        pts.append(pts[-1] + duration)
    return pts, durations, None


def audit_chain(item, current, manifest):
    paths = {key: verified(item[key], item[key + "_sha256"]) for key in ("source_report", "timing_report", "concat_source")}
    video = verified(item["path"], item["sha256"])
    actual = probe(video)
    need(len(actual["streams"]) == 1 and tuple(actual["streams"][0][k] for k in ("width", "height")) == SIZE,
         "Video changed native dimensions")
    stream = actual["streams"][0]
    need(stream["codec_name"] == "h264" and stream["time_base"] == "1/1000" and item["codec"] == stream["codec_name"], "Unexpected MP4 codec/time base")
    source = load(paths["source_report"])
    assert_source(source, current)
    timing = load(paths["timing_report"])
    need(timing.get("passed") is True and timing.get("source_pngs_unmodified") is True and timing.get("no_duplicate_or_interpolated_frames") is True,
         "Timing report did not preserve original frames")
    need(timing["source_report"] == item["source_report"] and timing["source_report_sha256"] == item["source_report_sha256"] and timing["video"] == item["path"],
         "Timing report pointer chain changed")
    route = "route" in item.get("coverage", [])
    metadata = timing["metadata"]
    if route:
        need(source.get("no_fixed_fps") is True and float(source.get("time_scale", 0)) == 1, "Route has a fixed/fabricated time base")
        need(source.get("route_result", {}).get("passed") is True and metadata["route_result"] == source["route_result"], "Physical route proof changed")
        need(metadata.get("cancel_result") == source.get("cancel_result", {}) and metadata.get("sampling") == source.get("sampling", {}), "Route sampling/cancel data changed")
        rows = source["frames"]
        key = ("route", "route")
    else:
        direction, mode = metadata["direction"], metadata["mode"]
        need(direction in DIRECTIONS and mode in ("color", "clay-sweep"), "Unknown character direction/mode")
        clips = [c for c in source["clips"] if (c["direction"], c["mode"]) == (direction, mode)]
        need(len(clips) == 1 and clips[0]["cycles_rendered"] == 3 and clips[0]["frames_per_loop"] == 27, "Missing unique three-cycle producer")
        need(metadata.get("complete_cycles") == 3 and metadata.get("original_frames_per_cycle") == 27, "Character loop metadata changed")
        need(metadata.get("internal_loop_seams") == [{"from_frame": 26, "to_frame": 0, "packet": 27}, {"from_frame": 26, "to_frame": 0, "packet": 54}], "Missing both real internal seams")
        rows = clips[0]["frames"]
        key = (mode, direction)
    pts, durations, wall_times = timeline(rows, route, manifest, metadata.get("direction"))
    frames, packets, declared = timing["frames"], actual["packets"], timing["packets"]
    need(len(rows) == len(frames) == len(packets) == len(declared) == item["frame_count"] == timing["frame_count"], "MP4/source/timing counts differ")
    need(item.get("timing_exact_ms") is True and timing["time_base"] == "1/1000", "Video timeline is not exact milliseconds")
    concat = ["ffconcat version 1.0"]
    png_paths = []
    for i, (row, frame, packet, packet_record) in enumerate(zip(rows, frames, packets, declared)):
        image = verified(frame["source_png"], frame["source_png_sha256"])
        need(image == captured_png(paths["source_report"], row["file"]) and row["sha256"] == frame["source_png_sha256"] == frame["producer_png_sha256"], "PNG differs from original capture")
        need(frame["packet"] == i and frame["pts_ms"] == pts[i] and type(frame["duration_ms"]) is int and frame["duration_ms"] == durations[i], "Encoded timeline differs from independently reconstructed source")
        actual_pts = float(packet["pts_time"]) * 1000
        actual_dts = float(packet["dts_time"]) * 1000
        actual_duration = float(packet["duration_time"]) * 1000
        need(all(math.isfinite(t) for t in (actual_pts, actual_dts, actual_duration)) and abs(actual_pts - pts[i]) < .0001 and abs(actual_dts - actual_pts) < .0001 and abs(actual_duration - durations[i]) < .0001,
             "Actual ffprobe packet PTS/DTS/duration differs")
        need(packet_record["packet"] == i and abs(packet_record["pts_ms"] - actual_pts) < .0001 and abs(packet_record["duration_ms"] - actual_duration) < .0001, "Recorded packet proof changed")
        if route:
            error = pts[i] - (wall_times[i] - wall_times[0])
            need(abs(error) <= .50001 and abs(frame["wall_time_rounding_error_ms"] - error) < .00001 and frame["wall_elapsed_ms"] == row["wall_elapsed_ms"], "Route timestamp rounding changed")
            for field in ("physics_index", "physics_elapsed_frames", "simulation_elapsed_ms", "period", "route_index", "world_foot", "phase"):
                if field in row:
                    need(frame[field] == row[field], "Route telemetry changed: " + field)
        else:
            pose = manifest["directions"][key[1]]["frames"][i % 27]
            need(frame["cycle"] == i // 27 and frame["frame"] == i % 27 and frame["direction"] == key[1] and frame["source_index"] == pose["source_index"], "Character pose binding changed")
        relative = os.path.relpath(image, paths["concat_source"].parent).replace(os.sep, "/").replace("'", "'\\''")
        concat.extend(["file '" + relative + "'", "option framerate 1000", f"duration {durations[i] / 1000:.6f}"])
        png_paths.append(image)
    total = sum(durations)
    need(paths["concat_source"].read_text() == "\n".join(concat) + "\n", "Concat is not original PNG/timing sequence")
    need(timing["duration_ms"] == total and abs(float(actual["format"]["duration"]) * 1000 - total) < .0001 and abs(item["duration_s"] * 1000 - total) < .0001,
         "Total MP4 duration changed")
    if route:
        need(metadata["first_wall_elapsed_ms"] == wall_times[0] and metadata["last_wall_elapsed_ms"] == wall_times[-1] and metadata["terminal_duration_ms"] == durations[-1] and metadata.get("terminal_duration_inferred") is True, "Route final inferred hold differs")
    else:
        need(clips[0]["duration_ms_per_loop"] == sum(durations[:27]), "Loop duration changed")
        if key[0] == "clay-sweep":
            for name, phase in {"right": 0, "up": math.pi / 2, "left": math.pi, "down": math.pi * 1.5}.items():
                sample = metadata["sweep_cardinal_samples"][name]
                original = [s for s in source["light_samples"] if s["direction"] == key[1] and s["cycle"] == sample["cycle"] and s["frame"] == sample["frame"]]
                need(len(original) == 1 and original[0]["phase"] == sample["phase"] and original[0]["position"] == sample["world_light_position"], "Gray sweep source changed")
                error = abs(math.atan2(math.sin(sample["phase"] - phase), math.cos(sample["phase"] - phase)))
                need(error < .13 and abs(math.degrees(error) - sample["angular_error_degrees"]) < .00001, "Gray sweep cardinal calibration changed")
    return {"item": item, "source": source, "timing": timing, "video": video, "paths": paths, "png_paths": png_paths, "probe": actual, "key": key,
            "audit": {"video": item["path"], "sha256": item["sha256"], "packet_count": len(packets), "duration_ms": total, "native_size": list(SIZE), "all_packet_pts_and_durations_exact": True,
                      "concat_entries_exact": True, "producer_mapping_exact": True, "artifact_chain_sha256_matches": True, "source_report": item["source_report"], "source_report_sha256": item["source_report_sha256"],
                      "timing_report": item["timing_report"], "timing_report_sha256": item["timing_report_sha256"], "concat_source": item["concat_source"], "concat_source_sha256": item["concat_source_sha256"],
                      "maximum_hold_ms": max(durations), "terminal_hold_ms": durations[-1], "route_observed_wall_duration_ms": (wall_times[-1] - wall_times[0]) if route else None}}


def metrics(decoded, original):
    difference = decoded.astype(np.int16) - original.astype(np.int16)
    mae = float(np.abs(difference).mean())
    mse = float(np.square(difference, dtype=np.float32).mean(dtype=np.float64))
    psnr = 10 * math.log10(255 * 255 / mse) if mse else None
    return mae, psnr


def normal_crop(source, direction):
    boxes = []
    for binding in source["bindings"]:
        if binding["direction"] == direction:
            with Image.open(ROOT / binding["sprite_color"]) as image:
                boxes.append(image.convert("RGBA").getchannel("A").getbbox())
    need(len(boxes) == 27 and all(boxes), "Cannot derive preserved character alpha extent")
    bbox = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    x, y, width, height = source["projected_sprite_rect"]
    # Include perspective/rounding room; contacts never remove original pixels.
    crop = (max(0, math.floor(x + width * bbox[0] / 256) - 32), max(0, math.floor(y + height * bbox[1] / 256) - 32),
            min(SIZE[0], math.ceil(x + width * bbox[2] / 256) + 32), min(SIZE[1], math.ceil(y + height * bbox[3] / 256) + 32))
    need(crop[0] < crop[2] and crop[1] < crop[3], "Invalid projected alpha crop")
    return crop


def contact(path, samples, columns, crop, tile_size, clip, item):
    rows = math.ceil(len(samples) / columns)
    cell_width, cell_height = tile_size[0], tile_size[1] + 40
    image = Image.new("RGB", (columns * cell_width, rows * cell_height), (24, 31, 38))
    draw = ImageDraw.Draw(image)
    sources = []
    for slot, sample in enumerate(samples):
        tile = sample["image"].crop(crop).resize(tile_size, Image.Resampling.NEAREST)
        x, y = (slot % columns) * cell_width, (slot // columns) * cell_height
        image.paste(tile, (x, y + 40))
        frame = sample["frame"]
        i = frame["packet"]
        label = f"{clip} #{i:03} {frame['pts_ms']}ms"
        if "cycle" in frame:
            sub = f"cycle{frame['cycle'] + 1} pose{frame['frame']}"
        else:
            sub = f"route{frame.get('route_index', '?')} {frame.get('period', '')}"
            if "world_foot" in frame:
                sub += f" y={frame['world_foot'][1]:.3f}"
        draw.text((x + 3, y + 2), label, fill="white")
        draw.text((x + 3, y + 19), sub, fill=(195, 210, 226))
        sources.append({"packet": i, "source_png": frame["source_png"], "source_png_sha256": frame["source_png_sha256"], "decoded_RGB_sha256": sample["decoded_sha256"], "crop": list(crop),
                        "pts_ms": frame["pts_ms"], "duration_ms": frame["duration_ms"]})
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return {**receipt(path), "root": "evidence", "source_video": item["path"], "source_video_sha256": item["sha256"],
            "timing_report": item["timing_report"], "timing_report_sha256": item["timing_report_sha256"],
            "scope": "Actual MP4 decoded contact, nearest-neighbour crop/downsample; not a native GPU screenshot", "source_frames": sources}


def wait_if_paused(path):
    announced = False
    while path.exists():
        if not announced:
            print("VIDEO_AUDIT_PAUSED", portable(path), flush=True)
            announced = True
        time.sleep(.5)
    if announced:
        print("VIDEO_AUDIT_RESUMED", flush=True)


def read_frame(pipe, size):
    data = bytearray()
    while len(data) < size:
        part = pipe.read(size - len(data))
        if not part:
            break
        data.extend(part)
    return bytes(data)


def decode_clip(clip, review_folder, pause_path):
    timing, source, item = clip["timing"], clip["source"], clip["item"]
    mode, direction = clip["key"]
    route = mode == "route"
    stem = clip["video"].stem
    crop = (0, 0, *SIZE) if route else normal_crop(source, direction)
    wanted = {} if route else {"keys": {cycle * 27 + frame for cycle in range(3) for frame in KEYS}, "seams": set(SEAMS)}
    if mode == "clay-sweep":
        wanted["fixed-shadow"] = set(range(70, 76))
    chosen = {name: [] for name in wanted}
    route_samples, contacts, full_samples, errors = [], [], [], []
    count = len(timing["frames"])
    full_indices = {0, count // 2, count - 1} if route else {0, 26}
    log_path = review_folder / (stem + "-decode.log")
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-threads", "1", "-noautorotate", "-i", str(clip["video"]), "-map", "0:v:0", "-an", "-sn", "-dn",
               "-fps_mode", "passthrough", "-threads", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
    with log_path.open("wb") as log:
        decoder = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=log)
        try:
            for i, frame in enumerate(timing["frames"]):
                wait_if_paused(pause_path)
                raw = read_frame(decoder.stdout, SIZE[0] * SIZE[1] * 3)
                need(len(raw) == SIZE[0] * SIZE[1] * 3, "Missing or partial decoded frame: " + stem + str(i))
                decoded = np.frombuffer(raw, dtype=np.uint8).reshape(SIZE[1], SIZE[0], 3)
                png_path = clip["png_paths"][i]
                need(sha(png_path) == frame["source_png_sha256"], "GPU PNG changed during decode")
                with Image.open(png_path) as original_image:
                    need(original_image.format == "PNG" and original_image.size == SIZE, "Original GPU PNG changed dimensions")
                    original = np.asarray(original_image.convert("RGB"))
                mae, psnr = metrics(decoded, original)
                need(mae <= MAX_MAE and (psnr is None or psnr >= MIN_PSNR), "Decoded/source fidelity outside preset bounds: " + stem + str(i))
                decoded_sha = hashlib.sha256(raw).hexdigest()
                errors.append({"packet": i, "source_png": frame["source_png"], "source_png_sha256": frame["source_png_sha256"], "decoded_RGB_sha256": decoded_sha,
                               "RGB_mean_absolute_error_8bit": mae, "PSNR_dB": psnr})
                sample = {"frame": frame, "decoded_sha256": decoded_sha, "image": Image.fromarray(decoded)}
                if route:
                    # Hold at most sixteen decoded thumbnails, not all RGB frames.
                    sample["image"] = sample["image"].resize((480, 270), Image.Resampling.NEAREST)
                    route_samples.append(sample)
                    if len(route_samples) == 16 or i == count - 1:
                        start = i - len(route_samples) + 1
                        record = contact(review_folder / f"{stem}-{start:03}-{i:03}.png", route_samples, 4, (0, 0, 480, 270), (480, 270), stem, item)
                        for row in record["source_frames"]:
                            row["crop"] = [0, 0, *SIZE]
                        contacts.append(record)
                        route_samples.clear()
                else:
                    for name, indices in wanted.items():
                        if i in indices:
                            chosen[name].append(sample)
                if i in full_indices:
                    full_path = review_folder / "full" / stem / f"{i:05}.png"
                    full_path.parent.mkdir(parents=True, exist_ok=True)
                    Image.fromarray(decoded).save(full_path)
                    full_samples.append({**receipt(full_path), "root": "evidence", "packet": i, "video": item["path"], "video_sha256": item["sha256"],
                                         "source_png": frame["source_png"], "source_png_sha256": frame["source_png_sha256"], "decoded_RGB_sha256": decoded_sha,
                                         "scope": "Native 1920x1080 decoded MP4 sample; derived encoding evidence, not a new native GPU capture"})
            need(decoder.stdout.read(1) == b"", "Extra decoded video frame")
            need(decoder.wait(timeout=30) == 0, "ffmpeg decode failed; see scoped decoder log")
        finally:
            if decoder.poll() is None:
                decoder.kill()
                decoder.wait(timeout=10)
            decoder.stdout.close()
    if not route:
        tile_width = 300
        tile_size = (tile_width, round((crop[3] - crop[1]) / (crop[2] - crop[0]) * tile_width))
        for name, samples in chosen.items():
            columns = 5 if name == "keys" else 4 if name == "seams" else 3
            contacts.append(contact(review_folder / (stem + "-" + name + ".png"), samples, columns, crop, tile_size, stem, item))
    finite_psnr = [f["PSNR_dB"] for f in errors if f["PSNR_dB"] is not None]
    return {**{k: item[k] for k in ("path", "sha256", "source_report", "source_report_sha256", "timing_report", "timing_report_sha256", "concat_source", "concat_source_sha256")},
            "passed": True, "decoded_frames": count, "native_size": list(SIZE), "max_RGB_mean_absolute_error_8bit": max(f["RGB_mean_absolute_error_8bit"] for f in errors),
            "minimum_PSNR_dB": min(finite_psnr) if finite_psnr else None, "frames": errors, "contacts": contacts, "full_decoded_samples": full_samples,
            "source_comparison": "Every actual native 1920x1080 RGB decoded frame matched corresponding freshly producer-SHA-verified GPU PNG in exact packet order; no extra/missing frame. Lossy compression fidelity, not RGB equality.",
            "visual_review_passed": None}


def audit(args):
    need(0 <= args.nice <= 19, "Niceness must be 0..19")
    os.nice(args.nice)
    current = fingerprint(ROOT)["sha256"]
    report_path = scoped(args.video_report)
    video_report = load(report_path)
    report_sha = sha(report_path)
    need(video_report.get("passed") is True and video_report.get("runtime_fingerprint") == current and len(video_report.get("videos", [])) == 9, "Nine current encoded GPU clips are required")
    need(video_report.get("remaining_scope") == [] and video_report.get("source_pngs_unmodified") is True and video_report.get("interpolated_frames") == 0 and video_report.get("resized_frames") == 0, "Video report is partial or synthesized")
    manifest = load(ROOT / "assets/ancient-canal/character-normals/v1/manifest.json")
    clips = []
    for item in video_report["videos"]:
        wait_if_paused(output_location(args.pause_file))
        clips.append(audit_chain(item, current, manifest))
        print("VIDEO_CHAIN_CHECKED", item["path"], flush=True)
    need({c["key"] for c in clips} == {(mode, direction) for mode in ("color", "clay-sweep") for direction in DIRECTIONS} | {("route", "route")}, "Missing or duplicate video direction/material/route")
    producer_records = {(r["path"], r["sha256"]) for r in video_report["source_reports"]}
    need(producer_records == {(c["item"]["source_report"], c["item"]["source_report_sha256"]) for c in clips}, "Aggregate source report set differs")
    initial = {p: sha(p) for c in clips for p in (c["video"], *c["paths"].values())}
    initial[report_path] = report_sha
    initial[Path(__file__).resolve()] = sha(Path(__file__).resolve())
    folder = output_location(args.review_dir)
    need(folder.is_relative_to(OUT) and not folder.exists(), "Use a fresh, scoped video-review directory")
    folder.mkdir(parents=True)
    decoded = []
    for clip in clips:
        wait_if_paused(output_location(args.pause_file))
        decoded.append(decode_clip(clip, folder, output_location(args.pause_file)))
        print("VIDEO_DECODE_CHECKED", clip["item"]["path"], decoded[-1]["decoded_frames"], flush=True)
        save(folder / "decode-progress.json", {"passed": False, "runtime_fingerprint": current, "scope": "Progress only; remaining clips and independent visual viewing pending", "completed_clips": [c["path"] for c in decoded]})
    need(fingerprint(ROOT)["sha256"] == current and all(sha(p) == digest for p, digest in initial.items()), "Runtime or encoded source receipts changed during audit")
    # Resolve the authoritative sibling API explicitly, avoiding ROOT/tools/package.py.
    sys.path.insert(0, str(ROOT / "tools/ancient_canal"))
    spec = importlib.util.spec_from_file_location("ancient_canal_video_contract", Path(__file__).with_name("package.py"))
    api = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = api
    spec.loader.exec_module(api)
    for clip in clips:
        api.video_chain(clip["item"], clip["probe"], current)
    shared = {"schema_version": 1, "passed": True, "runtime_fingerprint": current, "runtime_fingerprint_before": current, "runtime_fingerprint_after": current,
              "source_video_report": portable(report_path), "source_video_report_sha256": report_sha, "audit_script": Path(__file__).relative_to(ROOT).as_posix(), "audit_script_sha256": initial[Path(__file__).resolve()],
              "source_reports": video_report["source_reports"], "scope": "Encoded temporal/source fidelity and decoded quality only. Actual contact visual approval is separately pending; no GPU render, interaction or performance claim."}
    route = next(c for c in clips if c["key"][0] == "route")
    chain = {**shared, "method": "Independent fresh ffprobe packet PTS/DTS/duration, original pose manifest, monotonic wall timeline, concat bytes and SHA pointer verification; authoritative package.video_chain contract also cross-checked.",
             "videos": [c["audit"] for c in clips], "normal_timing": "All original 108 pose durations41/42ms repeated exactly three times per color/clay direction.",
             "route_timing": {"method": "Observed producer wall time rounded once to ms; actual gaps preserved; only final still has inferred median interval", **route["audit"], "sampling": route["source"].get("sampling", {})}}
    save(OUT / "video-chain-audit.json", chain)
    contacts = [a for c in decoded for a in c["contacts"]]
    decode = {**shared, "related_reports": [receipt(OUT / "video-chain-audit.json")], "decoded_frames": sum(c["decoded_frames"] for c in decoded), "videos": decoded,
              "quality_policy": {"fixed_before_current_MP4_read": True, "maximum_RGB_MAE_8bit": MAX_MAE, "minimum_PSNR_dB": MIN_PSNR, "zero_MSE_PSNR": "null means identical RGB, accepted"},
              "review_artifacts": contacts, "view_method_pending": "Actual MP4 decoded contacts generated, not visually approved. Independently view all route contacts, direction color/clay key poses and both loop seams before producing video-review.json.",
              "visual_review_passed": None, "ffmpeg_version": subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0]}
    save(OUT / "video-decode-audit.json", decode)
    save(folder / "contact-index.json", {"passed": True, "runtime_fingerprint": current, "source_video_report": portable(report_path), "source_video_report_sha256": report_sha,
                                        "source_reports": [receipt(OUT / "video-chain-audit.json"), receipt(OUT / "video-decode-audit.json")], "review_artifacts": contacts, "visual_review_passed": None})
    print("VIDEO_AUDIT_COMPLETE", len(decoded), decode["decoded_frames"], "native decoded frames;", len(contacts), "contacts awaiting view", flush=True)


def self_test():
    a = np.zeros((4, 4, 3), dtype=np.uint8)
    mae, psnr = metrics(a, a)
    need(mae == 0 and psnr is None, "Identical-array metric failure")
    mae, psnr = metrics(a + 1, a)
    need(mae == 1 and abs(psnr - 48.1308036087) < .00001, "One-step metric failure")
    mae, psnr = metrics(a + 100, a)
    need(mae > MAX_MAE and psnr < MIN_PSNR, "Wrong-image rejection failure")
    rows = [{"wall_elapsed_ms": x} for x in (16.103, 49.701, 350.8, 384.03)]
    pts, duration, _ = timeline(rows, True)
    need(pts == [0, 34, 335, 368] and duration == [34, 301, 33, 34], "Observed VFR/terminal median failure")
    try:
        timeline([{"wall_elapsed_ms": 1}, {"wall_elapsed_ms": 1}], True)
    except ValueError:
        pass
    else:
        raise ValueError("Repeated wall-time rejection failure")
    print("VIDEO_AUDIT_SELF_TEST passed; tiny in-memory metrics/timeline only, no scene or GPU evidence")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video-report", default="video-report.json", help="OUT-relative complete nine-clip report")
    parser.add_argument("--review-dir", default="video-review", help="Fresh OUT-relative decoded contact directory")
    parser.add_argument("--pause-file", default="video-audit.pause", help="Creating this OUT-relative file pauses decoder consumption between frames")
    parser.add_argument("--nice", type=int, default=10, help="CPU scheduling niceness, default10; ffmpeg also uses one thread")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--check-only", action="store_true", help="Print contract; does not read MP4, decode or write audit evidence")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.check_only:
        print(json.dumps({"expected_clips": 9, "native_size": SIZE, "quality_policy": {"max_MAE": MAX_MAE, "min_PSNR_dB": MIN_PSNR}, "full_decode": True,
                          "visual_review_passed": None, "outputs": ["video-chain-audit.json", "video-decode-audit.json", args.review_dir + "/contact-index.json"], "pause_file": args.pause_file}))
    else:
        audit(args)
