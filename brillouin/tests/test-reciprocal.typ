#import "/src/reciprocal.typ": reciprocal-vectors, params-to-vectors, from-wyckoff

#let fx = json("/tests/fixtures/reciprocal.json")
#let tol = 1e-9

// Max component-wise distance between two lists of 3-vectors.
#let maxdiff(got, want) = {
  let m = 0.0
  for (g, w) in got.zip(want) {
    for (x, y) in g.zip(w) {
      m = calc.max(m, calc.abs(x - y))
    }
  }
  m
}

// --- the three ground-truth cases: direct-vector input AND params input -------
#for case in fx.cases {
  // direct-vector input path
  let from-direct = reciprocal-vectors(case.direct)
  assert(maxdiff(from-direct, case.reciprocal) < tol,
    message: case.name + " (direct input): " + repr(maxdiff(from-direct, case.reciprocal)))

  // params input path — params->vectors must match wyckoff's orientation, so the
  // reciprocal built from params agrees with the pymatgen ground truth too.
  let from-params = reciprocal-vectors(case.ltype-params)
  assert(maxdiff(from-params, case.reciprocal) < tol,
    message: case.name + " (params input): " + repr(maxdiff(from-params, case.reciprocal)))
}

// --- adapter: a minimal wyckoff-NaCl-shaped structure -> cubic answer ----------
#let nacl = (vectors: ((5.64, 0, 0), (0, 5.64, 0), (0, 0, 5.64)))
#let adapted = from-wyckoff(nacl)
#assert(maxdiff(adapted, fx.nacl_adapter.reciprocal) < tol,
  message: "adapter: " + repr(maxdiff(adapted, fx.nacl_adapter.reciprocal)))

// --- negative control: the correct 2π answer must NOT match the no-2π entry ----
#let cubic-correct = reciprocal-vectors(fx.cubic_no_2pi.direct)
#assert(maxdiff(cubic-correct, fx.cubic_no_2pi.reciprocal) > tol,
  message: "negative control unexpectedly matched the no-2π fixture")

Reciprocal OK
