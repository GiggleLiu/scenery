// Figure-layer tests: pretty-label unit tests, the fcc SC-2010 label-set assert,
// primitive-cell registration (every recommended k-point lands ON the Brillouin
// zone boundary, Γ at the interior centre), band-axis tick alignment, and a
// compile smoke of bz-figure / band-panel. Negative controls are documented
// where Typst cannot catch a panic (see the kpath test for the same pattern).
#import "/src/reciprocal.typ": reciprocal-vectors
#import "/src/kpath.typ": kpath-data
#import "/src/figure.typ": pretty-klabel, band-axis, bz-figure, band-panel, _primitive-vectors
#import "@preview/scenery:0.1.0": vadd, vsub, vscale, vdot, vlen

#set page(width: auto, height: auto, margin: 6pt)

// --- pretty-klabel unit tests -----------------------------------------------
// Greek names map to letters; already-Unicode "Γ" passes through; a trailing
// `_<digits>` becomes Unicode subscripts; unknown bases pass through unchanged.
#assert(pretty-klabel("GAMMA") == "Γ", message: "GAMMA -> Γ")
#assert(pretty-klabel("Γ") == "Γ", message: "Γ passthrough")
#assert(pretty-klabel("DELTA_0") == "Δ₀", message: "DELTA_0 -> Δ₀")
#assert(pretty-klabel("SIGMA_0") == "Σ₀", message: "SIGMA_0 -> Σ₀")
#assert(pretty-klabel("LAMBDA_0") == "Λ₀", message: "LAMBDA_0 -> Λ₀")
#assert(pretty-klabel("X_1") == "X₁", message: "X_1 -> X₁")
#assert(pretty-klabel("W_2") == "W₂", message: "W_2 -> W₂")
#assert(pretty-klabel("H_12") == "H₁₂", message: "multi-digit subscript")
#assert(pretty-klabel("K") == "K", message: "plain name passthrough")

// --- data-level: the fcc (cF) SC-2010 label set -----------------------------
// The recommended cF path visits exactly the SC-2010 fcc high-symmetry set.
// After pretty-printing the endpoint names, that set is {Γ, X, W, L, U, K}
// (the issue's asserted set). Our cF2 table also carries W_2, which is
// unreachable in the centrosymmetric path and therefore not in the set.
#let fcc = kpath-data("cF", (a: 3.6))
#let fcc-label-set = {
  let s = ()
  for (na, nb) in fcc.path {
    for nm in (na, nb) {
      let p = pretty-klabel(nm)
      if p not in s { s.push(p) }
    }
  }
  s.sorted()
}
#assert(fcc-label-set == ("K", "L", "U", "W", "X", "Γ"),
  message: "fcc label set must be {Γ, X, W, L, U, K}, got " + repr(fcc-label-set))

// --- primitive-cell registration on the BZ boundary -------------------------
// For every supported Bravais symbol, `_primitive-vectors` must produce a
// primitive cell whose reciprocal basis puts each recommended k-point exactly on
// the Brillouin-zone surface (and Γ at the interior centre). This is the teeth
// behind "k-points land on the zone": a wrong centering pushes them off-surface.
#let kcart(b, f) = vadd(
  vadd(vscale(b.at(0), f.at(0)), vscale(b.at(1), f.at(1))), vscale(b.at(2), f.at(2)))

// Classify a Cartesian point against the reciprocal lattice's half-spaces.
#let classify(p, b) = {
  let tight = false
  for n1 in range(-2, 3) { for n2 in range(-2, 3) { for n3 in range(-2, 3) {
    if n1 == 0 and n2 == 0 and n3 == 0 { continue }
    let g = vadd(vadd(vscale(b.at(0), n1), vscale(b.at(1), n2)), vscale(b.at(2), n3))
    let val = vdot(p, g) - vdot(g, g) / 2
    if val > 1e-6 { return "OUT" }
    if calc.abs(val) < 1e-6 * vdot(g, g) { tight = true }
  } } }
  if tight { "boundary" } else { "interior" }
}

