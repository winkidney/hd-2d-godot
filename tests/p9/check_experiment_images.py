"""Measure P9 A-D GPU fixtures, independently of engine assertion results."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageStat


def validate_fixture(fixtures: dict, folder: Path) -> dict:
    if isinstance(fixtures, list):
        raise ValueError("Pass one variant's report; fixtures must be a dictionary.")
    checks: list[dict] = []
    measurements: list[dict] = []
    image_cache: dict[str, Image.Image] = {}

    def check(condition: bool, name: str) -> None:
        checks.append({"name": name, "passed": bool(condition)})
        print(("PASS " if condition else "FAIL ") + name)

    def load(name: str) -> Image.Image:
        if name not in image_cache:
            with Image.open(folder / name) as source:
                image_cache[name] = source.convert("L")
        return image_cache[name]

    def centroid(name: str, point: list[float]) -> tuple[float, float]:
        image = load(name)
        # A 23x31 white marker is isolated inside this predicted-position ROI.
        x0 = max(0, int(point[0]) - 40)
        y0 = max(0, int(point[1]) - 45)
        crop = image.crop((x0, y0, min(image.width, x0 + 80), min(image.height, y0 + 90)))
        total = sx = sy = 0.0
        for y in range(crop.height):
            for x in range(crop.width):
                weight = max(0, crop.getpixel((x, y)) - 8)
                total += weight
                # Pixel centres, not integer pixel addresses.
                sx += (x0 + x + 0.5) * weight
                sy += (y0 + y + 0.5) * weight
        if total < 247 * 100:
            raise ValueError(f"Missing marker in {name} at {point}")
        return sx / total, sy / total

    check(bool(fixtures.get("capture_success")), "all_gpu_fixture_captures_saved")
    tolerance = float(fixtures["markers"].get("tolerance_px", 0.8))
    for case in fixtures["markers"]["cases"]:
        for marker in case["markers"]:
            try:
                base = centroid(case["base_image"], marker["base_pixel"])
                actual = centroid(case["image"], marker["expected_pixel"])
                expected_delta = [marker["expected_pixel"][i] - marker["base_pixel"][i] for i in range(2)]
                measured_delta = [actual[i] - base[i] for i in range(2)]
                error = [abs(measured_delta[i] - expected_delta[i]) for i in range(2)]
                absolute_error = [abs(actual[i] - marker["expected_pixel"][i]) for i in range(2)]
                passed = max(error) <= tolerance and max(absolute_error) <= tolerance
                measurements.append({"case":case["image"], "layer":marker["layer"],
                    "expected_delta":expected_delta, "measured_delta":measured_delta,
                    "error_px":error, "absolute_error_px":absolute_error})
                check(passed, f"gpu_marker:{case['image']}:{marker['layer']}")
            except (OSError, ValueError) as error:
                measurements.append({"case":case["image"], "layer":marker["layer"], "error":str(error)})
                check(False, f"gpu_marker:{case['image']}:{marker['layer']}")

    def energy(image: Image.Image) -> float:
        width, height = image.size
        return ImageStat.Stat(image.filter(ImageFilter.FIND_EDGES).crop((2, 2, width - 2, height - 2))).mean[0]

    dof_metrics: dict = {}
    dof_start = len(checks)
    fixture_images = {key: load(value) for key, value in fixtures["dof"]["images"].items()}
    for roi in fixtures["dof"]["rois"]:
        crops = {key:image.crop(tuple(roi["box"])) for key, image in fixture_images.items()}
        energies = {key:energy(image) for key, image in crops.items()}
        differences = {key:ImageStat.Stat(ImageChops.difference(crops["off"], image)).mean[0] for key, image in crops.items()}
        name = roi["name"]
        dof_metrics[name] = {"edge_energy":energies, "mean_absolute_delta":differences}
        check(energies["off"] > 5.0, "checkerboard_has_detail:" + name)
        if name == "focus":
            check(max(differences.values()) < 1.0, "focus_region_preserves_detail")
        else:
            other = "far" if name == "near" else "near"
            check(energies[name] < energies["off"] * 0.90 and differences[name] > 2.0, "selective_blur:" + name)
            check(energies["both"] < energies["off"] * 0.90, "both_ends_blur:" + name)
            check(differences[other] < 1.0, "opposite_end_preserved:" + name)
    dof_passed = all(item["passed"] for item in checks[dof_start:])
    result = {"passed":all(item["passed"] for item in checks), "variant":fixtures["variant"],
        "projection":fixtures["projection"], "checks":checks, "pixel_measurements":measurements,
        "tolerance_px":tolerance, "dof_metrics":dof_metrics,
        "dof_status":"demonstrated" if dof_passed else "not_demonstrated",
        "scope":"GPU pixel centroids and equal-screen-size native DOF fixtures. Orthographic blur is not assumed supported; a missing blur effect remains a failed image check.",
        "limitation": "" if dof_passed else "Native near/far DOF was not demonstrated in this projection; inspect the measured images and engine support before claiming acceptance."}
    (folder / "experiment-image-report.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def validate(report_path: Path) -> dict:
    folder = report_path.parent
    report = json.loads(report_path.read_text())
    if "variants" not in report:
        return validate_fixture(report["fixtures"], folder)
    results = {}
    for variant, entry in report["variants"].items():
        fixtures = entry["fixtures"]
        subdir = fixtures.get("image_subdir", variant)
        candidate = folder / subdir
        if not candidate.is_dir():
            candidate = folder / variant
        results[variant] = validate_fixture(fixtures, candidate)
    result = {"passed":all(item["passed"] for item in results.values()), "variants":results,
        "scope":"Independent GPU pixel checks for every A-D variant. Unsupported native blur is reported as not demonstrated."}
    (folder / "experiment-image-report.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path, help="A variant folder or its experiment-report.json")
    args = parser.parse_args()
    path: Path = args.report
    if path.is_dir():
        candidates = [path / "experiment-report.json", path / "report.json"]
        path = next((candidate for candidate in candidates if candidate.exists()), candidates[0])
    result = validate(path)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
