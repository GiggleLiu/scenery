# scenery monorepo — top-level orchestration.
#
# Each package (scenery/, wyckoff/) is a self-contained Typst package with its
# own Makefile exposing `test` and `examples` targets. This root Makefile fans
# those out across every package and wires up local `@preview` resolution.

.PHONY: all test examples manual pkgroot clean

# Packages in dependency order (core first, then its consumers).
PACKAGES := scenery wyckoff

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

# Showcase manual(s). Only scenery ships one today; the fan-out builds each
# package's `manual` target where it exists.
manual: pkgroot
	@$(MAKE) -C scenery manual
	@echo "Manual(s) built."

clean:
	@for pkg in $(PACKAGES); do $(MAKE) -C $$pkg clean; done
	rm -rf _pkgroot
