"""Package P8 only after fresh source, GPU, persistence and standalone checks."""
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
BASE=ROOT/'build/p8'
def read(path): return json.loads((BASE/path).read_text())
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def require(value,message):
    if not value: raise RuntimeError(message)
def main():
    for script in ('check_project','check_features','check_parallax'):
        subprocess.run([sys.executable,'tests/'+script+'.py'],cwd=ROOT,check=True)
    current=fingerprint(ROOT)['sha256']
    for folder in ('headless','gpu','standalone/headless','standalone/gpu'):
        report=read(folder+'/features-report.json')
        require(report['passed'] and report['runtime_fingerprint']==current,'Stale native evidence: '+folder)
        for name,digest in report.get('capture_sha256',{}).items():
            require(sha(BASE/folder/name)==digest,'Modified capture: '+name)
    for folder in ('gpu','standalone/gpu'):
        image=read(folder+'/image-report.json')
        require(image['passed'] and image['runtime_fingerprint']==current,'Invalid image evidence: '+folder)
    performance=read('gpu/features-report.json')['performance']
    require(set(performance)=={'natural','soft','enhanced','maximum'},'Missing benchmark cases')
    for key,data in performance.items():
        require(data['duration_s']>=30 and data['target_60fps_p95_met'],'Failed performance: '+key)
    rebuilt=read('reproduction-report.json')
    require(rebuilt['passed'] and rebuilt['real_gpu_checked'] and rebuilt['origin_runtime_fingerprint']==current,'Fresh GPU rebuild required')
    for name in ('settings/report.json','standalone/settings/report.json'):
        data=read(name);require(data['passed'] and data['runtime_fingerprint']==current,'Preferences restart gate failed')
    binary=BASE/'linux/waystation.x86_64';standalone=read('standalone/report.json')
    require(standalone['passed'] and standalone['runtime_fingerprint']==current and standalone['binary_sha256']==sha(binary),'Stale executable')
    movie=BASE/'media/comparison.mp4';video=read('media/video-report.json')
    require(video['passed'] and video['runtime_fingerprint']==current and video['sha256']==sha(movie),'Stale video')
    out=ROOT/'build/delivery/p8';out.mkdir(parents=True,exist_ok=True)
    files=source_files(ROOT)
    require(not any(p.suffix.lower() in ('.ttf','.otf','.woff','.woff2') for p in files),'Unexpected standalone font file')
    manifest={p.relative_to(ROOT).as_posix():sha(p) for p in files}
    source_zip=out/'hd-2d-godot-p8-source.zip'
    with zipfile.ZipFile(source_zip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for path in files: archive.write(path,'hd-2d-godot/'+path.relative_to(ROOT).as_posix())
        archive.writestr('hd-2d-godot/SOURCE_SHA256.json',json.dumps(manifest,indent=2)+'\n')
    linux_zip=out/'hd-2d-waystation-p8-linux-x86_64.zip'
    with zipfile.ZipFile(linux_zip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        archive.write(binary,'hd-2d-waystation/waystation.x86_64')
        archive.write(ROOT/'docs/delivery/runtime-README.txt','hd-2d-waystation/README.txt')
        archive.write(ROOT/'NOTICE.md','hd-2d-waystation/NOTICE.md')
        for path in (ROOT/'licenses').glob('*.txt'): archive.write(path,'hd-2d-waystation/licenses/'+path.name)
    shutil.copy2(movie,out/'parallax-comparison.mp4')
    artifacts=[source_zip,linux_zip,out/'parallax-comparison.mp4']
    for path in (source_zip,linux_zip):
        with zipfile.ZipFile(path) as archive: require(archive.testzip() is None,'Corrupt ZIP')
    (out/'SHA256SUMS').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in artifacts))
    summary={'passed':True,'runtime_fingerprint':current,'source_file_count':len(files),
             'binary_sha256':sha(binary),'artifacts':[{'name':p.name,'bytes':p.stat().st_size,'sha256':sha(p)} for p in artifacts]}
    (out/'delivery-report.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2),flush=True)
if __name__=='__main__': main()
