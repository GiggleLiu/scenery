.PHONY: all test examples images manual plugin clean

TYPST = typst compile --root .
TESTS := $(wildcard tests/test-*.typ)
ERROR_TESTS := $(wildcard tests/errors/*.typ)
EXAMPLES := $(wildcard examples/*.typ)

all: test

# The manual doubles as an end-to-end test: every figure in it is produced by
# eval'ing the source string it displays, so a clean compile exercises the whole
# public API. Compiling == testing, so `test` depends on it (pixelman pattern).
manual: manual.pdf

manual.pdf: manual.typ lib.typ src/*.typ
	$(TYPST) manual.typ manual.pdf

test: manual
	@for t in $(TESTS); do \
	  echo "== $$t"; \
	  $(TYPST) $$t $${t%.typ}.pdf || exit 1; \
	done
	@for t in $(ERROR_TESTS); do \
	  echo "== $$t (expected error)"; \
	  expected=$$(sed -n 's|^// expected: ||p' $$t); \
	  if [ -z "$$expected" ]; then echo "missing // expected: marker in $$t"; exit 1; fi; \
	  out=$$($(TYPST) $$t /tmp/scenery-expected-error.pdf 2>&1); status=$$?; \
	  if [ $$status -eq 0 ]; then echo "expected compilation to fail"; exit 1; fi; \
	  echo "$$out" | grep -F -- "$$expected" >/dev/null || { echo "$$out"; exit 1; }; \
	done
	@echo "All tests passed!"

examples:
	@for f in $(EXAMPLES); do \
	  echo "== $$f"; \
	  $(TYPST) $$f $${f%.typ}.pdf || exit 1; \
	done

images:
	@for f in $(EXAMPLES); do \
	  echo "== $$f"; \
	  $(TYPST) --format png --ppi 144 $$f images/$$(basename $${f%.typ}).png || exit 1; \
	done

PLUGIN_CRATE = ../scenery-engine
WASM_OUT = plugin/scenery_engine.wasm

plugin:
	cargo build --manifest-path ../Cargo.toml -p scenery-engine --release --target wasm32-unknown-unknown
	@mkdir -p plugin
	cp ../target/wasm32-unknown-unknown/release/scenery_engine.wasm $(WASM_OUT)
	@if command -v wasm-opt >/dev/null 2>&1; then \
	  echo "wasm-opt -Oz"; wasm-opt -Oz $(WASM_OUT) -o $(WASM_OUT); \
	else echo "wasm-opt not found, skipping (optional)"; fi
	@ls -l $(WASM_OUT)

clean:
	rm -f tests/*.pdf examples/*.pdf manual.pdf
