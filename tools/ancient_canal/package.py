#!/usr/bin/env python3
"""Export from an isolated stage, then package only current accepted evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import posixpath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from urllib.parse import unquote, urlsplit

from run import ROOT,OUT,run,engine
sys.path.insert(0,str(ROOT/"tools"))
from feature_fingerprint import fingerprint
from source_files import source_files

MAIN_SCENE="res://scenes/ancient_canal.tscn"
DOC=ROOT/"docs/ancient-canal"
EVIDENCE_KEYS={"sources","headless","input_regression","gpu","video","performance","settings","standalone"}
REQUIREMENTS={"sources","models","character_normals","calibration","visual_loops","light_sweeps",
              "scene_comparison","interaction","input_safety","parameters","settings","old_regression",
              "gpu_performance","standalone","camera_profiles","upright_sprites","distant_scenery","streetlights","dock_stability"}
FORBIDDEN_PARTS={".git",".godot","__pycache__",".venv","node_modules","cache","logs","system-libs"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text())


def save(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")


def evidence_path(name):
    path=Path(name)
    if path.is_absolute() or any(part in FORBIDDEN_PARTS for part in path.parts):
        raise ValueError("Evidence path is not portable: "+str(name))
    candidate=OUT/path
    for part in [candidate,*candidate.parents]:
        if part==OUT.parent:break
        if part.is_symlink():
            raise ValueError("Evidence cannot redirect through symbolic links: "+str(name))
    resolved=(OUT/path).resolve()
    if not resolved.is_relative_to(OUT.resolve()) or not resolved.is_file() or resolved.is_symlink():
        raise ValueError("Missing scoped evidence: "+str(name))
    return resolved


def source_paths():
    values=[]
    for path in source_files(ROOT):
        relative=path.relative_to(ROOT)
        if "research" in relative.parts or any(p in FORBIDDEN_PARTS for p in relative.parts):continue
        if path.suffix.lower() in {".log",".pyc",".blend1",".blend2",".so",".dll",".dylib",".a"}:continue
        values.append(path)
    return values


def assert_current(data,label,current):
    if not data.get("passed") or data.get("runtime_fingerprint")!=current:
        raise RuntimeError(label+" is failed, unproven, or belongs to different runtime source")


def linked_record(record,scope):
    """Check a producer's recorded digest, before deriving a new bundle digest."""
    path=evidence_path(record["path"])
    if not record.get("sha256") or sha(path)!=record["sha256"]:
        raise RuntimeError("Changed "+scope+" artifact")
    return path


def audit_source_inventory(current):
    source=load(evidence_path("source-check.json"))
    inventory=load(evidence_path("source-hashes.json"))
    review=load(evidence_path("source-review.json"))
    for label,data in [("source check",source),("full source inventory",inventory),("source review",review)]:
        assert_current(data,label,current)
    if inventory.get("before")!=current or inventory.get("after")!=current:
        raise RuntimeError("Source inventory was not made against an unchanged current runtime")
    files=inventory.get("files",{})
    paths={p.relative_to(ROOT).as_posix():p for p in source_paths()}
    if not isinstance(files,dict) or not files or set(files)!=set(paths):
        raise RuntimeError("Complete current source boundary differs from its audited inventory")
    if inventory.get("source_file_count")!=len(paths):
        raise RuntimeError("Source inventory count differs from its actual complete boundary")
    digest=hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest()
    if digest!=inventory.get("inventory_sha256"):
        raise RuntimeError("Canonical source inventory digest changed")
    for name,path in paths.items():
        if sha(path)!=files[name]:
            raise RuntimeError("Authored source changed after full inventory audit: "+name)
    subset=source.get("files",{})
    if not isinstance(subset,dict) or not subset or any(files.get(name)!=value for name,value in subset.items()):
        raise RuntimeError("Asset checks do not match the complete audited source inventory")
    chain=review.get("evidence",{})
    for key,name in [("source_check","source-check.json"),("source_inventory","source-hashes.json")]:
        entry=chain.get(key,{})
        if entry.get("path")!=name:
            raise RuntimeError("Source review lacks its expected report chain: "+key)
        linked_record(entry,"source review "+key)
    requirements=review.get("requirements",[])
    if len(requirements)!=3 or {entry.get("id") for entry in requirements}!={"sources","models","character_normals"}:
        raise RuntimeError("Source review must independently cover all three source scopes")
    for entry in requirements:
        if not entry.get("passed") or not entry.get("scope") or "source-check.json" not in entry.get("evidence",[]):
            raise RuntimeError("Source review requirement lacks proved scope")
        if entry["id"]=="sources" and "source-hashes.json" not in entry["evidence"]:
            raise RuntimeError("Source requirement omits the complete editable inventory")
        for name in entry["evidence"]:
            evidence_path(name)
    return source,inventory,review


