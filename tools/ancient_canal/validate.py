"""Reproduce headless scene/settings/layout checks without imports or fixed FPS."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from project import engine
from feature_fingerprint import fingerprint

OUT = ROOT / 'build/ancient-canal'


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def archive_regression_transcripts(runs):
    """Preserve original process bytes in portable evidence paths, not host logs."""
    folder = OUT / 'regression/raw-transcripts'
    folder.mkdir(parents=True, exist_ok=True)
    records = []
    destinations = set()
    for entry in runs:
        original = entry['log']
        source = OUT / original
        destination = folder / source.with_suffix('.txt').name
        if destination in destinations:
            raise RuntimeError('Duplicate regression transcript archive destination')
        destinations.add(destination)
        original_sha = sha(source)
        shutil.copy2(source, destination)
        if sha(destination) != original_sha:
            raise RuntimeError('Regression transcript bytes changed during archival')
        record = dict(original_local_path=original, original_sha256=original_sha,
                      path=destination.relative_to(OUT).as_posix(), sha256=original_sha,
                      bytes_identical=True, test_rerun=False)
        entry.update(log=record['path'], log_sha256=original_sha, log_archival=record)
        records.append(record)
    return records


def run(label, script, args, raw_path=None):
    entry = [script] if script.endswith('.tscn') else ['--script', script]
    command = [engine(), '--headless', '--path', str(ROOT), *entry, '--', '--ignore-user-settings', *args]
    return run_command(label, command, raw_path)


def run_command(label, command, raw_path=None):
    before = fingerprint(ROOT)
    environment = os.environ.copy()
    for variable, folder in [('XDG_DATA_HOME', 'user-data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        environment[variable] = str(OUT / 'headless-environment' / folder)
    log = OUT / 'logs' / (label + '.log')
    log.parent.mkdir(parents=True, exist_ok=True)
    previous_mtime = raw_path.stat().st_mtime_ns if raw_path and raw_path.exists() else None
    start = time.monotonic()
    with log.open('w') as stream:
        result = subprocess.run(command, cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT, timeout=360)
    elapsed = time.monotonic() - start
    after = fingerprint(ROOT)
    errors = [line for line in log.read_text().splitlines() if 'ERROR:' in line or 'FAIL' in line]
    fresh = raw_path and raw_path.exists() and raw_path.stat().st_mtime_ns != previous_mtime
    raw = json.loads(raw_path.read_text()) if fresh else None
    if raw_path and not fresh:
        errors.append('Missing newly written raw report; old evidence was not reused.')
    if raw is not None:
        raw.update(runtime_fingerprint=before['sha256'], runtime_fingerprint_before=before['sha256'], runtime_fingerprint_after=after['sha256'], runtime_unchanged=before['sha256'] == after['sha256'])
        write(raw_path, raw)
    passed = result.returncode == 0 and not errors and (raw is None or raw.get('passed') is True)
    entry = dict(label=label, returncode=result.returncode, passed=passed, elapsed_s=elapsed, fixed_fps=False, import_performed=False,
                 errors=errors, log=log.relative_to(OUT).as_posix(), runtime_fingerprint_before=before['sha256'], runtime_fingerprint_after=after['sha256'], runtime_unchanged=before['sha256'] == after['sha256'])
    entry['import'] = False
    print(('PASS ' if passed else 'FAIL ') + label + f' ({elapsed:.2f}s)', flush=True)
    if not passed:
        print(log.read_text()[-12000:], flush=True)
    return entry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['all', 'headless', 'settings', 'blockout', 'contract', 'regression'], default='all')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    before = fingerprint(ROOT)
    runs = []
    selected = lambda mode: args.mode in ['all', mode]
    if selected('headless'):
        runs.append(run('final-headless', 'res://tests/ancient_canal/validation.gd', ['--canal-test', '--canal-output=res://build/ancient-canal/headless'], OUT/'headless/report.json'))
    if selected('blockout'):
        runs.append(run('final-blockout', 'res://tests/ancient_canal/blockout.gd', [], OUT/'blockout.json'))
    if args.mode == 'all':
        runs.append(run('background-unit', 'res://tests/ancient_canal/background_unit.gd', []))
        runs.append(run('upright-validation', 'res://tests/ancient_canal/upright_validation.gd', ['--upright-output=res://build/ancient-canal/upright-validation', '--canal-fingerprint='+fingerprint(ROOT)['sha256']], OUT/'upright-validation/upright-report.json'))
    if selected('settings'):
        for phase in ['write', 'read']:
            runs.append(run('final-settings-'+phase, 'res://tests/ancient_canal/validation.gd', ['--canal-test', '--canal-settings-'+phase, '--canal-output=res://build/ancient-canal/settings-'+phase], OUT/('settings-'+phase)/'report.json'))
        parts = [(OUT/('settings-'+phase)/'report.json') for phase in ['write', 'read']]
        reports = [json.loads(p.read_text()) for p in parts]
        after_settings = fingerprint(ROOT)
        settings_runs = [r for r in runs if r['label'].startswith('final-settings-')]
        settings_before = settings_runs[0]['runtime_fingerprint_before']
        checks = [c for report in reports for c in report['checks']]
        probe_removed = not (OUT/'scene-settings-cross-process.cfg').exists()
        write(OUT/'settings-report.json', dict(schema_version=2, passed=all(r['passed'] and r['runtime_unchanged'] for r in settings_runs) and settings_before == after_settings['sha256'] and probe_removed,
            runtime_fingerprint=settings_before, runtime_fingerprint_before=settings_before, runtime_fingerprint_after=after_settings['sha256'], runtime_unchanged=settings_before == after_settings['sha256'],
            independent_file=True, cross_process=True, write_report='settings-write/report.json', read_report='settings-read/report.json', checks=checks, checks_count=len(checks),
            source_reports=[dict(path=p.relative_to(OUT).as_posix(), sha256=sha(p)) for p in parts], settings_probe_file_removed=probe_removed, fixed_fps=False, import_performed=False,
            scope='Two real scene processes restore all F/W/O profiles, six requested parallax gains, native Colors, actual single-lamp overrides, explicit night background colors despite custom lighting, and material/DOF settings. Isolated XDG homes; no import, GPU or everyday preferences.'))
    if selected('contract'):
        runs.append(run('settings-contract', 'res://tests/ancient_canal/settings_contract.gd', ['--report=res://build/ancient-canal/settings-contract.json'], OUT/'settings-contract.json'))
        for phase in ['write', 'read']:
            runs.append(run('settings-contract-'+phase, 'res://tests/ancient_canal/settings_contract.gd', ['--settings-contract-'+phase, '--report=res://build/ancient-canal/settings-contract-'+phase+'.json'], OUT/('settings-contract-'+phase+'.json')))
    if args.mode == 'regression':
        for label, script in [('frontal-camera', 'camera_unit.gd'), ('frontal-lens', 'lens_unit.gd')]:
            runs.append(run(label, 'res://tests/p9frontal/'+script, []))
        runs.append(run('original-character', 'res://tests/character_animation.gd', []))
        runs.append(run('original-p9-scene', 'res://scenes/reference_scene.tscn', ['--p9-test', '--capture-dir=res://build/ancient-canal/regression/p9'], OUT/'regression/p9/report.json'))
        runs.append(run('original-frontal-scene', 'res://scenes/frontal_canal.tscn', ['--frontal-test', '--frontal-quick', '--frontal-output=res://build/ancient-canal/regression/frontal'], OUT/'regression/frontal/report.json'))
        runs.append(run('original-input-dispatch', 'res://tests/input_dispatch.gd', ['--input-output=res://build/ancient-canal/regression/input-dispatch.json'], OUT/'regression/input-dispatch.json'))
        runs.append(run_command('input-cleanup', ['/usr/bin/python3', 'tests/test_input_window_cleanup.py', '-v']))
    after = fingerprint(ROOT)
    changed = sorted(k for k in before['files'].keys() | after['files'].keys() if before['files'].get(k) != after['files'].get(k))
    stable = before['sha256'] == after['sha256'] and all(r['runtime_unchanged'] for r in runs)
    suite = dict(schema_version=2, passed=all(r['passed'] for r in runs) and stable, complete=True, mode=args.mode,
        runtime_fingerprint=before['sha256'], runtime_fingerprint_before=before['sha256'], runtime_fingerprint_after=after['sha256'], runtime_unchanged=stable,
        changed_files=changed, headless=True, fixed_fps=False, import_performed=False, time_scale=1, physics_ticks_per_second=60, runs=runs,
        scope='Actual current scene/settings/layout contract checks. Each run records before/after fingerprints; a source drift prevents a frozen pass. No GPU, screenshot, window-focus or performance claim.')
    target = 'final-headless-suite.json' if args.mode == 'all' else args.mode+'-suite.json'
    suite['import'] = False
    if args.mode == 'regression':
        transcript_archives = archive_regression_transcripts(runs)
        suite['transcript_archival'] = dict(
            scope='Original process logs copied byte-for-byte to portable raw-transcripts TXT files. Local host logs are retained but not bundled; archival does not rerun any test.',
            records=transcript_archives)
    write(OUT/target, suite)
    if args.mode == 'regression':
        folder = OUT/'regression'
        folder.mkdir(parents=True, exist_ok=True)
        transcript = folder/'transcript.txt'
        transcript.write_text('\n'.join('Process '+r['label']+'; exit '+str(r['returncode'])+'\n'+(OUT/r['log']).read_text() for r in runs))
        copied = []
        for name, source in [('make-p8-headless.json', ROOT/'build/p8/headless/features-report.json'), ('make-p8-settings.json', ROOT/'build/p8/settings/report.json'), ('make-p8-native.log', ROOT/'build/p8/headless/native.log')]:
            if source.exists():
                destination = folder/name
                shutil.copy2(source, destination)
                copied.append(dict(path=destination.relative_to(OUT).as_posix(), sha256=sha(destination)))
        evidence = [OUT/'regression-suite.json', transcript, OUT/'regression/input-dispatch.json', OUT/'regression/p9/report.json', OUT/'regression/frontal/report.json']
        evidence.extend(OUT/r['log'] for r in runs)
        input_report = json.loads((OUT/'regression/input-dispatch.json').read_text())
        write(OUT/'input-regression-report.json', dict(schema_version=2, passed=suite['passed'], runtime_fingerprint=before['sha256'],
            runtime_fingerprint_before=before['sha256'], runtime_fingerprint_after=after['sha256'], runtime_unchanged=stable,
            commands=[r['label'] for r in runs], checks=[line for r in runs for line in (OUT/r['log']).read_text().splitlines() if any(marker in line for marker in ['UNIT checks=', 'CHARACTER_TEST_DONE', 'Ran 4 tests', 'INPUT_DISPATCH_DONE'])],
            input_checks=len(input_report['checks']), actual_current_runs=runs, make_test_supplement=dict(scope='Parent completed make test earlier in this revision. The copied P8 reports retain their original fingerprints; these supplements do not claim a rerun at the final fingerprint.', artifacts=copied),
            transcript_archival=suite['transcript_archival'],
            artifacts=[dict(path=p.relative_to(OUT).as_posix(), sha256=sha(p)) for p in evidence]+copied,
            scope='Actual current character, Frontal camera/lens, P9/Frontal physical scenes, four-scene synthesized GUI input dispatch and cleanup unit tests. No import, GPU or native-window focus claim.'))
    raise SystemExit(0 if suite['passed'] else 1)


if __name__ == '__main__':
    main()
