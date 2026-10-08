#!/usr/bin/env python3
"""Read the complete Jiangnan source chain. GPU review remains a separate gate."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import math
import re
import struct
import sys

import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools"))
from feature_fingerprint import fingerprint
FILES={}
CHECKS=[]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source(name,base=ROOT):
    assert not Path(name).is_absolute(),name
    path=(base/name).resolve()
    assert path.is_relative_to(ROOT.resolve()) and path.is_file(),name
    FILES[path.relative_to(ROOT).as_posix()]=sha(path)
    return path


def load(name,base=ROOT):
    return json.loads(source(name,base).read_text())


def hashed(name,digest,base=ROOT):
    path=source(name,base)
    assert sha(path)==digest,(name,"source hash changed")
    return path


def rgba(name,base=ROOT):
    return np.array(Image.open(source(name,base)).convert("RGBA"))


def record(name,scope,**data):
    CHECKS.append({"id":name,"passed":True,"scope":scope,**data})


def vector_image(array,alpha=None):
    visible=np.ones(array.shape[:2],dtype=bool) if alpha is None else alpha>0
    vectors=array[...,:3].astype(float)/127.5-1
    assert visible.any()
    error=abs(np.linalg.norm(vectors[visible],axis=1)-1)
    assert error.max()<.012
    return float(error.max())


def data_import(name,mipmaps=False):
    text=source(name+".import").read_text()
    assert "compress/mode=0" in text,(name,"vector data was color-compressed")
    assert "compress/normal_map=0" in text and "compress/channel_pack=0" in text
    assert "mipmaps/generate="+str(mipmaps).lower() in text,(name,"wrong sampling chain")
    assert "process/fix_alpha_border=false" in text,(name,"color edge repair applied to vector/mask data")
    assert "process/premult_alpha=false" in text and "process/normal_map_invert_y=false" in text
    for channel,index in [("red",0),("green",1),("blue",2),("alpha",3)]:
        assert f"process/channel_remap/{channel}={index}" in text,(name,"data channel mapping changed")


def audit_character():
    baseline=load("art_source/ancient-canal/character-reuse.json")
    normals=load("assets/ancient-canal/character-normals/v1/manifest.json")
    assert baseline["frame_count"]==normals["frame_count"]==108
    hashed(baseline["source_definition"],baseline["source_definition_sha256"])
    hashed(normals["baseline"],normals["baseline_sha256"])
    total=0
    for original in baseline["directions"]:
        name=original["direction"];clip=normals["directions"][name]
        source_clip=load(original["manifest"])
        hashed(original["manifest"],original["manifest_sha256"])
        assert len(original["frames"])==len(clip["frames"])==27
        assert clip["pivot"]==original["pivot"]==[128,240]
        assert clip["idle_frame"]==original["idle_frame"]
        assert clip["duration_ms"]==sum(f["duration_ms"] for f in original["frames"])
        expected=sorted(set([0,6,13,20,26,original["idle_frame"]]))
        assert clip["keyposes"]==expected
        color_atlas=rgba(clip["source_atlas"])
        normal_atlas=rgba(clip["atlas"]);mask_atlas=rgba(clip["mask_atlas"])
        hashed(clip["source_atlas"],original["atlas_sha256"])
        hashed(clip["atlas"],clip["atlas_sha256"]);hashed(clip["mask_atlas"],clip["mask_atlas_sha256"])
        data_import(clip["atlas"]);data_import(clip["mask_atlas"])
        assert color_atlas.shape==normal_atlas.shape==mask_atlas.shape
        assert np.array_equal(color_atlas[...,3],normal_atlas[...,3])
        assert np.array_equal(color_atlas[...,3],mask_atlas[...,3])
        candidate_base=ROOT/"art_source/ancient-canal/character-normals/candidates"/name
        receipt=load("receipt.json",candidate_base)
        assert "imagegen" in receipt["tool"].lower() and receipt["seed"] is None
        assert sorted(set(receipt["keyposes"]))==expected
        hashed(receipt["raw_original"],receipt["sha256"],candidate_base)
        source(receipt["prompt"],candidate_base);source(receipt["reference"],candidate_base)
        motion=source("art_source/ancient-canal/character-normals/motion/"+name+".npz")
        with np.load(motion) as flow:
            assert flow["forward"].shape==flow["backward"].shape==(27,256,256,2)
            assert np.isfinite(flow["forward"]).all() and np.isfinite(flow["backward"]).all()
        max_error=0.
        for index,(old,frame) in enumerate(zip(original["frames"],clip["frames"])):
            assert frame["index"]==index and frame["source_index"]==old["source_index"]
            assert frame["source_path"]==old["path"] and frame["region"]==old["region"]
            assert frame["duration_ms"]==old["duration_ms"]==source_clip["frames"][index]["duration_ms"]
            hashed(old["path"],old["sha256"]);hashed(frame["path"],frame["sha256"])
            hashed(frame["mask_path"],frame["mask_sha256"])
            data_import(frame["path"]);data_import(frame["mask_path"])
            color=rgba(old["path"]);normal=rgba(frame["path"]);mask=rgba(frame["mask_path"])
            assert color.shape==normal.shape==mask.shape==(256,256,4)
            assert np.array_equal(color[...,3],normal[...,3]) and np.array_equal(color[...,3],mask[...,3])
            max_error=max(max_error,vector_image(normal,color[...,3]))
            x,y,w,h=frame["region"]
            assert np.array_equal(color_atlas[y:y+h,x:x+w],color)
            assert np.array_equal(normal_atlas[y:y+h,x:x+w],normal)
            assert np.array_equal(mask_atlas[y:y+h,x:x+w],mask)
            geometry_path=source(frame["editable"]);geometry=load(frame["editable"])
            assert geometry["direction"]==name and geometry["frame"]==index
            assert geometry["corrections"] and geometry["geometry_source"]
            labels=np.array(Image.open(source("semantic-labels.png",geometry_path.parent)))
            assert np.array_equal(labels>0,color[...,3]>0)
            summed=np.zeros((256,256),dtype=np.uint16)
            for layer_id,layer in enumerate(["face","hair","braids","cloth","skirt","metal","boots"],1):
                data=rgba(layer+".png",geometry_path.parent)
                expected_alpha=np.where(labels==layer_id,color[...,3],0)
                assert np.array_equal(data[...,3],expected_alpha)
                summed+=data[...,3]
            assert np.array_equal(summed,color[...,3])
            if name=="up":assert geometry["face"] is None
            if index in expected:
                source(f"art_source/ancient-canal/character-normals/keyposes/{name}/{index:05}.json")
            total+=1
        record("character_"+name,"27 immutable colors and timed normal/mask frames; exact slices/alpha; editable anatomy; six poses; finite bidirectional tracking",frames=27,max_vector_error=max_error)
    assert total==108
    surface=source("shaders/ancient_canal/sprite_surface.gdshaderinc").read_text()
    for sampler in ["normal_atlas","silver_atlas"]:
        declaration=re.search(r"uniform sampler2D "+sampler+r"[^;]*;",surface)
        assert declaration and "filter_nearest" in declaration.group() and "source_color" not in declaration.group()
    # This independent temporal audit measures all tracked 27 transitions and
    # each loop seam, rather than accepting the production validation manifest.
    module_path=source("tests/ancient_canal/check_normals.py")
    spec=importlib.util.spec_from_file_location("canal_normals_audit",module_path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    continuity=module.check()
    assert continuity["status"]=="passed"
    record("character_temporal","Corresponding visible surfaces through 108 transitions, including four loop seams",directions=continuity["directions"])


def decode_glb(path):
    content=path.read_bytes()
    magic,version,length=struct.unpack_from("<III",content)
    assert magic==0x46546C67 and version==2 and length==len(content)
    json_length,kind=struct.unpack_from("<II",content,12);assert kind==0x4E4F534A
    document=json.loads(content[20:20+json_length]);offset=20+json_length
    size,kind=struct.unpack_from("<II",content,offset);assert kind==0x004E4942
    payload=content[offset+8:offset+8+size]
    def attributes(index):
        acc=document["accessors"][index];view=document["bufferViews"][acc["bufferView"]]
        assert acc["componentType"]==5126
        width={"VEC2":2,"VEC3":3,"VEC4":4}[acc["type"]]
        start=acc.get("byteOffset",0)+view.get("byteOffset",0)
        stride=view.get("byteStride",width*4)
        value=np.array([struct.unpack_from("<"+"f"*width,payload,start+i*stride) for i in range(acc["count"])])
        assert np.isfinite(value).all()
        return value
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            attrs=primitive["attributes"]
            assert {"POSITION","NORMAL","TANGENT","TEXCOORD_0"}<=set(attrs)
            normals=attributes(attrs["NORMAL"]);tangent=attributes(attrs["TANGENT"])
            assert abs(np.linalg.norm(normals,axis=1)-1).max()<.0005
            assert abs(np.linalg.norm(tangent[:,:3],axis=1)-1).max()<.0005
            assert abs((normals*tangent[:,:3]).sum(1)).max()<.0005
            assert abs(abs(tangent[:,3])-1).max()<1e-6
            assert len(attributes(attrs["POSITION"]))==len(attributes(attrs["TEXCOORD_0"]))
    assert all("bufferView" in image and "uri" not in image for image in document.get("images",[]))
    for sampler in document.get("samplers",[]):
        assert sampler.get("magFilter",9728)==9728
    return document


def audit_environment():
    manifest=load("art_source/ancient-canal/blender/manifest.json")
    readback=load("art_source/ancient-canal/blender/source-validation.json")
    assert readback["passed"] and len(readback["models"])==13
    expected={"tavern","house","bridge","cloth_stall","food_stall","bank_wall","dock","boat","lantern","wine_jar","cloth_banner","willow","streetlamp"}
    assert {m["id"] for m in manifest["models"]}==expected
    reopened={m["id"]:m for m in readback["models"]}
    for model in manifest["models"]:
        hashed(model["blend"],model["blend_sha256"])
        glb=hashed(model["glb"],model["glb_sha256"])
        assert reopened[model["id"]]["blend_sha256"]==model["blend_sha256"]
        assert reopened[model["id"]]["glb_sha256"]==model["glb_sha256"]
        assert reopened[model["id"]]["reopened"] and reopened[model["id"]]["packed_images"]>0
        decoded=decode_glb(glb)
        assert len(decoded["meshes"])==model["material_meshes"]
    lamp=next(model for model in manifest["models"] if model["id"]=="streetlamp")
    assert lamp["source"]=="art_source/ancient-canal/blender/streetlamp-source.json"
    receipt=load(lamp["source"])
    assert receipt["id"]=="streetlamp" and receipt["third_party_model"] is False
    assert receipt["imagegen_calls"]==0 and receipt["authorship"] and receipt["licence"]
    assert receipt["recipe"]=="tools/ancient_canal/build_models.py:streetlamp"
    for kind in ("blend","glb"):
        assert receipt[kind]==lamp[kind] and receipt[kind+"_sha256"]==lamp[kind+"_sha256"]
        hashed(receipt[kind],receipt[kind+"_sha256"])
    hashed("art_source/ancient-canal/textures/manifest.json",receipt["texture_manifest_sha256"])
    assert receipt["dimensions"]["pole_height"]==lamp["pole_height"]==2.6
    assert receipt["dimensions"]["collision_radius"]==lamp["collision_radius"]==.12
    assert receipt["dimensions"]["paper_light_centre"]==lamp["light_offset"]==[0,2.2,.36]
    assert receipt["dimensions"]["hanging_point"]==[0,2.6,.36]
    assert lamp["bounds_min"][1]==0.0 and 2.6<=lamp["bounds_max"][1]<2.7
    source("NOTICE.md")
    tex_base=ROOT/"art_source/ancient-canal/textures"
    tex=load("manifest.json",tex_base);origin=tex["imagegen"]
    assert origin["seed"] is None and origin["calls"]==2
    hashed(origin["original"],origin["sha256"],tex_base)
    hashed(origin["detail_reference"],origin["detail_sha256"],tex_base)
    source(origin["prompt"],tex_base);source(origin["detail_prompt"],tex_base);source(origin["reference"])
    assert len(tex["materials"])==7
    for entry in tex["materials"]:
        name=entry["material"]
        for suffix,key in [("","color_sha256"),("_normal","normal_sha256")]:
            image=hashed(f"assets/ancient-canal/textures/{name}{suffix}.png",entry[key])
            data=np.array(Image.open(image).convert("RGB"));assert data.shape==(256,256,3)
            assert np.array_equal(data[0],data[-1]) and np.array_equal(data[:,0],data[:,-1])
            if suffix:vector_image(data)
            settings=source(f"assets/ancient-canal/textures/{name}{suffix}.png.import").read_text()
            assert "mipmaps/generate=true" in settings
            if suffix:data_import(f"assets/ancient-canal/textures/{name}{suffix}.png",True)
        structure=load(entry["structure"],tex_base)
        assert structure["height_source"] and "never diffuse luminance" in structure["height_source"]
        source(entry["height"],tex_base)
    source("tools/ancient_canal/build_models.py")
    record("environment_sources","13 Blender sources really reopened; current GLB UV/tangent vectors independently decoded; streetlamp producer receipt binds model/texture digests and original project-authored geometry; seven seamless pixel/normal pairs; two original ImageGen calls",models=13,materials=7,new_streetlamp_receipt=True)


def audit_background_reuse():
    manifest=load("art_source/background/models.json")
    assert manifest["source_type"]=="procedural-original" and manifest["generator"]=="tools/build_background.py"
    source(manifest["generator"])
    ridges={model["id"]:model for model in manifest["models"]}
    for name in ("ridge_near","ridge_mid"):
        model=ridges[name]
        assert model["seed"]==290928
        assert model["glb"]==f"assets/background/{name}.glb" and model["blend"]==f"art_source/background/{name}.blend"
        glb=hashed(model["glb"],model["sha256"])
        source(model["blend"])
        # These distant ridges use their original per-facet vertex pigments,
        # not texture normals; UV/tangent requirements belong to the 13 kit GLBs.
        content=glb.read_bytes();magic,version,length=struct.unpack_from("<III",content)
        assert magic==0x46546C67 and version==2 and length==len(content)
        json_length,kind=struct.unpack_from("<II",content,12);assert kind==0x4E4F534A
        document=json.loads(content[20:20+json_length]);offset=20+json_length
        size,kind=struct.unpack_from("<II",content,offset);assert kind==0x004E4942
        payload=content[offset+8:offset+8+size]
        for mesh in document["meshes"]:
            for primitive in mesh["primitives"]:
                assert {"POSITION","NORMAL","COLOR_0"}<=set(primitive["attributes"])
                count=None
                for key in ("POSITION","NORMAL","COLOR_0"):
                    acc=document["accessors"][primitive["attributes"][key]]
                    view=document["bufferViews"][acc["bufferView"]]
                    assert acc["componentType"]==5126 and acc["type"] in ("VEC3","VEC4")
                    width={"VEC3":3,"VEC4":4}[acc["type"]]
                    start=acc.get("byteOffset",0)+view.get("byteOffset",0);stride=view.get("byteStride",width*4)
                    values=np.array([struct.unpack_from("<"+"f"*width,payload,start+i*stride) for i in range(acc["count"])])
                    assert np.isfinite(values).all()
                    if key=="NORMAL":assert abs(np.linalg.norm(values,axis=1)-1).max()<.0005
                    if key=="COLOR_0":assert values.min()>=0 and values.max()<=1
                    if count is None:count=acc["count"]
                    assert count==acc["count"]
    clouds=load("art_source/background/clouds.json")
    assert clouds["source_type"]=="procedural-original" and clouds["seed"]==290928
    assert clouds["generator"]=="tools/generate_background_assets.py" and len(clouds["assets"])==3
    generator=source(clouds["generator"])
    spec=importlib.util.spec_from_file_location("canal_cloud_source_check",generator)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    for index,item in enumerate(clouds["assets"]):
        assert item["path"]==f"assets/background/cloud-{index}.png" and item["size"]==[256,96]
        image=hashed(item["path"],item["sha256"])
        pixels=np.array(Image.open(image).convert("RGBA"))
        assert pixels.shape==(96,256,4) and np.any(pixels[...,3]==0) and np.any(pixels[...,3]==255)
        assert np.array_equal(pixels,np.array(module.cloud_image(index)))
        source(item["path"]+".import")
    source("scripts/ancient_canal/background.gd")
    record("background_reuse_sources","Existing seed-290928 original near/middle ridges retain finite normals/vertex pigments and matching GLB receipts/editable sources; three original cloud PNG digests and in-memory generator pixels match exactly; no new generation or third-party model",ridge_models=2,cloud_images=3,new_imagegen_calls=0)


def audit_npcs_font_concepts():
    npc=load("art_source/ancient-canal/npcs/manifest.json")
    assert {entry["id"] for entry in npc["characters"]}=={"innkeeper","vendor","boatman"}
    assert npc["stationary_only"] and npc["pivot_px"]==[128,240]
    for entry in npc["characters"]:
        base=ROOT/"art_source/ancient-canal/npcs"/entry["id"]
        hashed(entry["source"]["path"],entry["source"]["sha256"])
        hashed(entry["structure"]["path"],entry["structure"]["sha256"])
        receipt=load("receipt.json",base)
        assert receipt["seed"] is None and receipt["calls"]==1 and receipt["original_bytes_preserved"]
        assert "imagegen" in receipt["tool"].lower() and receipt["no_walk_animation"]
        source(receipt["prompt"],base);source("transform.json",base)
        for output in entry["outputs"]:hashed(output["path"],output["sha256"])
        data_import(entry["outputs"][1]["path"]);data_import(entry["outputs"][2]["path"])
        color,normal,mask=[rgba(output["path"]) for output in entry["outputs"]]
        assert color.shape==normal.shape==mask.shape==(256,256,4)
        assert np.array_equal(color[...,3],normal[...,3]) and np.array_equal(color[...,3],mask[...,3])
        vector_image(normal,color[...,3])
    from fontTools.ttLib import TTFont
    font_base=ROOT/"assets/ancient-canal/fonts"
    meta=load("source.json",font_base)
    font_path=hashed("NotoSansSC.ttf",meta["sha256"],font_base)
    license_text=source(meta["license"],font_base).read_text()
    assert "SIL OPEN FONT LICENSE" in license_text.upper() and "1.1" in license_text
    with TTFont(font_path) as font:
        cmap=font.getBestCmap()
        required="江南河街桥头酒肆角色材质场景照明环境效果比较复现掌柜摊主船工法线银饰"
        assert all(ord(character) in cmap for character in required)
    concept_base=ROOT/"art_source/ancient-canal/concepts/2026-10-07"
    concepts=load("manifest.json",concept_base)
    assert concepts["selected_concept"]=="A"
    assert concepts["generation"]["calls_total"]==7 and concepts["generation"]["seed"] is None
    for concept in concepts["concepts"]:
        full=hashed(concept["image"]["path"],concept["image"]["sha256"],concept_base)
        hashed(concept["preserved_draft"]["path"],concept["preserved_draft"]["sha256"],concept_base)
        for prompt in concept["prompts"]:hashed(prompt["path"],prompt["sha256"],concept_base)
        source(concept["receipt"],concept_base)
        for crop in concept["crops"]:
            cropped=hashed(crop["path"],crop["sha256"],concept_base)
            assert np.array_equal(np.array(Image.open(full).crop(crop["rect_xyxy"])),np.array(Image.open(cropped)))
    adapted=concept_base/"a-runtime-adaptation"
    receipt=load("receipt.json",adapted)
    assert "imagegen" in receipt["tool"].lower() and receipt["seed"] is None and receipt["calls"]==1
    image=hashed(receipt["image"]["path"],receipt["image"]["sha256"],adapted)
    assert list(Image.open(image).size)==receipt["image"]["size"]
    hashed(receipt["prompt"]["path"],receipt["prompt"]["sha256"],adapted)
    for item in receipt["references"]:
        base=ROOT if item["path"].startswith("art_source/") else adapted
        hashed(item["path"],item["sha256"],base)
    record("npcs_font_concepts","Three independent original stationary NPCs and vector sources; bundled Chinese face has required glyphs and OFL; selected A and all comparison originals/crops plus one actual-layout adaptation retained",npcs=3,imagegen_concept_calls=7)


def audit_horizontal_assets():
    low=load("art_source/ancient-canal/blender/low-bridge/recipe.json")
    assert low["reopened"] and low["original_model_retained"]
    assert low["height"]==.6 and low["width"]==2.8 and low["half_span"]==4.2
    model=low["model"]
    hashed(model["blend"],model["blend_sha256"])
    decode_glb(hashed(model["glb"],model["glb_sha256"]))
    scenery=load("art_source/ancient-canal/scenery/recipe.json")
    assert scenery["seed"]==20261008 and scenery["sky"]["moon_diameter_deg"]==.75
    for item in scenery["outputs"]:
        path=hashed(item["path"],item["sha256"])
        image=Image.open(path)
        assert list(image.size)==item["size"]
        assert "mipmaps/generate=true" in source(item["path"]+".import").read_text()
        if "panorama" in item["path"]:
            assert image.mode=="RGB" and image.size==(4096,2048)
            data=np.array(image)
            assert np.array_equal(data[:,0],data[:,-1])
            assert 4096*2048*4*4/3<=48*1024*1024
        else:
            alpha=np.array(image)[...,3]
            assert np.any(alpha==0) and np.any(alpha==255)
    extra=load("art_source/ancient-canal/npcs/extra-manifest.json")
    assert extra["stationary_only"] and extra["pivot_px"]==[128,240]
    assert {x["id"] for x in extra["characters"]}=={"food_vendor","tea_guest"}
    for item in extra["characters"]:
        base=ROOT/"art_source/ancient-canal/npcs"/item["id"]
        hashed(item["source"]["path"],item["source"]["sha256"])
        hashed(item["structure"]["path"],item["structure"]["sha256"])
        receipt=load("receipt.json",base)
        assert receipt["seed"] is None and receipt["original_bytes_preserved"] and receipt["no_walk_animation"]
        source(receipt["prompt"],base);source("transform.json",base)
        for output in item["outputs"]: hashed(output["path"],output["sha256"])
        data_import(item["outputs"][1]["path"]);data_import(item["outputs"][2]["path"])
        color,normal,mask=[rgba(x["path"]) for x in item["outputs"]]
        assert color.shape==normal.shape==mask.shape==(256,256,4)
        assert np.array_equal(color[...,3],normal[...,3]) and np.array_equal(color[...,3],mask[...,3])
        vector_image(normal,color[...,3])
    record("horizontal_assets","Separate low stone bridge GLB and reopened editable source; seeded seamless static RGB sky and cutout willow; two independent stationary NPCs with original receipts and exact alpha/vector layers",extra_npcs=2,willow_images=1,panorama_images=1)


def check():
    FILES.clear();CHECKS.clear()
    before=fingerprint(ROOT)["sha256"]
    audit_character();audit_environment();audit_background_reuse();audit_npcs_font_concepts();audit_horizontal_assets()
    assert before==fingerprint(ROOT)["sha256"],"Runtime source changed during audit"
    return {"schema_version":1,"passed":True,"status":"passed","runtime_fingerprint":before,
            "scope":"Source and asset data verification. No GPU rendering, interaction or performance completion claim.",
            "checks":CHECKS,"files":FILES,
            "review_requirements":[
                {"id":"sources","passed":True,"scope":"Original bytes and generation receipts retained for three comparison concepts and the selected-layout adaptation, two material mother/detail calls, four character form guides and three static NPCs; streetlamp model/texture producer receipt and existing original ridge/cloud provenance verified; seeded cloud pixels match their retained generator; bundled SC font glyphs, digest and OFL verified. No claim about visual approval.","evidence":["source-check.json"]},
                {"id":"models","passed":True,"scope":"13 current textured GLBs and editable Blender sources match real reopen reports and the new streetlamp receipt; independent byte decoding verifies finite UVs, normalized orthogonal tangent frames, embedded textures and nearest samplers. Seven 256px color/normal repeat borders are exact, with independent editable relief. Two reused vertex-colour ridges have valid finite geometry, normal vectors and pigment attributes with original source receipts. Physics paths, scale in camera and visible tiling are separate runtime/GPU scopes.","evidence":["source-check.json"]},
                {"id":"character_normals","passed":True,"scope":"108 original 256x256 color frame digests unchanged. Independent normal/mask frames and four atlas pairs have exact Alpha/slices, original indexes/durations/pivot/idle, valid vector data imports, six keyposes per direction, editable seven-layer anatomy and finite bidirectional flow. All 108 tracked transitions and four seams measured; actual light response/three-loop review remains a separate GPU scope.","evidence":["source-check.json"]}
            ]}


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",default="build/ancient-canal/source-check.json")
    args=parser.parse_args();result=check()
    output=ROOT/args.output
    assert output.resolve().is_relative_to(ROOT.resolve())
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
    print("ANCIENT_CANAL_SOURCE_CHECK_OK",len(CHECKS),"scopes",len(FILES),"source files")