def audit_settings_chain(settings,current):
    assert_current(settings,"settings aggregate",current)
    if not settings.get("independent_file") or not settings.get("cross_process") or not settings.get("runtime_unchanged"):
        raise RuntimeError("Settings evidence does not prove isolated cross-process save/load")
    if settings.get("runtime_fingerprint_before")!=current or settings.get("runtime_fingerprint_after")!=current:
        raise RuntimeError("Settings processes belong to a stale or changing runtime")
    references=settings.get("source_reports",[])
    expected=[settings.get("write_report"),settings.get("read_report")]
    if None in expected or len(set(expected))!=2 or len(references)!=2 or {item.get("path") for item in references}!=set(expected):
        raise RuntimeError("Settings raw write/read report references are incomplete")
    raw={}
    paths=set()
    for item in references:
        path=linked_record(item,"settings raw process")
        data=load(path);assert_current(data,"settings raw process",current)
        if not data.get("checks") or not all(check.get("passed") for check in data["checks"]):
            raise RuntimeError("A settings process contains unproved checks")
        raw[item["path"]]=data;paths.add(path)
    checks=raw[expected[0]]["checks"]+raw[expected[1]]["checks"]
    if settings.get("checks")!=checks or settings.get("checks_count")!=len(checks):
        raise RuntimeError("Settings aggregate does not preserve both process check sets")
    if settings.get("fixed_fps") is not False or settings.get("import_performed") is not False or settings.get("settings_probe_file_removed") is not True:
        raise RuntimeError("Settings isolation or probe cleanup evidence is incomplete")
    return paths


def audit_review_links(data,current):
    """Keep reviewed capture reports and montage bytes bound to that review."""
    paths=set()
    if data.get("source_report"):
        path=linked_record({"path":data["source_report"],"sha256":data.get("source_report_sha256")},"reviewed capture")
        assert_current(load(path),"reviewed capture",current)
        paths.add(path)
    for item in data.get("source_reports",[]):
        path=linked_record(item,"reviewed producer")
        assert_current(load(path),"reviewed producer",current)
        paths.add(path)
    for item in data.get("related_reports",[]):
        path=linked_record(item,"related review report")
        assert_current(load(path),"related review report",current)
        paths.add(path)
    if data.get("source_video_report"):
        path=linked_record({"path":data["source_video_report"],"sha256":data.get("source_video_report_sha256")},"reviewed encoded-video producer")
        assert_current(load(path),"reviewed encoded-video producer",current)
        paths.add(path)
    for item in data.get("review_artifacts",[]):
        path=linked_record({"path":item.get("path",item.get("file")),"sha256":item.get("sha256")},"review montage")
        paths.add(path)
    for item in data.get("viewed",[]):
        if not isinstance(item,dict):
            continue
        if item.get("root")=="evidence":
            paths.add(linked_record(item,"reviewed scene pixels"))
        elif item.get("root")=="project":
            name=Path(item["path"])
            path=(ROOT/name).resolve()
            if name.is_absolute() or ".." in name.parts or not path.is_relative_to(ROOT.resolve()) or not path.is_file() or sha(path)!=item.get("sha256"):
                raise RuntimeError("Reviewed concept source changed")
    return paths


