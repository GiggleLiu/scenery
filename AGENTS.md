# Repository Guidelines

## Project Structure & Module Organization

This is a Typst monorepo containing three independently publishable packages:

- `scenery/`: shared 2D/3D scene core, renderer, shapes, tests, examples, and manual.
- `wyckoff/`: crystallographic structures and figures; generated reference data lives in `data/`.
- `brillouin/`: reciprocal-space geometry, k-paths, and band/BZ figures.

Each package has `lib.typ`, `typst.toml`, `src/`, `tests/`, `examples/`, `images/`, and its own `Makefile`. Shared scripts and fixtures are under `tools/`; architecture and implementation notes are under `docs/`.

Package-internal imports use root paths such as `#import "/src/render.typ"`. Cross-package imports must use `@preview/scenery:0.1.0`, resolved locally through `_pkgroot/`.

## Build, Test, and Development Commands

Run these from the repository root:

- `make test`: create local package links, check Markdown links, and compile every test suite.
- `make examples`: compile all package examples as integration checks.
- `make manual`: build `scenery/manual.pdf`.
- `make pkgroot`: rebuild `_pkgroot/preview/<package>/0.1.0` symlinks.
- `make clean`: remove generated PDFs and local package links.

Package-specific targets also work, for example `make -C scenery test` or `make -C brillouin images`.

## Coding Style & Naming Conventions

Use two-space indentation in Typst files. Prefer small pure functions and plain dictionaries for scene data. Public and private identifiers use lowercase kebab-case (`render-scene`, `_face-normal`); constants may use descriptive private names. Add `///` API documentation to exported functions and short comments for non-obvious geometry. Import names explicitly; avoid wildcard imports because names such as `scale`, `label`, and `group` shadow common bindings.

## Testing Guidelines

Tests are compile-time Typst assertions named `tests/test-*.typ`. Expected failures belong in `tests/errors/*.typ` and must begin with `// expected: <message fragment>`. Add value-based and adversarial geometry checks, including multiple scales when tolerances are involved. Rebuild examples and inspect affected PNG/PDF output for visual changes. There is no numeric coverage threshold; `make test` and `make examples` must both pass.

## Commit & Pull Request Guidelines

Use concise imperative commit subjects, following history such as `Add named object anchors` or `docs: design ...`. Keep design and implementation commits separate for substantial behavior changes. Pull requests should explain purpose, public-API impact, verification commands, and known rendering limitations; link the relevant issue and include before/after images for visual changes. Do not commit `_pkgroot/`, test PDFs, caches, credentials, or unrelated generated artifacts.
