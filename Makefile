PYTHON ?= python3
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
