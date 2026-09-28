"""Fingerprint the authored runtime and its validation code, excluding caches."""
from pathlib import Path
import hashlib
import json

def fingerprint(root: Path) -> dict:
    names=['project.godot','export_presets.cfg']
    for directory in ('assets','resources','scenes','scripts','shaders','tests'):
        for path in (root/directory).rglob('*'):
            if path.is_file() and not path.is_symlink() and '__pycache__' not in path.parts and path.suffix not in ('.pyc',):
                names.append(path.relative_to(root).as_posix())
    values={n:hashlib.sha256((root/n).read_bytes()).hexdigest() for n in sorted(set(names))}
    digest=hashlib.sha256(json.dumps(values,sort_keys=True).encode()).hexdigest()
    return {'sha256':digest,'files':values}
