"""Reproduce P9 four-method comparisons with existing local tools only."""
from pathlib import Path
import sys, os, subprocess, json, hashlib, shutil, tempfile, time, zipfile
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
from project import engine, desktop_environment
from feature_fingerprint import fingerprint
from source_files import source_files
OUT = ROOT/'build/p9-experiments'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p, data):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2)+'\n')

def run(args, label, gpu=False, cwd=ROOT, timeout=1800):
    logs=OUT/'logs'; logs.mkdir(parents=True,exist_ok=True)
    path=logs/(label+'.log')
    if path.exists(): shutil.copy2(path,logs/(label+'.'+str(time.time_ns())+'.previous.log'))
    env=desktop_environment() if gpu else os.environ.copy()
    env['XDG_DATA_HOME']=str(OUT/'isolated-user-data')
    print('RUN',label,flush=True)
    with path.open('w') as stream:
        result=subprocess.run([str(a) for a in args],cwd=cwd,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
    text=path.read_text()
    if result.returncode or 'ERROR:' in text or 'P9X_FAIL' in text or any(l.startswith('FAIL ') for l in text.splitlines()):
        raise RuntimeError(label+' failed: '+text[-7000:])
    print('PASS',label,flush=True)

def import_project():
    run([engine(),'--headless','--path',ROOT,'--editor','--quit'],'import')
    run([engine(),'--headless','--path',ROOT,'--script','res://tools/p9/bake.gd'],'bake')

def atlas():
    run([engine(),'--path',ROOT,'--script','res://tools/p9/capture_impostors.gd','--','--p9-impostors'],'atlas',True)
    run([engine(),'--headless','--path',ROOT,'--editor','--quit'],'atlas-import')

def native(label, gpu=False, quick=False, binary=None, extra=()):
    folder=OUT/label; folder.mkdir(parents=True,exist_ok=True)
    before=fingerprint(ROOT)
    args=[binary] if binary else [engine(),'--path',ROOT,'res://scenes/reference_scene.tscn']
    args+=['--resolution','1920x1080'] if gpu else ['--headless','--fixed-fps','60']
    args+=['--','--p9-experiment-test','--ignore-user-settings','--capture-dir='+str(folder)]
    if quick: args+=['--quick']
    args+=list(extra)
    run(args,label,gpu,cwd=binary.parent if binary else ROOT)
    data=json.loads((folder/'report.json').read_text())
    assert data['passed'] and data['real_gpu']==gpu
    assert before==fingerprint(ROOT),'Source changed during validation'
    data['runtime_fingerprint']=before['sha256']
    data['capture_sha256']={str(p.relative_to(folder)):sha(p) for p in folder.rglob('*.png')}
    if binary: data['binary_sha256']=sha(binary)
    save(folder/'report.json',data)
    if gpu and '--no-fixtures' not in extra:
        run([sys.executable,ROOT/'tests/p9/check_experiment_images.py',folder],label+'-pixels')
    return data

def copy_project(label):
    # Use project storage, not the small RAM-backed /tmp, for full original art.
    stage=Path(tempfile.mkdtemp(prefix=label+'-',dir=OUT/'staging'))/'project'
    stage.mkdir(parents=True)
    for p in source_files(ROOT):
        target=stage/p.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    return stage

def export():
    (OUT/'staging').mkdir(parents=True,exist_ok=True)
    stage=copy_project('export')
    config=stage/'project.godot'
    config.write_text(config.read_text().replace('run/main_scene="res://scenes/waystation.tscn"','run/main_scene="res://scenes/reference_scene.tscn"'))
    shutil.copytree(ROOT/'build/templates',stage/'build/templates')
    run([engine(),'--headless','--path',stage,'--editor','--quit'],'export-import')
    folder=OUT/'linux';folder.mkdir(exist_ok=True)
    binary=folder/'lantern-canal-four-experiments.x86_64'
    run([engine(),'--headless','--path',stage,'--export-release','Linux',binary],'export')
    isolated=OUT/'standalone';isolated.mkdir(exist_ok=True)
    target=isolated/binary.name;shutil.copy2(binary,target)
    native('standalone-headless',binary=target)
    native('standalone-gpu',True,True,binary=target,extra=['--no-route'])
    save(OUT/'export-report.json',{'passed':True,'binary_sha256':sha(binary),'standalone_sha256':sha(target),'isolated':True})

def rebuild():
    (OUT/'staging').mkdir(parents=True,exist_ok=True)
    stage=copy_project('rebuild')
    # Remove only generated runtime assets in the isolated copy; originals remain.
    for folder in ('assets/reference-scene/textures','assets/reference-scene/sprites','assets/reference-scene/models','assets/reference-scene/impostors','art_source/reference-scene/blender'):
        target=stage/folder
        if target.exists(): shutil.rmtree(target)
    run([sys.executable,'tools/p9/process_assets.py'],'rebuild-pixels',cwd=stage)
    assert sha(stage/'art_source/reference-scene/manifests/processed.json')==sha(ROOT/'art_source/reference-scene/manifests/processed.json')
    run(['blender','--background','--factory-startup','--disable-autoexec','--python','tools/p9/build_models.py'],'rebuild-models',cwd=stage)
    run([engine(),'--headless','--path',stage,'--editor','--quit'],'rebuild-import')
    run([engine(),'--headless','--path',stage,'--script','res://tools/p9/bake.gd'],'rebuild-bake')
    run([sys.executable,'tools/p9/experiments.py','atlas'],'rebuild-atlas',True,cwd=stage)
    run([sys.executable,'tests/p9/check_assets.py'],'rebuild-assets',cwd=stage)
    run([sys.executable,'tools/p9/experiments.py','headless'],'rebuild-headless',cwd=stage)
    run([sys.executable,'tools/p9/experiments.py','quick','--no-route'],'rebuild-gpu',True,cwd=stage)
    shutil.copytree(stage/'build/p9-experiments/quick',OUT/'rebuild-gpu',dirs_exist_ok=True)
    shutil.copytree(stage/'build/p9-experiments/headless',OUT/'rebuild-headless',dirs_exist_ok=True)
    from PIL import Image, ImageChops, ImageStat
    atlas_differences={}
    for period in ('day','dusk','night'):
        p=Path('assets/reference-scene/impostors')/('palazzo-'+period+'.png')
        left=Image.open(ROOT/p).convert('RGBA');right=Image.open(stage/p).convert('RGBA')
        delta=ImageChops.difference(left,right)
        atlas_differences[period]={'byte_identical':sha(ROOT/p)==sha(stage/p),'mean_absolute_rgba_error':ImageStat.Stat(delta).mean,'max_channel_error':max(x[1] for x in delta.getextrema())}
    save(OUT/'rebuild-report.json',{'passed':True,'pixel_outputs_identical':True,'models_regenerated_from_source':True,'gpu_atlas_regenerated':True,'atlas_differences':atlas_differences,'gpu_report':'rebuild-gpu/report.json','scope':'Clean isolated project; generated PNG/GLB/BLEND/atlases deleted before regeneration; no reused Godot import cache.'})

def record():
    (OUT/'staging').mkdir(parents=True,exist_ok=True)
    stage=copy_project('record')
    # MovieWriter uses the project window override, not --resolution, in 4.7.2.
    config=stage/'project.godot'
    config.write_text(config.read_text().replace('window/size/window_width_override=1280','window/size/window_width_override=1920').replace('window/size/window_height_override=720','window/size/window_height_override=1080'))
    run([engine(),'--headless','--path',stage,'--editor','--quit'],'record-import')
    folder=OUT/'media';folder.mkdir(parents=True,exist_ok=True)
    for variant in 'ABCD':
        avi=folder/(variant+'.avi');mp4=folder/(variant+'.mp4')
        evidence=folder/variant;evidence.mkdir(exist_ok=True)
        run([engine(),'--path',stage,'res://scenes/reference_scene.tscn','--resolution','1920x1080','--write-movie',avi,'--fixed-fps','30','--','--p9-experiment-test','--p9-experiment-record','--p9-experiment='+variant,'--capture-dir='+str(evidence)],'record-'+variant,True)
        assert json.loads((evidence/'report.json').read_text())['passed']
        run(['ffmpeg','-y','-i',avi,'-vf',"drawtext=text='P9 "+variant+"':x=32:y=26:fontsize=40:fontcolor=white:box=1:boxcolor=black@0.65",'-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-an',mp4],'encode-'+variant)
        # Keep original movie until delivery validation; no source evidence deletion.
    command=['ffmpeg','-y']
    for variant in 'ABCD': command+=['-i',folder/(variant+'.mp4')]
    command+=['-filter_complex','[0:v]scale=960:540[a];[1:v]scale=960:540[b];[2:v]scale=960:540[c];[3:v]scale=960:540[d];[a][b][c][d]xstack=inputs=4:layout=0_0|960_0|0_540|960_540:shortest=1[v]','-map','[v]','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-an',folder/'four-way.mp4']
    run(command,'encode-four-way')
    save(folder/'manifest.json',{'fps':30,'resolution':[1920,1080],'route':'tests/p9/experiment_route.gd','same_physics_speed':3.2,'time_schedule':'dusk through bridge and west/east; day from central stairs; night from dock','files':{p.name:sha(p) for p in folder.glob('*.mp4')}})
    validate_videos()

def validate_videos():
    folder=OUT/'media'
    metadata={}
    for name in ['A','B','C','D','four-way']:
        path=folder/(name+'.mp4')
        data=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,r_frame_rate,nb_frames:format=duration','-of','json',str(path)],text=True))
        stream=data['streams'][0]
        assert stream['width']==1920 and stream['height']==1080 and stream['r_frame_rate']=='30/1'
        metadata[name]={'metadata':data,'sha256':sha(path)}
    assert len({metadata[n]['metadata']['streams'][0]['nb_frames'] for n in metadata})==1,'Videos have different frame counts'
    routes={v:json.loads((folder/v/('route-'+v+'.json')).read_text()) for v in 'ABCD'}
    assert all(r['passed'] and r['recoveries']==0 for r in routes.values())
    trajectories={v:[x['position'] for x in r['trajectory']] for v,r in routes.items()}
    assert all(len(trajectories[v])==len(trajectories['A']) for v in 'ABCD')
    max_delta=max(abs(a-b) for v in 'ABCD' for p,q in zip(trajectories['A'],trajectories[v]) for a,b in zip(p,q))
    assert max_delta<.0001,'Physical routes differ'
    save(folder/'video-report.json',{'passed':True,'files':metadata,'maximum_route_coordinate_difference_m':max_delta,'motion_physics_frames':{v:r['frames'] for v,r in routes.items()},'scope':'Same initial spawn, real physical movement, identical speed, step times and time-of-day schedule. Quartet scaled and composited without per-stream retiming.'})

def package():
    run([sys.executable,ROOT/'tools/p9/report_experiments.py'],'review-report')
    folder=OUT/'delivery';folder.mkdir(exist_ok=True)
    reports={}
    for name in ('gpu','standalone-headless','standalone-gpu','rebuild-gpu'):
        data=json.loads((OUT/name/'report.json').read_text());assert data['passed'],name
        if name!='standalone-headless':
            assert json.loads((OUT/name/'experiment-image-report.json').read_text())['passed'],name+' pixel checks'
        reports[name]={'checks':len(data['checks']),'sha256':sha(OUT/name/'report.json')}
    gpu=json.loads((OUT/'gpu/report.json').read_text())
    assert gpu['runtime_fingerprint']==fingerprint(ROOT)['sha256'],'Stale GPU evidence'
    assert all(p['duration_s']>=30 for v in gpu['variants'].values() for p in v['performance'].values())
    assert json.loads((OUT/'rebuild-report.json').read_text())['passed']
    assert json.loads((OUT/'media/video-report.json').read_text())['passed']
    binary=OUT/'linux/lantern-canal-four-experiments.x86_64'
    exported=json.loads((OUT/'export-report.json').read_text())
    assert exported['passed'] and exported['binary_sha256']==sha(binary)==sha(OUT/'standalone'/binary.name)
    with zipfile.ZipFile(folder/'p9-four-experiments-linux.zip','w',zipfile.ZIP_DEFLATED) as z:
        z.write(binary,binary.name)
        z.write(ROOT/'NOTICE.md','NOTICE.md')
        z.writestr('README.txt','P9 four camera experiments. Run ./lantern-canal-four-experiments.x86_64\nC: A/B/C/D, reset and physical route. WASD/arrows: walk; E: interact; T: time; O: DOF; P: parallax; H: hide HUD. Click the toolbar for panels and confirmed Quit. F8 remains the editor Stop shortcut.\nAll four methods retained. D is a visual simulation, not volumetric geometry. Read comparison report for limitations.\n')
        for p in (ROOT/'licenses').rglob('*'):
            if p.is_file():z.write(p,p.relative_to(ROOT))
    with zipfile.ZipFile(folder/'p9-complete-project.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in source_files(ROOT):
            if 'research' not in p.parts:z.write(p,p.relative_to(ROOT))
    with zipfile.ZipFile(folder/'p9-evidence.zip','w',zipfile.ZIP_DEFLATED) as z:
        for name in ('gpu','headless','standalone-headless','standalone-gpu','rebuild-gpu','rebuild-headless','old-scene-regression','building-probe'):
            for p in (OUT/name).rglob('*'):
                if p.suffix=='.json' or (name in ('gpu','building-probe') and p.suffix=='.png'):z.write(p,p.relative_to(OUT))
        for p in OUT.glob('*.json'):z.write(p,p.name)
        for p in (OUT/'media').rglob('*.json'):z.write(p,p.relative_to(OUT))
    for p in (OUT/'media').glob('*.mp4'):shutil.copy2(p,folder/p.name)
    report_text=(ROOT/'docs/validation/p9-experiments/README.md').read_text()
    for source,target in {
        'docs/validation/p9-experiments/execution-log.md':'execution-log.md',
        'docs/validation/p9-experiments/source-audit.md':'source-audit.md',
        'docs/workflows/p9-four-experiments.md':'workflow.md',
        'docs/design/reference-experiments.md':'mechanism.md',
        'Plan/features/p9-four-experiments.md':'plan.md',
        'ADR/19-reference-camera-experiments.md':'decision.md',
    }.items():
        shutil.copy2(ROOT/source,folder/target)
    for old,new in [('../../workflows/p9-four-experiments.md','workflow.md'),('../../design/reference-experiments.md','mechanism.md'),('../../../Plan/features/p9-four-experiments.md','plan.md'),('../../../ADR/19-reference-camera-experiments.md','decision.md')]:report_text=report_text.replace(old,new)
    (folder/'comparison.md').write_text(report_text)
    for p in (ROOT/'docs/validation/p9-experiments').glob('*.png'):shutil.copy2(p,folder/p.name)
    for p in (OUT/'review').glob('*.png'):shutil.copy2(p,folder/p.name)
    save(folder/'delivery-report.json',{'status':'Implemented; all four retained; visual selection pending user review','reports':reports,'runtime_fingerprint':gpu['runtime_fingerprint'],'binary_sha256':sha(binary),'source_exclusion':'Original-game research screenshot excluded from distributable source; original user ImageGen PNGs included.'})
    for p in folder.glob('*.zip'):
        with zipfile.ZipFile(p) as z:assert z.testzip() is None
    (folder/'SHA256SUMS').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in sorted(folder.iterdir()) if p.name!='SHA256SUMS'))

if __name__=='__main__':
    action=sys.argv[1]
    if action=='import':import_project()
    elif action=='atlas':atlas()
    elif action=='headless':native('headless')
    elif action in ('gpu','quick'):native(action,True,action=='quick',extra=sys.argv[2:])
    elif action=='record':record()
    elif action=='verify-videos':validate_videos()
    elif action=='export':export()
    elif action=='rebuild':rebuild()
    elif action=='package':package()
    else:raise SystemExit('Unknown action '+action)
