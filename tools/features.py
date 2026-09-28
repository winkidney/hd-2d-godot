"""P6/P7 validation and recording; no installation or system configuration."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import sys
from project import ROOT, engine, desktop_environment, execute
from feature_fingerprint import fingerprint

def native(mode: str, out: Path, quick: bool=False, binary: Path|None=None) -> dict:
    out.mkdir(parents=True,exist_ok=True)
    report_path=out/'features-report.json'
    if report_path.exists(): report_path.unlink()
    command=[str(binary)] if binary else [engine(),'--path',str(ROOT)]
    command += ['--headless'] if mode=='headless' else ['--resolution','1920x1080']
    command += ['--fixed-fps','60','--','--p6p7-test','--capture-dir='+str(out)]
    if quick: command.append('--quick')
    before=fingerprint(ROOT)
    env=desktop_environment() if mode=='gpu' else os.environ.copy()
    with (out/'native.log').open('w') as log:
        result=subprocess.run(command,cwd=binary.parent if binary else ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=600)
    text=(out/'native.log').read_text()
    if result.returncode or 'ERROR:' in text or 'ASSERT_FAIL' in text or not report_path.exists():
        raise RuntimeError('Native validation failed: '+str(out/'native.log')+'\n'+text[-4000:])
    if before!=fingerprint(ROOT):
        raise RuntimeError('Runtime source changed during validation; rerun after import.')
    report=json.loads(report_path.read_text())
    if not report['passed']: raise RuntimeError('Failed feature assertions.')
    report['runtime_fingerprint']=before['sha256']
    report['simulation_fixed_fps']=60
    report_path.write_text(json.dumps(report)+'\n')
    (out/'runtime-files.json').write_text(json.dumps(before,indent=2)+'\n')
    if mode=='gpu':
        subprocess.run([sys.executable,str(ROOT/'tests/check_feature_images.py'),str(out)],check=True,cwd=ROOT)
    print('FEATURE_RUN_PASS',mode,len(report['checks']),out.relative_to(ROOT),flush=True)
    return report

def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['test','visual','quick-visual','record'])
    action=parser.parse_args().command
    base=ROOT/'build/p6p7'
    if action in ('test','visual','quick-visual'):
        execute([engine(),'--headless','--path',str(ROOT),'--editor','--quit'],'features-import')
        if action=='test':
            subprocess.run([sys.executable,'tests/check_features.py'],cwd=ROOT,check=True)
            native('headless',base/'headless',True)
        else:
            native('gpu',base/('gpu-quick' if action=='quick-visual' else 'gpu'),action=='quick-visual')
    else:
        folder=base/'media';folder.mkdir(parents=True,exist_ok=True)
        execute([engine(),'--path',str(ROOT),'--resolution','1920x1080','--write-movie',str(folder/'walkthrough.avi'),'--fixed-fps','30','--quit-after','720','--','--walk-recording'],'p6p7-record',True,600)
        subprocess.run(['ffmpeg','-y','-i',str(folder/'walkthrough.avi'),'-an','-c:v','libx264','-crf','20','-pix_fmt','yuv420p',str(folder/'walkthrough.mp4')],cwd=ROOT,check=True,capture_output=True)
        import hashlib
        movie=folder/'walkthrough.mp4'
        probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,r_frame_rate,nb_frames:format=duration,size','-of','json',str(movie)]))
        video={'runtime_fingerprint':fingerprint(ROOT)['sha256'],'sha256':hashlib.sha256(movie.read_bytes()).hexdigest(),'probe':probe,'passed':float(probe['format']['duration'])>=24 and int(probe['streams'][0]['nb_frames'])==720}
        (folder/'video-report.json').write_text(json.dumps(video,indent=2)+chr(10))
        if not video['passed']: raise RuntimeError('Walkthrough video contract failed.')


if __name__=='__main__':
    main()
