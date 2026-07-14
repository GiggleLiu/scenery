"""Ground-truth high-symmetry k-point / k-path fixtures for materia.

Ground truth is **seekpath** (Hinuma et al., Comp. Mater. Sci. 128, 140 (2017),
the "HPKOT" standardization), which is the machine-checkable realization of the
Setyawan & Curtarolo, Comp. Mater. Sci. 49, 299 (2010) ("SC-2010") k-point
tables. seekpath ships the SC-2010 coordinate FORMULAS verbatim (see
`seekpath/hpkot/band_path_data/<EXT>/{k_vector_parameters,points,path}.txt`);
materia/src/reciprocal/kpath.typ ports exactly those formulas, so the Typst module and
seekpath agree to machine precision on coordinates AND path segments.

BASIS MAPPING (why the fractional numbers are directly comparable)
------------------------------------------------------------------
seekpath returns each k-point in fractional coordinates of the reciprocal of its
standardized PRIMITIVE cell. SC-2010's tables are in the very same primitive
reciprocal basis (HPKOT deliberately keeps SC-2010's primitive-cell choice for
every Bravais type we cover here — verified case-by-case, e.g. ORCF's
X=(0,eta,eta) is seekpath's SIGMA_0, X1 is U_0, etc.: identical coordinates,
different labels). Fractional coordinates in a dual basis are invariant under a
rigid rotation of the cell, so seekpath's (possibly rotated) standardized frame
does not matter -- the numbers coincide with the SC-2010 formulas with no
transformation. What the two conventions genuinely differ on is (a) point LABELS
for the interior/free points of centered lattices (HPKOT: SIGMA_0, U_0, ...;
SC-2010 paper: X, X1, A, A1, ...) and (b) a few recommended PATH segments. Those
divergences are recorded per case in `notes`.

STANDARDIZED PARAMETERS (critical)
----------------------------------
The SC-2010/HPKOT formulas are evaluated on the a,b,c,alpha,beta,gamma of the
*standardized conventional cell* (e.g. spglib forces a<=b<=c for orthorhombic and
a monoclinic beta>=90: a user-supplied beta=80 becomes beta=100). We therefore
read the standardized (a,b,c,angles) back out of seekpath's `conv_lattice` and
store THOSE as each fixture's `params`. The Typst module, fed those standardized
scalars, reproduces seekpath's points with no standardization of its own.

Consequence for variant coverage: because standardization sorts a<=b<=c, the
axis-permutation variants oF2, oI2, oI3, oC2, oA1, oA2 are UNREACHABLE from a
symmetric structure (1/c^2 is always the smallest, the largest edge is always c,
etc.). We therefore cover the reachable variants oF1/oF3, oI1, oC1 and document
the rest as implemented-but-not-fixture-reachable in the Typst module.

Run:  tools/.venv/bin/python3.11 tools/gen_kpath_fixtures.py
"""
import json
import math
from pathlib import Path

import numpy as np
import seekpath
from pymatgen.core import Lattice, Structure

FIX = Path(__file__).resolve().parent.parent / "materia" / "tests" / "fixtures"
FIX.mkdir(parents=True, exist_ok=True)


def conv_params(conv_lattice):
    """Standardized conventional (a,b,c,alpha,beta,gamma) from a 3x3 cell (rows)."""
    L = np.asarray(conv_lattice, dtype=float)
    a, b, c = (np.linalg.norm(v) for v in L)

    def ang(u, v):
        cosv = np.dot(u, v) / (np.linalg.norm(u) * np.linalg.norm(v))
        return math.degrees(math.acos(max(-1.0, min(1.0, cosv))))

    return (float(a), float(b), float(c),
            float(ang(L[1], L[2])), float(ang(L[0], L[2])), float(ang(L[0], L[1])))


