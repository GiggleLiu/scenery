// Public structure() constructor: builds the structure value consumed by
// everything downstream. Validation lives in the pure check-site() helper.
#import "data.typ": group-data, element-info
#import "lattice.typ": lattice-params, lattice-vectors, frac-to-cart
#import "symmetry.typ": expand

/// Pure validator for a Wyckoff-input site against a group's data.
/// Returns (ok: bool, msg: str); never panics, so failure cases are testable.
#let check-site(group, site) = {
  if "element" not in site or "wyckoff" not in site {
    return (ok: false, msg: "each site needs (element: .., wyckoff: ..)")
  }
  if site.wyckoff not in group.wyckoff {
    return (ok: false, msg: "group " + group.symbol + " has no Wyckoff position '" + site.wyckoff
      + "' (available: " + group.wyckoff.keys().join(", ") + ")")
  }
  let w = group.wyckoff.at(site.wyckoff)
  let extra = site.keys().filter(k => k not in ("element", "wyckoff") and k not in w.vars)
  if extra.len() > 0 {
    return (ok: false, msg: "Wyckoff " + str(w.mult) + site.wyckoff + " of " + group.symbol
      + " does not have free coordinate(s) " + extra.join(", ")
      + if w.vars.len() > 0 { " (free: " + w.vars.join(", ") + ")" } else { " (no free coordinates)" })
  }
  let missing = w.vars.filter(v => v not in site)
  if missing.len() > 0 {
    return (ok: false, msg: "Wyckoff " + str(w.mult) + site.wyckoff + " of " + group.symbol
      + " requires free coordinate(s) " + missing.join(", "))
  }
  (ok: true, msg: "")
}

/// Build a structure value. Exactly one of spacegroup:, layergroup:, or an
/// explicit lattice: array (with atoms:) must be supplied.
#let structure(spacegroup: none, layergroup: none, lattice: (:), sites: (), atoms: ()) = {
  let explicit = type(lattice) == array
  let n-modes = (int(spacegroup != none) + int(layergroup != none) + int(explicit))
  assert(n-modes == 1, message: "wyckoff: give exactly one of spacegroup:, layergroup:, or an explicit lattice: array with atoms:")

  if explicit {
    assert(lattice.len() == 3 and atoms.len() > 0,
      message: "wyckoff: explicit form needs lattice: (v1, v2, v3) and a non-empty atoms: list")
    let vecs = lattice.map(v => v.map(float))
    let periodic = (true, true, true)
    let alist = atoms.enumerate().map(((i, (el, frac))) => {
      let _ = element-info(el)  // validates the symbol
      (element: el, frac: frac.map(float), cart: frac-to-cart(vecs, frac.map(float), periodic), site: i)
    })
    return (kind: "3d", group: none, vectors: vecs, periodic: periodic, atoms: alist)
  }

  let (kind, number) = if spacegroup != none { ("3d", spacegroup) } else { ("layer", layergroup) }
  let group = group-data(kind, number)
  let periodic = (true, true, kind == "3d")
  assert(sites.len() > 0, message: "wyckoff: sites: must contain at least one site")
  for site in sites {
    let chk = check-site(group, site)
    assert(chk.ok, message: "wyckoff: " + chk.msg)
  }
  let esites = sites.map(s => (
    element: s.element,
    wyckoff: s.wyckoff,
    p: ("x", "y", "z").map(v => if v in s { float(s.at(v)) } else { 0.0 }),
  ))
  for s in sites { let _ = element-info(s.element) }
  let params = lattice-params(group.ltype, lattice)
  let vecs = lattice-vectors(params)
  let alist = expand(group, esites, periodic).map(a =>
    (..a, cart: frac-to-cart(vecs, a.frac, periodic)))
  (kind: kind, group: (number: number, symbol: group.symbol), vectors: vecs, periodic: periodic, atoms: alist)
}
