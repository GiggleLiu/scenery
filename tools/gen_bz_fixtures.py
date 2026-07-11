"""Ground-truth reciprocal-lattice fixtures for the brillouin package.

pymatgen's `Lattice.reciprocal_lattice` is the 2π convention: it returns
2π·inv(M)ᵀ, an implementation of b_i = 2π (a_j × a_k)/V that is INDEPENDENT of
brillouin's cross-product formula (inverse-transpose vs explicit cross products).
We assert the 2π convention below before emitting anything.

Basis-orientation caveat (why we do NOT use `Lattice.from_parameters`):
pymatgen's `from_parameters` does not use wyckoff's basis orientation for the
general triclinic cell (it puts c along z; wyckoff/brillouin put a along x). If we
took pymatgen's own direct vectors, the reciprocal vectors would differ from
brillouin's by a rotation and fail a component-wise 1e-9 comparison. So we build
the direct matrix OURSELVES with the wyckoff convention (see wyckoff/src/lattice.typ
`lattice-vectors`, reimplemented in brillouin/src/reciprocal.typ `params-to-vectors`),
construct `Lattice(M)` from it, and let pymatgen compute the reciprocal by its
independent inverse-transpose route. This keeps pymatgen a genuine cross-check of
the reciprocal computation while guaranteeing the same basis the Typst code uses.

Each entry stores the direct vectors AND the reciprocal vectors so the Typst test
exercises both the direct-vector input path and (via `ltype-params`) the params
path. Full float precision is preserved (default json float repr, no rounding) so
the 1e-9 tolerance is meaningful.
"""
import json
from pathlib import Path

import numpy as np
from pymatgen.core import Lattice

FIX = Path(__file__).resolve().parent.parent / "brillouin" / "tests" / "fixtures"
FIX.mkdir(parents=True, exist_ok=True)


def wyckoff_matrix(p):
    """params dict -> direct matrix (rows a1,a2,a3) in wyckoff's orientation.

    Mirrors wyckoff/src/lattice.typ `lattice-vectors`: a along x, b in the xy
    plane, c completing the cell. b,c default to a; angles default to 90°.
    """
    a = p["a"]
    b = p.get("b", a)
    c = p.get("c", a)
    alpha = p.get("alpha", 90.0)
    beta = p.get("beta", 90.0)
    gamma = p.get("gamma", 90.0)
    ca, cb, cg = np.cos(np.deg2rad([alpha, beta, gamma]))
    sg = np.sin(np.deg2rad(gamma))
    cx = c * cb
    cy = c * (ca - cb * cg) / sg
    cz = np.sqrt(max(c * c - cx * cx - cy * cy, 0.0))
    return np.array([[a, 0.0, 0.0], [b * cg, b * sg, 0.0], [cx, cy, cz]])


def vecs_list(mat):
    """3x3 array -> list of three 3-lists, full float precision (no rounding)."""
    return [[float(x) for x in row] for row in mat]


# name, ltype-params dict (a, b, c in Å; angles in degrees). These mirror the
# forms wyckoff's lattice-params accepts and are fed to brillouin unchanged.
CASES = [
    ("cubic", dict(a=4.0)),
    ("hexagonal", dict(a=3.0, c=5.0, gamma=120.0)),
    ("triclinic", dict(a=3.0, b=4.0, c=5.0, alpha=80.0, beta=95.0, gamma=105.0)),
]

fixture = {"cases": []}
for name, params in CASES:
    direct = wyckoff_matrix(params)
    lat = Lattice(direct)
    recip = np.asarray(lat.reciprocal_lattice.matrix)     # 2π convention (Å^-1)

    # Assert pymatgen really uses the 2π convention: b_i · a_j = 2π δ_ij.
    assert np.allclose(recip @ direct.T, 2.0 * np.pi * np.eye(3), atol=1e-9), \
        f"{name}: pymatgen reciprocal_lattice is not 2π-convention"

    fixture["cases"].append({
        "name": name,
        "ltype-params": params,
        "direct": vecs_list(direct),
        "reciprocal": vecs_list(recip),
    })
    print(f"{name}: 2π-convention verified")

# Negative control: cubic reciprocal WITHOUT the 2π factor (bare a_j × a_k / V).
cubic_direct = wyckoff_matrix(dict(a=4.0))
recip_no_2pi = np.asarray(Lattice(cubic_direct).reciprocal_lattice.matrix) / (2.0 * np.pi)
fixture["cubic_no_2pi"] = {
    "name": "cubic_no_2pi",
    "note": "cubic reciprocal with the 2π factor omitted; MUST NOT match reciprocal-vectors",
    "ltype-params": dict(a=4.0),
    "direct": vecs_list(cubic_direct),
    "reciprocal": vecs_list(recip_no_2pi),
}
print("cubic_no_2pi: negative control written")

# Adapter case: a minimal wyckoff-NaCl-shaped structure (a=5.64 cubic) whose
# `vectors` field the adapter test feeds through from-wyckoff, expecting this answer.
nacl_direct = wyckoff_matrix(dict(a=5.64))
fixture["nacl_adapter"] = {
    "name": "nacl_adapter",
    "vectors": vecs_list(nacl_direct),
    "reciprocal": vecs_list(np.asarray(Lattice(nacl_direct).reciprocal_lattice.matrix)),
}
print("nacl_adapter: wyckoff-shaped structure written")

# Default json float repr keeps full precision (no rounding).
(FIX / "reciprocal.json").write_text(json.dumps(fixture, indent=1))
print(f"wrote {FIX / 'reciprocal.json'}")