def select_variant(base, a, b, c, alpha, beta, gamma):
    """Port of seekpath.hpkot's ext-Bravais selector (the exact conditions the
    Typst module reimplements). Operates on STANDARDIZED conventional params.
    Returns the extended Bravais symbol for the reachable variants."""
    cb = math.cos(math.radians(beta))
    sb = math.sin(math.radians(beta))
    if base == "cP":
        return "cP2"          # centrosymmetric default (cP1 only for 195-206)
    if base == "cF":
        return "cF2"
    if base == "cI":
        return "cI1"
    if base == "tP":
        return "tP1"
    if base == "tI":
        return "tI1" if c <= a else "tI2"
    if base == "oP":
        return "oP1"
    if base == "oF":
        if 1.0 / a**2 > 1.0 / b**2 + 1.0 / c**2:
            return "oF1"
        if 1.0 / c**2 > 1.0 / a**2 + 1.0 / b**2:
            return "oF2"
        return "oF3"
    if base == "oI":
        # variant = index of the LONGEST edge (c->1, a->2, b->3)
        longest = max((c, 1), (a, 2), (b, 3))[1]
        return f"oI{longest}"
    if base == "oC":
        return "oC1" if a <= b else "oC2"
    if base == "hP":
        return "hP2"          # centrosymmetric default
    if base == "hR":
        return "hR1" if math.sqrt(3.0) * a <= math.sqrt(2.0) * c else "hR2"
    if base == "mP":
        return "mP1"
    if base == "mC":
        if b < a * sb:
            return "mC1"
        return "mC2" if (-a * cb / c + a**2 * sb**2 / b**2) <= 1.0 else "mC3"
    if base == "aP":
        # all-obtuse reciprocal -> aP2, all-acute -> aP3 (already-reduced cell)
        return aP_variant(a, b, c, alpha, beta, gamma)
    raise ValueError(f"unknown base {base}")


def reciprocal_angles(a, b, c, alpha, beta, gamma):
    """cos of the three reciprocal-cell angles for a real cell (a,b,c,angles)."""
    ca, cb, cg = (math.cos(math.radians(x)) for x in (alpha, beta, gamma))
    sa, sb, sg = (math.sin(math.radians(x)) for x in (alpha, beta, gamma))
    cka = (cb * cg - ca) / (sb * sg)
    ckb = (cg * ca - cb) / (sg * sa)
    ckg = (ca * cb - cg) / (sa * sb)
    return cka, ckb, ckg


def aP_variant(a, b, c, alpha, beta, gamma):
    cka, ckb, ckg = reciprocal_angles(a, b, c, alpha, beta, gamma)
    tol = 1e-9
    if cka <= tol and ckb <= tol and ckg <= tol:
        return "aP2"          # all-obtuse reciprocal
    if cka >= -tol and ckb >= -tol and ckg >= -tol:
        return "aP3"          # all-acute reciprocal
    raise ValueError("aP cell not all-acute/all-obtuse; not already-reduced")


# Per-case SC-2010(paper) vs HPKOT(seekpath) relationship, recorded in `notes`.
# `path_agrees_sc2010` is informational: our module reproduces the HPKOT path
# exactly (== fixture), and we ALSO note where the SC-2010 paper path/labels
# differ so the discrepancy is explicit rather than papered over.
CONVENTION_NOTES = {
    "cP2": ("HPKOT==SC-2010 (labels & path agree; cP1 adds M-X_1 for "
            "non-centrosymmetric point groups).", True),
    "cF2": ("HPKOT==SC-2010 (cF1 adds X-W_2 for non-centrosymmetric groups).", True),
    "cI1": ("HPKOT==SC-2010.", True),
    "tP1": ("HPKOT==SC-2010.", True),
    "tI1": ("HPKOT==SC-2010; seekpath label Z_0 == SC-2010 Z1.", True),
    "tI2": ("HPKOT==SC-2010; seekpath S/S_0/R/G == SC-2010 Sigma/Sigma1/Y/Y1 "
            "relabeled.", True),
    "oP1": ("HPKOT==SC-2010.", True),
    "oF1": ("Coordinates identical to SC-2010 ORCF1; seekpath relabels the free "
            "points SIGMA_0=X, U_0=X1, A_0=A, C_0=A1; path ordering differs.", False),
    "oF3": ("Coordinates identical to SC-2010 ORCF3; free points relabeled "
            "(A_0/B_0/C_0/D_0/G_0/H_0); path differs from the SC-2010 paper.", False),
    "oI1": ("Coordinates identical to SC-2010 ORCI; seekpath relabels free "
            "points (SIGMA_0, F_2, Y_0, U_0, L_0, M_0, J_0); path differs.", False),
    "oC1": ("Coordinates identical to SC-2010 ORCC; seekpath relabels free "
            "points (SIGMA_0, C_0, A_0, E_0); path differs from the paper.", False),
    "hP2": ("HPKOT==SC-2010 (hP1 adds K-H_2 for non-centrosymmetric groups).", True),
    "hR1": ("Coordinates identical to SC-2010 RHL1; seekpath relabels free points "
            "(S_*, H_*, M_*, F_2, L_2/L_4); path differs.", False),
    "hR2": ("Coordinates identical to SC-2010 RHL2; seekpath labels P_0/P_2/R_0/"
            "M/M_2/F; path differs from the paper.", False),
    "mP1": ("HPKOT==SC-2010 MCL; extra +/- copies (Y_2, B_2, ...) are seekpath's "
            "time-reversal partners; shared names agree.", True),
    "mC1": ("Coordinates identical to SC-2010 MCLC1; seekpath relabels many free "
            "points; path differs.", False),
    "mC2": ("Coordinates identical to SC-2010 MCLC2; free points relabeled; path "
            "differs from the paper.", False),
    "mC3": ("Coordinates identical to SC-2010 MCLC3/MCLC4 family; relabeled; path "
            "differs.", False),
    "aP2": ("SC-2010 aP2 (all-obtuse reduced reciprocal cell); labels agree.", True),
    "aP3": ("SC-2010 aP3 (all-acute reduced reciprocal cell); labels agree.", True),
}


