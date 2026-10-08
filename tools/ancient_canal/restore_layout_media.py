"""Restore R5 full-resolution videos from verified byte-identical Git chunks."""
from pathlib import Path
import json
from archive_layout import OUT,read_record,sha

def main():
    manifest=json.loads((OUT/'archive-manifest.json').read_text())
    for record in manifest['records']:
        if record['encoding']!='chunked':continue
        content=read_record(record)
        assert sha(content)==record['original_sha256'] and len(content)==record['original_bytes']
        target=(OUT/record['path']).resolve();assert target.is_relative_to(OUT.resolve())
        if target.exists():assert sha(target.read_bytes())==record['original_sha256']
        else:
            temporary=target.with_name(target.name+'.restore-tmp')
            temporary.write_bytes(content);temporary.replace(target)
        print('RESTORED_MEDIA_VERIFIED',record['path'],len(content),'bytes')

if __name__=='__main__':main()
