.PHONY: all test data fixtures images clean venv

TYPST = typst compile --root .
TESTS := $(wildcard tests/test-*.typ)
VENV = tools/.venv/bin/python

all: test

test:
	@for t in $(TESTS); do \
	  echo "== $$t"; \
	  $(TYPST) $$t $${t%.typ}.pdf || exit 1; \
	done
	@echo "All tests passed!"

venv:
	python3 -m venv tools/.venv
	tools/.venv/bin/pip install -r tools/requirements.txt

data:
	$(VENV) tools/gen_elements.py
	$(VENV) tools/gen_groups.py

fixtures:
	$(VENV) tools/gen_fixtures.py

images:
	@for f in examples/*.typ; do $(TYPST) $$f images/$$(basename $${f%.typ}).png; done

clean:
	rm -f tests/*.pdf examples/*.pdf
