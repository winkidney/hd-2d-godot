"""Archive R5 raw evidence and independently recompute its performance summary."""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import statistics
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from feature_fingerprint import fingerprint
from archive_horizontal import stages
from verify_profile_archive import stats
BUILD=ROOT/'build/ancient-canal/layout-r5-20261008'
OUT=ROOT/'docs/ancient-canal/layout-r5-20261008'

def sha(data):return hashlib.sha256(data).hexdigest()
def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')

def chunk_record(record, content):
    """Keep large original media byte-identical below the remote blob limit."""
    assert record['encoding']=='identity'
    chunks=[]
    for index,start in enumerate(range(0,len(content),50*1024**2),1):
        data=content[start:start+50*1024**2]
        name=record['path']+'.part-%03d'%index
        path=OUT/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
        chunks.append(dict(path=name,bytes=len(data),sha256=sha(data)))
    record.update(encoding='chunked',chunks=chunks)
    return record

def read_record(record):
    if record['encoding']=='chunked':
        contents=[]
        for chunk in record['chunks']:
            path=(OUT/chunk['path']).resolve();assert path.is_relative_to(OUT.resolve())
            data=path.read_bytes();assert len(data)==chunk['bytes'] and sha(data)==chunk['sha256']
            contents.append(data)
        return b''.join(contents)
    path=(OUT/record['path']).resolve();assert path.is_relative_to(OUT.resolve())
    return path.read_bytes()

def archive():
    assert not (OUT/'archive-manifest.json').exists(),'Archive already exists'
    current=fingerprint(ROOT);records=[]
    def add(source,target,compress=False):
        content=source.read_bytes();stored=gzip.compress(content,mtime=0) if compress else content
        record=dict(source=source.relative_to(ROOT).as_posix(),path=target,encoding='gzip' if compress else 'identity',original_sha256=sha(content),stored_sha256=sha(stored),original_bytes=len(content),stored_bytes=len(stored))
        if len(stored)>50*1024**2 and not compress:chunk_record(record,stored)
        else:
            path=OUT/target;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(stored)
        records.append(record)
    for name in ['final-validation-v2','camera-validation-v2','input-regression-v2','make-test-final']:
        for source in sorted((BUILD/name).rglob('*.json')):
            add(source,'validation/'+name+'/'+source.relative_to(BUILD/name).as_posix())
    add(BUILD/'source-audit.json','validation/source-audit.json')
    for source in sorted((BUILD/'measurements').rglob('*')):
        if source.is_file() and source.suffix in ['.json','.gd']:
            relative=source.relative_to(BUILD/'measurements').as_posix()
            compressed=source.name.endswith('-samples.json') or source.suffix=='.gd'
            target='measurements/'+relative+('.txt.gz' if source.suffix=='.gd' else '.gz' if compressed else '')
            add(source,target,compressed)
    render=BUILD/'render-v2';capture=json.loads((render/'horizontal-capture.json').read_text())
    assert capture['runtime_fingerprint']==current['sha256'] and capture['passed']
    for shot in capture['screenshots']:
        source=render/Path(shot['path']).name
        assert sha(source.read_bytes())==shot['sha256']
        add(source,'render/'+source.name)
    for source in sorted(render.glob('*.json')):add(source,'render/'+source.name)
    for name in ['route.mp4','night.mp4','route-contact.png','night-contact.png','npc-contact.png']:
        add(render/name,'render/'+name)
    for source in sorted((BUILD/'construction-views').glob('*')):
        if source.suffix in ['.png','.json']:add(source,'construction-views/'+source.name)
    for name in ['resources/ancient-canal/layout.json','scripts/ancient_canal/world.gd','scripts/ancient_canal/background.gd','scripts/ancient_canal/scene.gd','tests/ancient_canal/blueprint_layout.gd',
                 'tools/ancient_canal/build_layout.py','tools/ancient_canal/build_layout_assembly.py','tools/ancient_canal/capture_layout.gd','tools/ancient_canal/profile.py','tools/ancient_canal/benchmark.gd','tools/ancient_canal/measure_layout.py','tools/ancient_canal/review_layout.py','tools/ancient_canal/archive_layout.py']:
        path=ROOT/name;add(path,'sources/'+name+('.txt' if path.suffix=='.gd' else ''))
    write(OUT/'source-fingerprint.json',current)
    write(OUT/'archive-manifest.json',dict(runtime_fingerprint=current['sha256'],records=records,policy='Immutable source bytes; raw GPU and CPU samples compressed losslessly. Large media stored in 50 MiB byte-identical chunks. No caches, build logs or everyday preferences. Original PNG frame hashes and timestamps retained; full frame sequences and process logs remain in build. Historical archives are untouched.'))

