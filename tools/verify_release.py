#!/usr/bin/env python3
"""Run the embedded-PCK binary from an isolated directory, without the editor."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
from project import ROOT, desktop_environment

binary = ROOT / 'build/linux/waystation.x86_64'
if not binary.is_file():
    raise SystemExit('Run make export first.')
isolated = ROOT / 'build/standalone'
isolated.mkdir(parents=True, exist_ok=True)
copy = isolated / binary.name
shutil.copy2(binary, copy)
copy.chmod(0o755)
results = []
for mode in ('headless', 'gpu'):
    output = ROOT / 'build/validation' / ('standalone-' + mode)
    command = [str(copy)]
    if mode == 'headless':
        command += ['--headless', '--fixed-fps', '60']
    else:
        command += ['--resolution', '1920x1080']
    command += ['--', '--self-test', '--capture-dir=' + str(output)]
    result = subprocess.run(command, cwd=isolated, env=desktop_environment(), capture_output=True, text=True, timeout=180)
    text = result.stdout + result.stderr
    (ROOT / 'build/logs' / ('standalone-' + mode + '.log')).write_text(text)
    if result.returncode or 'ERROR:' in text or 'ASSERT_FAIL' in text:
        raise SystemExit('Standalone ' + mode + ' failed; see its log.')
    report = json.loads((output / 'runtime-report.json').read_text())
    if not report['passed']:
        raise SystemExit('Standalone report failed.')
    results.append({'mode': mode, 'passed': True, 'checks': len(report['checks']), 'report': str((output / 'runtime-report.json').relative_to(ROOT))})
    print('STANDALONE_PASS', mode, len(report['checks']))
summary = {'passed': True, 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'runs': results, 'scope': 'embedded PCK; isolated executable directory, no project assets copied'}
(ROOT / 'build/validation/standalone-report.json').write_text(json.dumps(summary, indent=2) + '\n')
