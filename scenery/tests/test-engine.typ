#import "/src/engine.typ": engine-version, engine-sort
#import "/src/scene.typ": sphere, seg, edge, arrow, face, label
#import "/src/camera.typ": camera, camera-2d

// The second wasm artifact loads and reports its version.
#assert.eq(engine-version(), "scenery-engine 0.1.0")

// CBOR boundary smoke: every prim kind round-trips; the stub returns one
// record per prim carrying the ORIGINAL primitive's styling hooks (index
// reassembly works). Order/depth semantics land in Task 2.
#let ps = (
  sphere((0.0, 5.0, 0.0), 1.0, color: red),
  seg((0.0, 3.0, -1.0), (0.0, 3.0, 1.0)),
  edge((0.0, -1.0, -1.0), (0.0, -1.0, 1.0)),
  arrow((0.0, 2.0, 0.0), (1.0, 2.0, 0.0)),
  face(((-1.0, 1.0, -1.0), (1.0, 1.0, -1.0), (0.0, 1.0, 1.0))),
  label((0.0, 0.0, 0.0), [L]),
)
#let out = engine-sort(ps, camera(azimuth: 25deg, elevation: 15deg))
#assert.eq(out.len(), 6)
#assert.eq(out.map(p => p.kind), ("sphere", "seg", "edge", "arrow", "face", "label"))
#assert.eq(out.first().color, red, message: "styling must survive reassembly")
#assert(out.all(p => "depth" in p))

Engine boundary OK
