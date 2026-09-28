"""P9 repeatable acceptance and isolated Linux export. No dependency installation."""
from pathlib import Path
import sys, os, subprocess, json, hashlib, shutil, tempfile, time
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
from project import engine, desktop_environment
from feature_fingerprint import fingerprint
OUT=ROOT/'build/p9'
def run(args, name, gpu=False, cwd=None, timeout=900):
    folder=OUT/'logs'; folder.mkdir(parents=True, exist_ok=True)
    env=desktop_environment() if gpu else os.environ.copy()
    env['XDG_DATA_HOME']=str(OUT/'isolated-user-data')
    prior=folder/(name+'.log')
    if prior.exists(): shutil.copy2(prior,folder/(name+'.'+str(time.time_ns())+'.previous.log'))
    with (folder/(name+'.log')).open('w') as stream:
        p=subprocess.run(args,cwd=cwd or ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
    text=(folder/(name+'.log')).read_text()
    if p.returncode or 'ERROR:' in text or 'P9_FAIL' in text or any(line.startswith('FAIL ') for line in text.splitlines()):
        raise RuntimeError(name+' failed: '+text[-3500:])
    print('PASS',name,flush=True)
def native(folder, gpu=False, binary=None, quick=False):
    folder.mkdir(parents=True,exist_ok=True)
    before=fingerprint(ROOT)
    args=[str(binary)] if binary else [engine(),'--path',str(ROOT)]
    if not binary: args+=['res://scenes/reference_scene.tscn']
    args+=['--resolution','1920x1080'] if gpu else ['--headless']
    args+=['--','--p9-test','--ignore-user-settings','--capture-dir='+str(folder)]
    if quick: args+=['--quick']
    run(args,folder.name,gpu,cwd=binary.parent if binary else ROOT)
    report=json.loads((folder/'report.json').read_text())
    assert report['passed'] and report['real_gpu']==gpu
    if gpu: images(folder)
    assert before==fingerprint(ROOT), 'Runtime changed during validation'
    report['runtime_fingerprint']=before['sha256']
    report['capture_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.glob('*.png')}
    if binary: report['binary_sha256']=hashlib.sha256(binary.read_bytes()).hexdigest()
    (folder/'report.json').write_text(json.dumps(report,indent=2)+'\n')
def images(folder):
    # Shared fixture validator expects legacy location labels. Adapt in an isolated directory.
    with tempfile.TemporaryDirectory(prefix='p9-image-check-') as tmp:
        p=Path(tmp)
        shutil.copy2(folder/'report.json',p/'features-report.json')
        for source in folder.glob('*.png'):
            name=source.name.replace('-reference-','-center-').replace('-west-','-left-').replace('-east-','-right-')
            shutil.copy2(source,p/name)
        run([sys.executable,str(ROOT/'tests/check_feature_images.py'),str(p)],folder.name+'-dof-images')
        shutil.copy2(p/'image-report.json',folder/'dof-image-report.json')
    run([sys.executable,str(ROOT/'tests/check_parallax_images.py'),str(folder)],folder.name+'-parallax-images')
def export():
    folder=OUT/'linux';folder.mkdir(parents=True,exist_ok=True)
    binary=folder/'lantern-canal.x86_64'
    # Override only the independent export's main scene using a clean staging project.
    stage=copy_project('export')
    config=stage/'project.godot'
    config.write_text(config.read_text().replace('run/main_scene="res://scenes/waystation.tscn"','run/main_scene="res://scenes/reference_scene.tscn"'))
    shutil.copytree(ROOT/'build/templates',stage/'build/templates')
    run([engine(),'--headless','--path',str(stage),'--editor','--quit'],'export-import')
    run([engine(),'--headless','--path',str(stage),'--export-release','Linux',str(binary)],'export-linux')
    isolated=OUT/'standalone';isolated.mkdir(exist_ok=True)
    shutil.copy2(binary,isolated/binary.name)
    native(OUT/'standalone-headless',binary=isolated/binary.name)
    native(OUT/'standalone-gpu',gpu=True,binary=isolated/binary.name,quick=True)
    (folder/'SHA256SUMS').write_text(hashlib.sha256(binary.read_bytes()).hexdigest()+'  '+binary.name+'\n')
def copy_project(label):
    target=Path(tempfile.mkdtemp(prefix='p9-'+label+'-'))/'project'
    shutil.copytree(ROOT,target,ignore=shutil.ignore_patterns('.git','.godot','build','__pycache__','*.blend1'))
    return target
def rebuild():
    stage=copy_project('rebuild')
    run([sys.executable,'tools/p9/process_assets.py'],'rebuild-pixels',cwd=stage)
    original=json.loads((ROOT/'art_source/reference-scene/manifests/processed.json').read_text())
    rebuilt=json.loads((stage/'art_source/reference-scene/manifests/processed.json').read_text())
    assert original==rebuilt, 'Pixel rebuild differs'
    run(['blender','--background','--factory-startup','--disable-autoexec','--python','tools/p9/build_models.py'],'rebuild-blender',cwd=stage)
    run([engine(),'--headless','--path',str(stage),'--editor','--quit'],'rebuild-import')
    run([engine(),'--headless','--path',str(stage),'--script','res://tools/p9/bake.gd'],'rebuild-bake')
    run([sys.executable,'tests/p9/check_assets.py'],'rebuild-assets',cwd=stage)
    run([sys.executable,'tools/p9/accept.py','quick'],'rebuild-gpu',True,cwd=stage)
    shutil.copytree(stage/'build/p9/gpu',OUT/'rebuild-gpu',dirs_exist_ok=True)
    (OUT/'rebuild-report.json').write_text(json.dumps({'passed':True,'pixels_identical':True,'models_regenerated':True,'gpu_report':'rebuild-gpu/report.json','scope':'Retained normalized input only; original ImageGen source archive remains incomplete.'},indent=2)+'\n')
if __name__=='__main__':
    action=sys.argv[1]
    if action in ('gpu','quick'): native(OUT/'gpu',True,quick=action=='quick')
    elif action=='headless': native(OUT/'headless-current')
    elif action=='images': images(Path(sys.argv[2]))
    elif action=='export': export()
    elif action=='rebuild': rebuild()
    elif action=='assets': run([sys.executable,'tests/p9/check_assets.py'],'assets')
