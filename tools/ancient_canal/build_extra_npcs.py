"""Normalize the two new originals; editable shape normals never sample pigment."""
import json
import re
from pathlib import Path
import build_npcs as kit

ROOT = Path(__file__).resolve().parents[2]
p,f = kit.part,kit.fold

def layers(identity):
    # Authored against preserved 1280px mothers; coordinates use the whole image.
    food = identity == 'food_vendor'
    return [
        p('robe_or_apron',[.50,.57],[.14,.22],material='cloth',slope=(.48,.20)),
        p('left_sleeve',[.394,.42],[.054,.11],slope=(.65,.40)),
        p('right_sleeve',[.59,.44],[.05,.12],slope=(.65,.40)),
        p('left_trouser',[.43,.78],[.062,.073],slope=(.6,.25)),
        p('right_trouser',[.56,.78],[.062,.073],slope=(.6,.25)),
        p('left_shoe',[.43,.892],[.045,.035],material='leather'),
        p('right_shoe',[.57,.892],[.062,.035],material='leather'),
        p('neck',[.501,.271],[.036,.036],material='skin'),
        p('face',[.521,.21],[.064,.055],material='skin',slope=(.4,.3)),
        p('nose',[.548,.216],[.012,.012],material='skin'),
        p('hair',[.48,.166],[.10,.065],material='hair'),
        p('left_hand',[.377,.574] if food else [.455,.461],[.025,.042],material='skin'),
        p('right_hand',[.62,.577],[.025,.042],material='skin'),
        f('left_drape',[[.461,.46],[.448,.60],[.433,.72]],.009,.23),
        f('right_drape',[[.544,.48],[.56,.60],[.579,.73]],.008,.22),
    ]

def main():
    records=[]
    for identity in ['food_vendor','tea_guest']:
        folder=kit.SOURCE/identity
        recipe=kit.source_recipe('vendor' if identity=='food_vendor' else 'innkeeper')
        recipe.update(id=identity,layers=layers(identity))
        (folder/'structure.json').write_text(json.dumps(recipe,indent=2)+'\n')
        records.append(kit.build(identity))
        for suffix in ['', '-normal','-mask']:
            target=kit.DEST/(identity+suffix+'.png')
            template=kit.DEST/('vendor'+suffix+'.png.import')
            text=re.sub(r'^uid=.*\n','',template.read_text(),flags=re.MULTILINE)
            target.with_suffix('.png.import').write_text(text.replace('vendor'+suffix+'.png',identity+suffix+'.png'))
    (kit.SOURCE/'extra-manifest.json').write_text(json.dumps({'schema':1,'characters':records,
        'stationary_only':True,'pivot_px':[128,240],'builder':'tools/ancient_canal/build_extra_npcs.py'},indent=2)+'\n')
    print('EXTRA_NPCS_OK', [r['checks'] for r in records])

if __name__=='__main__': main()
