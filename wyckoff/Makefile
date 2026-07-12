.PHONY: all test examples data fixtures images clean venv plugin

TYPST = typst compile --root .
TESTS := $(wildcard tests/test-*.typ)
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
	@echo "All tests passed!"

examples:
	@for f in $(EXAMPLES); do \
	  echo "== $$f"; \
	  $(TYPST) $$f $${f%.typ}.pdf || exit 1; \
	done

venv:
	python3 -m venv $(TOOLS)/.venv
	$(TOOLS)/.venv/bin/pip install -r $(TOOLS)/requirements.txt

PLUGIN_CRATE = ../wyckoff-io
WASM_OUT = plugin/wyckoff_io.wasm

plugin:
	cargo build --manifest-path $(PLUGIN_CRATE)/Cargo.toml --release --target wasm32-unknown-unknown
	@mkdir -p plugin
	cp $(PLUGIN_CRATE)/target/wasm32-unknown-unknown/release/wyckoff_io.wasm $(WASM_OUT)
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
	rm -f tests/*.pdf examples/*.pdf
