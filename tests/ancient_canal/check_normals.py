#!/usr/bin/env python3
"""Independent pairing, vector, source-invariance and tracked continuity audit."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
NORMAL_ROOT=ROOT/"assets/ancient-canal/character-normals/v1"
SOURCE=ROOT/"art_source/ancient-canal/character-normals"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def im(path: Path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"))


def norm(rgb: np.ndarray) -> np.ndarray:
    value=rgb.astype(np.float32)/127.5-1.0
    return value/np.maximum(np.linalg.norm(value,axis=-1,keepdims=True),1e-8)


def check() -> dict:
    baseline=json.loads((ROOT/"art_source/ancient-canal/character-reuse.json").read_text())
    manifest=json.loads((NORMAL_ROOT/"manifest.json").read_text())
    assert manifest["frame_count"]==baseline["frame_count"]==108
    assert sha(ROOT/baseline["source_definition"])==baseline["source_definition_sha256"]
    assert manifest["baseline_sha256"]==sha(ROOT/manifest["baseline"])
    report={"status":"passed","frame_count":108,"directions":{},"scope":"data pairing and correspondence audit; actual Godot sweeps and loop videos are separate GPU acceptance"}
    total=0
    for source in baseline["directions"]:
        name=source["direction"];direction=manifest["directions"][name]
        color_manifest_path=ROOT/source["manifest"]
        assert sha(color_manifest_path)==source["manifest_sha256"]
        color_manifest=json.loads(color_manifest_path.read_text())
        assert len(direction["frames"])==len(source["frames"])==27
        assert direction["pivot"]==source["pivot"]==[128,240]
        assert direction["idle_frame"]==source["idle_frame"]
        assert direction["duration_ms"]==sum(f["duration_ms"] for f in source["frames"])
        assert direction["keyposes"]==sorted(set([0,6,13,20,26,source["idle_frame"]]))
        color_atlas=im(ROOT/direction["source_atlas"])
        normal_atlas=im(ROOT/direction["atlas"])
        mask_atlas=im(ROOT/direction["mask_atlas"])
        assert sha(ROOT/direction["source_atlas"])==source["atlas_sha256"]==direction["source_atlas_sha256"]
        assert sha(ROOT/direction["atlas"])==direction["atlas_sha256"]
        assert sha(ROOT/direction["mask_atlas"])==direction["mask_atlas_sha256"]
        assert normal_atlas.shape==mask_atlas.shape==color_atlas.shape
        assert np.array_equal(normal_atlas[...,3],color_atlas[...,3])
        assert np.array_equal(mask_atlas[...,3],color_atlas[...,3])
        colors=[];normals=[];labels=[];vector_errors=[];unique_vectors=set()
        minimum_layer_pixels={key:10**9 for key in ("face","hair","braids","cloth","skirt","metal","boots")}
        correction_count=0
        for index,(frame,original) in enumerate(zip(direction["frames"],source["frames"])):
            assert frame["index"]==index
            assert frame["source_index"]==original["source_index"]
            assert frame["source_path"]==original["path"]
            assert frame["region"]==original["region"]
            assert frame["duration_ms"]==original["duration_ms"]
            assert sha(ROOT/original["path"])==original["sha256"]==frame["source_sha256"]
            assert sha(ROOT/frame["path"])==frame["sha256"]
            assert sha(ROOT/frame["mask_path"])==frame["mask_sha256"]
            color=im(ROOT/frame["source_path"]);normal=im(ROOT/frame["path"]);mask=im(ROOT/frame["mask_path"])
            assert color.shape==normal.shape==mask.shape==(256,256,4)
            assert np.array_equal(color[...,3],normal[...,3])
            assert np.array_equal(color[...,3],mask[...,3])
            visible=color[...,3]>0
            vectors=normal[...,:3].astype(float)/127.5-1
            error=np.abs(np.linalg.norm(vectors[visible],axis=-1)-1)
            vector_errors.extend(error.tolist())
            assert error.max()<0.008, (name,index,"nonunit vector",float(error.max()))
            assert (vectors[visible,2]>0.15).all(),(name,index,"backfacing/tangent normal")
            unique_vectors.update(map(tuple,np.unique(normal[visible,:3],axis=0)))
            assert np.array_equal(mask[...,0],mask[...,1]) and np.array_equal(mask[...,0],mask[...,2])
            x,y,w,h=frame["region"]
            assert np.array_equal(normal_atlas[y:y+h,x:x+w],normal)
            assert np.array_equal(mask_atlas[y:y+h,x:x+w],mask)
            edit=ROOT/frame["editable"]
            geometry=json.loads(edit.read_text());assert geometry["frame"]==index and geometry["direction"]==name
            correction_count+=len(geometry["corrections"])
            semantic=np.array(Image.open(edit.parent/"semantic-labels.png"))
            assert np.array_equal(semantic>0,visible)
            layered_alpha=np.zeros_like(color[...,3],dtype=np.uint16)
            for layer_index,layer in enumerate(minimum_layer_pixels,1):
                png=im(edit.parent/(layer+".png"))
                assert np.array_equal(png[...,3],np.where(semantic==layer_index,color[...,3],0))
                layered_alpha+=png[...,3]
                count=int((semantic==layer_index).sum());minimum_layer_pixels[layer]=min(minimum_layer_pixels[layer],count)
            assert np.array_equal(layered_alpha,color[...,3])
            if name=="up":assert geometry["face"] is None,"back view invents a face"
            colors.append(color);normals.append(normal);labels.append(semantic)
            total+=1
        assert len(unique_vectors)>512,"normal vectors have been reduced to a color palette"
        assert correction_count>27,"missing per-frame ornament/occlusion correction"
        assert minimum_layer_pixels["hair"]>120 and minimum_layer_pixels["braids"]>50
        assert minimum_layer_pixels["metal"]>30 and minimum_layer_pixels["skirt"]>300
        # Audit vectors at corresponding visible material interiors. Motion flow
        # fields are production data but angular differences are recomputed here.
        motion=np.load(SOURCE/"motion"/(name+".npz"))
        flows=motion["forward"].astype(np.float32);backward=motion["backward"].astype(np.float32)
        assert flows.shape==backward.shape==(27,256,256,2)
        yy,xx=np.mgrid[:256,:256].astype(np.float32)
        angles=[];seam=None
        for index,flow in enumerate(flows):
            nxt=(index+1)%27;map_x=xx+flow[...,0];map_y=yy+flow[...,1]
            back=cv2.remap(backward[index],map_x,map_y,cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
            consistent=np.linalg.norm(flow+back,axis=-1)<1.5
            alpha=cv2.remap(colors[nxt][...,3],map_x,map_y,cv2.INTER_NEAREST)
            next_labels=cv2.remap(labels[nxt],map_x,map_y,cv2.INTER_NEAREST)
            same=(labels[index]==next_labels)&(labels[index]>0)&(alpha>127)&(colors[index][...,3]>127)&consistent
            same=cv2.erode(same.astype(np.uint8),np.ones((3,3),np.uint8))>0
            assert same.sum()>400,(name,index,"insufficient correspondence coverage")
            target=cv2.remap(norm(normals[nxt][...,:3]),map_x,map_y,cv2.INTER_LINEAR)
            target=target/np.maximum(np.linalg.norm(target,axis=-1,keepdims=True),1e-8)
            current=norm(normals[index][...,:3])
            angle=np.degrees(np.arccos(np.clip((current*target).sum(-1),-1,1)))[same]
            stats={"frame":index,"samples":int(angle.size),"mean_degrees":float(angle.mean()),"p95_degrees":float(np.quantile(angle,.95))}
            angles.append(stats)
            if index==26:seam=stats
        means=[a["mean_degrees"] for a in angles]
        # A diffuse-derived relief or screen-fixed pleat often changes abruptly
        # at the loop seam; these limits examine all 27 transitions explicitly.
        assert max(means)<12,(name,"tracked discontinuity",max(means))
        assert seam["mean_degrees"]<8,(name,"loop seam",seam)
        report["directions"][name]={"paired_frames":27,"atlas_size":direction["atlas_size"],"source_duration_ms":direction["duration_ms"],"source_idle_frame":direction["idle_frame"],"unique_normal_vectors":len(unique_vectors),"max_vector_length_error":max(vector_errors),"minimum_layer_pixels":minimum_layer_pixels,"per_frame_corrections":correction_count,"tracked_transitions":angles,"loop_seam":seam}
    assert total==108
    output=SOURCE/"validation.json";output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    return report


if __name__=="__main__":
    result=check()
    print("108 paired color/normal/silver frames, 4 exact-alpha atlases, 108 editable structures: passed")
    for name,data in result["directions"].items():
        print(name,"max vector error",round(data["max_vector_length_error"],5),"loop seam mean degrees",round(data["loop_seam"]["mean_degrees"],2))
