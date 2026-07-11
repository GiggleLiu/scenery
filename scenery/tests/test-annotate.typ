#import "/src/camera.typ": camera, camera-2d
#import "/src/scene.typ": sphere, label, build-scene
#import "/src/render.typ": sort-prims, render-scene
#import "/src/annotate.typ": (
  axes-triad, legend, colorbar,
  triad-dirs, legend-rows, is-color-swatch, colorbar-gradient,
)
#import "@preview/cetz:0.5.2"

// --- 1. identity-camera triad: x-arrow projects to the documented direction ---
// The 2D identity camera passes (x, y, z) through as (sx: x, sy: y). A unit
// x-vector therefore projects to screen direction (1, 0) (screen right), y to
// (0, 1) (screen up), and z collapses to (0, 0).
#let idcam = camera-2d()
#let dirs = triad-dirs(idcam, ((1, 0, 0), (0, 1, 0), (0, 0, 1)))
#assert(
  calc.abs(dirs.at(0).at(0) - 1) < 1e-9 and calc.abs(dirs.at(0).at(1)) < 1e-9,
  message: "x-arrow must project to screen +x (1, 0), got " + repr(dirs.at(0)),
)
#assert(
  calc.abs(dirs.at(1).at(0)) < 1e-9 and calc.abs(dirs.at(1).at(1) - 1) < 1e-9,
  message: "y-arrow must project to (0, 1), got " + repr(dirs.at(1)),
)
#assert(
  calc.abs(dirs.at(2).at(0)) < 1e-9 and calc.abs(dirs.at(2).at(1)) < 1e-9,
  message: "z collapses to (0, 0) under the identity camera, got " + repr(dirs.at(2)),
)

// n-axes < 3: a layer group passes two vectors and gets exactly two directions.
#assert(triad-dirs(idcam, ((1, 0, 0), (0, 1, 0))).len() == 2)

// The triad look normalises before projecting: a long a-vector still projects to
// a unit screen direction.
#let long = triad-dirs(idcam, ((5, 0, 0),))
#assert(calc.abs(long.at(0).at(0) - 1) < 1e-9, message: "vectors are normalised before projection")

// --- 2. legend(3 entries) yields exactly 3 swatch rows ------------------------
#let ents = (("A", red), ("B", green), ("C", blue))
#assert(legend-rows(ents).len() == 3, message: "3 entries must yield 3 rows")
// rows descend by row-height from the origin
#let rr = legend-rows(ents, row-height: 0.55, origin: (0, 0))
#assert(
  rr.at(0).pos.at(1) == 0 and calc.abs(rr.at(1).pos.at(1) + 0.55) < 1e-9,
  message: "rows must stack downward by row-height: " + repr(rr.map(r => r.pos.at(1))),
)

// --- negative control: a non-color swatch is rejected -------------------------
// `legend`/`legend-rows` assert on `is-color-swatch`. Typst cannot catch a
// panic, so the negative control tests the predicate the assert fires on (the
// returned-sentinel pattern, forced by the language): a gradient (a plausible
// mistaken "colormap-as-swatch") and a string are both rejected; a color passes.
#assert(is-color-swatch(red) == true)
#assert(is-color-swatch(luma(80)) == true)
#assert(
  is-color-swatch(gradient.linear(red, blue)) == false,
  message: "a gradient is not a valid legend swatch",
)
#assert(is-color-swatch("red") == false, message: "a string is not a valid legend swatch")

// --- 3. labels carry the 1e9 depth key (drawn last, above all geometry) -------
// Even against a very near sphere, the label sorts last with depth exactly 1e9.
#let lsc = build-scene(sphere((0, 100, 0), 1), label((0, 0, 0), [L]))
#let ord = sort-prims(lsc.prims, camera(azimuth: 0deg, elevation: 0deg))
#assert(
  ord.last().kind == "label" and ord.last().depth == 1e9,
  message: "label must sort last with depth 1e9, got " + repr(ord.last().depth),
)

// --- colorbar-gradient: array -> gradient, gradient passes through ------------
#assert(type(colorbar-gradient((blue, green, red))) == gradient, message: "an array of colors becomes a gradient")
#let g = gradient.linear(black, white)
#assert(type(colorbar-gradient(g)) == gradient, message: "an existing gradient passes through as a gradient")

Annotate data OK

// --- 4. content-level: all four annotation kinds on a demo scene --------------
// Axes triad, legend, colorbar (options on render-scene) plus a projected label
// (in the scene). Compiling this file at all is the assertion.
#let demo = build-scene(
  sphere((0, 0, 0), 1, color: rgb("#4c72b0")),
  sphere((2, 0, 0), 0.7, color: rgb("#dd8452")),
  label((0, 0, 1.5), [top]),
)
#render-scene(
  demo,
  camera(),
  width: 5cm,
  axes: (vectors: ((1, 0, 0), (0, 1, 0), (0, 0, 1)), names: ("a", "b", "c")),
  legend: (("Fe", rgb("#4c72b0")), ("O", rgb("#dd8452"))),
  colorbar: (colormap: (blue, green, yellow, red), range: (0, 1.5)),
)

// The standalone builders also compose inside a bare canvas (layer-group triad
// with two axes; a flat colorbar with a mid tick).
#cetz.canvas(length: 1cm, {
  axes-triad(camera(), ((1, 0, 0), (0, 1, 0)), names: ("a", "b"))
  legend((("x", red), ("y", blue)), origin: (3, 0))
  colorbar((blue, red), (0, 10), origin: (5, -1.5), mid: true)
})
