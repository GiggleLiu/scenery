.PHONY: all test examples fixtures images clean venv

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

fixtures:
	$(VENV) $(TOOLS)/gen_bz_fixtures.py
	$(VENV) $(TOOLS)/gen_kpath_fixtures.py

images:
	@for f in $(EXAMPLES); do $(TYPST) $$f images/$$(basename $${f%.typ}).png; done

clean:
	rm -f tests/*.pdf examples/*.pdf
