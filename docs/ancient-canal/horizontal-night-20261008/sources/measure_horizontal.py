"""Serial, alternating original/current route measurements; no captures during sampling."""
from pathlib import Path
import argparse,json,os,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from feature_fingerprint import fingerprint

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default='build/ancient-canal/horizontal-night-20261008/measurements')
    parser.add_argument('--original',default='build/ancient-canal/horizontal-night-20261008/original')
    args=parser.parse_args()
    out=(ROOT/args.output).resolve();original=(ROOT/args.original).resolve()
    if not out.is_relative_to(ROOT/'build/ancient-canal') or out.exists():parser.error('Use a fresh project build directory')
    if not original.is_relative_to(ROOT/'build/ancient-canal') or not (original/'project.godot').is_file():parser.error('Original runtime archive is required')
    out.mkdir(parents=True)
    current=fingerprint(ROOT)['sha256'];before=fingerprint(original)['sha256']
    runs=[]
    def run(root,label,period,cases='baseline',cpu=False):
        target=out/label if root==ROOT else root/'build/ancient-canal'/label
        relative=target.relative_to(root).as_posix()
        command=[sys.executable,'tools/ancient_canal/profile.py','--output',relative,'--cases',cases,'--period',period,'--warmup','5','--seconds','30']
        command.append('--instrument-cpu' if cpu else '--gpu-profile')
        print('BEGIN '+label,flush=True);started=time.monotonic()
        with (out/(label+'.log')).open('w') as stream:
            result=subprocess.run(command,cwd=root,stdout=stream,stderr=subprocess.STDOUT,timeout=360)
        report=json.loads((target/'performance-report.json').read_text()) if (target/'performance-report.json').exists() else {}
        passed=result.returncode==0 and report.get('passed') and fingerprint(ROOT)['sha256']==current and fingerprint(original)['sha256']==before
        entry={'id':label,'period':period,'cases':cases.split(','),'instrumented_cpu':cpu,'original':root==original,'passed':bool(passed),'elapsed_s':time.monotonic()-started,'source_fingerprint':before if root==original else current,'path':target.relative_to(ROOT).as_posix()}
        runs.append(entry)
        (out/'run-order.json').write_text(json.dumps({'current':current,'original':before,'runs':runs},indent=2)+'\n')
        print('END '+label+' passed='+str(passed),flush=True)
        if not passed:raise RuntimeError(label+' failed; inspect its isolated report')
    for period in ['day','dusk','night']:
        for round_id in range(1,4):
            pair=[('old',original),('new',ROOT)] if round_id%2 else [('new',ROOT),('old',original)]
            for kind,root in pair:
                cases=('baseline,plain_sky' if round_id%2 else 'plain_sky,baseline') if kind=='new' and period=='night' else 'baseline'
                run(root,kind+'-'+period+'-r'+str(round_id),period,cases)
    for round_id in range(1,4):run(ROOT,'cpu-night-r'+str(round_id),'night','baseline',True)
    print('HORIZONTAL_MEASUREMENTS_DONE '+str(len(runs))+' isolated processes',flush=True)

if __name__=='__main__':main()
