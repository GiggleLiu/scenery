#import "scene.typ": build-scene
#import "render.typ": render, draw-scene

#let _default-view = (azimuth: 25deg, elevation: 15deg)

#let crystal(
  structure,
  view: _default-view,
  supercell: (1, 1, 1),
  bonds: auto,
  polyhedra: (),
  labels: false,
  legend: true,
  axes: true,
  radius: 0.45,
  width: 8cm,
) = {
  let scene = build-scene(structure, view: view, supercell: supercell,
    bonds: bonds, polyhedra: polyhedra, labels: labels, radius: radius)
  render(scene, width: width, legend: legend,
    axes-info: if axes {
      (vectors: structure.vectors, view: view,
       n-axes: if structure.periodic.at(2) { 3 } else { 2 })
    } else { none })
}

#let crystal-group(
  structure,
  view: _default-view,
  supercell: (1, 1, 1),
  bonds: auto,
  polyhedra: (),
  labels: false,
  radius: 0.45,
  scale: 1.0,
) = {
  let scene = build-scene(structure, view: view, supercell: supercell,
    bonds: bonds, polyhedra: polyhedra, labels: labels, radius: radius)
  draw-scene(scene, scale: scale)
}
