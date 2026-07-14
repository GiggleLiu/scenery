# Materia Package Design

Date: 2026-07-14

Status: Validated

## Context

The repository currently contains three unpublished Typst packages:
`scenery`, `wyckoff`, and `brillouin`. The latter two serve the same scientific
audience and already share a natural data flow from real-space crystal
structures to reciprocal lattices, Brillouin zones, and band paths. Publishing
them separately would create an extra dependency and two package names that are
likely to need human review under Typst Universe's noncanonical naming rule.

The selected design keeps `scenery` as the general-purpose 2D/3D rendering
engine and replaces `wyckoff` plus `brillouin` with one broader materials-science
toolkit named `materia`. The package also introduces a small declarative
electronic-structure layer for energy-level and molecular-orbital diagrams.

Neither legacy package has been published, so the migration is a clean cut with
no compatibility wrappers.

## Goals

- Give materials scientists one coherent package for real-space,
  reciprocal-space, and electronic-structure figures.
- Use plain scientific data as the boundary between computation and rendering.
- Make all domain figures composable through stable `scenery` scene builders.
- Preserve the tested crystallographic and reciprocal-space behavior already in
  the repository.
- Add declarative molecular-orbital diagrams without attempting quantum
  chemistry or electronic-structure prediction.
- Submit `scenery:0.1.0` and `materia:0.1.0` to Typst Universe with clean
  package-check results and auditable third-party assets.

## Non-goals for 0.1

- Predicting molecular-orbital energies, orderings, or symmetries.
- Running DFT, tight-binding, DOS, or other electronic-structure solvers.
- Inferring scientifically ambiguous diagrams from a chemical formula alone.
- Preserving the unpublished `wyckoff` and `brillouin` package identities.
- Turning `scenery` into a materials-specific package.

## Package Boundary

The monorepo will contain two independently publishable packages:

```text
scenery/
materia/
```

`scenery` remains responsible for cameras, primitives, transforms, anchors,
depth ordering, occlusion, the optional WASM geometry engine, and CeTZ output.

`materia` depends on `@preview/scenery:0.1.0` and owns all materials-domain
concepts: structures, symmetry, lattices, file import, crystal rendering,
reciprocal geometry, Brillouin zones, k-paths, band panels, energy levels, and
molecular-orbital diagrams.

## Internal Architecture

The intended source layout is:

```text
materia/
  lib.typ
  typst.toml
  README.md
  LICENSE
  src/
    core/          lattice, symmetry, and structure data
    real/          bonds, polyhedra, and crystal scenes
    reciprocal/    reciprocal vectors, BZ cells, and k-paths
    electronic/    bands, energy levels, and MO diagrams
    io.typ
    prototypes.typ
  data/
  plugin/
  examples/
  images/
  tests/
```

The current `wyckoff-io` crate, plugin artifact, and diagnostics become
`materia-io`, `materia_io.wasm`, and `materia:` respectively. Generated
crystallographic data remains under `data/`, with its provenance and licensing
made explicit.

## Data and Rendering Flow

Every feature follows one pipeline:

```text
scientific input -> validated plain data -> scenery scene -> rendered content
```

The existing structure dictionary is the shared real-space value. It contains
lattice vectors, atoms, periodic axes, and relevant metadata. Constructors and
file importers return this same shape. Reciprocal functions accept a structure,
an explicit lattice, or lattice parameters directly; an adapter named after the
old package is unnecessary.

Electronic diagrams use a separate declarative model. The model describes
columns, energy levels, identifiers, labels, energies or ordering, degeneracy,
occupations, orbital classification, and correlations. Diagram-only fields do
not leak into crystal structures.

The public scene layer is stable:

- `crystal-scene(structure, ..options)`
- `bz-scene(structure-or-lattice, ..options)`
- `mo-scene(model, ..options)`

These functions return ordinary `scenery` scene data. Users can transform,
combine, annotate, or render the results. The legacy `crystal-group` and
`bz-group` APIs are removed rather than maintaining a parallel raw-CeTZ
composition path.

High-level convenience renderers remain:

- `crystal`
- `molecule`
- `bz-figure`
- `band-panel`
- `mo-diagram`

The package root explicitly re-exports these common functions and exposes
specialist `core`, `real`, `reciprocal`, and `electronic` modules for less common
operations. Wildcard imports remain discouraged.

## Electronic Module Scope

The 0.1 electronic module includes:

