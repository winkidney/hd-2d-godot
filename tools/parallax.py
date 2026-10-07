"""P8 acceptance, using isolated user-data and explicitly selected settings."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from project import ROOT, engine, desktop_environment, execute
from feature_fingerprint import fingerprint

OUT = ROOT/'build/p8'
SCENE = 'res://scenes/waystation.tscn'

def clean_errors(text: str) -> str:
    # Release stdout is buffered, so stderr can arrive outside the marker block.
    # Accept exactly one known negative-fixture message, only with its PASS evidence.
    expected = "ERROR: ConfigFile parse error at <string>:0: Unexpected EOF while parsing simple tag."
    if (text.count(expected) == 1 and text.count("EXPECTED_PREF_PARSE_BEGIN") == 1
            and text.count("EXPECTED_PREF_PARSE_END") == 1
            and "ASSERT_PASS malformed_config_rejected" in text):
        return text.replace(expected,"EXPECTED_MALFORMED_PREFERENCES_REJECTION",1)
    return text

def native(mode: str, folder: Path, quick=False, binary=None) -> dict:
    folder.mkdir(parents=True,exist_ok=True)
    report_path = folder/'features-report.json'
    report_path.unlink(missing_ok=True)
    before = fingerprint(ROOT)
    command = [str(binary)] if binary else [engine(),'--path',str(ROOT),SCENE]
    command += ['--headless'] if mode == 'headless' else ['--resolution','1920x1080']
    command += ['--fixed-fps','60','--','--p8-test','--ignore-user-settings','--capture-dir='+str(folder)]
    if quick: command.append('--quick')
    env = desktop_environment() if mode == 'gpu' else os.environ.copy()
    env['XDG_DATA_HOME'] = str(folder/'user-data')
    with (folder/'native.log').open('w') as log:
        process = subprocess.run(command,cwd=binary.parent if binary else ROOT,
            env=env,stdout=log,stderr=subprocess.STDOUT,timeout=900)
    text = (folder/'native.log').read_text()
    if process.returncode or 'ERROR:' in clean_errors(text) or 'ASSERT_FAIL' in text or not report_path.exists():
        raise RuntimeError('P8 native test failed: '+str(folder/'native.log')+'\n'+text[-5000:])
    if before != fingerprint(ROOT): raise RuntimeError('Runtime changed during validation.')
    report = json.loads(report_path.read_text())
    if not report['passed']: raise RuntimeError('Failed P8 report.')
    report['runtime_fingerprint'] = before['sha256']
    report['user_preferences'] = 'ignored; test storage isolated via XDG_DATA_HOME'
    report_path.write_text(json.dumps(report)+'\n')
    (folder/'runtime-files.json').write_text(json.dumps(before,indent=2)+'\n')
    if mode == 'gpu':
        subprocess.run([sys.executable,'tests/check_parallax_images.py',str(folder)],cwd=ROOT,check=True)
    images = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob('*.png')}
    report['capture_sha256'] = images
    report_path.write_text(json.dumps(report)+'\n')
    if mode == 'gpu':
        image_report = json.loads((folder/'image-report.json').read_text())
        image_report['runtime_fingerprint'] = before['sha256']
        image_report['capture_sha256'] = images
        (folder/'image-report.json').write_text(json.dumps(image_report,indent=2)+'\n')
    print('P8_NATIVE_PASS',mode,len(report['checks']),folder.relative_to(ROOT),flush=True)
    return report

def settings_processes(folder: Path, binary=None) -> dict:
    folder.mkdir(parents=True,exist_ok=True)
    env = os.environ.copy()
    env['XDG_DATA_HOME'] = str(folder/'user-data')
    reports = {}
    for mode in ('save','reload','ignore'):
        target = folder/mode
        command = [str(binary)] if binary else [engine(),'--path',str(ROOT),SCENE]
        command += ['--headless','--','--settings-probe','--capture-dir='+str(target)]
        if mode == 'save': command.append('--probe-save')
        if mode == 'ignore': command.append('--ignore-user-settings')
        process = subprocess.run(command,cwd=binary.parent if binary else ROOT,env=env,
                                 capture_output=True,text=True,timeout=60)
        text = process.stdout+process.stderr
        (folder/(mode+'.log')).write_text(text)
        if process.returncode or 'ERROR:' in text: raise RuntimeError(text)
        reports[mode] = json.loads((target/'probe-report.json').read_text())
    saved, loaded, ignored = [reports[key] for key in ('save','reload','ignore')]
    passed = (saved['passed'] and loaded['passed'] and loaded['load_attempted']
              and saved['snapshot'] == loaded['snapshot']
              and ignored['snapshot']['mode'] == 'natural' and not ignored['load_attempted'])
    result = {'passed':passed,'processes':reports,'runtime_fingerprint':fingerprint(ROOT)['sha256']}
    (folder/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    if not passed: raise RuntimeError('Cross-process preferences test failed.')
    print('P8_SETTINGS_RESTART_PASS',flush=True)
    return result

def export_binary() -> None:
    execute([engine(),'--headless','--path',str(ROOT),'--editor','--quit'],'p8-export-import')
    before = fingerprint(ROOT)['sha256']
    destination = OUT/'linux'; destination.mkdir(parents=True,exist_ok=True)
    target = destination/'waystation.x86_64'
    execute([engine(),'--headless','--path',str(ROOT),'--export-release','Linux',str(target)],'p8-export',timeout=300)
    if before != fingerprint(ROOT)['sha256']: raise RuntimeError('Import changed runtime during export; revalidate.')
    manifest = {'passed':True,'runtime_fingerprint':before,'binary_sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    (OUT/'export-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')

def verify_binary() -> None:
    import tempfile
    target = OUT/'linux/waystation.x86_64'
    manifest = json.loads((OUT/'export-manifest.json').read_text())
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest != manifest['binary_sha256'] or fingerprint(ROOT)['sha256'] != manifest['runtime_fingerprint']:
        raise RuntimeError('Export is stale; run make export.')
    base = OUT/'standalone'; base.mkdir(parents=True,exist_ok=True)
    isolated = Path(tempfile.mkdtemp(prefix='only-binary-',dir=base))
    copy = isolated/target.name; shutil.copy2(target,copy); copy.chmod(0o755)
    runs = {mode:native(mode,base/mode,True,copy) for mode in ('headless','gpu')}
    persistence = settings_processes(base/'settings',copy)
    summary = dict(manifest,runs={k:{'passed':v['passed'],'checks':len(v['checks'])} for k,v in runs.items()},settings_restart_passed=persistence['passed'])
    summary['scope'] = 'Embedded-PCK executable alone; no project assets copied; isolated preferences.'
    (base/'report.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('P8_STANDALONE_PASS',digest,flush=True)

def record_video() -> None:
    folder = OUT/'media'; folder.mkdir(parents=True,exist_ok=True)
    before = fingerprint(ROOT)['sha256']
    avi, movie = folder/'comparison.avi', folder/'comparison.mp4'
    execute([engine(),'--path',str(ROOT),SCENE,'--resolution','1920x1080','--write-movie',str(avi),
             '--fixed-fps','30','--quit-after','1080','--','--p8-recording','--ignore-user-settings'],
             'p8-record',True,600)
    subprocess.run(['ffmpeg','-y','-i',str(avi),'-an','-c:v','libx264','-crf','20',
                    '-pix_fmt','yuv420p',str(movie)],cwd=ROOT,check=True,capture_output=True)
    data = json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0',
        '-show_entries','stream=width,height,r_frame_rate,nb_frames:format=duration','-of','json',str(movie)],text=True))
    stream = data['streams'][0]
    passed = (abs(float(data['format']['duration'])-36.0)<0.1 and stream['r_frame_rate']=='30/1'
              and before==fingerprint(ROOT)['sha256'])
    report = {'passed':passed,'runtime_fingerprint':before,'metadata':data,
              'sha256':hashlib.sha256(movie.read_bytes()).hexdigest(),
              'scope':'Three matched 12s one-way walks; soft/natural/enhanced, frozen wind, explicit cuts between passes.'}
    (folder/'video-report.json').write_text(json.dumps(report,indent=2)+'\n')
    if not passed: raise RuntimeError('Video metadata or freshness failed.')
    print('P8_VIDEO_PASS',stream,flush=True)

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['test','quick-visual','visual','export','verify','record'])
    action = parser.parse_args().command
    OUT.mkdir(parents=True,exist_ok=True)
    if action in ('test','quick-visual','visual'):
        execute([engine(),'--headless','--path',str(ROOT),'--editor','--quit'],'p8-import')
    if action == 'test':
        for name in ('check_project.py','check_features.py','check_parallax.py'):
            subprocess.run([sys.executable,'tests/'+name],cwd=ROOT,check=True)
        native('headless',OUT/'headless',True)
        settings_processes(OUT/'settings')
    elif action in ('quick-visual','visual'):
        native('gpu',OUT/('gpu-quick' if action=='quick-visual' else 'gpu'),action=='quick-visual')
    elif action == 'export': export_binary()
    elif action == 'verify': verify_binary()
    elif action == 'record': record_video()

if __name__ == '__main__':
    try: main()
    except (RuntimeError,OSError,subprocess.SubprocessError,KeyError,ValueError) as exc:
        print(str(exc),file=sys.stderr)
        raise SystemExit(1)
