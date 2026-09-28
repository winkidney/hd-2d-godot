#!/usr/bin/env python3
"""Offline structural checks. Does not claim GPU or artistic acceptance."""
from pathlib import Path
from PIL import Image
import hashlib
import importlib.util
import io
import json
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
checks = []

def check(condition, label):
    checks.append({'name': label, 'passed': bool(condition)})
    print(('PASS ' if condition else 'FAIL ') + label)

manifest = json.loads((ROOT / 'art_source/generated/manifest.json').read_text())
check(len(manifest['assets']) == 14, 'fourteen_source_images')
for item in manifest['assets']:
    path = ROOT / item['path']
    check(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256'], 'hash:' + item['path'])
    with Image.open(path) as image:
        check(list(image.size) == item['size'], 'dimensions:' + item['path'])
        if path.stem in ('traveler', 'keeper'):
            check(image.size == (128, 192) and image.mode == 'RGBA', 'actor_atlas:' + path.stem)
            check(image.getextrema()[3] == (0, 255), 'actor_alpha:' + path.stem)

for path in sorted((ROOT / 'assets/models').glob('*.glb')):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<4sII', data)
    check(magic == b'glTF' and version == 2 and length == len(data), 'glb:' + path.stem)
    check((ROOT / 'art_source/blender' / (path.stem + '.blend')).is_file(), 'blend_source:' + path.stem)
for directory in ('tools', 'tests'):
    for path in (ROOT / directory).glob('*.py'):
        compile(path.read_text(), str(path), 'exec')
        check(True, 'python_parse:' + path.name)

spec = importlib.util.spec_from_file_location('asset_generator', ROOT / 'tools/generate_assets.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
regenerated = {}
def remember(image, relative):
    buffer = io.BytesIO()
    image.save(buffer, format='PNG')
    regenerated['assets/' + relative] = hashlib.sha256(buffer.getvalue()).hexdigest()
generator.save = remember
for kind in ('stone', 'brick', 'wood', 'roof', 'plaster', 'grass', 'soil'):
    generator.texture(kind)
generator.foliage()
generator.actors()
check(all(regenerated.get(item['path']) == item['sha256'] for item in manifest['assets']), 'deterministic_image_regeneration_in_memory')

required = ['README.md', 'Plan/README.md', 'ADR/README.md', 'domain-model/README.md', 'docs/workflows/README.md', 'scenes/waystation.tscn', 'scenes/world.tscn']
for name in required:
    check((ROOT / name).is_file(), 'entry:' + name)
missing = []
private_paths = []
for path in ROOT.rglob('*.md'):
    if any(part in ('.git', '.godot', 'build', '.venv') for part in path.relative_to(ROOT).parts):
        continue
    text = path.read_text()
    if re.search(r'/(?:home|Users)/[^/\s]+', text):
        private_paths.append(str(path.relative_to(ROOT)))
    for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', text):
        target = target.split('#', 1)[0]
        if not target or '://' in target or target.startswith('mailto:'):
            continue
        if not (path.parent / target).exists():
            missing.append(str(path.relative_to(ROOT)) + ' -> ' + target)
check(not missing, 'markdown_links:' + repr(missing))
check(not private_paths, 'no_private_host_paths_in_docs:' + repr(private_paths))
check('instance=ExtResource' not in (ROOT / 'scenes/world.tscn').read_text(), 'baked_models_do_not_retain_duplicate_instance_state')
output = ROOT / 'build/validation/static-report.json'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({'checks': checks, 'passed': all(c['passed'] for c in checks)}, indent=2) + '\n')
raise SystemExit(0 if all(c['passed'] for c in checks) else 1)
