PYTHON ?= python3
INPUT_PYTHON ?= /usr/bin/python3

.PHONY: input-test input-window-test
input-test:
	$(INPUT_PYTHON) tools/input_window_test.py --headless
	$(INPUT_PYTHON) tests/test_input_window_cleanup.py -v
input-window-test:
	$(INPUT_PYTHON) tools/input_window_test.py

.PHONY: frontal-run frontal-import frontal-bake frontal-test frontal-quick frontal-visual frontal-record frontal-export frontal-rebuild frontal-package
frontal-run:
	$(PYTHON) -c 'import sys,subprocess;sys.path.insert(0,"tools");from project import engine,ROOT,desktop_environment;subprocess.run([engine(),"--path",str(ROOT),"scenes/frontal_canal.tscn"],env=desktop_environment(),check=True)'
frontal-import frontal-bake frontal-quick frontal-record frontal-export frontal-rebuild:
	$(PYTHON) tools/p9frontal/run.py $(patsubst frontal-%,%,$@)
frontal-test:
	$(PYTHON) tests/p9/check_assets.py
	$(PYTHON) -c 'import sys,subprocess;sys.path.insert(0,"tools");from project import engine;subprocess.run([engine(),"--headless","--path",".","--script","res://tests/p9frontal/camera_unit.gd"],check=True)'
	$(PYTHON) -c 'import sys,subprocess;sys.path.insert(0,"tools");from project import engine;subprocess.run([engine(),"--headless","--path",".","--script","res://tests/p9frontal/lens_unit.gd"],check=True)'
	$(PYTHON) tools/p9frontal/run.py headless
frontal-visual:
	$(PYTHON) tools/p9frontal/run.py gpu
frontal-package:
	$(PYTHON) tools/p9frontal/package.py

.PHONY: p9-run p9-test p9-visual p9-export p9-rebuild p9-package
p9-run:
	$(PYTHON) -c 'import sys,subprocess;sys.path.insert(0,"tools");from project import engine,ROOT,desktop_environment;subprocess.run([engine(),"--path",str(ROOT),"scenes/reference_scene.tscn"],env=desktop_environment(),check=True)'
p9-test:
	$(PYTHON) tools/p9/accept.py assets
	$(PYTHON) tools/p9/accept.py headless
p9-visual:
	$(PYTHON) tools/p9/accept.py gpu
p9-export:
	$(PYTHON) tools/p9/accept.py export
p9-rebuild:
	$(PYTHON) tools/p9/accept.py rebuild
p9-package:
	$(PYTHON) tools/p9/package.py

.PHONY: p9x-import p9x-atlas p9x-test p9x-quick p9x-visual p9x-record p9x-export p9x-rebuild p9x-package
p9x-import:
	$(PYTHON) tools/p9/experiments.py import
p9x-atlas:
	$(PYTHON) tools/p9/experiments.py atlas
p9x-test:
	$(PYTHON) tests/p9/check_assets.py
	$(PYTHON) -c 'import sys,subprocess;sys.path.insert(0,"tools");from project import engine;subprocess.run([engine(),"--headless","--path",".","--script","res://tests/p9/experiment_camera_unit.gd"],check=True)'
	$(PYTHON) tools/p9/experiments.py headless
p9x-quick:
	$(PYTHON) tools/p9/experiments.py quick --no-route
p9x-visual:
	$(PYTHON) tools/p9/experiments.py gpu --no-route
p9x-record:
	$(PYTHON) tools/p9/experiments.py record
p9x-export:
	$(PYTHON) tools/p9/experiments.py export
p9x-rebuild:
	$(PYTHON) tools/p9/experiments.py rebuild
p9x-package:
	$(PYTHON) tools/p9/experiments.py package
BLENDER ?= blender
.DEFAULT_GOAL := help
.PHONY: help run editor import bake test visual export record assets models rebuild templates docs package reproduce
help:
	@printf '%s\n' 'run / editor: preview or edit' 'test / visual: offline tests or real GPU evidence' 'rebuild: regenerate assets, models, imports, baked scene' 'templates / export / package: Linux delivery' 'docs / reproduce: diagrams and clean-copy validation'
run editor import bake:
	$(PYTHON) tools/project.py $@
assets:
	$(PYTHON) tools/generate_assets.py
	$(PYTHON) tools/generate_background_assets.py
models:
	$(BLENDER) --background --factory-startup --disable-autoexec --python tools/build_models.py
	$(BLENDER) --background --factory-startup --disable-autoexec --python tools/build_background.py
rebuild:
	$(MAKE) assets
	$(MAKE) models
	$(MAKE) import
	$(MAKE) bake
templates:
	$(PYTHON) tools/prepare_templates.py
docs:
	$(PYTHON) tools/render_diagrams.py
package:
	$(PYTHON) tools/package_parallax.py
reproduce:
	$(PYTHON) tools/reproduce_parallax.py --headless-only

.PHONY: verify-release
verify-release:
	$(PYTHON) tools/parallax.py verify

.PHONY: features-test features-visual features-quick features-record verify-features package-features
test:
	$(PYTHON) tools/parallax.py test
	$(PYTHON) tests/check_character.py
	$(PYTHON) -c 'import sys,subprocess;sys.path.insert(0,"tools");from project import engine;subprocess.run([engine(),"--headless","--path",".","--script","res://tests/character_animation.gd","--","--ignore-user-settings"],check=True)'
features-test:
	$(PYTHON) tools/features.py test
features-visual:
	$(PYTHON) tools/features.py visual
features-quick:
	$(PYTHON) tools/features.py quick-visual
features-record:
	$(PYTHON) tools/features.py record
verify-features:
	$(PYTHON) tools/verify_features.py
package-features:
	$(PYTHON) tools/package_features.py

.PHONY: reproduce-visual
visual:
	$(PYTHON) tools/parallax.py visual
record:
	$(PYTHON) tools/parallax.py record
reproduce-visual:
	$(PYTHON) tools/reproduce_parallax.py

.PHONY: parallax-quick
export:
	$(PYTHON) tools/parallax.py export
parallax-quick:
	$(PYTHON) tools/parallax.py quick-visual

.PHONY: canal-run canal-import canal-quick canal-calibration canal-normals canal-route canal-benchmark canal-test canal-camera-test canal-export canal-package
canal-run canal-import canal-quick canal-calibration canal-normals canal-route canal-benchmark:
	$(PYTHON) tools/ancient_canal/run.py $(patsubst canal-%,%,$@)
canal-test:
	$(PYTHON) tests/ancient_canal/check_sources.py
	$(PYTHON) tools/ancient_canal/validate.py
	$(PYTHON) tools/ancient_canal/validate.py --mode camera
canal-camera-test:
	$(PYTHON) tools/ancient_canal/validate.py --mode camera
canal-export canal-package:
	$(PYTHON) tools/ancient_canal/package.py $(patsubst canal-%,%,$@)
