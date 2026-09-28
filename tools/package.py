#!/usr/bin/env python3
"""Create source and Linux bundles, with evidence gates and SHA-256 manifests."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile
from source_files import source_files

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/delivery'
OUT.mkdir(parents=True, exist_ok=True)
binary = ROOT / 'build/linux/waystation.x86_64'
verified = json.loads((ROOT / 'build/validation/standalone-report.json').read_text())
if not verified['passed'] or hashlib.sha256(binary.read_bytes()).hexdigest() != verified['binary_sha256']:
    raise SystemExit('The current binary must pass tools/verify_release.py before packaging.')
for name in ('static-report', 'runtime-report', 'reproduction-report'):
    report = json.loads((ROOT / 'build/validation' / (name + '.json')).read_text())
    if not report['passed']:
        raise SystemExit('Failed delivery gate: ' + name)
files = source_files(ROOT)
manifest = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
source_zip = OUT / 'hd-2d-godot-source.zip'
with zipfile.ZipFile(source_zip, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in files:
        archive.write(path, 'hd-2d-godot/' + path.relative_to(ROOT).as_posix())
    archive.writestr('hd-2d-godot/SOURCE_SHA256.json', json.dumps(manifest, indent=2) + '\n')
linux_zip = OUT / 'hd-2d-waystation-linux-x86_64.zip'
with zipfile.ZipFile(linux_zip, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    archive.write(binary, 'hd-2d-waystation-linux/waystation.x86_64')
    archive.write(ROOT / 'docs/delivery/runtime-README.txt', 'hd-2d-waystation-linux/README.txt')
    archive.write(ROOT / 'NOTICE.md', 'hd-2d-waystation-linux/NOTICE.md')
    for path in (ROOT / 'licenses').glob('*.txt'):
        archive.write(path, 'hd-2d-waystation-linux/licenses/' + path.name)
artifacts = [source_zip, linux_zip]
movie = ROOT / 'build/media/showcase.mp4'
if movie.is_file():
    target = OUT / 'waystation-preview.mp4'
    shutil.copy2(movie, target)
    artifacts.append(target)
lines = []
for path in artifacts:
    lines.append(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name)
    print('BUNDLE_READY', path.name, path.stat().st_size)
(OUT / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')
print('SOURCE_FILES', len(files))
