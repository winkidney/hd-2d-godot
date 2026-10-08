"""Project-local Jiangnan commands. Production tools are not runtime dependencies."""
from pathlib import Path
import os,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from project import engine,desktop_environment
from feature_fingerprint import fingerprint
OUT=ROOT/'build/ancient-canal'

def run(args,label,gpu=False,timeout=300):
    OUT.mkdir(parents=True,exist_ok=True)
    logs=OUT/'logs';logs.mkdir(exist_ok=True)
    env=desktop_environment() if gpu else os.environ.copy()
    env['XDG_DATA_HOME']=str(OUT/'user-data')
    env['XDG_CONFIG_HOME']=str(OUT/'config')
    env['XDG_CACHE_HOME']=str(OUT/'cache')
    with (logs/(label+'.log')).open('w') as stream:
        result=subprocess.run([str(a) for a in args],cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
    text=(logs/(label+'.log')).read_text()
    errors=[line for line in text.splitlines() if 'ERROR:' in line or 'FAIL' in line]
    # The sandbox refuses the editor's optional debug listener, not asset import.
    ignored=('Condition "_sock == -1"','Condition "err != OK"') if label=='import' else ()
    errors=[line for line in errors if not any(note in line for note in ignored)]
    if result.returncode or errors:
        raise RuntimeError(label+' failed:\n'+text[-9000:])
    print('PASS',label,text[-900:] if label!='import' else '')

def main():
    action=sys.argv[1]
    base=[engine(),'--path',ROOT]
    if action=='import': run(base+['--headless','--editor','--quit'],'import')
    elif action=='quick':
        run(base+['--display-driver','x11','--position','10000,10000','--audio-driver','Dummy','--disable-render-loop','--script','res://tools/ancient_canal/capture.gd','--','--ignore-user-settings','--canal-fingerprint='+fingerprint(ROOT)['sha256']],'quick',True)
    elif action=='run':
        subprocess.run(base+['res://scenes/ancient_canal.tscn'],cwd=ROOT,env=desktop_environment(),check=True)
    elif action=='headless':
        run(base+['--headless','--fixed-fps','60','--script','res://tests/ancient_canal/validation.gd','--','--ignore-user-settings'],'headless')
    elif action in ('calibration','normals','route','benchmark','upright','dock-stability','horizontal'):
        scripts={'calibration':'tests/ancient_canal/calibration.gd','normals':'tools/ancient_canal/capture_normals.gd','route':'tools/ancient_canal/capture_route.gd','benchmark':'tools/ancient_canal/benchmark.gd','upright':'tests/ancient_canal/upright_validation.gd','dock-stability':'tools/ancient_canal/capture_dock_stability.gd','horizontal':'tools/ancient_canal/capture_horizontal.gd'}
        extra=['--upright-gpu','--upright-output=res://build/ancient-canal/upright-validation-gpu'] if action=='upright' else []
        if action=='horizontal': extra=['--canal-output=res://build/ancient-canal/horizontal-night-20261008/render']+sys.argv[2:]
        run(base+['--display-driver','x11','--position','10000,10000','--audio-driver','Dummy','--disable-render-loop','--script','res://'+scripts[action],'--','--ignore-user-settings','--canal-fingerprint='+fingerprint(ROOT)['sha256']]+extra,action,True,timeout=900)
    else: raise SystemExit('Unknown action '+action)

if __name__=='__main__': main()
