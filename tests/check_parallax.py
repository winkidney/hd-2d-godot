"""Offline P8 contracts; runtime and pixel acceptance are separate gates."""
from pathlib import Path
import hashlib
import json
import re
ROOT = Path(__file__).resolve().parents[1]
checks = []
def check(value, name):
    checks.append({'name':name,'passed':bool(value)})
    print(('PASS ' if value else 'FAIL ')+name)
for name in ('parallax_profile','parallax_controller','parallax_preview','parallax_settings_store','parallax_panel','parallax_recording'):
    check((ROOT/'scripts'/f'{name}.gd').is_file(),'implementation:'+name)
for name in ('parallax_validation','parallax_pixel_fixture','parallax_coverage','parallax_benchmark'):
    check((ROOT/'tests'/f'{name}.gd').is_file(),'validation:'+name)
for name,mode,strength in [('natural','natural',1.0),('soft','artistic',0.6),('enhanced','artistic',1.5)]:
    text=(ROOT/'resources/parallax'/f'{name}.tres').read_text()
    check(f'mode = "{mode}"' in text and f'global_strength = {strength}' in text,'preset:'+name)
layout=json.loads((ROOT/'resources/world_layout.json').read_text())
check(layout['camera']['follow_gain']==0.45 and layout['camera']['follow_max']==[7.5,4.5],'project_camera_defaults_preserved')
check(layout['walkway']['length']==30.0 and layout['walkway']['width']==3.2,'walkway_geometry_preserved')
controller=(ROOT/'scripts/parallax_controller.gd').read_text()
check('global_transform = transform' in controller and 'transform: Transform3D = states[id].base' in controller,'absolute_world_transform_contract')
check('Input.' not in controller,'no_input_driven_background_scroll')
store=(ROOT/'scripts/parallax_settings_store.gd').read_text()
check('user://settings/parallax.cfg' in store and 'rename_absolute' in store,'explicit_local_preferences_and_replace')
check('32768' in store and 'Unsupported preferences schema.' in store,'bounded_versioned_settings')
scene=(ROOT/'scripts/waystation.gd').read_text()
for flag in ('--ignore-user-settings','--self-test','--p6p7-test','--p8-test','--p8-recording','--walk-recording'):
    check(flag in scene,'isolated_mode:'+flag)
for folder in ('tools','tests'):
    for path in sorted((ROOT/folder).glob('*.py')):
        compile(path.read_text(),path.name,'exec')
        check(True,'python_syntax:'+path.relative_to(ROOT).as_posix())
for name in ('Plan/features/adjustable-parallax.md','ADR/16-adjustable-parallax.md','domain-model/parallax-control.md'):
    check((ROOT/name).is_file(),'design:'+name)
report={'passed':all(c['passed'] for c in checks),'checks':checks,'scope':'Offline contracts only; GPU results reported separately.'}
out=ROOT/'build/p8/static-report.json';out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(0 if report['passed'] else 1)
