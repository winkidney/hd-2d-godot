"""Independent frontal reconstruction validation and deliverable tools."""
from pathlib import Path
import sys, json, shutil, subprocess, tempfile, zipfile, re, hashlib
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/p9'))
import experiments as previous
OUT=ROOT/'build/p9-frontal'
previous.OUT=OUT
from experiments import run,engine,save,sha,source_files,fingerprint

def native(label,gpu=False,quick=True,binary=None,extra=()):
    folder=OUT/label;folder.mkdir(parents=True,exist_ok=True)
    before=fingerprint(ROOT)['sha256']
    args=[binary] if binary else [engine(),'--path',ROOT,'res://scenes/frontal_canal.tscn']
    args+=['--resolution','1920x1080'] if gpu else ['--headless','--fixed-fps','60']
    args+=['--','--frontal-test','--ignore-user-settings','--frontal-output='+str(folder)]
    args+=['--frontal-quick'] if quick else ['--frontal-benchmark']
    args+=list(extra)
    run(args,label,gpu,cwd=binary.parent if binary else ROOT)
    data=json.loads((folder/'report.json').read_text())
    assert data['passed'],label
    assert before==fingerprint(ROOT)['sha256'],'Source changed during validation'
    data['runtime_fingerprint']=before
    data['capture_sha256']={p.name:sha(p) for p in folder.rglob('*.png')}
    save(folder/'report.json',data)
    return data

def copy_project(label):
    staging=OUT/'staging';staging.mkdir(parents=True,exist_ok=True)
    stage=Path(tempfile.mkdtemp(prefix=label+'-',dir=staging))/'project';stage.mkdir()
    for p in source_files(ROOT):
        if 'research' in p.parts:continue
        target=stage/p.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    return stage

def record():
    stage=copy_project('record')
    config=stage/'project.godot'
    config.write_text(config.read_text().replace('window/size/window_width_override=1280','window/size/window_width_override=1920').replace('window/size/window_height_override=720','window/size/window_height_override=1080'))
    run([engine(),'--headless','--path',stage,'--editor','--quit'],'record-import')
    folder=OUT/'media';folder.mkdir(exist_ok=True)
    for v in 'FWO':
        evidence=folder/v;evidence.mkdir(exist_ok=True)
        avi=folder/(v+'.avi');mp4=folder/(v+'.mp4')
        run([engine(),'--path',stage,'res://scenes/frontal_canal.tscn','--write-movie',avi,'--fixed-fps','30','--','--frontal-test','--frontal-record='+v,'--frontal-variant='+v,'--frontal-output='+str(evidence)],'record-'+v,True)
        assert json.loads((evidence/'report.json').read_text())['passed']
        run(['ffmpeg','-y','-i',avi,'-vf',"drawtext=text='P9R2 "+v+"':x=32:y=26:fontsize=40:fontcolor=white:box=1:boxcolor=black@0.65",'-c:v','libx264','-preset','fast','-crf','21','-pix_fmt','yuv420p','-an',mp4],'encode-'+v)
    command=['ffmpeg','-y']
    for v in 'FWO':command+=['-i',folder/(v+'.mp4')]
    command+=['-filter_complex','[0:v]scale=640:360[a];[1:v]scale=640:360[b];[2:v]scale=640:360[c];[a][b][c]hstack=inputs=3:shortest=1[v]','-map','[v]','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-an',folder/'three-way.mp4']
    run(command,'encode-three-way')
    verify_videos()

def verify_videos():
    folder=OUT/'media';results={}
    for v in ['F','W','O','three-way']:
        path=folder/(v+'.mp4')
        info=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height,r_frame_rate,nb_frames:format=duration','-of','json',str(path)],text=True))
        s=info['streams'][0]
        assert s['width']==1920 and s['height']==(360 if v=='three-way' else 1080) and s['r_frame_rate']=='30/1'
        results[v]={'metadata':info,'sha256':sha(path)}
    assert len({r['metadata']['streams'][0]['nb_frames'] for r in results.values()})==1
    routes={v:json.loads((folder/v/('route-'+v+'.json')).read_text()) for v in 'FWO'}
    assert all(r['passed'] and r['recoveries']==0 for r in routes.values())
    assert len({len(r['trajectory']) for r in routes.values()})==1
    assert len({r['frames'] for r in routes.values()})==1
    max_delta=max(abs(x-y) for v in 'FWO' for a,b in zip(routes['F']['trajectory'],routes[v]['trajectory']) for x,y in zip(a['position'],b['position']))
    assert max_delta<.0001,'Different physical trajectories'
    assert all(r['period_changes']==routes['F']['period_changes'] for r in routes.values())
    save(folder/'video-report.json',{'passed':True,'files':results,'maximum_route_coordinate_difference_m':max_delta,'motion_physics_frames':{v:r['frames'] for v,r in routes.items()},'time_schedule':routes['F']['period_changes'],'speed_m_s':3.2,'scope':'Identical physical route samples, frame counts, speeds and time schedules; no per-stream retiming.'})

