.PHONY: all test examples images manual clean

TYPST = typst compile --root .
TESTS := $(wildcard tests/test-*.typ)
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

clean:
	rm -f tests/*.pdf examples/*.pdf manual.pdf