def audit_revision_history(history):
    # Failed/older reports are retained with their own recorded digests. Their
    # passed flag or fingerprint must never be used as current acceptance.
    references=history.get("artifacts",[])
    if not isinstance(references,list):
        raise RuntimeError("Revision history artifact references must be a list")
    return {linked_record(item,"historical revision") for item in references}


def export():
    current=fingerprint(ROOT)["sha256"]
    freeze=load(OUT/"freeze-report.json")
    assert_current(freeze,"freeze report",current)
    verification=load(ROOT/"build/templates/verification.json")
    version=subprocess.check_output([engine(),"--version"],text=True).strip()
    if verification["status"]!="verified_project_local" or not version.startswith(verification["engine"]):
        raise RuntimeError("Export templates do not match this engine")
    templates=[]
    for entry in verification["outputs"]:
        path=ROOT/entry["path"]
        if sha(path)!=entry["sha256"]:raise RuntimeError("Template checksum changed")
        templates.append(path)
    original=ROOT/"project.godot";original_hash=sha(original)
    staging=OUT/"staging";staging.mkdir(parents=True,exist_ok=True)
    stage=Path(tempfile.mkdtemp(prefix="export-",dir=staging))/"project"
    stage.mkdir()
    for path in source_paths():
        target=stage/path.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(path,target)
    for path in templates:
        target=stage/path.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
    settings=stage/"project.godot"
    text,count=re.subn(r'^run/main_scene=.*$',f'run/main_scene="{MAIN_SCENE}"',settings.read_text(),flags=re.MULTILINE)
    if count!=1:raise RuntimeError("Main scene setting was not found exactly once")
    settings.write_text(text)
    preset=stage/"export_presets.cfg"
    text=preset.read_text()
    found=re.search(r'^include_filter="(.*)"$',text,flags=re.MULTILINE)
    if not found:raise RuntimeError("Export JSON inclusion rule missing")
    additions="resources/ancient-canal/*.json,assets/ancient-canal/character-normals/v1/*.json,assets/ancient-canal/character-normals/v1/*/*.json"
    text=text[:found.start()]+f'include_filter="{found.group(1)},{additions}"'+text[found.end():]
    preset.write_text(text)
    assert not (stage/".godot").exists()
    # The existing runner only ignores the sandbox's optional editor debug socket
    # refusal for this import label. Every other import error remains fatal.
    run([engine(),"--headless","--path",stage,"--editor","--quit"],"import",timeout=600)
    folder=OUT/"linux";folder.mkdir(exist_ok=True)
    binary=folder/"jiangnan-river-street.x86_64"
    run([engine(),"--headless","--path",stage,"--export-release","Linux",binary],"canal-export",timeout=600)
    if not binary.is_file() or binary.read_bytes()[:4]!=b"\x7fELF":raise RuntimeError("No standalone Linux ELF produced")
    binary.chmod(binary.stat().st_mode|stat.S_IXUSR|stat.S_IXGRP|stat.S_IXOTH)
    if sha(original)!=original_hash or fingerprint(ROOT)["sha256"]!=current:
        raise RuntimeError("Original runtime changed during staged export")
    save(OUT/"export-report.json",{"schema_version":1,"passed":True,"runtime_fingerprint":current,
        "engine":version,"binary_path":binary.relative_to(OUT).as_posix(),"binary_sha256":sha(binary),
        "binary_size":binary.stat().st_size,"stage_main_scene":MAIN_SCENE,"original_project_sha256":original_hash,
        "original_entry_unchanged":True,"fresh_stage_import":True,"template_verification_sha256":sha(ROOT/"build/templates/verification.json"),
        "scope":"Independent stage export only. Standalone launch/GPU acceptance is a later separate gate."})
    print("ANCIENT_CANAL_EXPORTED",binary.relative_to(ROOT),sha(binary))


def checked_record(record,scope):
    path=linked_record(record,scope)
    if not record.get("scope"):raise RuntimeError("Missing attribution for "+scope)
    return path


