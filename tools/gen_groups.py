"""Generate data/spacegroups.json (230 groups) and data/layergroups.json (80 layer groups).

Source: pyxtal.symmetry.Group (Bilbao-derived tables, standard ITA settings,
conventional cells; trigonal R groups in hexagonal setting).

Self-checks performed here (so the Typst side can trust the data):
  1. Orbit of each Wyckoff representative under `ops` has size == multiplicity.
  2. Every op leaves the lattice metric invariant for the group's lattice type.
  3. Layer-group ops never mix z with x,y and have zero z-translation.
"""
import json
from fractions import Fraction
from pathlib import Path

import numpy as np
from pyxtal.symmetry import Group

DATA = Path(__file__).resolve().parent.parent / "materia" / "data"

def ltype_3d(n):
    if n <= 2: return "triclinic"
    if n <= 15: return "monoclinic"
    if n <= 74: return "orthorhombic"
    if n <= 142: return "tetragonal"
    if n <= 167: return "trigonal"
    if n <= 194: return "hexagonal"
    return "cubic"

def ltype_layer(n):
    # ITA Vol. E: 1-7 oblique, 8-48 rectangular, 49-64 square, 65-80 hexagonal
    if n <= 7: return "oblique"
    if n <= 48: return "rectangular"
    if n <= 64: return "square"
    return "hexagonal2d"

# Representative metric tensors per lattice type (arbitrary but generic values)
def metric(ltype):
    import math
    def cell(a, b, c, al, be, ga):
        al, be, ga = map(math.radians, (al, be, ga))
        av = np.array([a, 0, 0])
        bv = np.array([b*math.cos(ga), b*math.sin(ga), 0])
        cx = c*math.cos(be)
        cy = c*(math.cos(al) - math.cos(be)*math.cos(ga))/math.sin(ga)
        cz = math.sqrt(max(c*c - cx*cx - cy*cy, 0))
        cv = np.array([cx, cy, cz])
        L = np.vstack([av, bv, cv])
        return L @ L.T
    return {
        "triclinic":    cell(3.1, 4.3, 5.7, 81, 94, 103),
        "monoclinic":   cell(3.1, 4.3, 5.7, 90, 104, 90),
        "orthorhombic": cell(3.1, 4.3, 5.7, 90, 90, 90),
        "tetragonal":   cell(3.1, 3.1, 5.7, 90, 90, 90),
        "trigonal":     cell(3.1, 3.1, 5.7, 90, 90, 120),
        "hexagonal":    cell(3.1, 3.1, 5.7, 90, 90, 120),
        "cubic":        cell(3.1, 3.1, 3.1, 90, 90, 90),
        "oblique":      cell(3.1, 4.3, 1.0, 90, 90, 103),
        "rectangular":  cell(3.1, 4.3, 1.0, 90, 90, 90),
        "square":       cell(3.1, 3.1, 1.0, 90, 90, 90),
        "hexagonal2d":  cell(3.1, 3.1, 1.0, 90, 90, 120),
    }[ltype]

def frac_round(x):
    """Snap float translations/matrix entries to exact simple fractions."""
    f = Fraction(x).limit_denominator(12)
    assert abs(float(f) - x) < 1e-8, f"non-fractional entry {x}"
    return float(f)

def encode_op(affine):
    R = [[frac_round(affine[i][j]) for j in range(3)] for i in range(3)]
    t = [frac_round(affine[i][3]) % 1.0 for i in range(3)]
    return [R, t]

def wrap(v, periodic):
    return np.where(periodic, v % 1.0, v)

def orbit_size(ops, rep, periodic, tol=1e-5):
    pts = []
    for R, t in ops:
        q = wrap(np.array(R) @ rep + np.array(t), periodic)
        if not any(np.all(np.abs(np.minimum(np.abs(q-p), np.where(periodic, 1-np.abs(q-p), np.inf))) < tol) for p in pts):
            pts.append(q)
    return len(pts)

def build(dim, count, ltype_fn, out_name):
    periodic = np.array([True, True, dim == 3])
    result = {}
    for n in range(1, count + 1):
        g = Group(n, dim=dim)
        lt = ltype_fn(n)
        gen_wp = g.Wyckoff_positions[0]           # general position = all group elements
        ops = [encode_op(op.affine_matrix) for op in gen_wp.ops]
        # check 2: metric invariance
        G = metric(lt)
        for R, t in ops:
            Rm = np.array(R)
            assert np.allclose(Rm.T @ G @ Rm, G, atol=1e-6), f"group {n} ({dim}D): op breaks {lt} metric"
            if dim == 2:  # check 3: layer safety
                assert abs(abs(Rm[2][2]) - 1) < 1e-9 and abs(Rm[2][0]) < 1e-9 and abs(Rm[2][1]) < 1e-9
                assert abs(Rm[0][2]) < 1e-9 and abs(Rm[1][2]) < 1e-9 and abs(t[2]) < 1e-9
        wyckoff = {}
        for wp in g.Wyckoff_positions:
            aff = wp.ops[0].affine_matrix
            m = [[frac_round(aff[i][j]) for j in range(3)] for i in range(3)]
            t = [frac_round(aff[i][3]) % 1.0 for i in range(3)]
            vars_ = [v for j, v in enumerate("xyz") if any(abs(m[i][j]) > 1e-9 for i in range(3))]
            letter = wp.get_label()  # e.g. "192l"
            letter = "".join(ch for ch in letter if ch.isalpha())
            # check 1: multiplicity via orbit of a generic representative
            p = np.array(m) @ np.array([0.1234, 0.2618, 0.3711]) + np.array(t)
            npts = orbit_size([(np.array(R), np.array(tt)) for R, tt in ops], p, periodic)
            assert npts == wp.multiplicity, \
                f"group {n} ({dim}D) wyckoff {letter}: orbit {npts} != mult {wp.multiplicity}"
            wyckoff[letter] = {"mult": wp.multiplicity, "vars": vars_, "m": m, "t": t}
        result[str(n)] = {"symbol": g.symbol, "ltype": lt, "ops": ops, "wyckoff": wyckoff}
        if n % 40 == 0:
            print(f"  {dim}D group {n}/{count}")
    out = DATA / out_name
    out.write_text(json.dumps(result, separators=(",", ":")))
    print(f"wrote {out} ({out.stat().st_size // 1024} KB)")

build(3, 230, ltype_3d, "spacegroups.json")
build(2, 80, ltype_layer, "layergroups.json")
