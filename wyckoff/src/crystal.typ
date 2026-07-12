#import "figure.typ": build-scene, render, draw-scene

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
  colors: (:),
  width: 8cm,
) = {
  let scene = build-scene(structure, view: view, supercell: supercell,
    bonds: bonds, polyhedra: polyhedra, labels: labels, radius: radius,
    colors: colors)
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
  colors: (:),
  scale: 1.0,
) = {
  let scene = build-scene(structure, view: view, supercell: supercell,
    bonds: bonds, polyhedra: polyhedra, labels: labels, radius: radius,
    colors: colors)
  draw-scene(scene, scale: scale)
}

/// Render a non-periodic molecule: atoms + bonds, no unit cell, no
/// crystallographic triad. Same scene options as crystal().
#let molecule(
  structure,
  view: _default-view,
  bonds: auto,
  labels: false,
  legend: true,
  radius: 0.45,
  colors: (:),
  mode: "ball-and-stick",
  width: 8cm,
) = {
  let scene = build-scene(structure, view: view, supercell: (1, 1, 1),
    bonds: bonds, polyhedra: (), labels: labels, radius: radius, colors: colors)
  render(scene, width: width, legend: legend, axes-info: none)
}
