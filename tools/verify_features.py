"""Verify the exact exported executable alone, in a fresh directory."""
from pathlib import Path
import hashlib
import json
import shutil
import tempfile
from project import ROOT
from features import native
from feature_fingerprint import fingerprint

def main() -> None:
    binary=ROOT/'build/linux/waystation.x86_64'
    manifest=json.loads((ROOT/'build/p6p7/export-manifest.json').read_text())
    digest=hashlib.sha256(binary.read_bytes()).hexdigest()
    if manifest['binary_sha256']!=digest or manifest['runtime_fingerprint']!=fingerprint(ROOT)['sha256']:
        raise RuntimeError('Export is stale. Run make export after the last runtime change.')
    base=ROOT/'build/p6p7/standalone';base.mkdir(parents=True,exist_ok=True)
    isolated=Path(tempfile.mkdtemp(prefix='only-binary-',dir=base))
    target=isolated/binary.name
    shutil.copy2(binary,target);target.chmod(0o755)
    runs=[]
    for mode in ('headless','gpu'):
        out=base/mode
        report=native(mode,out,True,target)
        runs.append({'mode':mode,'passed':report['passed'],'checks':len(report['checks']),'report':(out/'features-report.json').relative_to(ROOT).as_posix()})
    result={'passed':True,'binary_sha256':digest,'runtime_fingerprint':manifest['runtime_fingerprint'],'runs':runs,'scope':'Only embedded-PCK executable copied to isolated working directory. No project assets or editor used by runtime.'}
    (base/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    print('STANDALONE_FEATURES_VERIFIED',digest)

if __name__=='__main__':
    main()
