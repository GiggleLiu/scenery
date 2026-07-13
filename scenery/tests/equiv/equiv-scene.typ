// Pixel-equivalence gate (M4 design doc, "Accelerator equivalence"): this file
// compiles twice — --input engine=typst and --input engine=wasm — and the two
// PNGs must be byte-identical (scenery/Makefile `test-equiv`). Scenes cover:
// fragment-cutting lines (both paths cut identically), opaque + translucent
// faces, meshes, perspective, and translucent NON-intersecting solids (the
// BSP negative control at pixel level once Task 5 lands).
#import "/lib.typ": *
#let eng = sys.inputs.at("engine", default: "typst")
#set page(width: auto, height: auto, margin: 0.5cm)

#let cam = camera(azimuth: 25deg, elevation: 15deg)
#let sc1 = build-scene(
  sphere((0, 0, 0), 1, color: rgb("#c44e52")),
  sphere((2.5, 1, 0.5), 0.7, color: rgb("#4c72b0")),
  seg((-2, 0, 0), (4, 0, 0)),
  arrow((-2, 0.4, 0.8), (4, 0.4, 0.8)),
  edge((-2, -0.5, -0.5), (4, 1.5, 0.5)),
  face(((1, -1, -1.2), (3, -1, -1.2), (3, 2, -1.2), (1, 2, -1.2)),
    color: rgb("#55a868"), fill-opacity: 0%),
  face(((-1, -2, -1), (1, 2, -1), (0, 2, 1)),
    color: rgb("#8172b3"), depth-key: "back"),
  label((0, 1.6, 1.2), [cut]),
)
#render-scene(sc1, cam, engine: eng, width: 7cm)

#let sc2 = build-scene(
  uv-sphere((0, 0, 0), 1, color: rgb("#4c72b0"), fill-opacity: 45%),
  prism(((2.2, -0.5, -0.5), (3.2, -0.5, -0.5), (3.2, 0.5, -0.5), (2.2, 0.5, -0.5)),
    (0, 0, 1), color: rgb("#dd8452"), fill-opacity: 45%),
  seg((-1.5, 0, 0), (3.5, 0, 0)),
)
#render-scene(sc2, cam, engine: eng, width: 7cm)

#render-scene(sc1, camera(azimuth: 25deg, elevation: 15deg, mode: "perspective", distance: 12.0),
  engine: eng, width: 7cm)
