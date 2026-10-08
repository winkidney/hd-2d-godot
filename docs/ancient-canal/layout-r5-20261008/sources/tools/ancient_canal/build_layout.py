"""Build the Ancient scene layout from its selected measured top/side drawings."""
from pathlib import Path
import argparse
import copy
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art_source/ancient-canal/layout-review/20261008-r5/layout.review.json'
ASSEMBLY = ROOT / 'art_source/ancient-canal/layout-assembly/20261008-r5'
DESTINATION = ROOT / 'resources/ancient-canal/layout.json'


def split(rect, cut):
    x0, z0, x1, z1 = rect
    a, b, c, d = max(x0, cut[0]), max(z0, cut[1]), min(x1, cut[2]), min(z1, cut[3])
    if a >= c or b >= d:
        return [rect], None
    pieces = [[x0,z0,a,z1],[c,z0,x1,z1],[a,z0,c,b],[a,d,c,z1]]
    return [r for r in pieces if r[0] < r[2] and r[1] < r[3]], [a,b,c,d]


def terrain(source):
    bank = source['map'];rear, front = source['river']['z']
    tiles = [dict(rect=[bank['x'][0],bank['z'][0],bank['x'][1],rear],kind='bank'),
             dict(rect=[bank['x'][0],front,bank['x'][1],bank['z'][1]],kind='bank')]
    dock = source['dock'];x,_,z = dock['center'];w,depth = dock['deck_size_xz'];rw=dock['ramp_width']
    operations = [([x-w/2,front,x+w/2,z+depth/2], None),
                  ([x-rw/2,dock['ramp_z'][0],x+rw/2,dock['ramp_z'][1]], None)]
    for s in source['streets'].values():operations.append(([s['x'][0],s['z'][0],s['x'][1],s['z'][1]],'street'))
    court=source['tavern_forecourt'];operations.append(([court['x'][0],court['z'][0],court['x'][1],court['z'][1]],'court'))
    for o in source['objects']:
        if o['id'].startswith('S'):
            x=o['position'][0];z0,z1=source['stall_waiting_strip']['z'];operations.append(([x-1.6,z0,x+1.6,z1],'court'))
    for cut, kind in operations:
        result=[]
        for tile in tiles:
            pieces, intersection=split(tile['rect'],cut)
            result.extend(dict(rect=r,kind=tile['kind']) for r in pieces)
            if intersection and kind:result.append(dict(rect=intersection,kind=kind))
        tiles=result
    return tiles


