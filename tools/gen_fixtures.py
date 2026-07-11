"""Ground-truth expansion fixtures.

3D cases: pymatgen Structure.from_spacegroup — an implementation INDEPENDENT of
pyxtal, so this genuinely cross-checks data/spacegroups.json.
Layer cases: expanded with pyxtal ops directly (weaker check — same source as the
data) plus hand-verified atom counts from the literature.
"""
import json
from pathlib import Path

import numpy as np
from pymatgen.core import Lattice, Structure

FIX = Path(__file__).resolve().parent.parent / "tests" / "fixtures"
FIX.mkdir(parents=True, exist_ok=True)

# Origin-choice overrides: pymatgen's SpaceGroup(sg) setting differs from the
# pyxtal setting baked into data/spacegroups.json (which the Typst engine uses).
# For such groups we generate the INDEPENDENT pymatgen structure at a generating
# rep, then apply the fixed ITA origin transformation (a pure translation of every
# atom) so the ground-truth coords are expressed in the data's setting, and we
# store the data-setting rep `p` on the site. This keeps pymatgen as a genuine,
# independent structural cross-check while resolving the origin mismatch — it does
# NOT touch the engine. See README "SG 227 origin choice".
#   sg -> (element, pymatgen_gen_rep, origin_shift, data_setting_p)
# SG 227 (Fd-3m): pymatgen uses origin choice 1 (8a at 0,0,0); pyxtal/data uses
# origin choice 2 (8a at 1/8,1/8,1/8). x_choice2 = x_choice1 - (1/8,1/8,1/8).
ORIGIN_OVERRIDE = {
    227: dict(gen_rep=(0.0, 0.0, 0.0), shift=(-0.125, -0.125, -0.125),
              data_p=(0.125, 0.125, 0.125)),
}

# name, sg, lattice-kwargs, sites: (element, wyckoff, rep_frac)
CASES_3D = [
    ("nacl", 225, dict(a=5.64), [("Na", "a", (0, 0, 0)), ("Cl", "b", (0.5, 0.5, 0.5))]),
    ("cscl", 221, dict(a=4.11), [("Cs", "a", (0, 0, 0)), ("Cl", "b", (0.5, 0.5, 0.5))]),
    ("diamond", 227, dict(a=3.567), [("C", "a", (0.125, 0.125, 0.125))]),
    ("zincblende", 216, dict(a=5.41), [("Zn", "a", (0, 0, 0)), ("S", "c", (0.25, 0.25, 0.25))]),
    ("wurtzite", 186, dict(a=3.25, c=5.21, gamma=120), [("Zn", "b", (1/3, 2/3, 0.0)), ("O", "b", (1/3, 2/3, 0.375))]),
    ("rutile", 136, dict(a=4.59, c=2.96), [("Ti", "a", (0, 0, 0)), ("O", "f", (0.305, 0.305, 0))]),
    ("perovskite", 221, dict(a=3.905), [("Sr", "a", (0, 0, 0)), ("Ti", "b", (0.5, 0.5, 0.5)), ("O", "c", (0, 0.5, 0.5))]),
    ("fluorite", 225, dict(a=5.46), [("Ca", "a", (0, 0, 0)), ("F", "c", (0.25, 0.25, 0.25))]),
    ("corundum", 167, dict(a=4.76, c=12.99, gamma=120), [("Al", "c", (0, 0, 0.352)), ("O", "e", (0.306, 0, 0.25))]),
    ("baddeleyite", 14, dict(a=5.15, b=5.21, c=5.32, beta=99.2),
     [("Zr", "e", (0.275, 0.040, 0.208)), ("O", "e", (0.070, 0.332, 0.345)), ("O", "e", (0.442, 0.755, 0.480))]),
]