# (name, spacegroup, input params) -- input params are pre-standardization; the
# stored fixture params are read back STANDARDIZED from seekpath's conv cell.
CASES = [
    ("cubic-P", 221, dict(a=4.0)),
    ("cubic-F", 225, dict(a=4.0)),
    ("cubic-I", 229, dict(a=4.0)),
    ("tetragonal-P", 123, dict(a=4.0, c=6.0)),
    ("tetragonal-I-flat", 139, dict(a=4.0, c=3.0)),    # c<a -> tI1
    ("tetragonal-I-tall", 139, dict(a=4.0, c=6.0)),    # c>a -> tI2
    ("ortho-P", 47, dict(a=3.0, b=4.0, c=5.0)),
    ("ortho-F-1", 69, dict(a=3.0, b=5.0, c=7.0)),      # 1/a^2>1/b^2+1/c^2 -> oF1
    ("ortho-F-3", 69, dict(a=5.0, b=6.0, c=7.0)),      # triangle -> oF3
    ("ortho-I", 71, dict(a=3.0, b=4.0, c=5.0)),        # -> oI1
    ("ortho-C", 65, dict(a=3.0, b=4.0, c=5.0)),        # -> oC1
    ("hexagonal-P", 191, dict(a=4.0, c=6.0)),
    ("rhombohedral-1", 166, dict(a=4.0, c=10.0)),      # sqrt3 a<=sqrt2 c -> hR1
    ("rhombohedral-2", 166, dict(a=5.0, c=5.0)),       # sqrt3 a> sqrt2 c -> hR2
    ("monoclinic-P", 10, dict(a=3.0, b=4.0, c=5.0, beta=80.0)),
    ("monoclinic-C-1", 12, dict(a=5.0, b=4.0, c=6.0, beta=100.0)),   # -> mC1
    ("monoclinic-C-2", 12, dict(a=3.0, b=4.0, c=9.0, beta=95.0)),    # -> mC2
    ("monoclinic-C-3", 12, dict(a=6.0, b=8.0, c=5.0, beta=120.0)),   # -> mC3
    ("triclinic-2", 2, dict(a=4.0, b=5.0, c=6.0, alpha=80.0, beta=85.0, gamma=88.0)),  # aP2
    ("triclinic-3", 2, dict(a=4.0, b=5.0, c=6.0, alpha=95.0, beta=100.0, gamma=103.0)),  # aP3
]

BASE_OF_SG = {
    221: "cP", 225: "cF", 229: "cI", 123: "tP", 139: "tI", 47: "oP",
    69: "oF", 71: "oI", 65: "oC", 191: "hP", 166: "hR", 10: "mP",
    12: "mC", 2: "aP",
}


