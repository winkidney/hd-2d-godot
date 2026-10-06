"""Validate native pixels, frame timing, source hashes and self-contained runtime inputs."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/characters/crescent-traveler/v1'

def verify():
    definition = json.loads((ASSETS / 'character.json').read_text())
    assert list(definition['directions']) == ['down', 'up', 'left', 'right']
    results = []
    for name, entry in definition['directions'].items():
        folder = ASSETS / name
        manifest = json.loads((folder / 'animation.json').read_text())
        assert manifest['size'] == [256, 256] and manifest['pivot'] == [128, 240]
        assert manifest['loop'] and 16 <= len(manifest['frames']) <= 56
        assert 0 <= entry['idle_frame'] < len(manifest['frames'])
        palette = set(map(tuple, manifest['palette_rgb']))
        assert len(palette) <= 96
        with Image.open(folder / manifest['atlas']) as source:
            atlas = source.convert('RGBA')
        indices = []
        for frame in manifest['frames']:
            path = folder / frame['path']
            assert path.resolve().is_relative_to(ASSETS.resolve())
            assert hashlib.sha256(path.read_bytes()).hexdigest() == frame['sha256']
            with Image.open(path) as source:
                image = source.convert('RGBA')
            assert image.size == (256, 256)
            pixels = set(image.getdata())
            assert {p[3] for p in pixels} == {0, 255}
            assert all(p[:3] == (0, 0, 0) for p in pixels if not p[3])
            assert all(p[:3] in palette for p in pixels if p[3])
            bounds = image.getchannel('A').getbbox()
            assert bounds and 0 < bounds[0] < bounds[2] < 256 and 0 < bounds[1] < bounds[3] < 256
            x, y, width, height = frame['region']
            assert atlas.crop((x, y, x + width, y + height)).tobytes() == image.tobytes()
            assert frame['duration_ms'] in (41, 42)
            indices.append(frame['source']['source_index'])
        assert indices == list(range(indices[0], indices[0] + len(indices)))
        duration = sum(f['duration_ms'] for f in manifest['frames'])
        if name == 'right':
            assert indices == list(range(28, 55)) and duration == 1125
        import_file = (folder / 'atlas.png.import').read_text()
        assert 'mipmaps/generate=false' in import_file and 'compress/mode=0' in import_file
        results.append({'direction': name, 'frames': len(indices), 'duration_ms': duration, 'passed': True})
    manifest = json.loads((ROOT / 'art_source/characters/crescent-traveler/v1/manifest.json').read_text())
    for path, digest in manifest['runtime_sha256'].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest
    output = ROOT / 'build/character-directions/pixel-check.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({'passed': True, 'directions': results}, indent=2) + '\n')
    print('CHARACTER_PIXELS_PASS', results)

if __name__ == '__main__':
    verify()
