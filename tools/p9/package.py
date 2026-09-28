"""Package validated P9 engineering preview, retaining explicit source-art blockers."""
from pathlib import Path
import json, hashlib, zipfile, sys, shutil
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from source_files import source_files
from feature_fingerprint import fingerprint
BASE=ROOT/'build/p9'
OUT=BASE/'delivery'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    reports={}
    for name in ('gpu','standalone-headless','standalone-gpu','rebuild-gpu'):
        d=json.loads((BASE/name/'report.json').read_text())
        assert d['passed'], name
        if name!='standalone-headless':
            for kind in ('dof-image-report.json','image-report.json'):
                assert json.loads((BASE/name/kind).read_text())['passed'], name+kind
        reports[name]={'checks':len(d['checks']),'report_sha256':sha(BASE/name/'report.json')}
    gpu=json.loads((BASE/'gpu/report.json').read_text())
    assert gpu['runtime_fingerprint']==fingerprint(ROOT)['sha256'], 'Stale source GPU evidence'
    assert all(v['duration_s']>=30 and v['target_60fps_p95_met'] for v in gpu['performance'].values())
    assert json.loads((BASE/'rebuild-report.json').read_text())['passed']
    binary=BASE/'linux/lantern-canal.x86_64'
    assert sha(binary)==sha(BASE/'standalone/lantern-canal.x86_64')
    assert (BASE/'walkthrough.mp4').stat().st_size>10000
    OUT.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(OUT/'lantern-canal-linux-x86_64.zip','w',zipfile.ZIP_DEFLATED) as z:
        z.write(binary,binary.name)
        z.write(ROOT/'NOTICE.md','NOTICE.md')
        for p in (ROOT/'licenses').rglob('*'):
            if p.is_file(): z.write(p,p.relative_to(ROOT))
        z.writestr('README.txt','P9 engineering preview. Run ./lantern-canal.x86_64\nWASD/arrows: movement; E: interact; T: time; F6: DOF; F8: parallax.\nOriginal ImageGen source archive remains incomplete. Visual approval pending.\n')
    with zipfile.ZipFile(OUT/'p9-project-source.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in source_files(ROOT):
            if 'research' in p.parts: continue
            z.write(p,p.relative_to(ROOT))
    shutil.copy2(BASE/'walkthrough.mp4',OUT/'walkthrough.mp4')
    shutil.copy2(BASE/'gpu/dusk-reference-dof-on.png',OUT/'preview.png')
    with zipfile.ZipFile(OUT/'p9-validation-evidence.zip','w',zipfile.ZIP_DEFLATED) as z:
        for name in ('gpu','standalone-headless','standalone-gpu','rebuild-gpu'):
            for p in (BASE/name).glob('*.json'): z.write(p,p.relative_to(BASE))
        for p in (BASE/'gpu').glob('*.png'): z.write(p,p.relative_to(BASE))
        z.write(BASE/'rebuild-report.json','rebuild-report.json')
        for name in ('graybox-preview.png','final-preview.png'):
            z.write(BASE/name,name)
    manifest={'status':'engineering-preview; source-art archival incomplete; visual approval pending',
              'runtime_fingerprint':gpu['runtime_fingerprint'],'binary_sha256':sha(binary),'reports':reports,
              'source_archive_excludes':'copyrighted research screenshot; retains source-status manifest',
              'performance':{k:{'frame_p95_ms':v['p95_ms'],'gpu_p95_ms':v['gpu']['p95_ms'],'duration_s':v['duration_s']} for k,v in gpu['performance'].items()}}
    (OUT/'delivery-report.json').write_text(json.dumps(manifest,indent=2)+'\n')
    for p in OUT.glob('*.zip'):
        with zipfile.ZipFile(p) as z: assert z.testzip() is None
    files=sorted(p for p in OUT.iterdir() if p.name!='SHA256SUMS')
    (OUT/'SHA256SUMS').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in files))
    print(json.dumps(manifest,indent=2))
if __name__=='__main__': main()
