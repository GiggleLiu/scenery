#import "/src/core/lattice.typ": *

// cubic: only a; all vectors orthogonal
#let p = lattice-params("cubic", (a: 5.64))
#assert(p.b == 5.64 and p.c == 5.64 and p.gamma == 90.0)
#let v = lattice-vectors(p)
#assert(v.at(0) == (5.64, 0.0, 0.0))
#assert(calc.abs(v.at(2).at(2) - 5.64) < 1e-9)

// hexagonal: gamma filled as 120
#let ph = lattice-params("hexagonal", (a: 3.16, c: 12.3))
#assert(ph.gamma == 120.0)
#let vh = lattice-vectors(ph)
#assert(calc.abs(vh.at(1).at(0) - (-1.58)) < 0.01, message: "b_x = a cos120")

// angles may be typst angles
#let pm = lattice-params("monoclinic", (a: 5.1, b: 5.2, c: 5.3, beta: 99.2deg))
#assert(calc.abs(pm.beta - 99.2) < 1e-9)

// layer/hexagonal2d: only a; frac-to-cart passes z through in angstrom
#let p2 = lattice-params("hexagonal2d", (a: 3.16))
#let v2 = lattice-vectors(p2)
#let cart = frac-to-cart(v2, (1.0/3.0, 2.0/3.0, 1.56), (true, true, false))
#assert(calc.abs(cart.at(2) - 1.56) < 1e-9)

// validation is testable without a panic
#assert(not check-lattice-args("cubic", (a: 5.6, b: 5.6)).ok)
#assert(not check-lattice-args("tetragonal", (a: 5.6)).ok)
#assert(not check-lattice-args("cubic", (a: none)).ok)
#assert(check-lattice-args("triclinic", (a: 1, b: 2, c: 3, alpha: 80, beta: 95, gamma: 103)).ok)
Lattice OK