def verify():
    manifest=json.loads((OUT/'archive-manifest.json').read_text());files={}
    for r in manifest['records']:
        stored=read_record(r);assert sha(stored)==r['stored_sha256'] and len(stored)==r['stored_bytes']
        data=gzip.decompress(stored) if r['encoding']=='gzip' else stored
        assert sha(data)==r['original_sha256'] and len(data)==r['original_bytes']
        assert r['source'] not in files;files[r['source']]=data
    prefix=BUILD.relative_to(ROOT).as_posix()
    def load(name):return json.loads(files[prefix+'/'+name])
    validation={}
    for name,report in [('final-validation-v2','final-headless-suite.json'),('camera-validation-v2','camera-suite.json'),('input-regression-v2','regression-suite.json'),('make-test-final','report.json')]:
        data=load(name+'/'+report)
        assert data['passed'] and data['runtime_unchanged'] and data['runtime_fingerprint_before']==manifest['runtime_fingerprint']
        validation[name]=dict(passed=True,processes=len(data.get('runs',[])) if 'runs' in data else 1)
    order=load('measurements/run-order.json');assert order['passed'] and len(order['runs'])==4
    assert order['runtime_fingerprint']==manifest['runtime_fingerprint']
    cases=[];cpu=[];transitions=[]
    for run in order['runs']:
        base=run['path'];report=json.loads(files[base+'/performance-report.json']);launch=json.loads(files[base+'/manifest.json'])
        assert report['passed'] and report['hardware_gpu'] and report['viewport']==[1920,1080] and report['renderer']=='forward_plus'
        assert report['background_sleep_usec']==0 and report['readback_count']==0 and not report['fixed_fps'] and not report['low_processor_usage_mode']
        assert report['main_window_minimized'] and report['no_focus'] and report['preferences_ignored']
        assert launch['parameters']['warmup']==5 and launch['parameters']['seconds']==30
        assert sha(files[base+'/probe.gd'])==launch['probe_sha256']
        for name,checksum in launch['generated_sha256'].items():assert sha(files[base+'/'+name])==checksum
        for case,result in report['presets'].items():
            content=files[base+'/'+case.replace('/','-')+'-samples.json'];assert sha(content)==result['sha256'];raw=json.loads(content)
            assert raw['runtime_fingerprint']==manifest['runtime_fingerprint'] and raw['elapsed_s']>=30 and raw['warmup_elapsed_s']>=5
            assert raw['inventory']['msaa_3d']==1 and raw['draw_counters']['passed'] and raw['readback_count']==0
            metrics={k:stats(raw[field]) for k,field in [('gpu','gpu_timings_ms'),('cpu','cpu_timings_ms'),('wall','frame_intervals_ms')]}
            for label,saved in [('gpu',result['gpu']),('cpu',result['cpu']),('wall',result)]:
                for k in ['mean_ms','p50_ms','p95_ms','p99_ms']:assert abs(metrics[label][k]-saved[k])<1e-6
            positions=[p['foot'] for p in raw['render_counts']];extent=[[min(p[i] for p in positions),max(p[i] for p in positions)] for i in range(3)]
            assert extent[0][1]-extent[0][0]>10 and extent[2][1]-extent[2][0]>4
            cases.append(dict(run=run['id'],case=case,metrics=metrics,route_extent_xyz_m=extent,completed_routes=result['completed_routes'],gpu_stages=stages(raw['timestamp_frames']),inventory=raw['inventory']))
            if run['instrumented_cpu']:
                functions=raw['instrumented_cpu'];selected=[('night_sky','update'),('sky_focus','_render_callback'),('scene','update_focus')]
                cpu.append(dict(sky_control_mean_ms=sum(functions['night_sky']['update'])/raw['post_draw_sample_count'],
                                conservative_sky_and_existing_focus_mean_ms=sum(sum(functions[g][n]) for g,n in selected)/raw['post_draw_sample_count'],
                                samples=raw['post_draw_sample_count']))
            else:
                initial=stages(raw['transition_frames'])
                transitions.append(dict(run=run['id'],case=case,apply_preset_cpu_ms=raw['transition_apply_cpu_ms'],max_initial_viewport_gpu_ms=max(f['gpu_ms'] for f in raw['transition_frames']),
                                        initial_setup_sky=next((x for x in initial if x['name']=='Setup Sky'),None)))
    by_key={(c['run'],c['case']):c for c in cases};deltas=[]
    for r in range(1,4):
        on=by_key[('gpu-r'+str(r),'baseline/night')]['metrics']['gpu'];off=by_key[('gpu-r'+str(r),'plain_sky/night')]['metrics']['gpu']
        deltas.append(dict(round=r,gpu_mean_delta_ms=on['mean_ms']-off['mean_ms'],gpu_p95_delta_ms=on['p95_ms']-off['p95_ms']))
    budget=dict(gpu_mean_delta_ms=statistics.mean(d['gpu_mean_delta_ms'] for d in deltas),gpu_p95_delta_ms=statistics.mean(d['gpu_p95_delta_ms'] for d in deltas),
                sky_control_cpu_mean_ms=cpu[0]['sky_control_mean_ms'],conservative_sky_and_existing_focus_ms=cpu[0]['conservative_sky_and_existing_focus_mean_ms'],
                texture_mipmap_upper_bound_mib=4096*2048*4*4/3/1024**2,rounds=deltas,gpu_rounds=3,cpu_rounds=1)
    budget['passed']=budget['gpu_mean_delta_ms']<=.15 and budget['gpu_p95_delta_ms']<=.20 and budget['conservative_sky_and_existing_focus_ms']<=.03 and budget['texture_mipmap_upper_bound_mib']<=48
    capture=load('render-v2/horizontal-capture.json');render=load('render-v2/layout-review.json')
    assert capture['passed'] and capture['route_passed'] and render['passed'] and capture['runtime_fingerprint']==manifest['runtime_fingerprint']
    summary=dict(passed=True,runtime_fingerprint=manifest['runtime_fingerprint'],archive_records=len(manifest['records']),validation=validation,
                 cases=cases,night_budget=budget,cpu=cpu,transitions=transitions,
                 render=dict(screenshots=len(capture['screenshots']),route_elapsed_s=capture['route_elapsed_s'],route_frames=len(capture['route_frames']),night_frames=len(capture['night_frames']),
                             dock_micro=render['dock_micro'],static_sky_top_30_rows_max_delta_255=render['static_sky_top_30_rows_max_delta_255']),
                 scope='R5 layout assembly and current same-layout night-sky A/B. CPU instrumentation is a separate one-round sanity check. Earlier original-versus-horizontal measurements remain historical; these runs do not isolate the cost of each newly moved building. Offscreen GPU times exclude desktop presentation and recording costs.')
    write(OUT/'summary.json',summary)
    print('LAYOUT_ARCHIVE_VERIFIED',len(manifest['records']),'records; night budget',budget['passed'])
    return summary

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--verify-only',action='store_true');args=parser.parse_args()
    if not args.verify_only:archive()
    verify()
