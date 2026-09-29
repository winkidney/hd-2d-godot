"""Lens-only follow-up evidence. Never overwrite the original P9R2 review."""
from pathlib import Path
import json
import sys
import zipfile

import run as frontal

ROOT = frontal.ROOT
OUT = ROOT / 'build/p9-frontal-zoom'
frontal.OUT = OUT
frontal.previous.OUT = OUT


def probe(mode, gpu=False):
    folder = OUT / 'lens' / mode
    folder.mkdir(parents=True, exist_ok=True)
    args = [frontal.engine(), '--path', ROOT, '--script',
            'res://tools/p9frontal/lens_probe.gd']
    args += ['--resolution', '1920x1080'] if gpu else ['--headless', '--fixed-fps', '60']
    args += ['--', '--probe-mode=' + mode, '--probe-output=' + str(folder)]
    if mode not in ('save', 'load'):
        args += ['--ignore-user-settings']
    before = frontal.fingerprint(ROOT)['sha256']
    frontal.run(args, 'lens-' + mode, gpu)
    report = json.loads((folder / 'report.json').read_text())
    assert report['passed']
    assert before == frontal.fingerprint(ROOT)['sha256']
    report['runtime_fingerprint'] = before
    frontal.save(folder / 'report.json', report)


def tests():
    frontal.run([frontal.engine(), '--headless', '--path', ROOT, '--editor', '--quit'], 'lens-import')
    before = frontal.fingerprint(ROOT)['sha256']
    frontal.run(['make', 'test'], 'old-scene-regression')
    frontal.run([sys.executable, 'tests/p9/check_assets.py'], 'asset-provenance')
    for name in ('camera_unit', 'lens_unit'):
        frontal.run([frontal.engine(), '--headless', '--path', ROOT, '--script',
                     'res://tests/p9frontal/' + name + '.gd'], name)
    for mode in ('save', 'load', 'headless'):
        probe(mode)
    frontal.native('headless')
    assert before == frontal.fingerprint(ROOT)['sha256']
    frontal.save(OUT / 'test-report.json', {'passed': True, 'runtime_fingerprint': before,
                 'scope': 'Old scene regression, provenance, camera and lens units, save/load, UI state and default physical routes.'})


def package():
    fingerprint = frontal.fingerprint(ROOT)['sha256']
    reports = {}
    tests_report = json.loads((OUT / 'test-report.json').read_text())
    assert tests_report['passed'] and tests_report['runtime_fingerprint'] == fingerprint
    for label in ('headless', 'quick', 'standalone-headless', 'standalone-gpu'):
        report = json.loads((OUT / label / 'report.json').read_text())
        assert report['passed'] and report['runtime_fingerprint'] == fingerprint, label
        reports[label] = report
    for mode in ('save', 'load', 'headless', 'gpu'):
        report = json.loads((OUT / 'lens' / mode / 'report.json').read_text())
        assert report['passed'] and report['runtime_fingerprint'] == fingerprint, mode
        reports['lens-' + mode] = report
    export = json.loads((OUT / 'export-report.json').read_text())
    binary = OUT / 'linux/frontal-canal.x86_64'
    assert export['passed'] and frontal.sha(binary) == export['binary_sha256']
    folder = OUT / 'delivery'
    folder.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(folder / 'frontal-zoom-linux.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.write(binary, binary.name)
    with zipfile.ZipFile(folder / 'frontal-zoom-project.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in frontal.source_files(ROOT):
            if 'research' not in path.parts:
                archive.write(path, 'project/' + str(path.relative_to(ROOT)))
    with zipfile.ZipFile(folder / 'frontal-zoom-evidence.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in ('test-report.json', 'export-report.json'):
            archive.write(OUT / name, name)
        for label in ('headless', 'quick', 'standalone-headless', 'standalone-gpu', 'lens', 'logs'):
            for path in sorted((OUT / label).rglob('*')):
                if path.is_file():
                    archive.write(path, str(path.relative_to(OUT)))
    for path in folder.glob('*.zip'):
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None, path
    frontal.save(folder / 'delivery-report.json', {
        'passed': True, 'runtime_fingerprint': fingerprint,
        'linux_binary_sha256': frontal.sha(binary),
        'reports': {key: {'passed': value['passed'], 'checks': len(value.get('checks', []))}
                    for key, value in reports.items()},
        'scope': 'Adjustable lens follow-up; original review videos and performance report were not reissued.'})
    import shutil
    for name in ('README.md',):
        shutil.copy2(ROOT / 'docs/validation/p9-frontal-zoom' / name, folder / name)
    for path in (OUT / 'lens/gpu').glob('*.png'):
        shutil.copy2(path, folder / path.name)
    manifest = ''.join(frontal.sha(path) + '  ' + path.name + '\n'
                       for path in sorted(folder.iterdir()) if path.is_file() and path.name != 'SHA256SUMS')
    (folder / 'SHA256SUMS').write_text(manifest)
    print('LENS_DELIVERY', folder)


if __name__ == '__main__':
    action = sys.argv[1]
    if action == 'test':
        tests()
    elif action == 'gpu':
        probe('gpu', True)
        frontal.native('quick', True, True, extra=['--frontal-no-route'])
    elif action == 'export':
        frontal.export()
    elif action == 'package':
        package()
    elif action in ('save', 'load', 'headless'):
        probe(action)
    else:
        raise SystemExit('Unknown action: ' + action)
