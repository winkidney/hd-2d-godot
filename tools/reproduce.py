#!/usr/bin/env python3
"""Rebuild source assets and run tests in a new project copy without caches."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
from source_files import source_files
from project import ROOT, engine
from feature_fingerprint import fingerprint

origin_fingerprint = fingerprint(ROOT)['sha256']
base = ROOT / 'build/reproduction'
base.mkdir(parents=True, exist_ok=True)
clean = Path(tempfile.mkdtemp(prefix='clean-', dir=base))
for source in source_files(ROOT):
    target = clean / source.relative_to(ROOT)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
logs = clean / 'build/logs'
logs.mkdir(parents=True, exist_ok=True)
env = os.environ.copy()
env['GODOT'] = engine()
blender = os.environ.get('BLENDER', 'blender')
commands = [
    ('assets', [sys.executable, 'tools/generate_assets.py']),
    ('background-assets', [sys.executable, 'tools/generate_background_assets.py']),
    ('models', [blender, '--background', '--factory-startup', '--disable-autoexec', '--python', 'tools/build_models.py']),
    ('background-models', [blender, '--background', '--factory-startup', '--disable-autoexec', '--python', 'tools/build_background.py']),
    ('import', [sys.executable, 'tools/project.py', 'import']),
    ('bake', [sys.executable, 'tools/project.py', 'bake']),
    ('test', [sys.executable, 'tools/project.py', 'test']),
    ('features', [sys.executable, 'tools/features.py', 'test'])]
if '--visual' in sys.argv:
    commands.append(('features-gpu', [sys.executable, 'tools/features.py', 'quick-visual']))
steps = []
for name, command in commands:
    result = subprocess.run(command, cwd=clean, env=env, capture_output=True, text=True, timeout=240)
    output = result.stdout + result.stderr
    (logs / ('reproduce-' + name + '.log')).write_text(output)
    passed = result.returncode == 0 and 'ERROR:' not in output and 'ASSERT_FAIL' not in output
    steps.append({'step': name, 'passed': passed, 'returncode': result.returncode})
    print('REPRODUCE', name, 'PASS' if passed else 'FAIL', flush=True)
    if not passed:
        print(output[-6000:])
        break
report = {'passed': len(steps) == len(commands) and all(s['passed'] for s in steps), 'clean_copy': clean.relative_to(ROOT).as_posix(), 'steps': steps, 'origin_runtime_fingerprint': origin_fingerprint, 'real_gpu_checked': '--visual' in sys.argv, 'scope': 'fresh source-copy; 17 images, 12 Blender sources/GLBs regenerated; fresh import/bake; static/native features; optional real GPU when --visual is present'}
destination = ROOT / 'build/validation/reproduction-report.json'
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(report, indent=2) + '\n')
(ROOT/'build/p6p7').mkdir(parents=True,exist_ok=True)
(ROOT/'build/p6p7/reproduction-report.json').write_text(json.dumps(report,indent=2)+'\n')
print('REPRODUCTION_REPORT', destination.relative_to(ROOT))
raise SystemExit(0 if report['passed'] else 1)
