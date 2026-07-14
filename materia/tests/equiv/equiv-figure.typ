// materia pixel-equivalence gate: crystal() and molecule() through
// both engines must render BYTE-IDENTICALLY. This compiles twice —
// --input engine=typst and --input engine=wasm — and materia/Makefile's
// `test-equiv` `cmp`s the two PNGs. It exercises the accelerator's cull +
// detect_bonds + clip + sort on a periodic scene (with bonds + cell edges +
// occlusion), a molecule scene (benzene ring, bonds + occlusion), and a
// perspective supercell — ortho AND perspective.
#import "/lib.typ": structure, crystal, molecule, prototypes
#let eng = sys.inputs.at("engine", default: "typst")
#set page(width: auto, height: auto, margin: 0.5cm)
#crystal(prototypes.rocksalt("Na", "Cl", a: 5.64), engine: eng, width: 6cm)
#let ring(el, r) = range(6).map(k =>
  (el, (r * calc.cos(k * 60deg), r * calc.sin(k * 60deg), 0.0)))
#molecule(structure(atoms: ring("C", 1.39) + ring("H", 2.48)), engine: eng, width: 6cm)
#crystal(prototypes.rocksalt("Na", "Cl", a: 5.64), supercell: (2, 2, 1), engine: eng,
  view: (azimuth: 25deg, elevation: 15deg, mode: "perspective", distance: 18), width: 6cm)
