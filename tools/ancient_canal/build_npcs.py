#!/usr/bin/env python3
"""Rebuild static NPC color, authored shape normals and material masks.

ImageGen creates mother images. This offline step only crops, places, applies
nearest sampling and quantizes their colors. Normal vectors come exclusively
from editable semantic geometry, never from RGB brightness or image edges.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source/ancient-canal/npcs"
DEST = ROOT / "assets/ancient-canal/npcs"
IDS = ("innkeeper", "vendor", "boatman")


def part(name, center, radii, polygon=None, material="cloth", slope=(0.6, 0.4)):
    return {"name": name, "kind": "curved", "center": center, "radii": radii,
            "polygon": polygon, "material": material, "slope": slope}


def fold(name, points, width=0.008, strength=0.23):
    return {"name": name, "kind": "fold", "points": points,
            "width": width, "strength": strength}


def authored_layers(identity):
    """Coordinates were drawn from the visible mother images, in [0,1] units."""
    if identity == "innkeeper":
        return [
            part("robe_body", [.51, .58], [.24, .31], [[.4,.25],[.6,.25],[.7,.45],[.79,.76],[.65,.825],[.32,.80],[.26,.76],[.36,.49]], slope=(.43,.15)),
            part("left_sleeve", [.32,.35], [.11,.09], [[.35,.25],[.41,.38],[.35,.45],[.24,.47],[.225,.39],[.28,.30]], slope=(.6,.38)),
            part("right_sleeve", [.70,.385], [.07,.09], [[.635,.28],[.70,.32],[.73,.4],[.765,.435],[.73,.48],[.676,.46]], slope=(.7,.35)),
            part("left_trouser", [.397,.822], [.081,.073], [[.32,.77],[.49,.81],[.47,.867],[.375,.865],[.34,.84]], material="cloth"),
            part("right_trouser", [.636,.828], [.081,.071], [[.53,.815],[.72,.795],[.714,.847],[.653,.873],[.579,.86]], material="cloth"),
            part("left_shoe", [.398,.946], [.056,.044], [[.37,.87],[.429,.87],[.45,.96],[.435,.986],[.34,.986],[.337,.96]], material="leather", slope=(.6,.55)),
            part("right_shoe", [.69,.941], [.105,.034], [[.607,.871],[.67,.87],[.683,.905],[.775,.932],[.78,.971],[.6,.97],[.592,.947]], material="leather", slope=(.5,.7)),
            part("neck", [.523,.241], [.045,.043], [[.466,.197],[.556,.204],[.571,.241],[.537,.265],[.476,.231]], material="skin", slope=(.45,.25)),
            part("face", [.549,.155], [.102,.077], [[.499,.105],[.584,.10],[.601,.119],[.61,.174],[.586,.207],[.541,.216],[.49,.191],[.469,.159]], material="skin", slope=(.45,.35)),
            part("nose", [.578,.169], [.024,.021], material="skin", slope=(.65,.55)),
            part("ear", [.433,.17], [.022,.018], material="skin"),
            part("hair_cap", [.489,.10], [.124,.082], [[.45,.034],[.56,.062],[.59,.1],[.55,.095],[.509,.104],[.466,.139],[.448,.193],[.419,.154],[.394,.115],[.383,.074]], material="hair", slope=(.65,.4)),
            part("topknot", [.428,.037], [.052,.03], material="hair"),
            part("sash", [.515,.441], [.16,.023], [[.386,.406],[.475,.406],[.65,.408],[.663,.459],[.524,.47],[.412,.457]], slope=(.27,.4)),
            part("left_forearm", [.317,.428], [.068,.031], [[.281,.408],[.339,.404],[.379,.447],[.346,.47],[.271,.434]], material="skin", slope=(.5,.45)),
            part("left_hand", [.431,.457], [.05,.031], [[.405,.436],[.456,.427],[.481,.444],[.472,.478],[.43,.482],[.39,.459]], material="skin"),
            part("right_forearm", [.721,.48], [.029,.038], [[.69,.456],[.721,.443],[.749,.5],[.718,.522]], material="skin"),
            part("right_hand", [.743,.555], [.04,.045], [[.713,.518],[.744,.505],[.777,.545],[.773,.593],[.744,.609],[.716,.59]], material="skin", slope=(.45,.25)),
            part("silver_clasp", [.606,.46], [.019,.014], material="silver", slope=(.75,.75)),
            fold("robe_left_drape", [[.405,.5],[.389,.64],[.367,.78]], .008,.24),
            fold("robe_center_drape", [[.533,.493],[.532,.641],[.548,.808]], .007,.24),
            fold("robe_right_drape", [[.633,.5],[.65,.65],[.72,.78]], .009,.24),
            fold("sleeve_left_crease", [[.307,.302],[.339,.357],[.283,.383]], .006,.18),
            fold("sleeve_right_crease", [[.682,.345],[.686,.4],[.73,.43]], .007,.18),
        ]
    if identity == "vendor":
        return [
            part("cream_shirt", [.5,.48], [.22,.26], [[.426,.252],[.557,.25],[.633,.327],[.742,.63],[.722,.755],[.383,.744],[.315,.721],[.377,.483],[.313,.424],[.35,.313]], slope=(.4,.18)),
            part("left_sleeve", [.367,.418], [.068,.11], [[.37,.29],[.424,.39],[.403,.478],[.339,.531],[.266,.5],[.299,.428],[.315,.366]], slope=(.58,.35)),
            part("right_sleeve", [.66,.444], [.07,.077], [[.592,.341],[.642,.345],[.686,.425],[.74,.483],[.704,.52],[.648,.49]], slope=(.55,.4)),
            part("apron", [.54,.515], [.151,.229], [[.464,.32],[.611,.327],[.623,.395],[.61,.458],[.719,.718],[.48,.75],[.417,.648],[.456,.423]], slope=(.5,.15)),
            part("left_trouser", [.39,.799], [.095,.098], [[.34,.729],[.49,.744],[.478,.84],[.433,.884],[.354,.865],[.31,.832]], material="cloth", slope=(.6,.3)),
            part("right_trouser", [.589,.807], [.093,.09], [[.512,.738],[.665,.728],[.695,.822],[.654,.884],[.54,.878],[.505,.84]], material="cloth", slope=(.6,.3)),
            part("left_shoe", [.4,.953], [.063,.036], [[.353,.897],[.433,.914],[.465,.966],[.45,.987],[.35,.986],[.347,.959]], material="leather", slope=(.5,.5)),
            part("right_shoe", [.64,.95], [.087,.036], [[.57,.897],[.623,.905],[.726,.939],[.728,.978],[.563,.974],[.553,.945]], material="leather", slope=(.5,.6)),
            part("neck", [.499,.254], [.034,.042], [[.459,.225],[.519,.223],[.538,.25],[.531,.283],[.48,.267]], material="skin"),
            part("face", [.55,.178], [.101,.068], [[.513,.124],[.595,.126],[.624,.16],[.611,.206],[.576,.239],[.528,.242],[.488,.219],[.479,.18]], material="skin", slope=(.43,.35)),
            part("nose", [.569,.199], [.018,.015], material="skin", slope=(.6,.4)),
            part("ear", [.433,.192], [.027,.021], material="skin"),
            part("hair_cap", [.489,.134], [.151,.093], [[.403,.045],[.521,.053],[.609,.094],[.66,.154],[.636,.218],[.61,.175],[.582,.13],[.535,.16],[.487,.172],[.462,.252],[.447,.239],[.455,.17],[.409,.17],[.351,.153],[.356,.101]], material="hair", slope=(.65,.45)),
            part("hair_bun", [.4,.06], [.06,.04], material="hair"),
            part("left_forearm_cuff", [.337,.535], [.031,.025], [[.312,.509],[.35,.507],[.38,.546],[.344,.567],[.304,.56]], slope=(.6,.3)),
            part("left_hand", [.328,.599], [.041,.04], [[.313,.558],[.356,.561],[.364,.618],[.351,.646],[.318,.635],[.285,.599]], material="skin", slope=(.5,.2)),
            part("right_hand", [.733,.595], [.034,.04], [[.705,.563],[.747,.567],[.77,.613],[.764,.64],[.73,.645],[.703,.62]], material="skin", slope=(.5,.25)),
            part("silver_hairpin", [.402,.08], [.025,.012], material="silver", slope=(.7,.7)),
            part("silver_apron_left", [.466,.335], [.016,.012], material="silver", slope=(.7,.7)),
            part("silver_apron_right", [.599,.335], [.014,.012], material="silver", slope=(.7,.7)),
            part("silver_belt", [.514,.43], [.022,.014], material="silver", slope=(.75,.75)),
            fold("apron_center_pleat", [[.546,.461],[.545,.57],[.58,.736]], .008,.25),
            fold("apron_left_pleat", [[.477,.465],[.471,.592],[.469,.723]], .008,.26),
            fold("apron_right_pleat", [[.588,.45],[.619,.556],[.664,.7]], .008,.22),
            fold("trouser_left_crease", [[.413,.755],[.394,.819],[.417,.865]], .009,.19),
            fold("trouser_right_crease", [[.595,.75],[.63,.809],[.598,.871]], .009,.19),
        ]
    return [
        part("jacket_body", [.52,.402], [.205,.182], [[.425,.25],[.586,.255],[.655,.357],[.681,.545],[.627,.569],[.511,.551],[.393,.56],[.343,.529],[.365,.343]], slope=(.52,.15)),
        part("cream_inner_shirt", [.552,.402], [.068,.161], [[.469,.25],[.538,.29],[.589,.28],[.625,.56],[.577,.6],[.494,.57]], slope=(.4,.2)),
        part("left_sleeve", [.324,.383], [.08,.058], [[.316,.347],[.363,.346],[.389,.436],[.348,.457],[.254,.43],[.245,.409]], slope=(.58,.5)),
        part("right_sleeve", [.71,.411], [.054,.065], [[.668,.35],[.723,.357],[.757,.424],[.721,.48],[.685,.456]], slope=(.57,.5)),
        part("sash", [.569,.46], [.079,.027], [[.519,.445],[.611,.438],[.64,.486],[.574,.498],[.514,.482]], slope=(.3,.5)),
        part("left_trouser", [.44,.675], [.104,.11], [[.382,.557],[.532,.596],[.49,.749],[.41,.8],[.351,.761],[.349,.694]], material="cloth", slope=(.6,.2)),
        part("right_trouser", [.606,.681], [.092,.123], [[.516,.583],[.623,.563],[.676,.653],[.687,.779],[.618,.815],[.544,.784],[.554,.702]], material="cloth", slope=(.6,.2)),
        part("left_calf", [.397,.839], [.043,.041], [[.364,.798],[.43,.804],[.436,.857],[.384,.888],[.345,.869]], material="skin", slope=(.6,.3)),
        part("right_calf", [.613,.851], [.041,.043], [[.58,.8],[.649,.8],[.643,.869],[.616,.893],[.574,.87]], material="skin", slope=(.6,.3)),
        part("left_shoe", [.392,.94], [.061,.033], [[.36,.9],[.43,.9],[.442,.959],[.418,.974],[.336,.974],[.329,.953]], material="leather", slope=(.55,.6)),
        part("right_shoe", [.66,.942], [.093,.034], [[.592,.899],[.641,.903],[.727,.931],[.76,.949],[.758,.965],[.566,.965],[.56,.942]], material="leather", slope=(.5,.6)),
        part("neck", [.529,.248], [.056,.039], [[.477,.209],[.56,.215],[.577,.264],[.539,.295],[.472,.265]], material="skin", slope=(.5,.3)),
        part("face", [.555,.164], [.097,.067], [[.524,.12],[.619,.122],[.633,.174],[.605,.22],[.563,.236],[.519,.216],[.483,.195],[.482,.155]], material="skin", slope=(.43,.3)),
        part("nose", [.584,.185], [.02,.017], material="skin", slope=(.65,.4)),
        part("ear", [.455,.187], [.022,.023], material="skin"),
        part("hair", [.499,.145], [.106,.046], [[.43,.13],[.52,.094],[.627,.103],[.64,.152],[.606,.14],[.574,.128],[.533,.15],[.502,.181],[.477,.151],[.468,.22],[.445,.16],[.406,.167]], material="hair", slope=(.55,.4)),
        part("straw_hat", [.513,.086], [.283,.052], [[.251,.18],[.384,.104],[.485,.013],[.588,.036],[.736,.072],[.793,.094],[.767,.144],[.691,.15],[.639,.1],[.495,.117],[.37,.175],[.274,.201]], material="straw", slope=(.25,.68)),
        part("left_forearm", [.316,.509], [.037,.047], [[.283,.468],[.333,.466],[.349,.552],[.32,.583],[.29,.55]], material="skin", slope=(.6,.2)),
        part("left_hand", [.321,.585], [.049,.039], [[.297,.55],[.349,.56],[.357,.602],[.332,.625],[.287,.612],[.279,.592]], material="skin", slope=(.55,.25)),
        part("right_forearm", [.715,.495], [.027,.056], [[.689,.452],[.722,.457],[.744,.561],[.714,.582],[.699,.54]], material="skin", slope=(.6,.2)),
        part("right_hand", [.728,.592], [.037,.032], [[.702,.562],[.746,.559],[.763,.602],[.743,.622],[.715,.62],[.704,.604]], material="skin", slope=(.5,.3)),
        part("silver_clasp", [.619,.473], [.018,.012], material="silver", slope=(.75,.75)),
        fold("jacket_left_drape", [[.43,.282],[.441,.403],[.409,.543]], .008,.24),
        fold("jacket_right_drape", [[.612,.282],[.626,.401],[.637,.554]], .007,.22),
        fold("trouser_left_crease", [[.43,.58],[.42,.672],[.389,.753]], .009,.2),
        fold("trouser_right_crease", [[.589,.582],[.61,.689],[.637,.782]], .009,.2),
    ]


MATERIALS = {"cloth": [0.0, .93, 0.0], "skin": [0.0, .72, 0.0],
             "hair": [0.0, .78, 0.0], "leather": [0.0, .86, 0.0],
             "straw": [0.0, .96, 0.0], "silver": [1.0, .24, 1.0]}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_recipe(identity):
    return {"schema_version": 1, "id": identity, "coordinate_system": "normalized mother-image x-right y-down",
            "normal_convention": "OpenGL x-right y-up z-toward-camera, unit vectors, linear data",
            "authorship": "manually drawn semantic ellipsoids, garment crease polylines and independent material regions",
            "forbidden_sources": ["RGB luminance", "color Sobel", "grayscale bump", "generated baked light"],
            "foot_anchor": [128, 240], "target_height": 224, "canvas_size": [256, 256], "palette_size": 96,
            "mask_channels": {"r": "silver specular region", "g": "roughness", "b": "metallicity", "a": "exact color alpha"},
            "materials": MATERIALS, "layers": authored_layers(identity)}


def convert_color(mother, recipe):
    rgba = np.asarray(mother)
    alpha = rgba[:, :, 3]
    occupied = alpha > 0
    ys, xs = np.where(occupied)
    bbox = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
    bottom_region = (np.indices(alpha.shape)[0] > ys.max() - max(24, (ys.max()-ys.min()) * .13)) & (alpha >= 200)
    _, sole_x = np.where(bottom_region)
    foot_x = (float(sole_x.min()) + float(sole_x.max())) * .5
    crop = mother.crop(bbox)
    scale = min(recipe["target_height"] / crop.height, 220 / crop.width)
    width, height = round(crop.width * scale), round(crop.height * scale)
    resized = crop.resize((width, height), Image.Resampling.NEAREST)
    scale_x, scale_y = width / crop.width, height / crop.height
    offset = [round(recipe["foot_anchor"][0] - (foot_x - bbox[0]) * scale_x), recipe["foot_anchor"][1] - height]
    if offset[0] < 0 or offset[0] + width > 256:
        raise ValueError("horizontal sprite overflow")
    canvas = Image.new("RGBA", (256,256), (0,0,0,0))
    canvas.paste(resized, tuple(offset))
    pixels = np.asarray(canvas).copy()
    visible = pixels[:,:,3] > 0
    strip = Image.fromarray(pixels[visible,:3].reshape(1,-1,3), "RGB")
    palette = strip.quantize(colors=recipe["palette_size"], method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    color = canvas.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB")
    colored = np.asarray(color).copy()
    colored[~visible] = 0
    pixels[:,:,:3] = colored
    transform = {"crop_xyxy": bbox, "scaled_size": [width,height], "offset_xy": offset,
                 "scale_xy": [scale_x,scale_y], "source_foot_x": foot_x, "filter": "nearest", "dither": False}
    return Image.fromarray(pixels, "RGBA"), transform


def draw_maps(mother, color, transform, recipe):
    yy, xx = np.indices((256,256), dtype=np.float64)
    u = ((xx-transform["offset_xy"][0]+.5)/transform["scale_xy"][0]+transform["crop_xyxy"][0]) / mother.width
    v = ((yy-transform["offset_xy"][1]+.5)/transform["scale_xy"][1]+transform["crop_xyxy"][1]) / mother.height
    normals = np.zeros((256,256,3), dtype=np.float64)
    normals[:,:,2] = 1.0
    material = np.zeros((256,256,3), dtype=np.float64)
    material[:] = recipe["materials"]["cloth"]
    for layer in recipe["layers"]:
        if layer["kind"] == "fold":
            distance = np.full((256,256), np.inf)
            sign = np.zeros_like(distance)
            for first, last in zip(layer["points"][:-1],layer["points"][1:]):
                a, b = np.array(first), np.array(last)
                segment = b-a
                t = np.clip(((u-a[0])*segment[0]+(v-a[1])*segment[1]) / float(segment@segment), 0, 1)
                dx, dy = u-(a[0]+t*segment[0]), v-(a[1]+t*segment[1])
                local = np.sqrt(dx*dx+dy*dy)
                nearer = local < distance
                sign[nearer] = np.sign(dx*segment[1]-dy*segment[0])[nearer]
                distance[nearer] = local[nearer]
            mask = distance < layer["width"]
            normals[:,:,0][mask] += (np.sin(distance/layer["width"]*np.pi)*sign*layer["strength"])[mask]
            continue
        cx, cy = layer["center"]
        rx, ry = layer["radii"]
        ex, ey = (u-cx)/rx, (v-cy)/ry
        if layer.get("polygon"):
            mask_image = Image.new("L", (256,256))
            draw = ImageDraw.Draw(mask_image)
            polygon = [[round((x*mother.width-transform["crop_xyxy"][0])*transform["scale_xy"][0]+transform["offset_xy"][0]),
                        round((y*mother.height-transform["crop_xyxy"][1])*transform["scale_xy"][1]+transform["offset_xy"][1])] for x,y in layer["polygon"]]
            draw.polygon(polygon, fill=255)
            mask = np.asarray(mask_image) > 0
        else:
            mask = ex*ex+ey*ey <= 1.0
        sx, sy = layer["slope"]
        nx, ny = np.clip(ex, -1, 1)*sx, -np.clip(ey, -1, 1)*sy
        if layer["material"] == "straw":
            nx += .055*np.sin(u*250)
            ny += .035*np.sin(v*290)
        nz = np.sqrt(np.maximum(.12, 1-nx*nx-ny*ny))
        normals[mask] = np.stack([nx,ny,nz], axis=2)[mask]
        material[mask] = recipe["materials"][layer["material"]]
    normals /= np.maximum(np.linalg.norm(normals,axis=2,keepdims=True), 1e-12)
    alpha = np.asarray(color)[:,:,3]
    normal_png = np.zeros((256,256,4), dtype=np.uint8)
    normal_png[:,:,:3] = np.rint((normals+1)*127.5).astype(np.uint8)
    normal_png[:,:,3] = alpha
    normal_png[alpha==0,:3] = [128,128,255]
    mask_png = np.zeros_like(normal_png)
    mask_png[:,:,:3] = np.rint(np.clip(material,0,1)*255).astype(np.uint8)
    mask_png[:,:,3] = alpha
    mask_png[alpha==0,:3] = 0
    return Image.fromarray(normal_png, "RGBA"), Image.fromarray(mask_png, "RGBA")


def build(identity):
    source_dir = SOURCE / identity
    structure_path = source_dir / "structure.json"
    if not structure_path.exists():
        structure_path.write_text(json.dumps(source_recipe(identity),indent=2)+"\n")
    recipe = json.loads(structure_path.read_text())
    mother_path = source_dir / "mother.png"
    mother = Image.open(mother_path).convert("RGBA")
    color, transform = convert_color(mother,recipe)
    normal, mask = draw_maps(mother,color,transform,recipe)
    DEST.mkdir(parents=True, exist_ok=True)
    outputs = []
    for suffix, image in [("",color),("-normal",normal),("-mask",mask)]:
        path = DEST / (identity+suffix+".png")
        image.save(path)
        outputs.append({"path":path.relative_to(ROOT).as_posix(),"sha256":sha(path),"size":list(image.size)})
    pixels = np.asarray(color)
    visible = pixels[:,:,3] > 0
    decoded = np.asarray(normal)[:,:,:3].astype(np.float64)/127.5-1
    vector_error = abs(np.linalg.norm(decoded[visible],axis=1)-1)
    checks = {"color_palette_count":int(len(np.unique(pixels[visible,:3],axis=0))),
              "color_alpha_equals_normal":bool(np.array_equal(pixels[:,:,3],np.asarray(normal)[:,:,3])),
              "color_alpha_equals_mask":bool(np.array_equal(pixels[:,:,3],np.asarray(mask)[:,:,3])),
              "normal_vector_max_length_error":float(vector_error.max()),
              "silhouette_bbox":list(color.getbbox()), "foot_anchor":[128,240]}
    if checks["color_palette_count"] > 96 or vector_error.max() > .015 or not checks["color_alpha_equals_normal"] or not checks["color_alpha_equals_mask"]:
        raise ValueError("NPC data verification failed")
    (source_dir / "transform.json").write_text(json.dumps(transform,indent=2)+"\n")
    record = {"id":identity, "source":{"path":mother_path.relative_to(ROOT).as_posix(),"sha256":sha(mother_path)},
              "structure":{"path":structure_path.relative_to(ROOT).as_posix(),"sha256":sha(structure_path)},
              "outputs":outputs, "checks":checks, "mask_channels":recipe["mask_channels"]}
    (source_dir / "build.json").write_text(json.dumps(record,indent=2)+"\n")
    preview = Image.new("RGBA", (768,256),(42,48,61,255))
    for index,image in enumerate([color,normal,mask]):
        preview.alpha_composite(image,(256*index,0))
    preview.resize((1536,512),Image.Resampling.NEAREST).save(source_dir / "preview.png")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--npc", choices=IDS)
    args = parser.parse_args()
    records = [build(identity) for identity in ([args.npc] if args.npc else IDS)]
    if not args.npc:
        manifest = {"schema_version":1, "characters":records, "stationary_only":True,
                    "pivot_px":[128,240], "pixel_size":.009, "builder":"tools/ancient_canal/build_npcs.py"}
        (SOURCE / "manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    print(json.dumps({"npcs":[record["id"] for record in records],"checks":[record["checks"] for record in records]}))


if __name__ == "__main__":
    main()