def quantile(values,q):
    values=sorted(values);position=(len(values)-1)*q
    lo=math.floor(position);hi=math.ceil(position)
    return values[lo]+(values[hi]-values[lo])*(position-lo)


def capture_png(report_path,name):
    part=Path(name)
    if part.is_absolute() or ".." in part.parts:raise RuntimeError("Capture PNG path is not portable")
    candidates=list(dict.fromkeys(p for p in [report_path.parent/part,OUT/part] if p.is_file()))
    if len(candidates)!=1:raise RuntimeError("Capture PNG is missing or ambiguous: "+name)
    return evidence_path(candidates[0].relative_to(OUT).as_posix())


def video_chain(item,probe,current):
    """Bind the encoded MP4 to its actual capture, exact timestamps and concat."""
    paths={}
    source_images=set()
    for key in ["source_report","timing_report","concat_source"]:
        if not item.get(key) or not item.get(key+"_sha256"):
            raise RuntimeError("Video source chain is absent: "+key)
        path=evidence_path(item[key])
        if sha(path)!=item[key+"_sha256"]:raise RuntimeError("Video source chain changed: "+key)
        paths[key]=path
    source=load(paths["source_report"]);assert_current(source,"video capture",current)
    if source.get("hardware_gpu") is not True or source.get("renderer")!="forward_plus":
        raise RuntimeError("Video capture does not prove hardware Forward+")
    if source.get("size",source.get("viewport"))!=[1920,1080] or source.get("preferences_ignored") is not True:
        raise RuntimeError("Video capture is not isolated native 1080p evidence")
    if source.get("main_window_minimized") is not True or source.get("no_focus_flag",source.get("no_focus")) is not True:
        raise RuntimeError("Video capture did not preserve the desktop window policy")
    timing=load(paths["timing_report"])
    if not timing.get("passed") or not timing.get("no_duplicate_or_interpolated_frames") or not timing.get("source_pngs_unmodified"):
        raise RuntimeError("Video timing report did not pass original-frame fidelity")
    if evidence_path(timing["source_report"])!=paths["source_report"] or timing["source_report_sha256"]!=item["source_report_sha256"]:
        raise RuntimeError("Timing report points to a different GPU capture")
    if evidence_path(timing["video"])!=evidence_path(item["path"]):
        raise RuntimeError("Timing report points to a different MP4")
    frames=timing.get("frames",[]);packets=probe.get("packets",[])
    if not frames or len(frames)!=item["frame_count"] or len(frames)!=timing["frame_count"] or len(frames)!=len(packets) or len(frames)!=len(timing.get("packets",[])):
        raise RuntimeError("Video frame/packet counts differ along the source chain")
    if "route" in item.get("coverage",[]):
        rows=source.get("frames",[])
        if timing.get("metadata",{}).get("route_result")!=source.get("route_result") or not source.get("route_result",{}).get("passed"):
            raise RuntimeError("Route video belongs to a different or failed physical route")
    else:
        metadata=timing.get("metadata",{})
        clips=[clip for clip in source.get("clips",[]) if clip.get("direction")==metadata.get("direction") and clip.get("mode")==metadata.get("mode")]
        if len(clips)!=1:raise RuntimeError("Character timing cannot identify one captured clip")
        rows=clips[0].get("frames",[])
    if len(rows)!=len(frames):raise RuntimeError("Captured and encoded source-frame counts differ")
    concat=["ffconcat version 1.0"];pts=0
    for index,(frame,packet,declared,row) in enumerate(zip(frames,packets,timing["packets"],rows)):
        image=evidence_path(frame["source_png"])
        if image!=capture_png(paths["source_report"],row["file"]) or sha(image)!=frame["source_png_sha256"]:
            raise RuntimeError("Video source PNG differs from the captured/timing reference")
        if row.get("sha256") and row["sha256"]!=frame["source_png_sha256"]:
            raise RuntimeError("Video source PNG changed after its original capture")
        source_images.add(image)
        duration=frame["duration_ms"]
        if type(duration) is not int or duration<=0 or frame["packet"]!=index or frame["pts_ms"]!=pts:
            raise RuntimeError("Invalid source presentation timeline")
        if "duration_ms" in row and row["duration_ms"]!=duration:
            raise RuntimeError("Captured animation frame duration changed")
        actual_pts=float(packet["pts_time"])*1000;actual_duration=float(packet["duration_time"])*1000
        if not math.isfinite(actual_pts) or not math.isfinite(actual_duration) or abs(actual_pts-pts)>.0001 or abs(actual_duration-duration)>.0001:
            raise RuntimeError("Actual MP4 packets differ from recorded source timestamps")
        if declared["packet"]!=index or abs(declared["pts_ms"]-actual_pts)>.0001 or abs(declared["duration_ms"]-actual_duration)>.0001:
            raise RuntimeError("Timing proof does not match actual MP4 packets")
        relative=os.path.relpath(image,paths["concat_source"].parent).replace(os.sep,"/")
        escaped=relative.replace("'","'\\''")
        concat.extend(["file '"+escaped+"'","option framerate 1000",f"duration {duration/1000:.6f}"])
        pts+=duration
    if paths["concat_source"].read_text()!="\n".join(concat)+"\n":
        raise RuntimeError("Concat source does not identify the original PNG/timing sequence")
    duration=float(probe["format"]["duration"])
    if timing.get("time_base")!="1/1000" or item.get("timing_exact_ms") is not True or timing["duration_ms"]!=pts or abs(duration*1000-pts)>.0001 or abs(item["duration_s"]-duration)>.0001:
        raise RuntimeError("Video total duration or time base changed")
    return set(paths.values())|source_images


