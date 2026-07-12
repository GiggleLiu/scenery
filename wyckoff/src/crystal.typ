#import "figure.typ": build-scene, render, draw-scene

#let _default-view = (azimuth: 25deg, elevation: 15deg)

#let crystal(
  structure,
  view: _default-view,
  supercell: (1, 1, 1),
  mode: "ball-and-stick",
  bonds: auto,
  bond-color: auto,
  polyhedra: (),
  labels: false,
  legend: true,
  axes: true,
  radius: auto,
  colors: (:),
  width: 8cm,
) = {
  let scene = build-scene(structure, view: view, supercell: supercell,
    mode: mode, bonds: bonds, bond-color: bond-color, polyhedra: polyhedra,
    labels: labels, radius: radius, colors: colors)
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
  mode: "ball-and-stick",
  bonds: auto,
  bond-color: auto,
  polyhedra: (),
  labels: false,
  radius: auto,
  colors: (:),
  scale: 1.0,
) = {
  let scene = build-scene(structure, view: view, supercell: supercell,
    mode: mode, bonds: bonds, bond-color: bond-color, polyhedra: polyhedra,
    labels: labels, radius: radius, colors: colors)
  draw-scene(scene, scale: scale)
}

/// Render a non-periodic molecule: atoms + bonds, no unit cell, no
/// crystallographic triad. Same scene options as crystal().
/// mode: "ball-and-stick" (default) | "space-filling"/"cpk" | "licorice".
#let molecule(
  structure,
  view: _default-view,
  bonds: auto,
  bond-color: auto,
  labels: false,
  legend: true,
  radius: auto,
  colors: (:),
  mode: "ball-and-stick",
  width: 8cm,
) = {
  let scene = build-scene(structure, view: view, supercell: (1, 1, 1),
    mode: mode, bonds: bonds, bond-color: bond-color, polyhedra: (),
    labels: labels, radius: radius, colors: colors)
  render(scene, width: width, legend: legend, axes-info: none)
}
