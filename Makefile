PYTHON ?= python3
BLENDER ?= blender
.DEFAULT_GOAL := help
.PHONY: help run editor import bake test visual export record assets models rebuild templates docs package reproduce
help:
	@printf '%s\n' 'run / editor: preview or edit' 'test / visual: offline tests or real GPU evidence' 'rebuild: regenerate assets, models, imports, baked scene' 'templates / export / package: Linux delivery' 'docs / reproduce: diagrams and clean-copy validation'
run editor import bake test visual export record:
	$(PYTHON) tools/project.py $@
assets:
	$(PYTHON) tools/generate_assets.py
models:
	$(BLENDER) --background --factory-startup --disable-autoexec --python tools/build_models.py
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
	$(PYTHON) tools/package.py
reproduce:
	$(PYTHON) tools/reproduce.py

.PHONY: verify-release
verify-release:
	$(PYTHON) tools/verify_release.py
