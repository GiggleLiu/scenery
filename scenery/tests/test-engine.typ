#import "/src/engine.typ": engine-version, engine-sort
#import "/src/scene.typ": sphere, seg, edge, arrow, face, label, build-scene, mesh
#import "/src/shape.typ": uv-sphere
#import "/src/camera.typ": camera, camera-2d
#import "/src/render.typ": sort-prims, _prepare-faces

#assert.eq(engine-version(), "scenery-engine 0.1.0")

// ============ ORDERING-EQUIVALENCE GATE, level (a) ============
// Scenes where NEITHER path splits anything: engine output must be EXACTLY
// equal (assert.eq on full dicts, depth included) to the pure path. Until
// Task 3 the engine does not clip, so the pure comparator is sort-prims over
// _prepare-faces output (the same keys-and-stable-sort stage the engine mirrors).
#let gate(prims, cam) = {
  let prepared = _prepare-faces(prims, cam)
  assert.eq(engine-sort(prepared, cam), sort-prims(prepared, cam))
}

// The documented 4-prim scene (test-render.typ) + its shuffle, exact depths.
#let cam0 = camera(azimuth: 0deg, elevation: 0deg)
#let ps = (
  edge((0, -1, -1), (0, -1, 1)),
  face(((-1, 1, -1), (1, 1, -1), (0, 1, 1))),
  seg((0, 3, -1), (0, 3, 1)),
  sphere((0, 5, 0), 1),
  label((0, 0, 0), [L]),
)
#gate(ps, cam0)
#gate(ps.rev(), cam0)

// Generic camera: the engine consumes the SAME cos/sin values Typst computed,
// so depth keys are bit-identical, not merely close.
#gate(ps, camera(azimuth: 25deg, elevation: 15deg))
#gate(ps, camera(azimuth: -73deg, elevation: 41deg))

// Perspective and 2d cameras.
#gate(ps, camera(azimuth: 25deg, elevation: 15deg, mode: "perspective", distance: 30.0))
#gate(((sphere((0, 0), 1), seg((1, 1), (2, 2)), label((0, 3), [x]))), camera-2d())

// Meshes: _prepare-faces explodes + culls Typst-side; the engine keys the
// resulting faces by centroid exactly like sort-prims.
#let mesh-scene = (uv-sphere((0, 0, 0), 1, segments: 6, rings: 3), sphere((0, 4, 0), 0.5))
#gate(mesh-scene, camera(azimuth: 25deg, elevation: 15deg))

Engine sort OK