for name, sg, lat, sites in CASES_3D:
    lattice = Lattice.from_parameters(
        lat.get("a"), lat.get("b", lat["a"]), lat.get("c", lat["a"]),
        lat.get("alpha", 90), lat.get("beta", 90), lat.get("gamma", 90))
    ov = ORIGIN_OVERRIDE.get(sg)
    if ov is None:
        gen_coords = [c for _, _, c in sites]
        shift = (0.0, 0.0, 0.0)
        store_sites = [(e, w, c) for e, w, c in sites]
    else:
        gen_coords = [ov["gen_rep"] for _ in sites]
        shift = ov["shift"]
        store_sites = [(e, w, ov["data_p"]) for e, w, _ in sites]
    s = Structure.from_spacegroup(sg, lattice, [e for e, _, _ in sites], gen_coords)
    atoms = [{"element": site.specie.symbol,
              "frac": [round((x + sh) % 1.0, 6) for x, sh in zip(site.frac_coords, shift)]}
             for site in s]
    fixture = {
        "name": name, "kind": "3d", "group": sg,
        "ltype-params": lat,
        "sites": [{"element": e, "wyckoff": w,
                   "p": list(c)} for e, w, c in store_sites],
        "expected": {"natoms": len(atoms), "atoms": atoms},
    }
    (FIX / f"{name}.json").write_text(json.dumps(fixture, indent=1))
    print(f"{name}: sg {sg}, {len(atoms)} atoms")

# Layer-group cases. Expected atom COUNTS are hand-verified from the literature
# (graphene: 2 C; hBN: 1 B + 1 N; MoS2 monolayer: 1 Mo + 2 S) — that is the real
# check here. The Wyckoff letter for each site is chosen to match the setting baked
# into data/layergroups.json (which the Typst engine uses): the earlier "pick the
# first Wyckoff of matching multiplicity" heuristic mislabels sites, because a layer
# group has several positions of equal multiplicity with different representatives.
# Ground-truth POSITIONS are produced by expanding the site's representative with
# pyxtal's general-position ops (a second code path from the JSON the engine reads).
# z is non-periodic (no c lattice); the MoS2 S out-of-plane offset is a fractional
# placeholder (0.15) — only its self-consistency with the engine is tested.
from pyxtal.symmetry import Group

#   name, lg, lattice-kwargs, sites: (element, wyckoff-letter, p_frac), total
CASES_LAYER = [
    ("graphene", 80, dict(a=2.46), [("C", "b", (0.0, 0.0, 0.0))], 2),
    ("hbn", 78, dict(a=2.50), [("B", "b", (0.0, 0.0, 0.0)), ("N", "c", (0.0, 0.0, 0.0))], 2),
    ("mos2", 78, dict(a=3.16), [("Mo", "b", (0.0, 0.0, 0.0)), ("S", "f", (0.0, 0.0, 0.15))], 3),
]

_LG = json.loads((FIX.parent.parent / "data" / "layergroups.json").read_text())

def expand_layer(gnum, rep):
    ops = Group(gnum, dim=2).Wyckoff_positions[0].ops
    pts = []
    for op in ops:
        A = op.affine_matrix
        q = A[:3, :3] @ np.array(rep) + A[:3, 3]
        q[:2] %= 1.0
        if not any(np.allclose(np.minimum(np.abs(q[:2] - p[:2]), 1 - np.abs(q[:2] - p[:2])), 0, atol=1e-5)
                   and abs(q[2] - p[2]) < 1e-5 for p in pts):
            pts.append(q)
    return pts

for name, lg, lat, sites, total in CASES_LAYER:
    atoms, out_sites = [], []
    for el, letter, p in sites:
        w = _LG[str(lg)]["wyckoff"][letter]
        # representative in the data's setting: rep = m . p + t
        rep = np.array(w["m"]) @ np.array(p, float) + np.array(w["t"])
        pts = expand_layer(lg, rep)
        assert len(pts) == w["mult"], f"{name}: {letter} orbit {len(pts)} != mult {w['mult']}"
        out_sites.append({"element": el, "wyckoff": letter, "p": list(p)})
        atoms += [{"element": el, "frac": [round(float(x), 6) for x in q]} for q in pts]
    assert len(atoms) == total, f"{name}: {len(atoms)} != {total}"
    fixture = {"name": name, "kind": "layer", "group": lg, "ltype-params": lat,
               "sites": out_sites, "expected": {"natoms": total, "atoms": atoms}}
    (FIX / f"{name}.json").write_text(json.dumps(fixture, indent=1))
    print(f"{name}: lg {lg}, {total} atoms, letters {[s['wyckoff'] for s in out_sites]}")
