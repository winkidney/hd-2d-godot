"""Measure rendered marker centroids separately from engine projection checks."""
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
import json
import sys

folder = Path(sys.argv[1])
checks = []
records = []

def check(value, name):
    checks.append({'name': name, 'passed': bool(value)})
    print(('PASS ' if value else 'FAIL ') + name)

def centroid(path, marker):
    image = Image.open(path).convert('L')
    x0, y0 = int(marker['x'])-100, int(marker['y'])-45
    crop = image.crop((x0,y0,x0+200,y0+90))
    pixels = crop.load()
    total = sx = sy = 0.0
    for y in range(crop.height):
        for x in range(crop.width):
            value = pixels[x,y]
            total += value
            sx += (x+x0)*value
            sy += (y+y0)*value
    if total < 255*100: raise ValueError('Marker missing: '+str(path))
    return sx/total, sy/total

fixture = json.loads((folder/'markers.json').read_text())
for item in fixture['cases']:
    for marker in fixture['markers']:
        a = centroid(folder/'markers-base.png', marker)
        b = centroid(folder/item['image'], marker)
        expected = -marker['focal']*item['k']*item['dx']/marker['depth']
        error = abs(b[0]-a[0]-expected)
        check(error < 0.8 and abs(b[1]-a[1]) < 0.8, 'pixel_ratio:'+item['image']+':'+marker['layer'])
        records.append({'case': item['image'], 'layer':marker['layer'],
                        'expected_dx':expected, 'measured_dx':b[0]-a[0], 'error_px':error})

for period in ('day','dusk','night'):
    natural = Image.open(folder/f'{period}-natural-x0.png').convert('RGB')
    for preset in ('natural','soft','enhanced'):
        zero = Image.open(folder/f'{period}-{preset}-x0.png').convert('RGB')
        shifted = Image.open(folder/f'{period}-{preset}-x2.png').convert('RGB')
        check(zero.size == (1920,1080) and shifted.size == (1920,1080), 'resolution:'+period+':'+preset)
        difference = sum(ImageStat.Stat(ImageChops.difference(natural,zero)).mean)/3
        check(difference < 0.5, 'anchor_has_no_compensation:'+period+':'+preset)
    a = Image.open(folder/f'{period}-soft-x2.png').convert('RGB')
    b = Image.open(folder/f'{period}-enhanced-x2.png').convert('RGB')
    change = sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3
    check(change > 0.01,'artistic_gain_changes_scene_pixels:'+period)
report = {'passed': all(v['passed'] for v in checks), 'checks':checks,
          'pixel_measurements':records, 'tolerance_px':0.8,
          'scope':'Intensity-weighted centroids of real GPU markers; scene matrix checked separately.'}
(folder/'image-report.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(0 if report['passed'] else 1)
