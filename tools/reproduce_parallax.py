"""Rebuild P8 in a fresh source copy and verify default/custom GPU output."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
from project import ROOT,engine
from source_files import source_files
from feature_fingerprint import fingerprint
origin=fingerprint(ROOT)['sha256']
base=ROOT/'build/p8/reproduction';base.mkdir(parents=True,exist_ok=True)
clean=Path(tempfile.mkdtemp(prefix='clean-',dir=base))
for source in source_files(ROOT):
    target=clean/source.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
env=os.environ.copy();env['GODOT']=engine();env['XDG_DATA_HOME']=str(clean/'build/test-user-data')
blender=os.environ.get('BLENDER','blender')
steps=[('assets',[sys.executable,'tools/generate_assets.py']),
       ('background-assets',[sys.executable,'tools/generate_background_assets.py']),
       ('models',[blender,'--background','--factory-startup','--disable-autoexec','--python','tools/build_models.py']),
       ('background-models',[blender,'--background','--factory-startup','--disable-autoexec','--python','tools/build_background.py']),
       ('import',[sys.executable,'tools/project.py','import']),
       ('bake',[sys.executable,'tools/project.py','bake']),
       ('p8-test',[sys.executable,'tools/parallax.py','test']),
       ('p8-gpu',[sys.executable,'tools/parallax.py','quick-visual'])]
if '--headless-only' in sys.argv: steps=[s for s in steps if s[0]!='p8-gpu']
results=[]
for name,command in steps:
    result=subprocess.run(command,cwd=clean,env=env,capture_output=True,text=True,timeout=600)
    text=result.stdout+result.stderr
    (base/(clean.name+'-'+name+'.log')).write_text(text)
    passed=result.returncode==0 and 'ERROR:' not in text and 'ASSERT_FAIL' not in text
    results.append({'step':name,'passed':passed,'returncode':result.returncode})
    print('P8_REBUILD',name,'PASS' if passed else 'FAIL',flush=True)
    if not passed:
        print(text[-5000:]);break
passed=len(results)==len(steps) and all(r['passed'] for r in results)
if fingerprint(ROOT)['sha256']!=origin: passed=False
report={'passed':passed,'origin_runtime_fingerprint':origin,'real_gpu_checked':passed and '--headless-only' not in sys.argv,
        'steps':results,'clean_copy':clean.relative_to(ROOT).as_posix(),
        'scope':'Fresh source copy; 17 images and 12 Blender models rebuilt; new imports/bake; P8 default/custom, actual GPU, pixels and preferences process tests.'}
(ROOT/'build/p8/reproduction-report.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(0 if passed else 1)
