#!/usr/bin/env python3
"""Draw semantic geometric normals without reading diffuse values as height.

RGB is used only for motion correspondence and material/occlusion masks. All
surface vectors come from editable ellipsoids, braid tubes, fabric pleats and
metal volumes. The existing 108 color files are immutable build inputs.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source/ancient-canal/character-normals"
OUTPUT = ROOT / "assets/ancient-canal/character-normals/v1"
BASELINE = ROOT / "art_source/ancient-canal/character-reuse.json"
SIZE = 256
YY, XX = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
GRID = np.stack((XX, YY), axis=-1)
LAYERS = {"face": 1, "hair": 2, "braids": 3, "cloth": 4, "skirt": 5, "metal": 6, "boots": 7}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def unit(v: np.ndarray) -> np.ndarray:
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-8)


def rgba(v: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    result = np.empty((SIZE, SIZE, 4), dtype=np.uint8)
    result[..., :3] = np.rint(np.clip(v * 0.5 + 0.5, 0, 1) * 255).astype(np.uint8)
    result[..., 3] = alpha
    result[alpha == 0, :3] = (128, 128, 255)
    return result


def authored_rig(direction: str) -> dict:
    """Hand-drawn frame-0 coordinates, in original sprite pixels.

    These are geometric interpretations of the four viewed color key boards
    and ImageGen sculpting candidates. Front/back and the two distinct quarter
    views have separate annotations; neither left nor up is a mirrored normal.
    """
    rigs = {
        "down": {
            "face": [130, 77, 12, 13], "face_yaw": 0.06,
            "head": [125, 59, 28, 28], "torso": [129, 106, 17, 18],
            "braids": [[[110, 82], [103, 94], [96, 104], [90, 114], [81, 129]], [[145, 81], [151, 93], [160, 106], [169, 119], [174, 128]]],
            "strands": [[[102, 62], [108, 47], [129, 40]], [[110, 58], [128, 46], [145, 56]], [[131, 45], [137, 59], [129, 70]], [[142, 48], [149, 61], [148, 76]], [[108, 62], [111, 77], [107, 87]]],
            "sleeves": [[[113, 98], [108, 115], [102, 131]], [[145, 100], [151, 116], [157, 129]]],
            "skirt": [129, 155, 40, 34], "belt": [129, 121],
            "pleats": [[[109, 127], [103, 150], [92, 170]], [[118, 126], [114, 157], [113, 185]], [[130, 127], [131, 157], [133, 184]], [[139, 128], [147, 153], [153, 177]], [[146, 133], [155, 151], [167, 168]]],
            "apron": [133, 151, 11, 28],
            "metal_regions": [[112, 37, 15, 17], [104, 53, 4, 8], [105, 76, 4, 7], [129, 100, 14, 12], [130, 127, 8, 13], [88, 115, 6, 9], [167, 115, 6, 9], [102, 139, 5, 5], [160, 138, 5, 5], [116, 193, 4, 8], [143, 203, 4, 8]],
            "legs": [[[124, 183], [121, 203], [122, 215]], [[134, 190], [134, 219], [136, 233]]],
        },
        "up": {
            "face": None, "face_yaw": 0.0,
            "head": [120, 61, 28, 29], "torso": [128, 103, 18, 19],
            "braids": [[[111, 77], [106, 89], [99, 101], [91, 113], [85, 128]], [[139, 79], [149, 93], [156, 104], [164, 115], [172, 125]]],
            "strands": [[[97, 63], [106, 44], [121, 35]], [[112, 40], [119, 62], [115, 78]], [[123, 37], [128, 57], [126, 78]], [[133, 41], [140, 61], [135, 80]], [[100, 54], [100, 70], [105, 81]]],
            "sleeves": [[[112, 96], [107, 115], [102, 128]], [[144, 96], [150, 116], [156, 129]]],
            "skirt": [128, 156, 40, 31], "belt": [128, 116],
            "pleats": [[[112, 125], [106, 151], [94, 173]], [[121, 124], [119, 152], [119, 177]], [[131, 125], [134, 152], [138, 184]], [[140, 126], [148, 153], [157, 176]], [[147, 132], [156, 151], [168, 169]]],
            "apron": None,
            "metal_regions": [[141, 35, 12, 15], [144, 53, 4, 8], [143, 74, 4, 7], [126, 84, 13, 4], [94, 112, 5, 9], [163, 113, 5, 9], [98, 140, 5, 5], [160, 137, 5, 5], [113, 193, 4, 8], [140, 197, 4, 8]],
            "legs": [[[121, 182], [119, 199], [121, 215]], [[130, 184], [129, 213], [128, 231]]],
        },
        "left": {
            "face": [111, 76, 11, 13], "face_yaw": -0.23,
            "head": [118, 60, 30, 27], "torso": [121, 107, 20, 18],
            "braids": [[[106, 80], [101, 92], [96, 104], [85, 114], [80, 128]], [[136, 83], [151, 92], [163, 102], [173, 115], [179, 129]]],
            "strands": [[[91, 61], [103, 43], [123, 38]], [[106, 44], [110, 62], [113, 80]], [[121, 43], [133, 57], [140, 72]], [[135, 42], [146, 52], [143, 74]], [[96, 48], [99, 67], [98, 78]]],
            "sleeves": [[[106, 106], [94, 123], [88, 132]], [[135, 99], [145, 122], [152, 139]]],
            "skirt": [129, 155, 46, 40], "belt": [117, 122],
            "pleats": [[[105, 130], [97, 157], [89, 179]], [[115, 128], [112, 156], [110, 191]], [[123, 126], [134, 160], [143, 181]], [[131, 129], [153, 155], [165, 174]], [[137, 134], [158, 151], [174, 163]]],
            "apron": [109, 149, 11, 28],
            "metal_regions": [[135, 39, 14, 18], [140, 52, 4, 8], [139, 78, 5, 8], [112, 100, 13, 13], [112, 128, 8, 14], [86, 117, 6, 10], [165, 116, 6, 10], [83, 140, 5, 5], [160, 147, 5, 5], [111, 206, 4, 8], [153, 192, 5, 9]],
            "legs": [[[108, 188], [99, 208], [87, 229]], [[145, 180], [156, 207], [159, 225]]],
        },
        "right": {
            "face": [139, 77, 12, 13], "face_yaw": 0.23,
            "head": [127, 59, 28, 27], "torso": [135, 109, 20, 18],
            "braids": [[[113, 81], [103, 94], [98, 105], [90, 116], [80, 127]], [[142, 84], [151, 96], [159, 109], [165, 121], [172, 128]]],
            "strands": [[[107, 60], [112, 44], [128, 36]], [[116, 42], [133, 48], [145, 59]], [[136, 48], [137, 65], [131, 78]], [[147, 48], [154, 63], [153, 76]], [[109, 63], [110, 76], [104, 83]]],
            "sleeves": [[[117, 101], [108, 121], [101, 136]], [[150, 107], [158, 126], [166, 139]]],
            "skirt": [124, 155, 44, 41], "belt": [137, 120],
            "pleats": [[[110, 130], [95, 155], [86, 171]], [[120, 127], [111, 163], [108, 190]], [[130, 125], [129, 164], [131, 194]], [[140, 126], [146, 159], [148, 187]], [[146, 131], [158, 157], [166, 178]]],
            "apron": [145, 150, 11, 30],
            "metal_regions": [[112, 34, 14, 15], [103, 50, 4, 8], [104, 73, 4, 7], [136, 97, 14, 12], [142, 126, 8, 14], [88, 114, 6, 10], [163, 116, 5, 8], [95, 145, 5, 5], [170, 142, 5, 5], [96, 194, 5, 8], [147, 205, 4, 8]],
            "legs": [[[109, 185], [96, 208], [89, 219]], [[142, 186], [147, 211], [157, 233]]],
        },
    }
    rig = rigs[direction]
    rig.update(direction=direction, frame=0, size=[256, 256], geometry_source="hand-authored visible form annotations assisted by ImageGen construction studies")
    return rig


def optical_flow(frames: list[np.ndarray]) -> tuple[list[np.ndarray], list[np.ndarray]]:
    """Diffuse channels are correspondence features only, never elevation."""
    grays = []
    for im in frames:
        g = cv2.cvtColor(im[..., :3], cv2.COLOR_RGB2GRAY)
        g[im[..., 3] == 0] = 0
        grays.append(g)
    forward, backward = [], []
    for i, gray in enumerate(grays):
        other = grays[(i + 1) % len(grays)]
        forward.append(cv2.calcOpticalFlowFarneback(gray, other, None, 0.5, 4, 17, 4, 7, 1.5, 0))
        backward.append(cv2.calcOpticalFlowFarneback(other, gray, None, 0.5, 4, 17, 4, 7, 1.5, 0))
    return forward, backward


def sample_flow(flow: np.ndarray, point: list[float]) -> np.ndarray:
    # Local median is stable on narrow braid segments and tassels.
    x, y = np.rint(point).astype(int)
    x, y = np.clip(x, 2, 253), np.clip(y, 2, 253)
    return np.median(flow[y - 2:y + 3, x - 2:x + 3].reshape(-1, 2), axis=0)


def warp_rig(rig: dict, flow: np.ndarray, frame: int) -> dict:
    output = copy.deepcopy(rig)
    for name in ("head", "face", "torso", "skirt", "apron"):
        if output[name] is not None:
            point = output[name][:2]
            output[name][:2] = (np.asarray(point) + sample_flow(flow, point)).round(4).tolist()
    output["belt"] = (np.asarray(output["belt"]) + sample_flow(flow, output["belt"])).round(4).tolist()
    for name in ("braids", "strands", "sleeves", "pleats", "legs"):
        for line in output[name]:
            for i, point in enumerate(line):
                line[i] = (np.asarray(point) + sample_flow(flow, point)).round(4).tolist()
    for rect in output["metal_regions"]:
        rect[:2] = (np.asarray(rect[:2]) + sample_flow(flow, rect[:2])).round(4).tolist()
    output["frame"] = frame
    return output


def cyclic_rigs(initial: dict, forward: list[np.ndarray], backward: list[np.ndarray]) -> list[dict]:
    """Anchor both ends to frame 0 and blend independent flow trajectories.

    Forward-only accumulation drifts at the loop seam, especially where the
    feet cross. This symmetric transport uses the actual last-to-first flow
    correspondence and preserves a seamless geometric annotation trajectory.
    """
    count=len(forward)
    front=[copy.deepcopy(initial)]
    for i in range(1,count):front.append(warp_rig(front[-1],forward[i-1],i))
    back=[None]*count;current=copy.deepcopy(initial)
    for i in reversed(range(1,count)):
        current=warp_rig(current,backward[i],i)
        back[i]=current
    back[0]=copy.deepcopy(initial)
    result=[]
    names=("head","face","torso","skirt","apron","belt","braids","strands","sleeves","pleats","legs","metal_regions")
    for i in range(count):
        weight=i/count
        geometry=copy.deepcopy(front[i])
        for name in names:
            if geometry[name] is not None:
                a=np.asarray(front[i][name]);b=np.asarray(back[i][name])
                geometry[name]=((1-weight)*a+weight*b).round(4).tolist()
        geometry["motion_transport"]={"method":"cyclic forward/backward anchored blend","forward_weight":round(1-weight,6),"backward_weight":round(weight,6)}
        result.append(geometry)
    return result


def ellipse_region(spec: list[float], scale=1.0) -> np.ndarray:
    cx, cy, rx, ry = spec
    return ((XX - cx) / (rx * scale)) ** 2 + ((YY - cy) / (ry * scale)) ** 2 <= 1


def tube_geometry(points: list[list[float]], radius: float, amplitude=0.72, braid=False) -> tuple[np.ndarray, np.ndarray]:
    """Analytic cylinder following the drawn polyline, optionally braided."""
    distance2 = np.full((SIZE, SIZE), np.inf, np.float32)
    radial = np.zeros((SIZE, SIZE, 2), np.float32)
    station = np.zeros((SIZE, SIZE), np.float32)
    arc = 0.0
    for pa, pb in zip(points, points[1:]):
        a, b = np.array(pa, np.float32), np.array(pb, np.float32)
        axis = b - a
        length = max(float(np.linalg.norm(axis)), 0.1)
        t = np.clip(((GRID - a) * axis).sum(-1) / (length * length), 0, 1)
        q = a + t[..., None] * axis
        delta = GRID - q
        d2 = (delta * delta).sum(-1)
        pick = d2 < distance2
        distance2[pick] = d2[pick]
        radial[pick] = delta[pick] / radius
        station[pick] = arc + t[pick] * length
        arc += length
    xy = radial * amplitude
    if braid:
        phase = station * (2 * math.pi / 9.0)
        xy[..., 0] += np.sin(phase) * 0.18
        xy[..., 1] += np.cos(phase) * 0.12
    xy[..., 1] *= -1  # original image Y grows down, tangent Y points up.
    z = np.sqrt(np.maximum(0.16, 1 - (xy * xy).sum(-1)))
    n = unit(np.dstack((xy, z)))
    return distance2 <= (radius * 1.45) ** 2, n


def ellipsoid(spec: list[float], slope=0.65, yaw=0.0) -> np.ndarray:
    cx, cy, rx, ry = spec
    x = np.clip((XX - cx) / rx, -1.15, 1.15) * slope + yaw
    y = np.clip(-(YY - cy) / ry, -1.15, 1.15) * slope
    z = np.sqrt(np.maximum(0.22, 1 - x*x - y*y))
    return unit(np.dstack((x, y, z)))


def material_classes(im: np.ndarray, rig: dict) -> tuple[np.ndarray, np.ndarray]:
    """Recognize material identities, then apply drawn occlusion regions.

    Channel thresholds never set normal magnitude. White skirt embroidery is
    cloth; white crescent/tassels in explicitly annotated jewelry ROIs is metal.
    """
    visible = im[..., 3] > 0
    r, g, b = [im[..., i].astype(float) for i in range(3)]
    skin = skin_pixels(im, rig)
    red = visible & (r > 40) & (r > g*1.38) & (r > b*1.10) & ~skin
    blue = visible & (b-r > 7) & (b-g > 2)
    labels = np.full((SIZE, SIZE), LAYERS["cloth"], dtype=np.uint8)
    labels[(YY > rig["belt"][1] + 3) & (YY < 196)] = LAYERS["skirt"]
    labels[YY >= 192] = LAYERS["boots"]
    hair_region = ellipse_region(rig["head"], 1.20)
    braid_region = np.zeros((SIZE, SIZE), bool)
    for line in rig["braids"]:
        mask, _ = tube_geometry(line, 8.0)
        braid_region |= mask
    dark_neutral = ~blue & ~red & ~skin
    labels[hair_region & dark_neutral] = LAYERS["hair"]
    labels[braid_region & ~hair_region & dark_neutral] = LAYERS["braids"]
    labels[skin] = LAYERS["face"]
    # Eyes, mouth ink and fine facial outlines share cheek geometry. Preserve
    # bangs as hair; fill only the convex exposed lower-face skin region.
    if rig["face"] is not None:
        face_skin = skin & ellipse_region(rig["face"], 1.5)
        ys,xs=np.where(face_skin)
        if xs.size>15:
            hull=cv2.convexHull(np.stack((xs,ys),axis=-1).astype(np.int32))
            face_region=np.zeros((SIZE,SIZE),np.uint8);cv2.fillConvexPoly(face_region,hull,1)
            face_region=(face_region>0)&(YY>=rig["face"][1]-7)&visible
            labels[face_region]=LAYERS["face"]
    if rig["apron"] is not None:
        labels[ellipse_region(rig["apron"], 1.3) & blue] = LAYERS["cloth"]
    silver = (np.maximum.reduce([r,g,b]) - np.minimum.reduce([r,g,b]) < 34) & (r > 108) & ~skin & visible
    jewelry_region = np.zeros((SIZE, SIZE), bool)
    for spec in rig["metal_regions"]:
        jewelry_region |= ellipse_region(spec, 1.12)
    silver &= jewelry_region
    # Include a one-pixel silver outline only inside the annotated material ROIs.
    expanded = cv2.dilate(silver.astype(np.uint8), np.ones((3,3), np.uint8)) > 0
    labels[expanded & jewelry_region & dark_neutral & visible] = LAYERS["metal"]
    labels[silver] = LAYERS["metal"]
    labels[~visible] = 0
    return labels, silver


def skin_pixels(im: np.ndarray, rig: dict) -> np.ndarray:
    """Skin material constrained to exposed head/neck and two hand forms.

    Rose skirt embroidery can share skin RGB palette values, so global color
    segmentation is insufficient. The hand regions follow the sleeve axes.
    """
    r,g,b=[im[...,i].astype(float) for i in range(3)]
    identity=(im[...,3]>0)&(r>140)&(r-g>18)&(g-b>3)&(g>75)
    region=np.zeros((SIZE,SIZE),bool)
    if rig["face"] is not None:
        region|=ellipse_region(rig["face"],1.6)
        cx,cy,rx,ry=rig["face"]
        region|=ellipse_region([cx,cy+15,10,10],1.0)
    else:
        cx,cy,rx,ry=rig["head"]
        region|=ellipse_region([cx+5,cy+23,12,8],1.0)
    for line in rig["sleeves"]:
        a,b=np.array(line[-2]),np.array(line[-1]);axis=b-a
        axis=axis/max(float(np.linalg.norm(axis)),1.0)
        center=b+axis*12
        region|=ellipse_region([*center,10,15],1.0)
    return identity&region


def correct_rig(rig: dict, im: np.ndarray) -> tuple[dict, list[dict]]:
    """Per-frame skin and jewelry alignment corrections after flow transport."""
    out = copy.deepcopy(rig)
    records = []
    r, g, b = [im[..., i].astype(float) for i in range(3)]
    visible = im[..., 3] > 0
    skin = skin_pixels(im, out)
    if out["face"]:
        target = skin & ellipse_region(out["face"], 1.8)
        ys, xs = np.where(target)
        if xs.size > 15:
            # The actual exposed cheek mask changes with bangs and direction.
            center = [float((xs.min()+xs.max())/2), float((ys.min()+ys.max())/2)]
            old = out["face"][:2]
            out["face"][:2] = center
            out["face"][2:] = [max(7.0,float((xs.max()-xs.min())/2)+2),max(8.0,float((ys.max()-ys.min())/2)+2)]
            records.append({"feature":"face","method":"visible skin bounds in transported face ROI","before":old,"after":center,"pixels":int(xs.size)})
    # Correct each silver ornament independently. This follows dangling tassels
    # that move relative to the torso instead of locking them to a body ellipse.
    silver = visible & (np.maximum.reduce([r,g,b])-np.minimum.reduce([r,g,b]) < 34) & (r>108) & ~skin
    for i, spec in enumerate(out["metal_regions"]):
        local = silver & ellipse_region(spec, 1.4)
        ys,xs=np.where(local)
        if xs.size >= 3:
            old=spec[:2]
            center=[float(np.median(xs)),float(np.median(ys))]
            # Small bounded correction prevents a cuff snapping to a sleeve edge.
            delta=np.clip(np.array(center)-np.array(old),-3.0,3.0)
            spec[:2]=(np.array(old)+delta).round(4).tolist()
            records.append({"feature":"silver_"+str(i),"method":"local visible material centroid, capped 3px","before":old,"after":spec[:2],"pixels":int(xs.size)})
    out["corrections"] = records
    return out,records


def draw_surfaces(im: np.ndarray, rig: dict) -> tuple[np.ndarray,np.ndarray,np.ndarray,dict]:
    labels,silver=material_classes(im,rig)
    n=np.zeros((SIZE,SIZE,3),np.float32);n[...,2]=1
    # Torso and hanging textile are broad fabric forms with mild curvature.
    cloth=ellipsoid(rig["torso"],0.37,yaw=rig["face_yaw"]*0.25)
    for line in rig["sleeves"]:
        area,surface=tube_geometry(line,12.0,0.56)
        cloth[area]=surface[area]
    if rig["apron"]:
        area=ellipse_region(rig["apron"],1.5)
        spec=rig["apron"]
        # Embroidery does not become height; cloth bends independently.
        apron=ellipsoid(spec,0.24)
        cloth[area]=apron[area]
    n[labels==LAYERS["cloth"]]=cloth[labels==LAYERS["cloth"]]
    # Hair has separate broad curved strands, not diffuse highlight ridges.
    hair=ellipsoid(rig["head"],0.53,rig["face_yaw"]*0.4)
    for line in rig["strands"]:
        area,surface=tube_geometry(line,5.5,0.45)
        hair[area]=surface[area]
    n[labels==LAYERS["hair"]]=hair[labels==LAYERS["hair"]]
    braid=hair.copy()
    for line in rig["braids"]:
        area,surface=tube_geometry(line,5.0,0.7,True)
        braid[area]=surface[area]
    n[labels==LAYERS["braids"]]=braid[labels==LAYERS["braids"]]
    # Convex pleats fan from waist toward the actual hem. These curves travel
    # with the skirt flow; fixed screen-space sine stripes are never used.
    skirt=ellipsoid(rig["skirt"],0.48)
    for line in rig["pleats"]:
        area,surface=tube_geometry(line,6.0,0.56)
        skirt[area]=surface[area]
    n[labels==LAYERS["skirt"]]=skirt[labels==LAYERS["skirt"]]
    # Each exposed skin island is its own ellipsoid. Hands can separate from
    # the body and cannot inherit head normals from a global silhouette.
    count, islands, stats, _ = cv2.connectedComponentsWithStats((labels==LAYERS["face"]).astype(np.uint8),8)
    face=np.zeros_like(n);face[...,2]=1
    for island in range(1,count):
        x,y,w,h,area=stats[island]
        if area<2:continue
        spec=[x+(w-1)/2,y+(h-1)/2,max(3,w*.62),max(3,h*.62)]
        yaw=rig["face_yaw"] if y<100 else 0.0
        surface=ellipsoid(spec,0.62,yaw)
        if y<100 and rig["face"]:
            surface=ellipsoid(rig["face"],0.59,yaw)
            # A separately authored short nose volume, aligned to the face.
            cx,cy,rx,ry=rig["face"]
            nose=[cx+yaw*18,cy+1.5,2.3,3.0]
            nose_area=ellipse_region(nose,1.0)
            nose_surface=ellipsoid(nose,0.42,yaw)
            surface[nose_area]=nose_surface[nose_area]
        pick=islands==island
        face[pick]=surface[pick]
    n[labels==LAYERS["face"]]=face[labels==LAYERS["face"]]
    boots=np.zeros_like(n);boots[...,2]=1
    for line in rig["legs"]:
        area,surface=tube_geometry(line,6.5,0.61)
        boots[area]=surface[area]
    # Crossing feet can defeat dense correspondence. Repair each currently
    # visible boot island using its drawn silhouette principal axis. This is
    # geometry from the alpha/material boundary, not a brightness-to-height map.
    count,islands,stats,_=cv2.connectedComponentsWithStats((labels==LAYERS["boots"]).astype(np.uint8),8)
    for island in range(1,count):
        pick=islands==island
        ys,xs=np.where(pick)
        if xs.size<12:continue
        points=np.stack((xs,ys),axis=-1).astype(float)
        center=points.mean(0)
        covariance=np.cov((points-center).T)
        values,basis=np.linalg.eigh(covariance)
        along=basis[:,np.argmax(values)];across=np.array([-along[1],along[0]])
        offsets=GRID-center
        axial=(offsets*along).sum(-1)
        lateral=(offsets*across).sum(-1)
        span=max(4,float(np.quantile(np.abs((points-center)@across),.95)))
        length=max(5,float(np.quantile(np.abs((points-center)@along),.95)))
        xy=(lateral[...,None]/span)*across*.62+(axial[...,None]/length)*along*.16
        xy[...,1]*=-1
        z=np.sqrt(np.maximum(.2,1-(xy*xy).sum(-1)))
        surface=unit(np.dstack((xy,z)))
        boots[pick]=surface[pick]
    n[labels==LAYERS["boots"]]=boots[labels==LAYERS["boots"]]
    metal=np.zeros_like(n);metal[...,2]=1
    # Independent crescent, collar and pendant volumes are selected by the
    # authored ROIs, then fine tassels receive their own local convex faces.
    for spec in rig["metal_regions"]:
        area=ellipse_region(spec,1.3)
        surface=ellipsoid(spec,0.68)
        metal[area]=surface[area]
    count,islands,stats,_=cv2.connectedComponentsWithStats(silver.astype(np.uint8),8)
    for island in range(1,count):
        x,y,w,h,area=stats[island]
        # Do not replace the crescent or wide neckpiece with tiny pixel islands.
        if area<3 or w>16 or h>20:continue
        spec=[x+(w-1)/2,y+(h-1)/2,max(2,w*.65),max(2,h*.6)]
        surface=ellipsoid(spec,0.68)
        pick=(islands==island)
        metal[pick]=surface[pick]
    n[labels==LAYERS["metal"]]=metal[labels==LAYERS["metal"]]
    n=unit(n)
    normal=rgba(n,im[...,3])
    # Silver highlight is a material mask, never multiplied into normal RGB.
    mask=np.zeros_like(im);mask[...,:3]=silver[...,None]*255;mask[...,3]=im[...,3]
    layers={}
    for name,index in LAYERS.items():
        layers[name]=rgba(n,np.where(labels==index,im[...,3],0).astype(np.uint8))
    return normal,mask,labels,layers


def atlas_pair(source_atlas: np.ndarray, frames: list[np.ndarray], regions: list[list[int]]) -> np.ndarray:
    atlas=np.zeros_like(source_atlas);atlas[...,:3]=(128,128,255)
    for im,(x,y,w,h) in zip(frames,regions):
        # Repeat the exact one-pixel gutter used by the immutable color atlas.
        padded=np.pad(im,((1,1),(1,1),(0,0)),mode="edge")
        atlas[y-1:y+h+1,x-1:x+w+1]=padded
    atlas[...,3]=source_atlas[...,3]
    return atlas


def make_review(direction: str, frames: list[np.ndarray], normals: list[np.ndarray], masks: list[np.ndarray], idle: int, durations: list[int]) -> None:
    output=SOURCE/"review";output.mkdir(parents=True,exist_ok=True)
    keys=[0,6,13,20,26,idle]
    board=Image.new("RGBA",(6*256,4*280),(33,38,43,255));draw=ImageDraw.Draw(board)
    light=unit(np.array([-0.65,0.50,0.6],np.float32))
    for col,index in enumerate(keys):
        for row,im in enumerate((frames[index],normals[index],masks[index])):
            board.alpha_composite(Image.fromarray(im),(col*256,row*280+24))
            draw.text((col*256+6,row*280+6),f"{direction} frame {index} / "+["color","normal","silver"][row],fill="white")
        normal=normals[index][...,:3].astype(float)/127.5-1
        illumination=0.20+0.8*np.maximum((normal*light).sum(-1),0)
        clay=np.empty_like(normals[index]);clay[...,:3]=np.clip(illumination[...,None]*np.array([185,184,178]),0,255).astype(np.uint8);clay[...,3]=normals[index][...,3]
        board.alpha_composite(Image.fromarray(clay),(col*256,3*280+24));draw.text((col*256+6,3*280+6),"analytic clay / left-top light",fill="white")
    board.save(output/(direction+"-key-gallery.png"))
    # Three complete source loops plus continuous rotating light, original timing.
    loop=[]
    for cycle in range(3):
        for index,normal in enumerate(normals):
            angle=(cycle+index/len(normals))*2*math.pi/3
            lamp=unit(np.array([math.cos(angle),math.sin(angle),.65]))
            n=unit(normal[...,:3].astype(float)/127.5-1)
            brightness=.17+.83*np.maximum((n*lamp).sum(-1),0)
            clay=np.empty_like(normal);clay[...,:3]=np.clip(brightness[...,None]*np.array([205,204,198]),0,255).astype(np.uint8);clay[...,3]=normal[...,3]
            canvas=Image.new("RGBA",(768,288),(35,40,46,255));canvas.alpha_composite(Image.fromarray(frames[index]),(0,24));canvas.alpha_composite(Image.fromarray(normal),(256,24));canvas.alpha_composite(Image.fromarray(clay),(512,24))
            ImageDraw.Draw(canvas).text((8,6),f"{direction} frame {index:02} / color - normal - clay sweep / original timing",fill="white")
            loop.append(canvas.convert("RGB"))
    loop[0].save(output/(direction+"-three-loops.gif"),save_all=True,append_images=loop[1:],duration=durations*3,loop=0,disposal=2)


def build(use_geometry_edits=False, use_painted_layers=False) -> dict:
    baseline=json.loads(BASELINE.read_text())
    SOURCE.mkdir(parents=True,exist_ok=True);OUTPUT.mkdir(parents=True,exist_ok=True)
    manifest={"schema_version":1,"character_id":"crescent-traveler","version":"v1","frame_count":108,"size":[256,256],"pivot":[128,240],"normal_convention":{"x":"right","y":"up","z":"toward viewer","encoding":"linear RGB = vector * 0.5 + 0.5","vector_source":"analytic semantic geometry, not diffuse luminance","alpha":"exact immutable color alpha"},"baseline":relative(BASELINE),"baseline_sha256":digest(BASELINE),"directions":{}}
    for entry in baseline["directions"]:
        direction=entry["direction"]
        color_manifest_path=ROOT/entry["manifest"]
        color_manifest=json.loads(color_manifest_path.read_text())
        assert digest(color_manifest_path)==entry["manifest_sha256"],"source timing manifest changed"
        colors=[]
        for frame in entry["frames"]:
            path=ROOT/frame["path"];assert digest(path)==frame["sha256"],f"source color changed: {path}"
            colors.append(np.array(Image.open(path).convert("RGBA")))
        original_atlas_path=color_manifest_path.parent/color_manifest["atlas"]
        assert digest(original_atlas_path)==entry["atlas_sha256"]
        original_atlas=np.array(Image.open(original_atlas_path).convert("RGBA"))
        forward,backward=optical_flow(colors)
        motions=SOURCE/"motion"/(direction+".npz");motions.parent.mkdir(parents=True,exist_ok=True)
        np.savez_compressed(motions,forward=np.stack(forward).astype(np.float16),backward=np.stack(backward).astype(np.float16),method=np.array("Farneback correspondence only; no normal-from-color inference"))
        rig=authored_rig(direction)
        write_json(SOURCE/"authored"/(direction+"-frame-0.json"),rig)
        transported=[]
        cyclic=cyclic_rigs(rig,forward,backward)
        for i,(color,tracked) in enumerate(zip(colors,cyclic)):
            corrected,records=correct_rig(tracked,color)
            transported.append(corrected)
            # Keep the transported geometry separate from bounded local material
            # corrections, so a blinking ornament cannot accumulate torso drift.
        keys=sorted(set([0,6,13,20,26,entry["idle_frame"]]))
        for i in keys:
            write_json(SOURCE/"keyposes"/direction/f"{i:05}.json",transported[i])
        normal_frames=[];mask_frames=[];frame_records=[];correction_records=[]
        d_out=OUTPUT/direction;d_out.mkdir(parents=True,exist_ok=True)
        for i,(color,geometry,frame) in enumerate(zip(colors,transported,entry["frames"])):
            edit_dir=SOURCE/"editable"/direction/f"{i:05}"
            if use_geometry_edits:
                geometry=json.loads((edit_dir/"geometry.json").read_text())
                if i in keys:write_json(SOURCE/"keyposes"/direction/f"{i:05}.json",geometry)
            normal,mask,labels,layers=draw_surfaces(color,geometry)
            if use_painted_layers:
                # The editable PNGs are mutually exclusive semantic normal
                # layers. Recompose painted vectors, then normalize vector data
                # without palette quantization or diffuse color operations.
                combined=np.zeros((SIZE,SIZE,3),np.float32)
                covered=np.zeros((SIZE,SIZE),bool)
                for name in LAYERS:
                    painted=np.array(Image.open(edit_dir/(name+".png")).convert("RGBA"))
                    area=painted[...,3]>0
                    assert not np.any(area&covered),"painted layers overlap; adjust layer alpha"
                    combined[area]=painted[area,:3]/127.5-1
                    covered|=area
                    layers[name]=painted
                assert np.array_equal(covered,color[...,3]>0),"painted layers must preserve the original silhouette"
                normal=rgba(unit(combined),color[...,3])
            frame_path=d_out/"frames"/f"{i:05}.png";frame_path.parent.mkdir(parents=True,exist_ok=True);Image.fromarray(normal).save(frame_path)
            mask_path=d_out/"masks"/f"{i:05}.png";mask_path.parent.mkdir(parents=True,exist_ok=True);Image.fromarray(mask).save(mask_path)
            edit_dir.mkdir(parents=True,exist_ok=True)
            write_json(edit_dir/"geometry.json",geometry);Image.fromarray(labels).save(edit_dir/"semantic-labels.png")
            for name,im in layers.items():Image.fromarray(im).save(edit_dir/(name+".png"))
            normal_frames.append(normal);mask_frames.append(mask)
            correction_records.append({"frame":i,"source_index":frame["source_index"],"corrections":geometry["corrections"],"visible_pixels":int((color[...,3]>0).sum()),"semantic_pixels":{name:int((labels==idx).sum()) for name,idx in LAYERS.items()}})
            frame_records.append({"index":i,"source_index":frame["source_index"],"path":relative(frame_path),"sha256":digest(frame_path),"mask_path":relative(mask_path),"mask_sha256":digest(mask_path),"source_path":frame["path"],"source_sha256":frame["sha256"],"region":frame["region"],"duration_ms":frame["duration_ms"],"editable":relative(edit_dir/"geometry.json")})
        regions=[f["region"] for f in entry["frames"]]
        atlas=atlas_pair(original_atlas,normal_frames,regions)
        mask_atlas=atlas_pair(original_atlas,mask_frames,regions);mask_atlas[mask_atlas[...,3]==0,:3]=0
        atlas_path=d_out/"atlas.png";mask_atlas_path=d_out/"mask-atlas.png"
        Image.fromarray(atlas).save(atlas_path);Image.fromarray(mask_atlas).save(mask_atlas_path)
        write_json(SOURCE/"corrections"/(direction+".json"),correction_records)
        manifest["directions"][direction]={"atlas":relative(atlas_path),"atlas_sha256":digest(atlas_path),"mask_atlas":relative(mask_atlas_path),"mask_atlas_sha256":digest(mask_atlas_path),"source_atlas":relative(original_atlas_path),"source_atlas_sha256":digest(original_atlas_path),"source_manifest":entry["manifest"],"atlas_size":list(Image.open(atlas_path).size),"pivot":entry["pivot"],"idle_frame":entry["idle_frame"],"keyposes":keys,"loop":True,"duration_ms":sum(f["duration_ms"] for f in frame_records),"frames":frame_records}
        make_review(direction,colors,normal_frames,mask_frames,entry["idle_frame"],[f["duration_ms"] for f in entry["frames"]])
        print(direction,len(frame_records),"paired normals, editable layers, motion and atlas")
    write_json(OUTPUT/"manifest.json",manifest)
    write_json(SOURCE/"build-recipe.json",{"schema_version":1,"script":relative(Path(__file__).resolve()),"seed":0,"baseline":relative(BASELINE),"method":"hand-authored semantic analytic geometry; Farneback feature correspondence; per-frame skin/jewelry corrections; exact-alpha compose","normal_RGB":"vector data; no palette, dither, mipmap or color space conversion","imagegen":"four six-keypose volume guides; only a form interpretation source, never resampled into runtime normals","editable_layers":LAYERS,"source_color_policy":"read-only, verify hashes before every build","directions":["down","up","left","right"]})
    return manifest


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--use-geometry-edits",action="store_true",help="Read edited per-frame geometry JSON instead of regenerating it from motion")
    parser.add_argument("--use-painted-layers",action="store_true",help="Recompose manually edited vector-normal PNG layers, preserving alpha")
    args=parser.parse_args()
    build(args.use_geometry_edits,args.use_painted_layers)
