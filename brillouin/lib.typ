#let brillouin-version = version(0, 1, 0)

// Reciprocal lattice vectors (2π convention) from direct vectors or crystal
// parameters, plus a soft-dependency adapter reading a wyckoff structure.
#import "src/reciprocal.typ": reciprocal-vectors, params-to-vectors, from-wyckoff

// First Brillouin zone (Wigner-Seitz cell of the reciprocal lattice) built at
// runtime by half-space intersection, plus its volume invariant.
#import "src/wigner-seitz.typ": bz-cell, bz-volume
