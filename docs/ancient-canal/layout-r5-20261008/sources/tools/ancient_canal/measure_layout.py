"""R5 same-layout night-sky A/B: three alternating 1080p GPU rounds, separate CPU."""
from pathlib import Path
import json
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from feature_fingerprint import fingerprint
OUT=ROOT/'build/ancient-canal/layout-r5-20261008/measurements'

def main():
    assert not OUT.exists(),'Use a fresh evidence directory'
    OUT.mkdir(parents=True)
    before=fingerprint(ROOT)['sha256'];runs=[]
    for label,cases,cpu in [('gpu-r1','baseline,plain_sky',False),('gpu-r2','plain_sky,baseline',False),
                            ('gpu-r3','baseline,plain_sky',False),('cpu','baseline',True)]:
        print('BEGIN '+label,flush=True)
        target=OUT/label
        command=[sys.executable,'tools/ancient_canal/profile.py','--output',target.relative_to(ROOT).as_posix(),
                 '--cases',cases,'--period','night','--warmup','5','--seconds','30',
                 '--instrument-cpu' if cpu else '--gpu-profile']
        with (OUT/(label+'.log')).open('w') as stream:
            result=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,timeout=360)
        report=json.loads((target/'performance-report.json').read_text())
        passed=result.returncode==0 and report['passed'] and fingerprint(ROOT)['sha256']==before
        runs.append(dict(id=label,path=target.relative_to(ROOT).as_posix(),cases=cases.split(','),instrumented_cpu=cpu,passed=passed))
        (OUT/'run-order.json').write_text(json.dumps(dict(runtime_fingerprint=before,runs=runs,passed=all(r['passed'] for r in runs)),indent=2)+'\n')
        print('END '+label+' passed='+str(passed),flush=True)
        assert passed,label

if __name__=='__main__':main()
