"""Shared, explicit source-bundle boundary. No parent workspace traversal."""
from pathlib import Path
import os

DIRECTORIES = {'assets', 'art_source', 'scenes', 'scripts', 'shaders', 'resources', 'tools', 'tests', 'docs', 'Plan', 'ADR', 'domain-model', 'licenses'}
FILES = {'project.godot', 'export_presets.cfg', 'Makefile', 'README.md', 'NOTICE.md', 'AGENTS.md', '.gitignore', 'dependencies.lock.json'}

def source_files(root: Path):
    found = []
    for name in sorted(FILES):
        path = root / name
        if path.is_file() and not path.is_symlink():
            found.append(path)
    for name in sorted(DIRECTORIES):
        base = root / name
        if not base.is_dir():
            continue
        for current, directories, filenames in os.walk(base, followlinks=False):
            directories[:] = [d for d in directories if d not in ('.git', '.godot', 'build', '.venv', '__pycache__') and not (Path(current) / d).is_symlink()]
            for filename in sorted(filenames):
                path = Path(current) / filename
                if path.is_symlink() or path.suffix in ('.pyc', '.blend1', '.blend2') or path.name == '.env':
                    continue
                found.append(path)
    return sorted(found)
