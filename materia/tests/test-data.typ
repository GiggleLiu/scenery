#import "/src/core/data.typ": element-info

#let na = element-info("Na")
#assert(na.r-cov > 1.5 and na.r-cov < 1.8, message: "Na covalent radius ~1.66")
#assert(type(na.color) == color, message: "color must be a Typst color")
#let o = element-info("O")
#assert(o.r-cov < 0.8, message: "O covalent radius ~0.66")
#assert(element-info("Ti").r-atom > 1.0)

// van der Waals radii (issue #27): pymatgen table, Å.
#assert(calc.abs(o.r-vdw - 1.52) < 0.01, message: "O vdW radius ~1.52")
#assert(calc.abs(element-info("C").r-vdw - 1.70) < 0.01, message: "C vdW radius ~1.70")
#assert(calc.abs(element-info("H").r-vdw - 1.10) < 0.05, message: "H vdW radius ~1.10")
#assert(na.r-vdw > 2.2 and na.r-vdw < 2.35, message: "Na vdW radius ~2.27")
#assert(o.r-vdw > o.r-atom and na.r-vdw > na.r-atom,
  message: "vdW radius must exceed the atomic radius")
#assert(type(o.r-vdw) == float, message: "r-vdw must be a float")

#import "/src/core/data.typ": group-data

#let sg225 = group-data("3d", 225)
#assert(sg225.symbol == "Fm-3m")
#assert(sg225.ops.len() == 192, message: "Fm-3m has 192 ops incl. centering")
#assert(sg225.wyckoff.a.mult == 4)
#assert(sg225.wyckoff.a.vars == ())
#assert(sg225.ltype == "cubic")

#let lg78 = group-data("layer", 78)
#assert(lg78.symbol.contains("6"), message: "LG 78 is p-6m2")
#assert(lg78.ltype == "hexagonal2d")
#assert(group-data("3d", 1).ops.len() == 1)

Data OK
