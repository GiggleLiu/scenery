# scenery monorepo — top-level orchestration.
#
# Each package (scenery/, wyckoff/) is a self-contained Typst package with its
# own Makefile exposing `test` and `examples` targets. This root Makefile fans
# those out across every package and wires up local `@preview` resolution.

.PHONY: all test examples site-assets serve manual pkgroot plugin clean

# Packages in dependency order (core first, then its consumers).
PACKAGES := scenery wyckoff brillouin

# Local preview server port for `make serve`.
PORT ?= 8000

# During development `@preview/<pkg>:<version>` must resolve to the local
# checkout. Typst searches TYPST_PACKAGE_PATH for a `<namespace>/<name>/<version>`
# tree, so we point it at `_pkgroot`, whose `preview/` subtree symlinks each
# package dir into place (see the `pkgroot` target and docs/DEVELOPMENT.md).
export TYPST_PACKAGE_PATH := $(CURDIR)/_pkgroot

all: test

pkgroot:
	@rm -rf _pkgroot/preview
	@for pkg in $(PACKAGES); do \
	  mkdir -p _pkgroot/preview/$$pkg; \
	  ln -sfn $(CURDIR)/$$pkg _pkgroot/preview/$$pkg/0.1.0; \
	  echo "linked @preview/$$pkg:0.1.0 -> $$pkg/"; \
	done

check-links:
	python3 tools/check_links.py

# Build native/WASM plugins. Only wyckoff ships one today; the fan-out builds
# each package's `plugin` target where it exists.
plugin:
	@$(MAKE) -C wyckoff plugin
	@$(MAKE) -C scenery plugin
	@echo "Plugin(s) built."

test: pkgroot check-links
	@for pkg in $(PACKAGES); do \
	  echo "==> $$pkg: tests"; \
	  $(MAKE) -C $$pkg test || exit 1; \
	done
	@echo "All package test suites passed!"

examples: pkgroot
	@for pkg in $(PACKAGES); do \
	  echo "==> $$pkg: examples"; \
	  $(MAKE) -C $$pkg examples || exit 1; \
	done

# Regenerate the showcase site's images (site/assets/*.png) from the package
# examples. Every asset is a page of a committed example, so the site can't
# drift from what the code actually renders (see tools/gen_site_assets.py).
site-assets: pkgroot
	python3 tools/gen_site_assets.py
	@# The interactive demo runs the SAME engine wasm Typst uses, straight in
	@# the browser — keep site/ in sync with the committed plugin.
	cp scenery/plugin/scenery_engine.wasm site/assets/scenery_engine.wasm

# Preview the showcase site locally. Binds the first free port at or above
# $(PORT), so a second `make serve` just lands on the next one.
serve:
	@python3 -u tools/serve.py $(PORT)

# Showcase manual(s). Only scenery ships one today; the fan-out builds each
# package's `manual` target where it exists.
manual: pkgroot
	@$(MAKE) -C scenery manual
	@echo "Manual(s) built."

clean:
	@for pkg in $(PACKAGES); do $(MAKE) -C $$pkg clean; done
	rm -rf _pkgroot
