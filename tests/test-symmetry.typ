#import "/src/symmetry.typ": expand
#import "/src/data.typ": group-data

#let frac-close(p, q, periodic) = {
  range(3).all(i => {
    let d = calc.abs(p.at(i) - q.at(i))
    let d = if periodic.at(i) { calc.min(d, 1.0 - d) } else { d }
    d < 1e-4
  })
}

#let fixtures = ("nacl", "cscl", "diamond", "zincblende", "wurtzite", "rutile",
                 "perovskite", "fluorite", "corundum", "baddeleyite",
                 "graphene", "hbn", "mos2")

#for name in fixtures {
  let fx = json("/tests/fixtures/" + name + ".json")
  let periodic = (true, true, fx.kind == "3d")
  let group = group-data(fx.kind, fx.group)
  let sites = fx.sites.map(s => (element: s.element, wyckoff: s.wyckoff, p: s.p))
  let atoms = expand(group, sites, periodic)
  assert(atoms.len() == fx.expected.natoms,
    message: fx.name + ": got " + str(atoms.len()) + " atoms, want " + str(fx.expected.natoms))
  for want in fx.expected.atoms {
    assert(
      atoms.any(a => a.element == want.element and frac-close(a.frac, want.frac, periodic)),
      message: fx.name + ": missing " + want.element + " at " + repr(want.frac),
    )
  }
}

// multiplicity spot-sweep with generic parameters (generator already sweeps ALL groups)
#for (kind, num) in (("3d", 2), ("3d", 14), ("3d", 62), ("3d", 136), ("3d", 167),
                     ("3d", 186), ("3d", 194), ("3d", 216), ("3d", 225), ("3d", 227), ("3d", 230),
                     ("layer", 1), ("layer", 8), ("layer", 49), ("layer", 65), ("layer", 78), ("layer", 80)) {
  let g = group-data(kind, num)
  let periodic = (true, true, kind == "3d")
  for (letter, w) in g.wyckoff {
    let atoms = expand(g, ((element: "C", wyckoff: letter, p: (0.1234, 0.2618, 0.3711)),), periodic)
    assert(atoms.len() == w.mult,
      message: kind + " " + str(num) + " wyckoff " + letter + ": " + str(atoms.len()) + " != " + str(w.mult))
  }
}
Symmetry OK