def acceptance():
    current=fingerprint(ROOT)["sha256"]
    final=load(OUT/"final-report.json")
    assert_current(final,"final acceptance",current)
    if final.get("status")!="accepted":raise RuntimeError("Final acceptance is not complete")
    source,inventory,source_review=audit_source_inventory(current)
    requirements={entry["id"]:entry for entry in final["requirements"]}
    if not REQUIREMENTS<=set(requirements):raise RuntimeError("Missing planned acceptance scopes")
    artifacts={OUT/"final-report.json"}
    for name in REQUIREMENTS:
        req=requirements[name]
        if not req.get("passed") or not req.get("scope") or not req.get("evidence"):
            raise RuntimeError("Requirement lacks proved scope: "+name)
        for reference in req["evidence"]:artifacts.add(evidence_path(reference))
    evidence=final["evidence"]
    if not EVIDENCE_KEYS<=set(evidence):raise RuntimeError("Missing independent acceptance report")
    reports={}
    for name in EVIDENCE_KEYS:
        record=evidence[name];path=evidence_path(record["path"])
        if sha(path)!=record["sha256"]:raise RuntimeError("Acceptance report changed: "+name)
        data=load(path);assert_current(data,name,current)
        reports[name]=data;artifacts.add(path)
    if final.get("revision_history"):
        path=checked_record(final["revision_history"],"revision history index")
        artifacts.add(path)
        artifacts.update(audit_revision_history(load(path)))
    if reports["sources"]!=source:
        raise RuntimeError("Final acceptance references a different source check")
    for name in ["blockout.json","freeze-report.json","final-headless-suite.json"]:
        path=evidence_path(name)
        assert_current(load(path),name,current)
        artifacts.add(path)
    artifacts.update(evidence_path(name) for name in ("source-check.json","source-hashes.json","source-review.json"))
    artifacts.update(audit_settings_chain(reports["settings"],current))
    for item in reports["input_regression"].get("artifacts",[]):
        artifacts.add(linked_record(item,"input regression"))
    gpu=reports["gpu"]
    if not gpu.get("gpu") or gpu.get("viewport")!=[1920,1080] or not gpu.get("screenshots"):
        raise RuntimeError("Real 1080p GPU evidence missing")
    review_names={"visual-review.json","route-visual-review.json","video-review.json","scene-comparison.json"}
    gpu_reports=gpu.get("reports",[])
    if not review_names<={item.get("path") for item in gpu_reports}:
        raise RuntimeError("GPU acceptance lacks the independent visual review chain")
    for item in gpu_reports:
        path=linked_record(item,"GPU capture/review")
        data=load(path);assert_current(data,"GPU capture/review",current)
        artifacts.add(path)
        artifacts.update(audit_review_links(data,current))
    for item in gpu.get("review_artifacts",[]):
        artifacts.add(checked_record(item,"derived review contact"))
    from PIL import Image
    for item in gpu["screenshots"]:
        path=checked_record(item,"GPU screenshot")
        if Image.open(path).size!=(1920,1080):raise RuntimeError("Screenshot viewport changed")
        artifacts.add(path)
    videos=reports["video"].get("videos",[])
    if not videos:raise RuntimeError("No actual Godot video artifacts")
    video_scopes=set()
    for item in videos:
        path=checked_record(item,"video")
        data=json.loads(subprocess.check_output(["ffprobe","-v","error","-select_streams","v:0",
              "-show_packets","-show_entries","stream=width,height:format=duration:packet=pts_time,duration_time","-of","json",str(path)],text=True))
        stream=data["streams"][0]
        if [stream["width"],stream["height"]]!=[1920,1080]:raise RuntimeError("Video is not native 1080p")
        if float(data["format"]["duration"])<=0:raise RuntimeError("Empty video")
        artifacts.update(video_chain(item,data,current))
        video_scopes.update(item.get("coverage",[]));artifacts.add(path)
    expected={"loops:down:3","loops:up:3","loops:left:3","loops:right:3","loop-seams",
              "sweep:left","sweep:right","sweep:up","sweep:down","clay","route"}
    if not expected<=video_scopes:raise RuntimeError("Videos do not cover all planned loop/light/route scopes")
    presets=reports["performance"].get("presets",{})
    if set(presets)!={"day","dusk","night"}:raise RuntimeError("Three real-time presets are required")
    for period,entry in presets.items():
        if entry["duration_s"]<30 or entry["viewport"]!=[1920,1080]:raise RuntimeError("Insufficient performance window")
        sample_path=evidence_path(entry["samples_path"])
        if sha(sample_path)!=entry["sha256"]:raise RuntimeError("Performance samples changed")
        samples=load(sample_path)
        if samples.get("mode")!="real-time" or samples.get("viewport")!=[1920,1080] or samples["elapsed_s"]<30:
            raise RuntimeError("Offline or wrong-resolution samples cannot prove runtime performance")
        values=samples["frame_intervals_ms"]
        if samples.get("warmup_elapsed_s",0)<5 or samples.get("fixed_fps") is not False or samples.get("time_scale")!=1 or samples.get("readback_count")!=0:
            raise RuntimeError("Performance isolation or warmup contract changed")
        counters=samples.get("draw_counters",{})
        post_ids=samples.get("server_post_draw_ids",[])
        pre_ids=samples.get("completed_pre_draw_ids",[])
        if not counters.get("passed") or len(post_ids)!=len(values) or len(pre_ids)!=len(values):
            raise RuntimeError("Completed GPU draw counts are unproven")
        if not all(b==a+1 for ids in (post_ids,pre_ids) for a,b in zip(ids,ids[1:])):
            raise RuntimeError("Repeated or missing completed GPU draw samples")
        if counters.get("deltas",{}).get("post_events")!=len(values):
            raise RuntimeError("Frame samples do not match independent draw events")
        if len(values)<100 or not all(math.isfinite(v) and v>0 for v in values):raise RuntimeError("Invalid frame samples")
        if abs(sum(values)/1000-samples["elapsed_s"])>max(.5,samples["elapsed_s"]*.03):
            raise RuntimeError("Frame intervals do not cover the declared wall clock")
        for label,q in [("p50_ms",.5),("p95_ms",.95),("p99_ms",.99)]:
            if abs(quantile(values,q)-entry[label])>.1:raise RuntimeError("Frame quantile does not match raw samples")
        if bool(entry["target_60fps_p95_met"])!=(entry["p95_ms"]<=1000/60):raise RuntimeError("Incorrect 60 FPS conclusion")
        if not entry["target_60fps_p95_met"]:raise RuntimeError("60 FPS acceptance target remains unmet: "+period)
        artifacts.add(sample_path)
    export_report=load(OUT/"export-report.json")
    assert_current(export_report,"export",current)
    binary=evidence_path(export_report["binary_path"])
    if sha(binary)!=export_report["binary_sha256"]:raise RuntimeError("Exported binary changed")
    standalone=reports["standalone"]
    if standalone.get("binary_sha256")!=sha(binary) or not standalone.get("headless") or not standalone.get("gpu"):
        raise RuntimeError("Current standalone binary has not passed both launch scopes")
    if not standalone.get("empty_cwd") or not standalone.get("fresh_xdg") or standalone.get("explicit_scene_argument") is not False:
        raise RuntimeError("Standalone relied on the source checkout or an explicit scene override")
    standalone_artifacts=standalone.get("artifacts",[])
    if len(standalone_artifacts)<3:raise RuntimeError("Standalone raw launch/screenshot evidence missing")
    for item in standalone_artifacts:artifacts.add(checked_record(item,"standalone"))
    artifacts.add(OUT/"export-report.json")
    return final,binary,artifacts


