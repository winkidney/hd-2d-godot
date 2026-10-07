#!/usr/bin/env python3
"""Encode existing real GPU PNG captures, verifying every presentation time.

This tool never renders, changes source frames, resizes captures, synthesizes
animation, or measures performance. Its fixture is explicitly not GPU evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/"build/ancient-canal"
sys.path.insert(0,str(ROOT/"tools"))
from feature_fingerprint import fingerprint

DIRECTIONS=("down","up","left","right")
SIZE=(1920,1080)
TICKS_PER_SECOND=1000


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: Path):
    return json.loads(path.read_text())


def save(path: Path,data) -> None:
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")


def need(condition: bool,description: str) -> None:
    if not condition:raise ValueError(description)


def portable(path: Path) -> str:
    path=path.resolve()
    need(path.is_relative_to(OUT.resolve()),"Evidence is outside the Jiangnan output boundary")
    return path.relative_to(OUT.resolve()).as_posix()


def scoped_file(path: Path) -> Path:
    need(not path.is_symlink(),"Evidence cannot be a symbolic link")
    path=path.resolve()
    portable(path)
    need(path.is_file(),"Missing evidence "+str(path.name))
    return path


def png_from_report(report_path: Path,name: str,producer_sha256: str|None) -> Path:
    part=Path(name)
    need(not part.is_absolute() and ".." not in part.parts,"Report frame path is not scoped/portable")
    choices=[report_path.parent/part,OUT/part]
    existing=list(dict.fromkeys(p.resolve() for p in choices if p.is_file()))
    need(len(existing)==1,"Missing or ambiguous report PNG "+name)
    result=scoped_file(existing[0])
    need(isinstance(producer_sha256,str) and len(producer_sha256)==64 and all(c in "0123456789abcdef" for c in producer_sha256),"Missing or invalid original producer PNG SHA256 "+name)
    need(sha(result)==producer_sha256,"PNG no longer matches original capture report SHA256 "+name)
    with Image.open(result) as image:
        need(image.format=="PNG" and image.size==SIZE,"Frame is not original 1920x1080 PNG "+name)
    return result


def check_report(path: Path,current: str) -> dict:
    path=scoped_file(path)
    data=load(path)
    need(data.get("passed") is True,"GPU capture report did not pass: "+path.name)
    need(data.get("runtime_fingerprint")==current,"Capture is missing the frozen runtime fingerprint or is stale: "+path.name)
    need(data.get("hardware_gpu") is True and data.get("renderer")=="forward_plus","Source report does not prove hardware Forward+")
    need(data.get("size",data.get("viewport"))==list(SIZE),"Source report is not native 1080p")
    need(data.get("main_window_minimized") is True and data.get("no_focus_flag",data.get("no_focus")) is True,"Source window was not minimized and without focus")
    need(data.get("preferences_ignored") is True,"Source used ordinary user settings")
    return data


def packet_probe(path: Path) -> dict:
    command=["ffprobe","-v","error","-select_streams","v:0","-show_packets","-show_streams","-show_format","-show_entries","packet=pts_time,dts_time,duration_time:stream=codec_name,width,height,nb_frames,time_base:format=duration","-of","json",str(path)]
    return json.loads(subprocess.check_output(command,text=True))


def encode_clip(name: str,frames: list[dict],folder: Path,scope: str,coverage: list[str],source_report: Path|None=None,metadata=None) -> dict:
    """One PNG equals one output packet, with explicit millisecond durations.

    image2 normally uses 25fps, which would quantize 41/42ms to 40ms. Each concat
    entry instead opens its PNG at a 1ms time base. H.264 B frames are disabled,
    VFR preserves source PTS, and setts supplies the actual final frame duration.
    ffprobe then verifies every packet, including the last one and total length.
    """
    folder.mkdir(parents=True,exist_ok=True)
    need(bool(frames),"Cannot encode empty evidence clip")
    for frame in frames:
        need(isinstance(frame["duration_ms"],int) and frame["duration_ms"]>0,"Invalid integer millisecond duration")
        scoped_file(frame["path"])
        with Image.open(frame["path"]) as image:need(image.size==SIZE,"Encoding would need resizing")
    manifest_path=folder/(name+"-timing.json")
    concat_path=folder/(name+".ffconcat")
    video_path=folder/(name+".mp4")
    lines=["ffconcat version 1.0"]
    source_frames=[]
    pts=0
    for index,frame in enumerate(frames):
        original_sha256=sha(frame["path"])
        if source_report is not None:
            need(original_sha256==frame.get("source_metadata",{}).get("producer_png_sha256"),"PNG changed between producer validation and encoding")
        # Paths in the reproducible concat source are relative to that file.
        relative=os.path.relpath(frame["path"],concat_path.parent).replace(os.sep,"/")
        escaped=relative.replace("'","'\\''")
        lines.extend(["file '"+escaped+"'","option framerate 1000",f"duration {frame['duration_ms']/1000:.6f}"])
        source_frames.append({"packet":index,"source_png":portable(frame["path"]),"source_png_sha256":original_sha256,"pts_ms":pts,"duration_ms":frame["duration_ms"],**frame.get("source_metadata",{})})
        pts+=frame["duration_ms"]
    concat_path.write_text("\n".join(lines)+"\n")
    last_duration=frames[-1]["duration_ms"]
    command=["ffmpeg","-hide_banner","-loglevel","error","-y","-f","concat","-safe","0","-i",str(concat_path),"-an","-c:v","libx264","-preset","fast","-crf","14","-pix_fmt","yuv420p","-bf","0","-fps_mode","vfr","-enc_time_base","1:1000","-video_track_timescale","1000","-bsf:v",f"setts=duration='if(eq(N,{len(frames)-1}),{last_duration},DURATION)'","-movflags","+faststart",str(video_path)]
    subprocess.run(command,check=True)
    probe=packet_probe(video_path)
    need(len(probe["streams"])==1 and (probe["streams"][0]["width"],probe["streams"][0]["height"])==SIZE,"Encoded video changed viewport")
    packets=probe["packets"]
    need(len(packets)==len(frames),"Encoder duplicated or dropped source frames")
    packet_rows=[]
    for expected,packet in zip(source_frames,packets):
        actual_pts=float(packet["pts_time"])*1000
        actual_duration=float(packet["duration_time"])*1000
        need(abs(actual_pts-expected["pts_ms"])<.0001,"Video PTS does not preserve source animation timing")
        need(abs(actual_duration-expected["duration_ms"])<.0001,"Video packet duration differs from source, including terminal frame")
        packet_rows.append({"packet":expected["packet"],"pts_ms":actual_pts,"duration_ms":actual_duration})
    duration=float(probe["format"]["duration"])
    need(abs(duration*1000-pts)<.0001,"Video total duration differs from source")
    for frame,record in zip(frames,source_frames):
        need(sha(frame["path"])==record["source_png_sha256"],"Source PNG changed while encoding")
    timing={"schema_version":1,"passed":True,"scope":"PNG-to-video temporal fidelity only; source GPU rendering is proved by the separate capture report","source_report":portable(source_report) if source_report else None,"source_report_sha256":sha(source_report) if source_report else None,"video":portable(video_path),"time_base":"1/1000","frames":source_frames,"packets":packet_rows,"frame_count":len(frames),"duration_ms":pts,"no_duplicate_or_interpolated_frames":True,"source_pngs_unmodified":True,"encoder":"H.264 libx264 CRF14, VFR, no B frames, original 1080p, yuv420p","metadata":metadata or {}}
    save(manifest_path,timing)
    record={"path":portable(video_path),"sha256":sha(video_path),"scope":scope,"coverage":coverage,"viewport":list(SIZE),"codec":probe["streams"][0]["codec_name"],"time_base":probe["streams"][0]["time_base"],"duration_s":duration,"frame_count":len(frames),"timing_exact_ms":True,"timing_report":portable(manifest_path),"timing_report_sha256":sha(manifest_path),"concat_source":portable(concat_path),"concat_source_sha256":sha(concat_path),"source_report":portable(source_report) if source_report else None,"source_report_sha256":sha(source_report) if source_report else None}
    print("ENCODED",record["path"],len(frames),"frames",pts,"ms, PTS/durations verified")
    return record


def normal_clips(path: Path,data: dict,folder: Path) -> list[dict]:
    manifest=load(ROOT/"assets/ancient-canal/character-normals/v1/manifest.json")
    need(data.get("recorded_frames")==648 and len(data.get("bindings",[]))==108,"Capture does not cover all original normals")
    seen=set();videos=[]
    for clip in data["clips"]:
        direction=clip["direction"];mode=clip["mode"]
        need(direction in DIRECTIONS and mode in ("color","clay-sweep"),"Unexpected character clip")
        need((mode,direction) not in seen,"Duplicate character clip")
        seen.add((mode,direction))
        need(clip["cycles_rendered"]==3 and clip["frames_per_loop"]==27 and len(clip["frames"])==81,"Incomplete three-cycle source capture")
        frames=[]
        for index,frame in enumerate(clip["frames"]):
            need(frame["cycle"]==index//27 and frame["frame"]==index%27,"Source capture skipped/reordered animation")
            expected=manifest["directions"][direction]["frames"][index%27]
            need(frame["duration_ms"]==expected["duration_ms"] and frame["duration_ms"] in (41,42),"Original character animation was retimed")
            frames.append({"path":png_from_report(path,frame["file"],frame.get("sha256")),"duration_ms":int(frame["duration_ms"]),"source_metadata":{"direction":direction,"cycle":frame["cycle"],"frame":frame["frame"],"source_index":expected["source_index"],"producer_png_sha256":frame["sha256"]}})
        need(clip["duration_ms_per_loop"]==sum(f["duration_ms"] for f in frames[:27]),"Declared loop duration is wrong")
        coverage=["loops:"+direction+":3","loop-seams"]
        metadata={"direction":direction,"mode":mode,"complete_cycles":3,"original_frames_per_cycle":27,"internal_loop_seams":[{"from_frame":26,"to_frame":0,"packet":27},{"from_frame":26,"to_frame":0,"packet":54}],"scope":"Three original animation cycles; two internal loop boundaries are present. These captures are force-drawn visual evidence and do not measure real-time playback speed."}
        if mode=="clay-sweep":
            samples=[s for s in data["light_samples"] if s["direction"]==direction]
            need(len(samples)>=15,"Missing recorded gray-material lamp sweep")
            nearest={}
            for name,phase in {"right":0.0,"up":math.pi*.5,"left":math.pi,"down":math.pi*1.5}.items():
                sample=min(samples,key=lambda s:abs(math.atan2(math.sin(s["phase"]-phase),math.cos(s["phase"]-phase))))
                error=abs(math.atan2(math.sin(sample["phase"]-phase),math.cos(sample["phase"]-phase)))
                need(error<.13,"Gray sweep does not approach camera-relative "+name)
                nearest[name]={"cycle":sample["cycle"],"frame":sample["frame"],"phase":sample["phase"],"angular_error_degrees":math.degrees(error),"world_light_position":sample["position"]}
            metadata["sweep_cardinal_samples"]=nearest
            coverage.extend(["clay","sweep:left","sweep:right","sweep:up","sweep:down"])
        videos.append(encode_clip(mode+"-"+direction,frames,folder,"Actual Godot character "+direction+" original three loops"+(" with gray material and camera-relative four-direction lamp sweep" if mode=="clay-sweep" else " under scene lighting"),coverage,path,metadata))
    need(seen=={(mode,direction) for mode in ("color","clay-sweep") for direction in DIRECTIONS},"Missing direction/material capture")
    return videos


def route_clip(path: Path,data: dict,folder: Path) -> dict:
    need(data.get("no_fixed_fps") is True and float(data.get("time_scale",0))==1.0,"Route has a fabricated fixed-FPS time base")
    rows=data.get("frames",[])
    need(len(rows)>=20 and data.get("route_result",{}).get("passed") is True,"Incomplete physical route capture")
    times=[float(frame["wall_elapsed_ms"]) for frame in rows]
    need(all(math.isfinite(value) for value in times),"Invalid route wall-clock data")
    need(all(b>a for a,b in zip(times,times[1:])),"Route capture timestamps are not strictly monotonic")
    # Presentation times follow the observed wall clock, rounded once to 1ms.
    # This preserves long gaps/backpressure rather than inventing smooth FPS.
    pts=[round(value-times[0]) for value in times]
    need(all(b>a for a,b in zip(pts,pts[1:])),"Route sampling is too fast for millisecond video timestamps")
    observed=[b-a for a,b in zip(pts,pts[1:])]
    final_duration=max(1,round(statistics.median(observed)))
    durations=observed+[final_duration]
    frames=[]
    for index,(row,duration) in enumerate(zip(rows,durations)):
        metadata={key:row[key] for key in ("wall_elapsed_ms","physics_index","physics_elapsed_frames","simulation_elapsed_ms","period","route_index","world_foot","phase") if key in row}
        metadata["wall_time_rounding_error_ms"]=pts[index]-(times[index]-times[0])
        metadata["producer_png_sha256"]=row.get("sha256")
        frames.append({"path":png_from_report(path,row["file"],row.get("sha256")),"duration_ms":duration,"source_metadata":metadata})
    need(max(abs(f["source_metadata"]["wall_time_rounding_error_ms"]) for f in frames)<=.50001,"Wall-clock timestamp rounding drift")
    metadata={"timing_source":"actual monotonic wall_elapsed_ms from GPU route captures, nearest-millisecond VFR","first_wall_elapsed_ms":times[0],"last_wall_elapsed_ms":times[-1],"terminal_duration_ms":final_duration,"terminal_duration_inferred":True,"terminal_duration_method":"median observed adjacent presentation interval; only the final still has inferred display duration","route_result":data["route_result"],"cancel_result":data.get("cancel_result",{}),"sampling":data.get("sampling",{}),"scope":"Physical route plus observed capture/readback/backpressure pacing. This video is not a throughput benchmark; quantitative performance is measured separately."}
    return encode_clip("physical-route",frames,folder,"Actual Godot CharacterBody3D route with collision and monotonic wall-clock capture timing",["route"],path,metadata)


def encode(args) -> dict:
    current=fingerprint(ROOT)["sha256"]
    normal_path=Path(args.normal_report).resolve()
    normal=check_report(normal_path,current)
    route_path=Path(args.route_report).resolve()
    route=None if args.normals_only else check_report(route_path,current)
    folder=Path(args.output_dir).resolve();portable(folder)
    videos=normal_clips(normal_path,normal,folder)
    if route is not None:videos.append(route_clip(route_path,route,folder))
    need(fingerprint(ROOT)["sha256"]==current,"Runtime source changed while encoding evidence")
    sources=[normal_path]+([route_path] if route is not None else [])
    for path,data in [(normal_path,normal)]+([(route_path,route)] if route is not None else []):
        need(load(path)==data,"Capture report changed while encoding")
    result={"schema_version":1,"passed":True,"runtime_fingerprint":current,"status":"normal-clips-only" if args.normals_only else "encoded-requested-evidence","scope":"Encoding verifies existing real GPU PNG provenance, original animation milliseconds, exact MP4 frame PTS/durations and native 1080p. This report does not generate GPU evidence or substitute for interaction/visual/performance review.","videos":videos,"coverage":sorted({scope for record in videos for scope in record["coverage"]}),"source_reports":[{"path":portable(p),"sha256":sha(p)} for p in sources],"remaining_scope":["route"] if args.normals_only else [],"ffmpeg_version":subprocess.check_output(["ffmpeg","-version"],text=True).splitlines()[0],"source_pngs_unmodified":True,"interpolated_frames":0,"resized_frames":0}
    report_path=OUT/"video-report.json"
    save(report_path,result)
    print("ANCIENT_CANAL_VIDEO_REPORT",portable(report_path),len(videos),"verified videos")
    return result


def self_test() -> None:
    folder=OUT/"encoder-fixture"
    folder.mkdir(parents=True,exist_ok=True)
    frames=[]
    durations=[41,42,41,42,42,17,29,33]
    for index,duration in enumerate(durations):
        path=folder/f"fixture-{index:05}.png"
        image=Image.new("RGB",SIZE,(index*25,60,130))
        ImageDraw.Draw(image).text((50,50),"ENCODER SYNTHETIC FIXTURE; NOT GPU EVIDENCE; "+str(index),fill="white")
        image.save(path)
        frames.append({"path":path,"duration_ms":duration,"source_metadata":{"fixture":True}})
    record=encode_clip("encoder-self-test",frames,folder,"Synthetic codec/time-base verification only; not GPU or scene evidence",[])
    need(round(record["duration_s"]*1000)==sum(durations),"Synthetic timing self-test failed")
    save(folder/"encoder-self-test-report.json",{"passed":True,"scope":"Synthetic 1080p PNG encoder exact VFR millisecond round-trip, explicitly not GPU evidence","durations_ms":durations,"video":record})
    print("ENCODER_SELF_TEST passed; no GPU evidence created")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--normal-report",default=OUT/"character-normal-render/normal-render-report.json")
    parser.add_argument("--route-report",default=OUT/"route-render/route-render-report.json")
    parser.add_argument("--output-dir",default=OUT/"videos")
    parser.add_argument("--normals-only",action="store_true",help="Encode eight normal clips while route capture is pending; package still requires route evidence")
    parser.add_argument("--self-test",action="store_true",help="Test exact codec timestamps on explicitly synthetic PNGs; never writes the acceptance video report")
    parsed=parser.parse_args()
    self_test() if parsed.self_test else encode(parsed)
