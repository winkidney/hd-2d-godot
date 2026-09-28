"""Package P6/P7 with fresh runtime, native GPU, standalone and rebuild gates."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from project import ROOT
from feature_fingerprint import fingerprint
from source_files import source_files

def read(name):
    return json.loads((ROOT/name).read_text())

def require(value,message):
    if not value: raise RuntimeError(message)

def main() -> None:
    for script in ('tests/check_project.py','tests/check_features.py'):
        subprocess.run([sys.executable,script],cwd=ROOT,check=True)
    current=fingerprint(ROOT)['sha256']
    for folder in ('headless','gpu'):
        report=read('build/p6p7/'+folder+'/features-report.json')
        require(report['passed'] and report['runtime_fingerprint']==current,'Stale or failed '+folder+' report')
    gpu=read('build/p6p7/gpu/features-report.json')
    require(len(gpu.get('performance',{}))==5,'Full performance report required')
    for name,data in gpu['performance'].items():
        require(data['duration_s']>=30 and data['target_60fps_p95_met'],'Performance gate failed: '+name)
    for path in ('build/validation/static-report.json','build/p6p7/static-report.json','build/p6p7/gpu/image-report.json'):
        require(read(path)['passed'],'Failed report: '+path)
    rebuilt=read('build/p6p7/reproduction-report.json')
    require(rebuilt['passed'] and rebuilt['real_gpu_checked'] and rebuilt['origin_runtime_fingerprint']==current,'Fresh clean-copy GPU rebuild required')
    binary=ROOT/'build/linux/waystation.x86_64'
    standalone=read('build/p6p7/standalone/report.json')
    require(standalone['passed'] and standalone['runtime_fingerprint']==current,'Standalone runtime fingerprint mismatch')
    require(standalone['binary_sha256']==hashlib.sha256(binary.read_bytes()).hexdigest(),'Standalone executable hash mismatch')
    require(read('build/p6p7/standalone/gpu/image-report.json')['passed'],'Standalone image checks failed')
    out=ROOT/'build/delivery/p6p7';out.mkdir(parents=True,exist_ok=True)
    files=source_files(ROOT)
    require(not any(p.suffix.lower() in ('.ttf','.otf','.woff','.woff2') for p in files),'Unexpected font file in source export')
    sources={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    source_zip=out/'hd-2d-godot-p6p7-source.zip'
    with zipfile.ZipFile(source_zip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for path in files:
            archive.write(path,'hd-2d-godot/'+path.relative_to(ROOT).as_posix())
        archive.writestr('hd-2d-godot/SOURCE_SHA256.json',json.dumps(sources,indent=2)+'\n')
    linux_zip=out/'hd-2d-waystation-p6p7-linux-x86_64.zip'
    with zipfile.ZipFile(linux_zip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        archive.write(binary,'hd-2d-waystation/waystation.x86_64')
        archive.write(ROOT/'docs/delivery/runtime-README.txt','hd-2d-waystation/README.txt')
        archive.write(ROOT/'NOTICE.md','hd-2d-waystation/NOTICE.md')
        for path in (ROOT/'licenses').glob('*.txt'):
            archive.write(path,'hd-2d-waystation/licenses/'+path.name)
    movie=ROOT/'build/p6p7/media/walkthrough.mp4'
    require(movie.is_file(),'Recorded walkthrough missing')
    video=read('build/p6p7/media/video-report.json')
    require(video['passed'] and video['runtime_fingerprint']==current and video['sha256']==hashlib.sha256(movie.read_bytes()).hexdigest(),'Recorded walkthrough is stale or failed')
    shutil.copy2(movie,out/'walkthrough.mp4')
    artifacts=[source_zip,linux_zip,out/'walkthrough.mp4']
    (out/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in artifacts))
    for path in (source_zip,linux_zip):
        with zipfile.ZipFile(path) as archive:
            require(archive.testzip() is None,'Corrupt ZIP: '+path.name)
    manifest={'passed':True,'runtime_fingerprint':current,'source_file_count':len(files),'binary_sha256':standalone['binary_sha256'],'artifacts':[{'name':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in artifacts]}
    (out/'delivery-report.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2))

if __name__=='__main__':
    main()