def build(params):
    p = dict(alpha=90.0, beta=90.0, gamma=90.0)
    p.update({"a": params["a"],
              "b": params.get("b", params["a"]),
              "c": params.get("c", params["a"])})
    p["alpha"] = params.get("alpha", 90.0)
    p["beta"] = params.get("beta", 90.0)
    p["gamma"] = params.get("gamma", 90.0)
    if BASE_OF_SG.get(params.get("_sg")) in ("hP", "hR"):
        p["gamma"] = 120.0
    return p


def norm_name(n):
    """seekpath uses GAMMA for the zone center; the module/interface uses 'Γ'."""
    return "Γ" if n == "GAMMA" else n


fixture = {
    "_meta": {
        "source": "seekpath " + seekpath.__version__ + " (HPKOT), realizing SC-2010",
        "basis": "fractional coordinates of the primitive reciprocal cell "
                 "(SC-2010 == HPKOT primitive-cell choice; see module header)",
        "params_note": "params are the STANDARDIZED conventional cell "
                       "(a<=b<=c, monoclinic beta>=90) read from seekpath.",
    },
    "cases": [],
}

for name, sg, raw in CASES:
    base = BASE_OF_SG[sg]
    p = dict(raw)
    p["_sg"] = sg
    bp = build(p)
    if base in ("hP", "hR"):
        bp["gamma"] = 120.0
    lat = Lattice.from_parameters(bp["a"], bp["b"], bp["c"],
                                  bp["alpha"], bp["beta"], bp["gamma"])
    st = Structure.from_spacegroup(sg, lat, ["Si"], [[0, 0, 0]])
    r = seekpath.get_path((st.lattice.matrix, st.frac_coords, [1] * len(st)))
    ext = r["bravais_lattice_extended"]
    a, b, c, al, be, ga = conv_params(r["conv_lattice"])

    # Cross-check: our selector must reproduce seekpath's ext symbol.
    mine = select_variant(base, a, b, c, al, be, ga)
    assert mine == ext, f"{name}: selector {mine} != seekpath {ext}"

    pts = {norm_name(k): [float(x) for x in v] for k, v in r["point_coords"].items()}
    assert pts["Γ"] == [0.0, 0.0, 0.0], f"{name}: Gamma not origin"
    path = [[norm_name(u), norm_name(v)] for (u, v) in r["path"]]
    note, path_agrees = CONVENTION_NOTES[ext]

    fixture["cases"].append({
        "name": name,
        "bravais": base,
        "variant": ext,
        "params": {"a": round(a, 12), "b": round(b, 12), "c": round(c, 12),
                   "alpha": round(al, 12), "beta": round(be, 12), "gamma": round(ga, 12)},
        "points": pts,
        "path": path,
        "notes": note,
        "path_agrees_sc2010": path_agrees,
    })
    print(f"{name:20s} base={base} ext={ext:4s} npts={len(pts):2d} "
          f"nseg={len(path):2d} params=({a:.3f},{b:.3f},{c:.3f},"
          f"{al:.1f},{be:.1f},{ga:.1f})")

# --- NEGATIVE CONTROL --------------------------------------------------------
# Cross oF1 params against oF3 expected points. seekpath's a<=b<=c
# standardization makes the SC-2010 ORCF2 variant unreachable, so we cross the
# two REACHABLE ORCF variants (oF1 x oF3). Feeding the oF1 params to the module
# yields oF1 points/variant, which MUST NOT equal these oF3 points -- proving
# variant selection has teeth.
of1 = next(c for c in fixture["cases"] if c["variant"] == "oF1")
of3 = next(c for c in fixture["cases"] if c["variant"] == "oF3")
fixture["negative_control"] = {
    "note": "oF1 params vs oF3 expected points; module(oF1 params) must select "
            "oF1 and its points must NOT match these oF3 points.",
    "params": of1["params"],
    "wrong_variant": "oF3",
    "wrong_points": of3["points"],
    "right_variant": "oF1",
}
print(f"negative-control: oF1 params ({of1['name']}) x oF3 points ({of3['name']})")

out = FIX / "kpath.json"
out.write_text(json.dumps(fixture, indent=1))
print(f"\nwrote {out}  ({len(fixture['cases'])} cases)")