def zip_verified(path,items,extra=None):
    with zipfile.ZipFile(path,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for source,name in sorted(items,key=lambda v:v[1]):archive.write(source,name)
        for name,content in (extra or {}).items():archive.writestr(name,content)
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:raise RuntimeError("Bundle integrity check failed")


def runtime_documentation():
    documents={name:(DOC/name).read_bytes() for name in ("README.md","production.md","acceptance.md")}
    documents["NOTICE.md"]=(ROOT/"NOTICE.md").read_bytes()
    replacements={
        "README.md":("[领域模型](../../domain-model/ancient-canal.md)","完整工程中的 `domain-model/ancient-canal.md`"),
        "NOTICE.md":("[角色来源](art_source/characters/crescent-traveler/v1/README.md)","完整工程中的 `art_source/characters/crescent-traveler/v1/README.md`"),
    }
    derivations={}
    for name,(original,replacement) in replacements.items():
        text=documents[name].decode("utf-8")
        if text.count(original)!=1:
            raise RuntimeError("Expected one full-project documentation link in "+name)
        derivations[name]={"source_sha256":hashlib.sha256(documents[name]).hexdigest(),"replaced_link":original,"replacement":replacement}
        documents[name]=text.replace(original,replacement).encode("utf-8")
    return documents,derivations


def verify_runtime_markdown_links(path):
    with zipfile.ZipFile(path) as archive:
        names=set(archive.namelist())
        for name in names:
            if not name.lower().endswith(".md"):
                continue
            text=archive.read(name).decode("utf-8")
            inline=re.findall(r'!?\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|([^\s)]+))',text)
            references=re.findall(r'^\s{0,3}\[[^\]\n]+\]:\s*(?:<([^>\n]+)>|([^\s]+))',text,re.MULTILINE)
            for angled,plain in inline+references:
                target=angled or plain
                url=urlsplit(target)
                if url.scheme or url.netloc or not url.path:
                    continue
                local=unquote(url.path)
                resolved=posixpath.normpath(posixpath.join(posixpath.dirname(name),local))
                if local.startswith("/") or (resolved not in names and not any(entry.startswith(resolved.rstrip("/")+"/") for entry in names)):
                    raise RuntimeError("Missing local runtime Markdown target: "+name+" -> "+target)


def package():
    final,binary,evidence=acceptance()
    if not all((DOC/name).is_file() for name in ("README.md","production.md","acceptance.md")):raise RuntimeError("Chinese delivery documentation missing")
    folder=OUT/"delivery";folder.mkdir(parents=True,exist_ok=True)
    sources=source_paths();source_checksums={p.relative_to(ROOT).as_posix():sha(p) for p in sources}
    evidence_checksums={p.relative_to(OUT).as_posix():sha(p) for p in evidence}
    binary_hash=sha(binary)
    required=["scenes/ancient_canal.tscn","art_source/ancient-canal/character-reuse.json",
              "art_source/ancient-canal/character-normals/build-recipe.json","art_source/ancient-canal/textures/mother-sheet.png",
              "art_source/ancient-canal/blender/tavern.blend","assets/ancient-canal/fonts/OFL.txt"]
    if not set(required)<=set(source_checksums):raise RuntimeError("Complete source boundary omitted production assets")
    zip_verified(folder/"jiangnan-complete-project.zip",[(p,"hd-2d-godot/"+p.relative_to(ROOT).as_posix()) for p in sources],
                 {"hd-2d-godot/SOURCE_SHA256.json":json.dumps(source_checksums,ensure_ascii=False,indent=2)+"\n"})
    documents,document_derivations=runtime_documentation()
    document_checksums={name:hashlib.sha256(content).hexdigest() for name,content in documents.items()}
    runtime=[(binary,"jiangnan-river-street/"+binary.name),
             (ROOT/"assets/ancient-canal/fonts/OFL.txt","jiangnan-river-street/licenses/Noto-OFL.txt")]
    runtime.extend((p,"jiangnan-river-street/licenses/"+p.relative_to(ROOT/"licenses").as_posix()) for p in (ROOT/"licenses").rglob("*") if p.is_file())
    runtime_extra={"jiangnan-river-street/"+name:content for name,content in documents.items()}
    runtime_extra["jiangnan-river-street/RUNTIME_SHA256.json"]=json.dumps({"binary":sha(binary),"runtime_fingerprint":final["runtime_fingerprint"],"default_scene":MAIN_SCENE,"documents":document_checksums,"document_derivations":document_derivations},ensure_ascii=False,indent=2)+"\n"
    zip_verified(folder/"jiangnan-linux-x86_64.zip",runtime,runtime_extra)
    verify_runtime_markdown_links(folder/"jiangnan-linux-x86_64.zip")
    zip_verified(folder/"jiangnan-evidence.zip",[(p,p.relative_to(OUT).as_posix()) for p in evidence],
                 {"EVIDENCE_SHA256.json":json.dumps(evidence_checksums,indent=2)+"\n"})
    if fingerprint(ROOT)["sha256"]!=final["runtime_fingerprint"] or sha(binary)!=binary_hash:
        raise RuntimeError("Runtime changed while assembling delivery")
    if source_checksums!={p.relative_to(ROOT).as_posix():sha(p) for p in source_paths()}:
        raise RuntimeError("Editable production sources changed while assembling delivery")
    if any(sha(OUT/name)!=digest for name,digest in evidence_checksums.items()):
        raise RuntimeError("Acceptance evidence changed while assembling delivery")
    for name in ("README.md","production.md","acceptance.md"):
        (folder/name).write_bytes(documents[name])
    save(folder/"delivery-report.json",{"schema_version":1,"passed":True,"runtime_fingerprint":final["runtime_fingerprint"],
        "binary_sha256":sha(binary),"default_scene":MAIN_SCENE,"original_project_entry_preserved":True,
        "source_file_count":len(sources),"evidence_file_count":len(evidence),"committed":False,"pushed":False,
        "runtime_document_sha256":document_checksums,"runtime_document_derivations":document_derivations,"runtime_markdown_links_valid":True,
        "acceptance_report_sha256":sha(OUT/"final-report.json"),"limitations":final.get("limitations",[])})
    sums="".join(sha(p)+"  "+p.name+"\n" for p in sorted(folder.iterdir()) if p.is_file() and p.name!="SHA256SUMS")
    (folder/"SHA256SUMS").write_text(sums)
    print("ANCIENT_CANAL_DELIVERY",folder.relative_to(ROOT),len(sources),"source files")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action",choices=["export","package"])
    args=parser.parse_args()
    export() if args.action=="export" else package()