- Existing band-axis and band-panel functionality.
- Generic energy-level columns.
- Electron arrows, paired occupations, and degenerate levels.
- Labelled correlations between atomic and molecular levels.
- Bonding, antibonding, and nonbonding classifications.
- Electron-count and bond-order arithmetic derived from explicit occupations.
- `mo-scene` and `mo-diagram`.

The first complete example is a CO molecular-orbital correlation diagram with
atomic 2s/2p levels, molecular sigma/pi levels, occupations, correlations, and
bond order. The user-provided reference image is a requirements reference only.
The repository will contain an independently constructed native Typst vector
figure driven by public declarative data, not a copy, trace, or embedded raster.

## Validation and Errors

Scientific ambiguity must not be hidden by convenience behavior. Constructors
validate data before layout or rendering and use diagnostics prefixed with
`materia:`.

Electronic validation includes:

- Unique level and column identifiers.
- Positive degeneracy.
- Nonnegative occupation no greater than twice the degeneracy.
- Existing endpoints for every correlation.
- Consistent bonding classifications when bond order is requested.
- Data-path context in failures, such as
  `columns[1].levels[2].occupation exceeds capacity`.

Existing structure, symmetry, lattice, BZ, k-path, and file-format validation is
preserved. The package does not silently select a molecular-orbital ordering.

## File Import Boundary

`materia` requires Typst 0.15. File importers accept caller-created `path` values
so paths retain their origin across the package boundary. Bytes input should
also be accepted where practical for generated or embedded data. String paths
that would resolve inside the installed package are not documented as the user
file API.

External-project fixtures must test CIF, POSCAR, XYZ, and extended-XYZ imports
from outside the package directory. This is a release blocker because compiling
only inside the source tree does not exercise the installed-package boundary.

## Migration

Implementation performs one clean migration:

1. Rename `wyckoff/` to `materia/` while preserving history.
2. Move `brillouin` source, tests, fixtures, examples, and images into the
   corresponding `materia` domains.
3. Replace cross-package imports between the old packages with package-internal
   imports.
4. Add stable scene builders and update high-level renderers to use them.
5. Rename the I/O crate, WASM artifact, version constant, error prefixes, and
   generated-data references.
6. Add the electronic model, validation, layout, CO example, and tests.
7. Remove the remaining `wyckoff/` and `brillouin/` package directories.
8. Update root orchestration, local package links, CI, website, documentation,
   and release workflows for `scenery` plus `materia`.

No deprecated wrapper packages or old-name aliases are retained.

## Testing

The current numerical and rendering suites move with their implementation and
must continue to pass. New coverage includes:

- Structure-to-reciprocal-to-BZ cross-module invariants.
- Exact reciprocal volume/determinant checks.
- Electron capacity, degeneracy, electron-count, and bond-order invariants.
- Missing and duplicate correlation endpoint failures.
- Layout checks at multiple output scales.
- A native CO golden example.
- External-project file import fixtures.
- Existing pure-Typst/WASM pixel-equivalence gates.
- Full tests and examples on Typst 0.15.

Every expected failure retains a stable message fragment. Visual changes require
rendered inspection in addition to compile success.

## Documentation and Release

The `materia` README and gallery present three equal entry points:

1. A real-space crystal structure from symmetry or an imported file.
2. Its reciprocal lattice, Brillouin zone, and k-path.
3. A declarative molecular-orbital diagram.

README-linked examples, illustrations, and source documentation are committed
to the Universe submission and excluded from the compiler download bundle when
not needed at runtime. Tests, Makefiles, caches, local links, and generated PDFs
are omitted from the submission tree.

Before registration:

- Third-party notices cover generated crystallographic/k-path data and bundled
  WASM dependencies.
- The repository is public and all metadata URLs resolve.
- The current official package checker reports no warnings or errors.
- `make test`, `make examples`, and external-project import tests pass.
- The website shows real-space, reciprocal-space, and electronic examples.
- The exact staged package contents and checksums are recorded.

`scenery:0.1.0` is submitted first. Once it is available as a dependency,
`materia:0.1.0` is submitted under the selected noncanonical name.

## Definition of Done

The design is complete when a new user can follow the public documentation to:

- construct or import a material structure;
- render it as a crystal or molecule;
- derive and draw its Brillouin zone and k-path;
- build and render a validated CO-like molecular-orbital diagram;
- compose any of those figures through stable scene data;
- compile the examples from an external project using published package imports.

At that point only `scenery` and `materia` remain as publishable packages, and
both satisfy the documented Universe release gates.