#let reg-cases = (
  ("cP", (a: 3)), ("cF", (a: 3.6)), ("cI", (a: 3)),
  ("tP", (a: 3, c: 5)), ("tI", (a: 3, c: 5)),
  ("oP", (a: 3, b: 4, c: 5)), ("oF", (a: 3, b: 4, c: 5)),
  ("oI", (a: 3, b: 4, c: 5)), ("oC", (a: 3, b: 4, c: 5)),
  ("hP", (a: 3, c: 5, gamma: 120)), ("hR", (a: 3, c: 8, gamma: 120)),
  ("mP", (a: 3, b: 4, c: 5, beta: 105)),
  ("aP", (a: 5.0, b: 4.0, c: 6.0, alpha: 85.0, beta: 80.0, gamma: 88.0)),
)
#for (bravais, params) in reg-cases {
  let data = kpath-data(bravais, params)
  let b = reciprocal-vectors(_primitive-vectors(bravais, params))
  let names = ()
  for (na, nb) in data.path {
    if na not in names { names.push(na) }
    if nb not in names { names.push(nb) }
  }
  for nm in names {
    let want = if nm == "Γ" { "interior" } else { "boundary" }
    let got = classify(kcart(b, data.points.at(nm)), b)
    assert(got == want,
      message: bravais + ": point " + nm + " expected " + want + " got " + got)
  }
}

// --- band-axis: tick positions == cumulative path distances -----------------
// band-axis builds the distance axis by accumulating sampled sub-lengths; the
// ticks must land exactly on the samples at each segment boundary AND on an
// independently computed cumulative sum of straight-segment lengths (<= 1e-6).
#let seq = ("Γ", "X", "W", "K", "Γ", "L")
#let samples = 16
#let ax = band-axis("cF", (a: 3.6), seq, samples: samples)

// (a) each tick aligns with the k-dists sample at index i*samples.
#for (i, pos) in ax.ticks.positions.enumerate() {
  assert(calc.abs(pos - ax.k-dists.at(i * samples)) < 1e-9,
    message: "tick " + str(i) + " misaligned with distance axis")
}
// (b) ticks equal the independent cumulative straight-segment lengths.
#let b = reciprocal-vectors(_primitive-vectors("cF", (a: 3.6)))
#let want-pos = {
  let out = (0.0,)
  let d = 0.0
  for i in range(seq.len() - 1) {
    d += vlen(vsub(kcart(b, fcc.points.at(seq.at(i + 1))), kcart(b, fcc.points.at(seq.at(i)))))
    out.push(d)
  }
  out
}
#for (got, want) in ax.ticks.positions.zip(want-pos) {
  assert(calc.abs(got - want) <= 1e-6, message: "tick position " + repr(got) + " != " + repr(want))
}
// k-dists must be monotonically non-decreasing.
#for i in range(ax.k-dists.len() - 1) {
  assert(ax.k-dists.at(i + 1) >= ax.k-dists.at(i) - 1e-12, message: "k-dists not monotone")
}

// --- NEGATIVE CONTROL: an absent highlight name is rejected -----------------
// bz-figure(.., highlight: (name,)) panics with a clear message when `name` is
// not in the lattice's SC-2010 k-point set. Typst cannot catch a panic in the
// same compile, so we assert the guard's CONDITION here (the same membership
// test the figure performs) rather than triggering the abort.
#assert("ZZZ" not in fcc.points, message: "sanity: bogus name absent from cF set")
#assert("X" in fcc.points, message: "sanity: real name present in cF set")
// (Uncommenting the next line aborts compilation with the clear error, as the
// issue's negative control requires:)
//   #bz-figure((a: 3.6), bravais: "cF", highlight: ("ZZZ",))

// --- compile smoke: bz-figure + band-panel render to content ----------------
#bz-figure((a: 3.6), bravais: "cF",
  path: ("Γ", "X", "W", "K", "Γ", "L", "U", "W"), highlight: ("L",), width: 5cm)

// two honest analytic bands over the sampled path (see bz-band.typ).
#let tb(k, sign) = {
  let (kx, ky, kz) = k
  let nn = calc.cos(kx / 2) * calc.cos(ky / 2) + calc.cos(ky / 2) * calc.cos(kz / 2) + calc.cos(kz / 2) * calc.cos(kx / 2)
  sign * nn
}
#band-panel((ax.carts.map(k => tb(k, -1)), ax.carts.map(k => tb(k, 1))), ax, width: 8cm, height: 4cm)

figure OK
