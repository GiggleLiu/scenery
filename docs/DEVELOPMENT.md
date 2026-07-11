# Development

## Repository layout

`scenery` is a monorepo. Each package is a self-contained Typst package
directory (a `typst.toml` plus its entrypoint) that is published separately to
Typst Universe, so each carries its own `LICENSE`, `Makefile`, tests, and
examples.

```
scenery/            repo root
├── Makefile        orchestrates all packages (test / examples / pkgroot)
├── README.md       monorepo overview
├── LICENSE         MIT (also copied into each package dir)
├── docs/           shared design docs and this file
├── tools/          shared Python generators (JSON data / test fixtures)
├── scenery/        package: shared 2D/3D scene core
│   ├── typst.toml
│   ├── lib.typ
│   ├── LICENSE
│   ├── Makefile
│   └── tests/
└── wyckoff/        package: crystal-structure figures
    ├── typst.toml
    ├── lib.typ
    ├── LICENSE
    ├── Makefile
    ├── src/  data/  tests/  examples/  images/
    └── README.md
```

Packages import their own sources with root-absolute paths (e.g.
`#import "/src/foo.typ"`); each package Makefile compiles with `--root .` so `/`
resolves to the package directory. Cross-package imports use the published
`@preview` name (see below), never a filesystem path — a published package
cannot path-import outside its own root.

## Make targets

Run from the repo root:

| Target | Effect |
| --- | --- |
| `make test` | Run every package's test suite (delegates to each package Makefile). |
| `make examples` | Compile every package's examples. |
| `make pkgroot` | (Re)build the local `@preview` resolution tree under `_pkgroot/`. |
| `make clean` | Clean each package and remove `_pkgroot/`. |

Each package Makefile also works on its own from inside the package directory
(`cd wyckoff && make test`).

## How `@preview` resolves locally

A published package depends on other packages through the `@preview` namespace,
e.g. `#import "@preview/scenery:0.1.0": ...`. During development those versions
are not on Universe yet, so we make Typst resolve them to the local checkout.

Typst searches `TYPST_PACKAGE_PATH` for a `<namespace>/<name>/<version>` tree.
`make pkgroot` builds exactly that tree under `_pkgroot/`, symlinking each
package directory into place:

```
_pkgroot/preview/scenery/0.1.0  ->  ../scenery
_pkgroot/preview/wyckoff/0.1.0  ->  ../wyckoff
```

The root Makefile exports `TYPST_PACKAGE_PATH=$(CURDIR)/_pkgroot`, and the
`test` / `examples` targets depend on `pkgroot`, so `@preview/scenery:0.1.0` and
`@preview/wyckoff:0.1.0` resolve to the working tree with no download.

To compile a scratch document against the local packages by hand:

```bash
make pkgroot
TYPST_PACKAGE_PATH="$PWD/_pkgroot" typst compile scratch.typ
```

`_pkgroot/` is generated and git-ignored.
