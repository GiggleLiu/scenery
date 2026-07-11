# scenery — scientific visualization for Typst

**scenery** is a monorepo of [Typst](https://typst.app) Universe packages for
scientific visualization built on one shared 2D/3D scene core (typed primitives →
transforms/projection → depth sort → styled [CeTZ](https://typst.app/universe/package/cetz)
rendering). It fills the missing scientific-visualization layer of Typst Universe:
no 3D capability and no dedicated tools exist today for crystal structures,
Brillouin zones, tensor networks, lattice/spin models, and more — figures that are
currently imported as static images from Python/Mathematica, breaking fonts,
theming, vector quality, and reproducibility. Every package is pure Typst at
runtime (cetz the only dependency) and published separately to Universe.

## Packages

| Package | Description |
| --- | --- |
| [`scenery/`](scenery/) | Shared 2D/3D scene core: typed primitives, orthographic projection, depth-sorted CeTZ output. |
| [`wyckoff/`](wyckoff/) | Materials Project style crystal-structure figures from space groups, layer groups, and Wyckoff positions. |

## Development

See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) for the monorepo layout, make
targets, and how `@preview` imports resolve against the local checkout.

```bash
make test       # run every package's test suite
make examples   # compile every package's examples
```

The full gallery README is tracked in
[issue #13](https://github.com/GiggleLiu/scenery/issues/13).

## License

MIT — see [LICENSE](LICENSE).