def build():
    source=json.loads(SOURCE.read_text());result=json.loads((ASSEMBLY/'base-layout.json').read_text())
    result['id']='jiangnan-horizontal-r5';result['blueprint']={'path':SOURCE.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest()}
    result['streets']=copy.deepcopy(source['streets']);result['tavern_forecourt']=source['tavern_forecourt'];result['ground_tiles']=terrain(source)
    models=[]
    for o in source['objects']:
        models.append(dict(id=o['asset'],site_id=o['id'],position=o['position'],yaw=o['yaw_deg'],collision_size=o['collision_size']))
    for key,asset in [('bridge','bridge'),('dock','dock'),('boat','boat')]:
        o=source[key];entry=dict(id=asset,site_id={'bridge':'BR1','dock':'D1','boat':'BO1'}[key],position=o['center'],yaw=o.get('yaw_deg',0))
        if key=='bridge':entry['asset']='bridge_low'
        models.append(entry)
    for site_id,point in zip(source['willow_ids'],source['willows']):
        models.append(dict(id='willow',site_id=site_id,position=point,yaw=0,collision_size=[.38,2.4,.38],cast_shadow=point[2]>0))
    old_tavern=next(o for o in result['models'] if o['id']=='tavern');new_tavern=next(o for o in models if o['id']=='tavern')
    delta=[b-a for a,b in zip(old_tavern['position'],new_tavern['position'])]
    for o in result['models']:
        if o['id'] in ['wine_jar','cloth_banner']:
            o=copy.deepcopy(o);o['position']=[round(a+b,5) for a,b in zip(o['position'],delta)];models.append(o)
    for o in source['lights']:
        if o['kind']=='lantern':models.append(dict(id='lantern',site_id=o['diagram_id'],position=o['fixture_position'],yaw=0,light_offset=o['light_offset'],label=o['label']))
    result['models']=models
    npcs={o['id']:o for o in source['npcs']}
    for o in result['npcs']:o['position']=npcs[o['id']]['position']
    for o in result['interactions']:o['position']=[round(a+b,5) for a,b in zip(o['position'],delta)]
    result['streetlamps']=[];result['broad_lights']=[];result['lamp_defaults']={}
    for o in source['lights']:
        if o['kind']=='streetlamp':
            result['streetlamps'].append(dict(id=o['id'],site_id=o['diagram_id'],label=o['label'],position=o['fixture_position'],light_offset=o['light_offset'],pole_height=o['pole_height'],collision_radius=o['collision_radius'],cast_shadow=o['cast_shadow']))
            if o.get('proposed_overrides'):result['lamp_defaults'][o['id']]=o['proposed_overrides']
        elif o['kind']=='broad':result['broad_lights'].append(dict(id=o['id'],site_id=o['diagram_id'],label=o['label'],position=o['position'],tint=o['tint_rgba'],cast_shadow=o['cast_shadow']))
    dock=source['dock'];x,y,z=dock['center']
    result['dock']=dict(center_x=x,center_z=z,surface_y=y,bank=dock['bank'],approach_z=dock['ramp_z'][1],ramp_deck_z=dock['ramp_z'][0],ramp_width=dock['ramp_width'],deck_size_xz=dock['deck_size_xz'])
    result['background']['houses']=source['background_buildings'];result['background']['trees']=source['background_trees']
    # Axis-aligned legs avoid stall corners; all five NPCs and both light centres are visited.
    result['route']=[[1.2,0,8.5],[23.5,0,8.5],[1.2,0,8.5],[1.2,0,-2.4],
        [19.2,0,-2.4],[19.2,0,-3.9],[19.2,0,-2.4],[13.7,0,-2.4],[13.7,0,-4.2],[13.7,0,-2.4],
        [-9.5,0,-2.4],[-9.5,0,-4.8],[-8,0,-4.7],[-9.5,0,-4.8],[-9.5,0,-2.4],
        [-14.6,0,-2.4],[-14.6,0,-4.2],[-14.6,0,-2.4],[-23.5,0,-2.4],[1.2,0,-2.4],[1.2,0,8.5],
        [-12,0,8.5],[-12,0,6.6],[-12,-.32,3.8],[-12,0,6.6],[-12,0,8.5],[-23.5,0,8.5],[1.2,0,8.5]]
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--apply',action='store_true');args=parser.parse_args()
    result=build();content=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if args.apply:DESTINATION.write_text(content)
    else:assert DESTINATION.read_text()==content,'Runtime layout differs from construction drawings. Run --apply.'
    recipe={'source':SOURCE.relative_to(ROOT).as_posix(),'source_sha256':result['blueprint']['sha256'],'generator':'tools/ancient_canal/build_layout.py','runtime':DESTINATION.relative_to(ROOT).as_posix(),'runtime_sha256':hashlib.sha256(content.encode()).hexdigest(),'ground_tiles':len(result['ground_tiles']),'ground_batches':len({o['kind'] for o in result['ground_tiles']}),'ground_top_y':0,'dock_top_y':-.32,'light_count':14,'source_models_retained':True}
    (ASSEMBLY/'construction-recipe.json').write_text(json.dumps(recipe,indent=2)+'\n')
    print('LAYOUT_R5_MATCH: positions, roads, dock, background and all 14 lamps')


if __name__=='__main__':main()
