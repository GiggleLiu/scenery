"""Generate data/elements.json: Jmol/VESTA colors + covalent/atomic radii per element."""
import json
from pathlib import Path

from pymatgen.core.periodic_table import Element
from pymatgen.analysis.local_env import CovalentRadius
from pymatgen.vis.structure_vtk import EL_COLORS

OUT = Path(__file__).resolve().parent.parent / "data" / "elements.json"

def hexcolor(rgb):
    return "#{:02X}{:02X}{:02X}".format(*rgb)

data = {}
for el in Element:
    sym = el.symbol
    r_cov = CovalentRadius.radius.get(sym)
    r_atom = float(el.atomic_radius) if el.atomic_radius is not None else None
    if r_cov is None and r_atom is None:
        continue  # exotic elements without any radius data
    data[sym] = {
        "color": hexcolor(EL_COLORS["Jmol"].get(sym, (128, 128, 128))),
        "color-vesta": hexcolor(EL_COLORS["VESTA"].get(sym, (128, 128, 128))),
        "r-cov": round(r_cov if r_cov is not None else r_atom, 3),
        "r-atom": round(r_atom if r_atom is not None else r_cov, 3),
    }

assert len(data) > 90, f"only {len(data)} elements"
assert abs(data["O"]["r-cov"] - 0.66) < 0.05
OUT.parent.mkdir(exist_ok=True)
OUT.write_text(json.dumps(data, indent=1, sort_keys=True))
print(f"wrote {OUT} ({len(data)} elements)")
