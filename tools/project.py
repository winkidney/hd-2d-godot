#!/usr/bin/env python3
"""Project-local commands. Never installs software or changes desktop settings."""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / 'build/logs'
LOGS.mkdir(parents=True, exist_ok=True)

def engine():
    value = os.environ.get('GODOT', 'godot')
    found = shutil.which(value)
    fallback = Path.home() / '.local/bin/godot'
    if not found and value == 'godot' and fallback.is_file():
        found = str(fallback)
    if not found:
        raise RuntimeError('Godot not found. Set GODOT to an installed executable.')
    return found

def desktop_environment():
    env = os.environ.copy()
    runtime = Path('/run/user') / str(os.getuid())
    if not env.get('DISPLAY') and not env.get('WAYLAND_DISPLAY') and runtime.is_dir():
        env['XDG_RUNTIME_DIR'] = str(runtime)
        env['DBUS_SESSION_BUS_ADDRESS'] = 'unix:path=' + str(runtime / 'bus')
        result = subprocess.run(['systemctl', '--user', 'show-environment'], env=env, capture_output=True, text=True, timeout=10)
        for line in result.stdout.splitlines():
            if line.startswith(('DISPLAY=', 'WAYLAND_DISPLAY=', 'XAUTHORITY=')):
                key, value = line.split('=', 1)
                env[key] = value
    if not env.get('DISPLAY') and not env.get('WAYLAND_DISPLAY'):
        raise RuntimeError('No graphical session. Use make test for headless checks.')
    return env

def execute(command, label, graphical=False, timeout=180):
    env = desktop_environment() if graphical else os.environ.copy()
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)
    output = result.stdout + result.stderr
    (LOGS / (label + '.log')).write_text(output)
    print(output if len(output) < 10000 else output[-10000:])
    if result.returncode or 'ERROR:' in output or 'ASSERT_FAIL' in output:
        raise RuntimeError(f'{label} failed; see build/logs/{label}.log')
    return output

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['run', 'editor', 'import', 'bake', 'test', 'visual', 'export', 'record'])
    action = parser.parse_args().command
    binary = engine()
    base = [binary, '--path', str(ROOT)]
    if action in ('run', 'editor'):
        subprocess.run(base + (['--editor'] if action == 'editor' else []), cwd=ROOT, env=desktop_environment(), check=True)
    elif action == 'import':
        execute(base + ['--headless', '--editor', '--quit'], 'import')
    elif action == 'bake':
        execute(base + ['--headless', '--script', 'res://tools/bake_scene.gd'], 'bake')
    elif action == 'test':
        execute([sys.executable, str(ROOT / 'tests/check_project.py')], 'static-tests')
        execute(base + ['--headless', '--editor', '--quit'], 'import')
        execute(base + ['--headless', '--fixed-fps', '60', '--', '--self-test'], 'runtime-tests')
    elif action == 'visual':
        target = ROOT / 'build/visual'
        execute(base + ['--resolution', '1920x1080', '--', '--self-test', '--capture-dir=' + str(target)], 'visual-tests', True, 240)
    elif action == 'export':
        destination = ROOT / 'build/linux'
        destination.mkdir(parents=True, exist_ok=True)
        execute(base + ['--headless', '--export-release', 'Linux', str(destination / 'waystation.x86_64')], 'linux-export', timeout=240)
    elif action == 'record':
        destination = ROOT / 'build/media'
        destination.mkdir(parents=True, exist_ok=True)
        execute(base + ['--resolution', '1280x720', '--write-movie', str(destination / 'showcase.avi'), '--fixed-fps', '30', '--quit-after', '240', '--', '--showcase'], 'record', True, 300)

if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