def export():
    stage=copy_project('export')
    config=stage/'project.godot';config.write_text(config.read_text().replace('run/main_scene="res://scenes/waystation.tscn"','run/main_scene="res://scenes/frontal_canal.tscn"'))
    shutil.copytree(ROOT/'build/templates',stage/'build/templates')
    run([engine(),'--headless','--path',stage,'--editor','--quit'],'export-import')
    folder=OUT/'linux';folder.mkdir(exist_ok=True)
    binary=folder/'frontal-canal.x86_64'
    run([engine(),'--headless','--path',stage,'--export-release','Linux',binary],'export')
    isolated=OUT/'standalone';isolated.mkdir(exist_ok=True);target=isolated/binary.name;shutil.copy2(binary,target)
    native('standalone-headless',binary=target)
    native('standalone-gpu',True,True,binary=target,extra=['--frontal-no-route'])
    save(OUT/'export-report.json',{'passed':True,'binary_sha256':sha(binary),'isolated_sha256':sha(target)})

def rebuild():
    stage=copy_project('rebuild')
    # New world is rebuilt from its recipe in a copy with no Godot import cache.
    world=stage/'scenes/frontal_canal_world.tscn'
    run([engine(),'--headless','--path',stage,'--editor','--quit'],'rebuild-import')
    if world.exists():world.unlink()
    run([engine(),'--headless','--path',stage,'--script','res://tools/p9frontal/build_world.gd'],'rebuild-world')
    run([sys.executable,'tests/p9/check_assets.py'],'rebuild-asset-provenance',cwd=stage)
    run([sys.executable,'tools/p9frontal/run.py','headless'],'rebuild-headless',cwd=stage)
    run([sys.executable,'tools/p9frontal/run.py','quick','--frontal-no-route'],'rebuild-gpu',True,cwd=stage)
    for name in ['headless','quick']:shutil.copytree(stage/'build/p9-frontal'/name,OUT/('rebuild-'+name),dirs_exist_ok=True)
    save(OUT/'rebuild-report.json',{'passed':True,'world_sha256':sha(world),'original_world_sha256':sha(ROOT/'scenes/frontal_canal_world.tscn'),'scope':'New world regenerated; original P9 assets reused with source hashes verified; fresh Godot import cache. Original image/Blender pipeline was independently rebuilt at checkpoint 171e632.'})
    verify_rebuild()

def verify_rebuild():
    copies=list((OUT/'staging').glob('rebuild-*/project/scenes/frontal_canal_world.tscn'))
    world=max(copies,key=lambda p:p.stat().st_mtime)
    original=ROOT/'scenes/frontal_canal_world.tscn'
    normalize=lambda p:re.sub(r' unique_id=\d+','',p.read_text())
    left,right=normalize(original),normalize(world)
    assert left==right,'Rebuilt scene differs beyond generated node IDs'
    data=json.loads((OUT/'rebuild-report.json').read_text())
    assert data['world_sha256']==sha(world) and data['original_world_sha256']==sha(original)
    data.update({'scene_identical_except_generated_node_unique_ids':True,'canonical_world_sha256':hashlib.sha256(left.encode()).hexdigest(),'byte_identical':sha(original)==sha(world),'difference_note':'Godot assigns fresh serialized node unique_id values. Every other byte of the regenerated scene is identical.'})
    save(OUT/'rebuild-report.json',data)

if __name__=='__main__':
    action=sys.argv[1]
    if action=='import':run([engine(),'--headless','--path',ROOT,'--editor','--quit'],'import')
    elif action=='bake':run([engine(),'--headless','--path',ROOT,'--script','res://tools/p9frontal/build_world.gd'],'bake')
    elif action=='headless':native('headless')
    elif action in ['quick','gpu']:native(action,True,action=='quick',extra=sys.argv[2:])
    elif action=='record':record()
    elif action=='verify-videos':verify_videos()
    elif action=='export':export()
    elif action=='rebuild':rebuild()
    elif action=='verify-rebuild':verify_rebuild()
    else:raise SystemExit('Unknown action '+action)
