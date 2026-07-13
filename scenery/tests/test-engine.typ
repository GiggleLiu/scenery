#import "/src/engine.typ": engine-version, engine-sort
#import "/src/scene.typ": sphere, seg, edge, arrow, face, label, build-scene, mesh
#import "/src/shape.typ": uv-sphere
#import "/src/camera.typ": camera, camera-2d
#import "/src/render.typ": sort-prims, _prepare-faces, _clip-lines, render-scene

#assert.eq(engine-version(), "scenery-engine 0.1.0")

// ============ FULL-PIPELINE EQUALITY (fragments included) ============
// The engine now mirrors _clip-lines: for ANY scene (cutting or not), engine
// output must be EXACTLY equal to sort-prims(_clip-lines(..)) — fragments,
// draw-head flags, and depth keys bit-for-bit. The engine receives already
// _prepare-faces'd prims and clips without re-preparing; the pure comparator
// runs _clip-lines (which prepares internally) then the identical keys+sort.
#let full-gate(prims, cam) = assert.eq(
  engine-sort(_prepare-faces(prims, cam), cam),
  sort-prims(_clip-lines(prims, cam), cam),
)

// The documented 5-prim scene (test-render.typ) + its shuffle. Under cam0 the
// near sphere occludes the lines that stack behind it, so both paths clip
// identically — the gate has teeth on the clip stage, not just the sort.
#let cam0 = camera(azimuth: 0deg, elevation: 0deg)
#let ps = (
  edge((0, -1, -1), (0, -1, 1)),
  face(((-1, 1, -1), (1, 1, -1), (0, 1, 1))),
  seg((0, 3, -1), (0, 3, 1)),
  sphere((0, 5, 0), 1),
  label((0, 0, 0), [L]),
)
#full-gate(ps, cam0)                                 // the Task-2 scenes still hold
#full-gate(ps.rev(), cam0)

// Generic cameras: the engine consumes the SAME cos/sin values Typst computed,
// so depth keys and cut points are bit-identical, not merely close.
#full-gate(ps, camera(azimuth: 25deg, elevation: 15deg))
#full-gate(ps, camera(azimuth: -73deg, elevation: 41deg))

// Perspective and 2d cameras.
#full-gate(ps, camera(azimuth: 25deg, elevation: 15deg, mode: "perspective", distance: 30.0))
#full-gate(((sphere((0, 0), 1), seg((1, 1), (2, 2)), label((0, 3), [x]))), camera-2d())

// Meshes: _prepare-faces explodes + culls Typst-side; the engine keys the
// resulting faces by centroid exactly like sort-prims.
#let mesh-scene = (uv-sphere((0, 0, 0), 1, segments: 6, rings: 3), sphere((0, 4, 0), 0.5))
#full-gate(mesh-scene, camera(azimuth: 25deg, elevation: 15deg))

// Fragment-cutting scenes (the reason the naive ordering gate is ill-defined):
// segments/edges/arrows that pass behind or through spheres and faces, plus an
// opaque face (hides) and a translucent face (cuts only). Covers ortho +
// perspective; the engine's produced fragments must equal the pure path's
// element-for-element, bit-identically.
#let cutting = (
  sphere((0, 0, 0), 1), sphere((2.5, 1, 0.5), 0.7),
  seg((-2, 0, 0), (4, 0, 0)),
  arrow((-2, 0.4, 0.8), (4, 0.4, 0.8)),
  edge((-2, -0.5, -0.5), (4, 1.5, 0.5)),
  face(((1, -1, -1.2), (3, -1, -1.2), (3, 2, -1.2), (1, 2, -1.2)), fill-opacity: 0%),
  face(((-1, 0.5, -1), (1.5, 0.5, -1), (0.2, 0.5, 1.5))),  // translucent: cuts only
)
#full-gate(cutting, cam0)
#full-gate(cutting, camera(azimuth: 25deg, elevation: 15deg))
#full-gate(cutting, camera(azimuth: 25deg, elevation: 15deg, mode: "perspective", distance: 20.0))
#full-gate(mesh-scene + (seg((-2, 0, 0), (2, 0, 0)),), camera(azimuth: 25deg, elevation: 15deg))

// ============ OPT-IN NEGATIVE CONTROL (public entry, both engines compile) ===
// The default path is untouched: engine: "typst" is the pre-Stage-4 code branch
// by construction. Pin that the public entry compiles both ways on the same
// scene; the Makefile `test-equiv` pixel gate carries the byte-equality burden.
#let _sc = build-scene(sphere((0, 0, 0), 1), seg((-2, 0, 0), (2, 0, 0)), label((0, 2, 0), [x]))
#let _cam = camera(azimuth: 25deg, elevation: 15deg)
#render-scene(_sc, _cam)
#render-scene(_sc, _cam, engine: "wasm")

Engine sort OK
