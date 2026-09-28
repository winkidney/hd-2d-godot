#!/usr/bin/env python3
"""Verify project-local templates; fetch the locked official archive if missing."""
from pathlib import Path
import hashlib
import json
import shutil
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / 'dependencies.lock.json').read_text())
DEST = ROOT / 'build/templates'
DEST.mkdir(parents=True, exist_ok=True)

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def main():
    outputs = LOCK['template_outputs']
    if all((ROOT / item['path']).is_file() and digest(ROOT / item['path']) == item['sha256'] for item in outputs):
        print('TEMPLATES_VERIFIED_EXISTING')
        return
    metadata = LOCK['templates']
    parsed = urllib.parse.urlparse(metadata['url'])
    if parsed.scheme != 'https' or parsed.netloc != 'github.com' or not parsed.path.startswith('/godotengine/godot-builds/releases/download/'):
        raise RuntimeError('Template URL is not an allowlisted official HTTPS release.')
    archive = DEST / metadata['name']
    expected = metadata['digest'].removeprefix('sha256:')
    if not archive.is_file() or digest(archive) != expected:
        partial = archive.with_suffix('.partial')
        print('Downloading official templates:', metadata['size'], 'bytes', flush=True)
        request = urllib.request.Request(metadata['url'], headers={'User-Agent': 'hd-2d-waystation-template-setup'})
        with urllib.request.urlopen(request, timeout=90) as source, partial.open('wb') as target:
            shutil.copyfileobj(source, target, 1024 * 1024)
        if partial.stat().st_size != metadata['size'] or digest(partial) != expected:
            raise RuntimeError('Template archive verification failed; partial file was not installed.')
        partial.replace(archive)
    with zipfile.ZipFile(archive) as bundle:
        for item in outputs:
            path = ROOT / item['path']
            if path.parent != DEST or path.name not in ('linux_debug.x86_64', 'linux_release.x86_64', 'version.txt'):
                raise RuntimeError('Unexpected template destination in lock file.')
            member = bundle.getinfo('templates/' + path.name)
            if member.file_size != item['size']:
                raise RuntimeError('Template member size mismatch.')
            partial = path.with_suffix('.partial')
            with bundle.open(member) as source, partial.open('wb') as target:
                shutil.copyfileobj(source, target)
            if digest(partial) != item['sha256']:
                raise RuntimeError('Extracted template verification failed.')
            partial.replace(path)
            if path.suffix == '.x86_64':
                path.chmod(0o755)
    print('TEMPLATES_VERIFIED_AND_READY')

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile) as exc:
        raise SystemExit(str(exc))
