"""Decode actual dock PNGs; keep camera-edge motion separate from material flicker.

The hard gate is the historical 1% static micro-camera criterion. Moving-frame
statistics are diagnostic; their contacts need an actual visual review.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/ancient-canal"
sys.path.insert(0, str(ROOT / "tools"))
from feature_fingerprint import fingerprint

SIZE = (1920, 1080)
PHASES = ("bank_stop", "down_slope", "dock_stop", "up_slope", "return_stop")
LIMIT = 0.01


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decoded_image(images, index):
    with Image.open(images[int(index)]) as source:
        return source.convert("RGB")


def evidence_file(name):
    path = (OUT / name).resolve()
    if not path.is_relative_to(OUT.resolve()) or not path.is_file():
        raise ValueError("missing or nonportable evidence file: " + str(name))
    return path


def polygon_mask(points, erode=1):
    array = np.asarray(points, dtype=float)
    if array.shape != (4, 2) or not np.isfinite(array).all():
        raise ValueError("invalid projected plane polygon")
    mask = np.zeros((SIZE[1], SIZE[0]), np.uint8)
    cv2.fillConvexPoly(mask, np.rint(array).astype(np.int32), 1)
    if erode:
        mask = cv2.erode(mask, np.ones((erode*2+1, erode*2+1), np.uint8))
    return mask.astype(bool)


def rectangle_mask(rect):
    x0, y0, x1, y1 = map(int, rect)
    if not (0 <= x0 < x1 <= SIZE[0] and 0 <= y0 < y1 <= SIZE[1]):
        raise ValueError("invalid fixed ROI")
    mask = np.zeros((SIZE[1], SIZE[0]), bool)
    mask[y0:y1, x0:x1] = True
    return mask


def temporal_metrics(pixels):
    pixels = np.asarray(pixels, dtype=np.int16)
    if pixels.ndim != 3 or pixels.shape[0] < 2 or pixels.shape[1] < 100 or pixels.shape[2] != 3:
        raise ValueError("temporal ROI has too few actual pixels/frames")
    steps = np.abs(np.diff(pixels, axis=0)).max(axis=-1)
    fractions = (steps > 16).mean(axis=1)
    ranges = (pixels.max(axis=0)-pixels.min(axis=0)).max(axis=-1)
    return {"pixel_count": int(pixels.shape[1]), "pair_count": int(steps.shape[0]),
            "mean_step_255": float(steps.mean()), "p99_step_255": float(np.quantile(steps, .99)),
            "max_step_255": int(steps.max()), "fraction_above_16": float(fractions.mean()),
            "max_pair_fraction_above_16": float(fractions.max()),
            "pair_fractions_above_16": fractions.tolist(),
            "fraction_range_above_32": float((ranges > 32).mean())}


def projected_crop(frame, points, pad=(18, 60, 18, 18)):
    xy = np.asarray(points, dtype=float)
    left, top, right, bottom = pad
    x0 = max(0, int(np.floor(xy[:, 0].min()))-left)
    x1 = min(SIZE[0], int(np.ceil(xy[:, 0].max()))+right)
    y0 = max(0, int(np.floor(xy[:, 1].min()))-top)
    y1 = min(SIZE[1], int(np.ceil(xy[:, 1].max()))+bottom)
    if x1 <= x0 or y1 <= y0:
        raise ValueError("dock crop outside actual frame")
    return frame.crop((x0, y0, x1, y1)), (x0, y0, x1, y1)


def contact(entries, images, path, legacy_rect=None):
    tile_w, tile_h, caption = 340, 210, 34
    columns = 4
    rows = math.ceil(len(entries)/columns)
    sheet = Image.new("RGB", (columns*tile_w, rows*(tile_h+caption)), "#18202a")
    draw = ImageDraw.Draw(sheet)
    provenance = []
    for index, entry in enumerate(entries):
        source = decoded_image(images, entry["index"])
        if legacy_rect:
            x0, y0, x1, y1 = legacy_rect
            rect = (max(0,x0-16),max(0,y0-55),min(SIZE[0],x1+16),min(SIZE[1],y1+16))
            cropped = source.crop(rect)
        else:
            cropped, rect = projected_crop(source, entry["dock_polygon"])
        scale = min(tile_w/cropped.width, tile_h/cropped.height)
        preview = cropped.resize((round(cropped.width*scale), round(cropped.height*scale)), Image.Resampling.NEAREST)
        xx, yy = (index%columns)*tile_w, (index//columns)*(tile_h+caption)
        sheet.paste(preview, (xx+(tile_w-preview.width)//2, yy+(tile_h-preview.height)//2))
        foot = entry["world_foot"]
        text = f"{entry['variant']} {entry['phase']} #{entry['index']}  x={foot[0]:.2f} y={foot[1]:.3f}"
        if entry["kind"] == "micro": text += f"  dx={entry['camera_dx_metres']*1000:+.1f}mm"
        draw.text((xx+5, yy+tile_h+2), text, fill="#e5e8eb")
        draw.text((xx+5, yy+tile_h+17), f"wall {entry['wall_elapsed_ms']/1000:.3f}s  physics {entry['physics_index']}", fill="#b7c5d4")
        provenance.append({"file":entry["file"],"sha256":entry["sha256"],"index":entry["index"],"crop":list(rect)})
    sheet.save(path)
    return {"file":path.relative_to(OUT).as_posix(),"sha256":sha(path),
            "scope":"Nearest-neighbour diagnostic crops from verified actual 1080p PNGs; captions use producer telemetry",
            "source_frames":provenance}


def registered_strip(image, polygon):
    # The quad is a real fixed world plane. This homography removes camera
    # perspective solely for diagnostics; original screenshots stay untouched.
    target = np.array([[0,0],[127,0],[127,39],[0,39]], np.float32)
    matrix = cv2.getPerspectiveTransform(np.asarray(polygon, np.float32), target)
    return cv2.warpPerspective(np.asarray(image), matrix, (128,40), flags=cv2.INTER_LINEAR)


def analyze(capture_dir, expected=None):
    capture_dir = Path(capture_dir).resolve()
    if not capture_dir.is_relative_to(OUT.resolve()):
        raise ValueError("capture directory outside independent evidence tree")
    source_path = capture_dir / "dock-capture-report.json"
    source = json.loads(source_path.read_text())
    current = expected or fingerprint(ROOT)["sha256"]
    if source.get("runtime_fingerprint") != current:
        raise ValueError("dock capture is not the current runtime")
    if source.get("producer_script") != "tools/ancient_canal/capture_dock_stability.gd" or source.get("producer_script_sha256") != sha(ROOT/source["producer_script"]):
        raise ValueError("actual dock producer script changed since capture")
    required = ("passed","hardware_gpu","main_window_minimized","no_focus_flag",
                "viewport_own_world_3d","disabled_render_loop","process_command_complete","preferences_ignored_requested")
    if not all(source.get(key) is True for key in required):
        raise ValueError("actual GPU/window/process evidence is incomplete")
    if source.get("fixed_fps_flag_present") is not False or source.get("root_hidden") is not False:
        raise ValueError("capture used fixed FPS or a hidden/suspended root")
    if source.get("renderer") != "forward_plus" or source.get("display_driver") == "headless" or source.get("size") != list(SIZE):
        raise ValueError("capture is not actual 1080p Forward+ GPU evidence")
    if source.get("time_scale") != 1.0 or source.get("physics_ticks_per_second") != 60:
        raise ValueError("capture is not actual 60 Hz simulation at time scale one")
    if source["criterion"] != {"fraction_above_16_max":.01,"delta_255":16,"micro_camera_metres":.0005,"frames_per_group":24}:
        raise ValueError("producer changed the specified static criterion")
    audit = source["surface_audit"]
    if audit["DockFloor"]["visible_mesh_count"] != 0 or audit["DockFloor"]["collision_count"] != 1:
        raise ValueError("coplanar helper remains visible or collision was removed")
    entries = source["frames"]
    if len(entries) < 126 or [entry["index"] for entry in entries] != list(range(len(entries))):
        raise ValueError("dock frame inventory is incomplete")
    if len({entry["file"] for entry in entries}) != len(entries):
        raise ValueError("raw frame filenames must be unique")
    images = {}
    previous_wall = -1.0
    previous_draw = -1
    for entry in entries:
        path = evidence_file(entry["file"])
        if sha(path) != entry["sha256"]:
            raise ValueError("raw PNG changed: " + entry["file"])
        image = Image.open(path).convert("RGB")
        if image.size != SIZE:
            raise ValueError("raw image is not 1080p")
        rgb = np.asarray(image)
        if float(rgb.std()) < 5 or float(np.quantile(rgb.max(axis=-1), .99)) < 16:
            raise ValueError("raw GPU readback was blank or uniform")
        # Store paths, not hundreds of 6 MiB decoded images. Each later ROI
        # decode is temporary, so analysis stays bounded regardless of gaps.
        images[entry["index"]] = path
        if entry["wall_elapsed_ms"] <= previous_wall or entry["post_draw_sequence"] <= previous_draw:
            raise ValueError("raw timestamps/draw sequence did not advance")
        previous_wall = entry["wall_elapsed_ms"]
        previous_draw = entry["post_draw_sequence"]
        polygon_mask(entry["floor_polygon"])
    contacts_dir = capture_dir / "contacts"
    contacts_dir.mkdir(exist_ok=True)
    contacts = []
    groups = {}
    for group in source["micro_groups"]:
        key = group["id"]
        frames = [entry for entry in entries if entry["kind"] == "micro" and entry["variant"] == key]
        if len(frames) != 24 or [entry["micro_index"] for entry in frames] != list(range(24)):
            raise ValueError("missing micro frames: " + key)
        for index, entry in enumerate(frames):
            if not entry["world_frozen"] or not entry["camera_locked"] or entry["camera_dx_metres"] != (.0005 if index%2 else -.0005):
                raise ValueError("micro-camera frame was not the specified frozen alternation")
            if entry["water_clock"] != frames[0]["water_clock"] or entry["world_foot"] != frames[0]["world_foot"] or entry["animation_frame"] != frames[0]["animation_frame"]:
                raise ValueError("micro-camera changed actor pose or world clock")
        if key == "legacy_projection":
            if group["fixed_roi"] != [1160,1030,1380,1070]:
                raise ValueError("historical ROI changed")
            mask = rectangle_mask(group["fixed_roi"])
        else:
            mask = polygon_mask(frames[0]["floor_polygon"])
        array = np.stack([np.asarray(decoded_image(images, entry["index"]))[mask] for entry in frames])
        metrics = temporal_metrics(array)
        metrics["passed"] = metrics["max_pair_fraction_above_16"] <= LIMIT
        metrics["mask_policy"] = group["roi_policy"]
        metrics["indices"] = [entry["index"] for entry in frames]
        metrics["control_bank"] = None
        if key != "legacy_projection":
            bank_mask = polygon_mask(frames[0]["bank_polygon"])
            bank_pixels = np.stack([np.asarray(decoded_image(images, entry["index"]))[bank_mask] for entry in frames])
            metrics["control_bank"] = temporal_metrics(bank_pixels)
        groups[key] = metrics
        contacts.append(contact(frames, images, contacts_dir/(key+"-micro-contact.png"), group["fixed_roi"] if key=="legacy_projection" else None))
    if set(groups) != {"legacy_projection","F","W","O"}:
        raise ValueError("must capture old projection and all three current camera variants")
    motion = {}
    for case in source["motion_cases"]:
        key = case["id"]
        if not case["passed"] or not case["initial_placement_only"] or not case["camera_follow"]:
            raise ValueError("actual moving dock case failed: " + key)
        frames = [entry for entry in entries if entry["kind"]=="motion" and entry["variant"]==key]
        phase_counts = {phase:sum(entry["phase"]==phase for entry in frames) for phase in PHASES}
        if min(phase_counts.values()) < 2 or any(entry["world_frozen"] or entry["camera_locked"] for entry in frames):
            raise ValueError("moving/stopped/slope coverage is incomplete: " + key)
        samples = []
        selection = []
        for phase in PHASES:
            candidates = [entry for entry in frames if entry["phase"]==phase]
            selection.extend(candidates[index] for index in sorted({0,len(candidates)//2,len(candidates)-1}))
        for entry in frames:
            strip = registered_strip(decoded_image(images, entry["index"]), entry["floor_polygon"])
            pixels = strip[3:-3,3:-3].astype(float)
            spread = pixels.max(axis=-1)-pixels.min(axis=-1)
            warm = (pixels[...,0]-pixels[...,1]>5) & (pixels[...,0]-pixels[...,2]>10)
            samples.append({"index":entry["index"],"phase":entry["phase"],"mean_rgb":pixels.mean(axis=(0,1)).tolist(),
                "warm_colour_fraction":float(warm.mean()),"low_chroma_fraction":float((spread<18).mean()),
                "wall_elapsed_ms":entry["wall_elapsed_ms"],"world_foot":entry["world_foot"]})
        motion[key] = {"passed_physics":True,"phase_counts":phase_counts,"foot_y_range":[min(entry["world_foot"][1] for entry in frames),max(entry["world_foot"][1] for entry in frames)],
            "registered_plane_colour_statistics":samples,
            "interpretation":"Diagnostic only: moving lights, contact shadows and nearest texture sampling can change pixels. No automatic wood/stone or smoothness claim.",
            "visual_review_required":True}
        contacts.append(contact(selection, images, contacts_dir/(key+"-motion-contact.png")))
    if set(motion) != {"F","W","O"}:
        raise ValueError("actual moving coverage must include F/W/O")
    final_current = fingerprint(ROOT)["sha256"]
    if final_current != current:
        raise ValueError("runtime changed during PNG analysis")
    result = {"schema_version":1,"runtime_fingerprint":current,
        "source_report":source_path.relative_to(OUT).as_posix(),"source_report_sha256":sha(source_path),
        "producer_script":source["producer_script"],"producer_script_sha256":source["producer_script_sha256"],
        "analyzer_script":"tools/ancient_canal/analyze_dock_stability.py","analyzer_script_sha256":sha(Path(__file__)),
        "passed":all(group["passed"] for group in groups.values()),"criterion":source["criterion"],
        "scope":"Verified current hardware GPU producer/PNG chain; each adjacent static +/-0.5mm dock pair <=1% changed pixels above16/255; actual F/W/O downhill/stop/uphill physical movement. Visual texture consistency and natural pixel edges are reviewed separately using the contacts.",
        "static_micro_groups":groups,"motion_cases":motion,"raw_frame_count":len(entries),
        "raw_frame_sha256":{entry["file"]:entry["sha256"] for entry in entries},"contacts":contacts,
        "surface_audit":audit,"sampling":source["sampling"],"wall_duration_ms":source["wall_duration_ms"],
        "hardware_gpu":True,"adapter":source["adapter"],"renderer":source["renderer"],"display_driver":source["display_driver"],
        "size":source["size"],"main_window_minimized":True,"no_focus_flag":True,
        "no_fixed_fps":True,"disabled_render_loop":True,"time_scale":1.0,"physics_ticks_per_second":60,
        "visual_review_passed":None,"performance_benchmark":False}
    destination = capture_dir / "dock-stability-report.json"
    destination.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
    return result


def self_test():
    stable = np.tile(np.arange(600, dtype=np.int16).reshape(200,3)%255, (24,1,1))
    assert temporal_metrics(stable)["max_pair_fraction_above_16"] == 0
    unstable = stable.copy()
    unstable[1::2,:17] += 40
    assert temporal_metrics(unstable)["max_pair_fraction_above_16"] > LIMIT
    edge_only = stable.copy()
    edge_only[1::2,:1] += 40
    assert temporal_metrics(edge_only)["max_pair_fraction_above_16"] <= LIMIT
    mask = polygon_mask([[100,100],[200,100],[200,120],[100,120]])
    assert 1500 < mask.sum() < 2200
    try: polygon_mask([[math.nan,0]]*4)
    except ValueError: pass
    else: raise AssertionError("nonfinite polygon accepted")
    print("DOCK_ANALYZER_UNIT_OK actual GPU performed=false")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-dir",default=OUT/"dock-stability",type=Path)
    parser.add_argument("--expected-fingerprint")
    parser.add_argument("--self-test",action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    result = analyze(args.capture_dir,args.expected_fingerprint)
    print(json.dumps({"passed":result["passed"],"raw_frame_count":result["raw_frame_count"],
        "max_pair_fraction":{key:value["max_pair_fraction_above_16"] for key,value in result["static_micro_groups"].items()}},indent=2))
    if not result["passed"]: raise SystemExit(1)


if __name__ == "__main__": main()
