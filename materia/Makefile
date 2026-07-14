.PHONY: all test test-equiv examples data fixtures images clean venv plugin

TYPST = typst compile --root .
TESTS := $(wildcard tests/test-*.typ)
ERROR_TESTS := $(wildcard tests/errors/*.typ)
EXAMPLES := $(wildcard examples/*.typ)

# Python generators are shared across the monorepo and live at the repo root.
TOOLS = ../tools
VENV = $(TOOLS)/.venv/bin/python

all: test

test:
	@for t in $(TESTS); do \
	  echo "== $$t"; \
	  $(TYPST) $$t $${t%.typ}.pdf || exit 1; \
	done
	@for t in $(ERROR_TESTS); do \
	  echo "== $$t (expected error)"; \
	  expected=$$(sed -n 's|^// expected: ||p' $$t); \
	  if [ -z "$$expected" ]; then echo "missing // expected: marker in $$t"; exit 1; fi; \
	  out=$$($(TYPST) $$t /tmp/materia-expected-error.pdf 2>&1); status=$$?; \
	  if [ $$status -eq 0 ]; then echo "expected compilation to fail"; exit 1; fi; \
	  echo "$$out" | grep -F -- "$$expected" >/dev/null || { echo "$$out"; exit 1; }; \
	done
	@$(MAKE) test-equiv
	@echo "All tests passed!"

# Accelerator pixel-equivalence gate (issue #32): the same materia figure through
# engine="typst" and engine="wasm" must render byte-identically — this exercises
# the occlusion-cull mirror + detect_bonds through the accelerator on a periodic
# scene, a molecule, and a perspective supercell. tests/*.png is gitignored, so
# the outputs never dirty the tree.
test-equiv:
	$(TYPST) --format png --ppi 144 --input engine=typst tests/equiv/equiv-figure.typ tests/equiv-figure-typst.png
	$(TYPST) --format png --ppi 144 --input engine=wasm  tests/equiv/equiv-figure.typ tests/equiv-figure-wasm.png
	cmp tests/equiv-figure-typst.png tests/equiv-figure-wasm.png
	@echo "materia engine=wasm and engine=typst render pixel-identically"

examples:
	@for f in $(EXAMPLES); do \
	  echo "== $$f"; \
	  $(TYPST) $$f $${f%.typ}.pdf || exit 1; \
	done

venv:
	python3 -m venv $(TOOLS)/.venv
	$(TOOLS)/.venv/bin/pip install -r $(TOOLS)/requirements.txt

PLUGIN_CRATE = ../materia-io
WASM_OUT = plugin/materia_io.wasm

plugin:
	cargo build --manifest-path ../Cargo.toml -p materia-io --release --target wasm32-unknown-unknown
	@mkdir -p plugin
	cp ../target/wasm32-unknown-unknown/release/materia_io.wasm $(WASM_OUT)
	@if command -v wasm-opt >/dev/null 2>&1; then \
	  echo "wasm-opt -Oz"; wasm-opt -Oz $(WASM_OUT) -o $(WASM_OUT); \
	else echo "wasm-opt not found, skipping (optional)"; fi
	@ls -l $(WASM_OUT)

data:
	$(VENV) $(TOOLS)/gen_elements.py
	$(VENV) $(TOOLS)/gen_groups.py

fixtures:
	$(VENV) $(TOOLS)/gen_fixtures.py

images:
	@for f in $(EXAMPLES); do $(TYPST) $$f images/$$(basename $${f%.typ}).png; done

clean:
	rm -f tests/*.pdf tests/*.png examples/*.pdf
