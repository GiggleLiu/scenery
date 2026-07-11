// Minimal 3-vector / 3x3-matrix helpers for the symmetry engine.
// Plain arrays only; deliberately cetz-free so the engine has no renderer deps.
#let vadd(a, b) = a.zip(b).map(((x, y)) => x + y)
#let vsub(a, b) = a.zip(b).map(((x, y)) => x - y)
#let vscale(a, s) = a.map(x => x * s)
#let vdot(a, b) = a.zip(b).map(((x, y)) => x * y).sum()
#let vcross(a, b) = (
  a.at(1) * b.at(2) - a.at(2) * b.at(1),
  a.at(2) * b.at(0) - a.at(0) * b.at(2),
  a.at(0) * b.at(1) - a.at(1) * b.at(0),
)
#let vlen(a) = calc.sqrt(vdot(a, a))
#let vnorm(a) = vscale(a, 1 / vlen(a))
#let mvec(m, v) = m.map(row => vdot(row, v))
#let lerp(a, b, t) = vadd(vscale(a, 1 - t), vscale(b, t))
