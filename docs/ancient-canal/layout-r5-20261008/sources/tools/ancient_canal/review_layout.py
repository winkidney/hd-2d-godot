"""Encode current R5 captures with original wall timing and check dock/sky stability."""
from pathlib import Path
import json
import statistics
import subprocess
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/ancient_canal'))
import encode_evidence as codec
from analyze_dock_stability import polygon_mask,temporal_metrics
import review_horizontal
OUT=ROOT/'build/ancient-canal/layout-r5-20261008/render-v2'

def main():
    capture=json.loads((OUT/'horizontal-capture.json').read_text())
    assert capture['passed'] and capture['route_passed'] and not capture['write_failures']
    records=[]
    for name,field in [('route','route_frames'),('night','night_frames')]:
        rows=capture[field];times=[round(r['time_s']*1000) for r in rows]
        gaps=[b-a for a,b in zip(times,times[1:])]
        durations=gaps+[max(1,round(statistics.median(gaps)))]
        frames=[]
        for row,duration in zip(rows,durations):
            path=OUT/(name+'-frames')/row['path']
            assert codec.sha(path)==row['sha256']
            frames.append(dict(path=path,duration_ms=duration,source_metadata=dict(producer_png_sha256=row['sha256'],foot=row['foot'],sky_yaw=row['sky_yaw'])))
        record=codec.encode_clip(name,frames,OUT,'Actual R5 GPU route with observed wall timing',[name],OUT/'horizontal-capture.json',dict(terminal_duration_inferred=True,terminal_method='Median observed interval; no interpolated frames',throughput_benchmark=False))
        records.append(record)
    review_horizontal.OUT=OUT
    # Existing decoder checks complete streams and every original PNG hash.
    review_horizontal.main()
    for record,name in zip(records,['route','night']):
        spacing=record['duration_s']/12 if name=='route' else record['duration_s']/6
        subprocess.run(['ffmpeg','-v','error','-y','-threads','2','-i',str(OUT/(name+'.mp4')),
                        '-vf',f'fps=1/{spacing},scale=480:270,tile={4 if name=="route" else 3}x{3 if name=="route" else 2}',
                        '-frames:v','1',str(OUT/(name+'-contact.png'))],check=True)
    micro=[]
    for group in capture['dock_micro_groups']:
        masks=[polygon_mask(row['plank_polygon'],erode=2) for row in group['frames']]
        mask=np.logical_and.reduce(masks)
        pixels=[np.asarray(Image.open(OUT/row['path']).convert('RGB'))[mask] for row in group['frames']]
        metrics=temporal_metrics(pixels)
        micro.append(dict(lens=group['lens'],metrics=metrics,passed=metrics['max_pair_fraction_above_16']<=.01))
    a=np.asarray(Image.open(OUT/'night-still-a.png').convert('RGB'))[:30]
    b=np.asarray(Image.open(OUT/'night-still-b.png').convert('RGB'))[:30]
    sky_delta=int(np.abs(a.astype(int)-b.astype(int)).max())
    report=dict(passed=all(row['passed'] for row in micro) and sky_delta==0,runtime_fingerprint=capture['runtime_fingerprint'],
                dock_micro=micro,criterion=dict(delta_255=16,max_fraction=.01,camera_offset_m=.0005),
                static_sky_top_30_rows_max_delta_255=sky_delta,videos=records,
                visual_notes='Actual top view shows vertical billboard trees edge-on. Side view projects objects at different X together. Original default F/W framing gives a narrow sky strip; clouds can partly cover the small crescent. Contact sheets cover the entire new route.',
                source_pngs_unmodified=True)
    (OUT/'layout-review.json').write_text(json.dumps(report,indent=2)+'\n')
    assert report['passed'],report
    print('LAYOUT_RENDER_REVIEW_PASS')

if __name__=='__main__':main()
