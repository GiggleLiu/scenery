#import "/src/kpath.typ": kpoints, kpath, kpath-data

// Ground truth: seekpath (HPKOT), the machine-checkable realization of the
// Setyawan-Curtarolo (2010) k-point tables. See tools/gen_kpath_fixtures.py for
// the basis mapping and the standardized-params explanation.
#let fx = json("/tests/fixtures/kpath.json")
#let tol = 1e-6

// Max abs component difference between two 3-vectors.
#let vdiff(x, y) = calc.max(
  calc.abs(x.at(0) - y.at(0)),
  calc.abs(x.at(1) - y.at(1)),
  calc.abs(x.at(2) - y.at(2)),
)

// --- per-case fixture verification ------------------------------------------
#for case in fx.cases {
  let got = kpath-data(case.bravais, case.params)

  // (1) variant selection must match seekpath's extended-Bravais symbol.
  assert(got.variant == case.variant,
    message: case.name + ": variant " + got.variant + " != " + case.variant)

  // Unit sanity: Gamma is the origin in every table.
  assert(vdiff(got.points.at("Γ"), (0, 0, 0)) < tol,
    message: case.name + ": Gamma not at origin")

  // (2) every k-point NAME shared by our SC-2010 table and the seekpath fixture
  //     must agree in coordinates to <= 1e-6 (in the shared primitive reciprocal
  //     basis). At least Gamma is always shared; for the agreeing lattices this
  //     covers the whole table.
  let shared = 0
  for (name, coord) in case.points {
    if name in got.points {
      shared += 1
      assert(vdiff(got.points.at(name), coord) < tol,
        message: case.name + ": point " + name + " " + repr(got.points.at(name))
          + " != fixture " + repr(coord))
    }
  }
  assert(shared >= 1, message: case.name + ": no shared point names")

  // (3) recommended path: compare segment-list exactly. Because our module ports
  //     the HPKOT tables that seekpath itself evaluates, the path matches for
  //     every case (stronger than the issue's "exact where conventions agree").
  //     `path_agrees_sc2010` records, per case, whether this HPKOT path also
  //     equals the SC-2010 *paper* path or diverges from it (documentation).
  assert(got.path.len() == case.path.len(),
    message: case.name + ": path length " + repr(got.path.len()) + " != " + repr(case.path.len()))
  for (seg, ref) in got.path.zip(case.path) {
    assert(seg.at(0) == ref.at(0) and seg.at(1) == ref.at(1),
      message: case.name + ": path segment " + repr(seg) + " != " + repr(ref))
  }
}

// --- coverage assertions: every crystal system is exercised -----------------
#let variants-seen = fx.cases.map(c => c.variant)
#for v in ("cP2", "cF2", "cI1", "tP1", "tI1", "tI2", "oP1", "oF1", "oF3",
          "oI1", "oC1", "hP2", "hR1", "hR2", "mP1", "mC1", "mC2", "mC3", "aP2", "aP3") {
  assert(v in variants-seen, message: "coverage: variant " + v + " missing from fixtures")
}

// --- NEGATIVE CONTROL: cross-variant params vs points MUST mismatch ----------
// Feeding the oF1 params must resolve to oF1 (not the fixture's wrong oF3), and
// the resulting points must NOT match the oF3 expected points -- proving the
// variant selection has teeth.
#let nc = fx.negative_control
#let nc-got = kpath-data("oF", nc.params)
#assert(nc-got.variant == nc.right_variant,
  message: "negative control: expected " + nc.right_variant + " got " + nc-got.variant)
#assert(nc-got.variant != nc.wrong_variant,
  message: "negative control: variant selection failed to distinguish variants")

// The oF1 points must differ from the oF3 expected points on some shared name.
#let mismatch-found = {
  let found = false
  for (name, coord) in nc.wrong_points {
    if name in nc-got.points and vdiff(nc-got.points.at(name), coord) > tol {
      found = true
    }
  }
  found
}
#assert(mismatch-found,
  message: "negative control: oF1 points unexpectedly matched oF3 expectations")

// --- validation guards: inconsistent params must panic ----------------------
// (cubic rejects a non-90 angle; monoclinic rejects beta == 90.)
// These are compile-time panics; we just document them here rather than catch.

kpath OK
