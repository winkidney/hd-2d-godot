"""Verify captured frame bytes, decode complete videos and prepare review sheets."""
from pathlib import Path
import hashlib
import json
import subprocess
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/ancient-canal/horizontal-night-20261008/accepted-render-v2"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    capture = json.loads((OUT / "horizontal-capture.json").read_text())
    assert capture["passed"] and not capture["write_failures"]
    verified = []
    for label, directory in [("route_frames", "route-frames"), ("night_frames", "night-frames")]:
        # Frame directories are recorded by the capture tool, not video FPS slots.
        path = OUT / directory
        for frame in capture[label]:
            assert sha(path / frame["path"]) == frame["sha256"]
        verified.append({"kind": label, "frames": len(capture[label]), "all_original_png_bytes_match": True})
    decodes = []
    sheets = []
    for name, spacing, columns in [("route", 7, 3), ("night", 3, 3)]:
        result = subprocess.run(["ffmpeg", "-v", "error", "-threads", "2", "-i", str(OUT / (name + ".mp4")),
                                 "-f", "null", "-"], capture_output=True, text=True)
        assert result.returncode == 0 and not result.stderr, result.stderr
        decodes.append({"video": name + ".mp4", "sha256": sha(OUT / (name + ".mp4")), "returncode": result.returncode,
                        "error_output_empty": True, "scope": "Decode the entire encoded stream"})
        target = OUT / (name + "-contact.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-threads", "2", "-i", str(OUT / (name + ".mp4")),
                        "-vf", f"fps=1/{spacing},scale=640:360,tile={columns}x{2 if name == 'route' else 1}",
                        "-frames:v", "1", str(target)], check=True)
        sheets.append({"path": target.name, "sha256": sha(target), "sample_spacing_s": spacing})
    names = ["innkeeper", "vendor", "boatman", "food_vendor", "tea_guest"]
    sheet = Image.new("RGB", (1440, 588), "#172035")
    draw = ImageDraw.Draw(sheet)
    for index, name in enumerate(names):
        with Image.open(OUT / ("npc-" + name + ".png")) as source:
            tile = source.convert("RGB").resize((480, 270), Image.Resampling.LANCZOS)
        x, y = index % 3 * 480, index // 3 * 294
        sheet.paste(tile, (x, y))
        draw.text((x + 8, y + 274), name, fill="white")
    sheet.save(OUT / "npc-contact.png")
    sheets.append({"path": "npc-contact.png", "sha256": sha(OUT / "npc-contact.png")})
    report = {"passed": True, "runtime_fingerprint": capture["runtime_fingerprint"], "original_frames": verified,
              "video_decodes": decodes, "review_sheets": sheets,
              "visual_scope": "Contact sheets assist human review; full-resolution source captures remain authoritative. They do not measure runtime FPS or replace the complete video.",
              "known_visibility": "The small natural crescent is partly occluded by clouds in default F; clouds can cover it in W. Milky Way contrast is intentionally faint. Default F has a narrow visible sky strip because the original camera framing is preserved."}
    (OUT / "visual-review.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PASS: all source PNG hashes and both complete video decodes")


if __name__ == "__main__":
    main()
