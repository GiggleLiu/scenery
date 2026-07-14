#import "/src/core/symmetry.typ": expand, expand-general
#import "/src/core/data.typ": group-data

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
// ---- expand-general: explicit asymmetric-unit atoms as general positions ----

// NaCl in Fm-3m (225): both atoms sit on special positions; each 4-atom orbit.
#let g225 = group-data("3d", 225)
#let p3 = (true, true, true)
#let nacl = expand-general(g225, (("Na", (0.0, 0.0, 0.0)), ("Cl", (0.5, 0.0, 0.0))), p3)
#assert.eq(nacl.len(), 8)
#for want in ((0.0, 0.0, 0.0), (0.0, 0.5, 0.5), (0.5, 0.0, 0.5), (0.5, 0.5, 0.0)) {
  assert(nacl.any(a => a.element == "Na" and frac-close(a.frac, want, p3)),
    message: "expand-general: missing Na at " + repr(want))
}
#for want in ((0.5, 0.0, 0.0), (0.0, 0.5, 0.0), (0.0, 0.0, 0.5), (0.5, 0.5, 0.5)) {
  assert(nacl.any(a => a.element == "Cl" and frac-close(a.frac, want, p3)),
    message: "expand-general: missing Cl at " + repr(want))
}

// Must agree atom-for-atom with the Wyckoff-letter path (4a + 4b of 225).
#let via-wyckoff = expand(g225, (
  (element: "Na", wyckoff: "a", p: (0.0, 0.0, 0.0)),
  (element: "Cl", wyckoff: "b", p: (0.0, 0.0, 0.0)),
), p3)
#assert.eq(via-wyckoff.len(), 8)
#for a in via-wyckoff {
  assert(nacl.any(b => b.element == a.element and frac-close(b.frac, a.frac, p3)),
    message: "expand-general disagrees with expand at " + repr(a.frac))
}

// Rutile TiO2 in P42/mnm (136): unequal orbit sizes — no multiplicity assert.
#let g136 = group-data("3d", 136)
#let rutile = expand-general(g136, (("Ti", (0.0, 0.0, 0.0)), ("O", (0.305, 0.305, 0.0))), p3)
#assert.eq(rutile.len(), 6)
#assert.eq(rutile.filter(a => a.element == "Ti").len(), 2)
#assert.eq(rutile.filter(a => a.element == "O").len(), 4)
#assert(rutile.any(a => a.element == "O" and frac-close(a.frac, (0.805, 0.195, 0.5), p3)),
  message: "rutile O at (1/2+x, 1/2-x, 1/2) missing")

Symmetry OK
