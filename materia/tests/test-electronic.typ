#import "/lib.typ": energy-level, orbital-column, correlate, mo-model, bond-order, mo-scene, mo-diagram

#let left = orbital-column("left", (
  energy-level("left-s", -10, occupation: 2),
  energy-level("left-p", -3, degeneracy: 2, occupation: 2),
))
#let middle = orbital-column("middle", (
  energy-level("bond", -8, occupation: 2, role: "bonding"),
  energy-level("nonbond", -2, occupation: 2),
  energy-level("antibond", 2, occupation: 0, role: "antibonding"),
), kind: "molecular")
#let model = mo-model(
  (left, middle),
  correlations: (
    correlate("left-s", "bond"),
    correlate("left-p", "nonbond"),
  ),
)

#assert.eq(bond-order(model), 1)
#let scene = mo-scene(model)
#assert(type(scene) == dictionary and "prims" in scene and "bbox" in scene)
#assert(scene.bbox.min.at(0) < scene.bbox.max.at(0))
#assert.eq(scene.prims.filter(p => p.kind == "arrow").len(), 9,
  message: "eight electron arrows plus the energy arrow")
#assert.eq(scene.prims.filter(p => p.at("dash", default: none) == "dashed").len(), 2)

#mo-diagram(model, width: 8cm)
