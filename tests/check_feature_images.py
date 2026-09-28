"""Validate real GPU captures; image assertions do not replace artistic review."""
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter, ImageStat
import json
import sys

def validate(folder: Path) -> dict:
    report=json.loads((folder/'features-report.json').read_text())
    checks=[]
    def check(value,label):
        checks.append({'name':label,'passed':bool(value)})
        print(('PASS ' if value else 'FAIL ')+label)
    check(report.get('real_gpu') and report.get('passed'),'native_gpu_report_passed')
    for period in ('day','dusk','night'):
        for side in ('left','center','right'):
            images=[]
            for state in ('off','on'):
                name=f'{period}-{side}-dof-{state}.png'
                with Image.open(folder/name) as im:
                    check(im.size==(1920,1080),'resolution:'+name)
                    images.append(im.convert('RGB'))
            delta=sum(ImageStat.Stat(ImageChops.difference(*images)).mean)/3
            check(delta>0.02,'scene_dof_changes_pixels:'+period+':'+side)
    fixture={key:Image.open(folder/f'fixture-{key}.png').convert('L') for key in ('off','near','far','both')}
    metrics={}
    def energy(image):
        w,h=image.size
        return ImageStat.Stat(image.filter(ImageFilter.FIND_EDGES).crop((2,2,w-2,h-2))).mean[0]
    for roi in report['dof_fixture']['rois']:
        crops={key:im.crop(tuple(roi['box'])) for key,im in fixture.items()}
        energies={key:energy(im) for key,im in crops.items()}
        diff={key:ImageStat.Stat(ImageChops.difference(crops['off'],im)).mean[0] for key,im in crops.items()}
        metrics[roi['name']]={'edge_energy':energies,'mean_absolute_delta':diff}
        check(energies['off']>5.0,'fixture_has_detail:'+roi['name'])
        if roi['name']=='focus':
            check(max(diff.values())<1.0,'focus_region_preserves_detail')
        else:
            target=roi['name']
            other='far' if target=='near' else 'near'
            check(energies[target]<energies['off']*.90 and diff[target]>2,'selective_blur:'+target)
            check(energies['both']<energies['off']*.90,'both_ends_blur:'+target)
            check(diff[other]<1.0,'opposite_end_not_blurred:'+target)
    result={'passed':all(c['passed'] for c in checks),'checks':checks,'fixture_metrics':metrics,'scope':'Pixel measurements from native GPU test fixtures plus 18 scene captures; no artistic approval inferred'}
    (folder/'image-report.json').write_text(json.dumps(result,indent=2)+'\n')
    return result

if __name__=='__main__':
    result=validate(Path(sys.argv[1]))
    raise SystemExit(0 if result['passed'] else 1)
