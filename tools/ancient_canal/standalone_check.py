#!/usr/bin/env python3
"""Verify the exported embedded game from an empty, isolated working directory."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

from run import ROOT, OUT
sys.path.insert(0,str(ROOT/"tools"))
from feature_fingerprint import fingerprint
from project import desktop_environment

SCENE="res://scenes/ancient_canal.tscn"
EXPECTED_RESOURCES={"color_frames":108,"normal_frames":108,"mask_frames":108,
    "directions":4,"models":12,"npcs":3,"frame_size":[256,256],"pivot":[128,240],
    "font_loaded":True,"ui_pages":4}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")


def validate_result(data,mode,current):
    if not data.get("passed") or data.get("runtime_fingerprint")!=current:
        raise RuntimeError(mode+" failed or belongs to different runtime source")
    if data.get("scene")!=SCENE or data.get("mode")!=mode:
        raise RuntimeError("Standalone did not enter the exported default Jiangnan scene")
    resources=data.get("resources",{})
    for name,value in EXPECTED_RESOURCES.items():
        if resources.get(name)!=value:raise RuntimeError("Standalone resource mismatch: "+name)
    checks=data.get("checks",[])
    if not checks or any(not item.get("passed") or not item.get("scope") for item in checks):
        raise RuntimeError("Standalone resource checks are absent, failed, or lack attribution")
    if mode=="gpu":
        if data.get("viewport")!=[1920,1080] or not data.get("screenshot_saved"):
            raise RuntimeError("Standalone actual 1080p screenshot was not saved")
        if not data.get("hardware_gpu") or not data.get("renderer"):
            raise RuntimeError("Standalone renderer attribution is missing")
        if not data.get("main_window_minimized") or not data.get("no_focus"):
            raise RuntimeError("Standalone GPU check did not preserve the desktop window policy")


def launch(binary,mode,current,folder,timeout):
    result_path=folder/(mode+"-result.json")
    screenshot=folder/"standalone.png"
    result_path.unlink(missing_ok=True)
    if mode=="gpu":screenshot.unlink(missing_ok=True)
    # A copy in an empty /tmp directory avoids both parent project discovery
    # and loading imported resources from the source checkout's cache.
    with tempfile.TemporaryDirectory(prefix="jiangnan-standalone-") as isolated:
        isolated=Path(isolated)
        game=isolated/binary.name
        shutil.copy2(binary,game)
        game.chmod(game.stat().st_mode|stat.S_IXUSR)
        if sha(game)!=sha(binary):raise RuntimeError("Isolated binary copy changed")
        env=desktop_environment() if mode=="gpu" else os.environ.copy()
        for name in ["DATA","CONFIG","CACHE"]:
            destination=isolated/("xdg-"+name.lower())
            destination.mkdir()
            env["XDG_"+name+"_HOME"]=str(destination)
        command=[str(game),"--audio-driver","Dummy"]
        if mode=="headless":command.append("--headless")
        else:command.extend(["--display-driver","x11","--position","10000,10000",
                             "--resolution","1920x1080","--disable-render-loop"])
        command.extend(["--","--canal-standalone-test","--ignore-user-settings",
                        "--canal-fingerprint="+current,"--canal-test-output="+str(result_path)])
        if mode=="gpu":command.extend(["--canal-test-gpu","--canal-test-screenshot="+str(screenshot)])
        logs=OUT/"logs";logs.mkdir(parents=True,exist_ok=True)
        with (logs/("standalone-"+mode+".log")).open("w") as output:
            process=subprocess.run(command,cwd=isolated,env=env,stdout=output,
                                   stderr=subprocess.STDOUT,timeout=timeout)
    output=(logs/("standalone-"+mode+".log")).read_text()
    if process.returncode or any(marker in output for marker in ["ERROR:","ASSERT_FAIL","CANAL_STANDALONE_FAIL"]):
        raise RuntimeError("Standalone "+mode+" process failed; see its scoped build log")
    if not result_path.is_file():raise RuntimeError("Standalone result was not produced")
    data=json.loads(result_path.read_text());validate_result(data,mode,current)
    artifacts=[{"path":result_path.relative_to(OUT).as_posix(),"sha256":sha(result_path),
                "scope":"Embedded standalone "+mode+" resource/UI/default-scene probe"}]
    if mode=="gpu":
        from PIL import Image
        import numpy as np
        if not screenshot.is_file():raise RuntimeError("Standalone screenshot does not exist")
        with Image.open(screenshot) as image:
            if image.size!=(1920,1080):raise RuntimeError("Standalone screenshot dimensions differ")
            pixels=np.asarray(image.convert("RGB"),dtype=np.float32)
            if pixels.std()<2:raise RuntimeError("Standalone screenshot is empty or uniform")
        artifacts.append({"path":screenshot.relative_to(OUT).as_posix(),"sha256":sha(screenshot),
                          "scope":"Real standalone own-world 1080p GPU viewport, minimized and without focus"})
    return data,artifacts


def check(timeout):
    OUT.mkdir(parents=True,exist_ok=True)
    report_path=OUT/"standalone-report.json"
    current=fingerprint(ROOT)["sha256"]
    save(report_path,{"schema_version":1,"passed":False,"runtime_fingerprint":current,
                      "scope":"Standalone checks pending; no earlier success retained"})
    export=json.loads((OUT/"export-report.json").read_text())
    if not export.get("passed") or export.get("runtime_fingerprint")!=current:
        raise RuntimeError("A current successful staged export is required")
    relative=Path(export["binary_path"])
    binary=(OUT/relative).resolve()
    if relative.is_absolute() or not binary.is_relative_to(OUT.resolve()) or not binary.is_file():
        raise RuntimeError("Exported binary must be scoped to this build")
    binary_hash=sha(binary)
    if binary_hash!=export["binary_sha256"] or binary.read_bytes()[:4]!=b"\x7fELF":
        raise RuntimeError("Exported ELF changed")
    folder=OUT/"standalone";folder.mkdir(exist_ok=True)
    headless,headless_artifacts=launch(binary,"headless",current,folder,timeout)
    gpu,gpu_artifacts=launch(binary,"gpu",current,folder,timeout)
    if fingerprint(ROOT)["sha256"]!=current or sha(binary)!=binary_hash:
        raise RuntimeError("Runtime or binary changed during standalone acceptance")
    save(report_path,{"schema_version":1,"passed":True,"runtime_fingerprint":current,
        "binary_sha256":binary_hash,"headless":True,"gpu":True,"default_scene":SCENE,
        "empty_cwd":True,"fresh_xdg":True,"explicit_scene_argument":False,
        "resources":gpu["resources"],"headless_checks":headless["checks"],"gpu_checks":gpu["checks"],
        "renderer":gpu["renderer"],"hardware_gpu":gpu["hardware_gpu"],"viewport":[1920,1080],
        "artifacts":headless_artifacts+gpu_artifacts,
        "scope":"Current exported ELF only in an empty temporary directory: default scene, 108 color/normal/mask resources, 12 original model resources plus the complete live scene (including the new streetlamps), 3 NPCs, font/UI, and actual 1080p GPU screenshot. No route or performance claim."})
    print("ANCIENT_CANAL_STANDALONE_CHECK_OK",binary_hash)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout",type=int,default=180)
    args=parser.parse_args()
    try:check(args.timeout)
    except (RuntimeError,OSError,ValueError,subprocess.SubprocessError) as error:
        print(str(error),file=sys.stderr)
        raise SystemExit(1)
