// The scene the live viewer shows: SrTiO3 perovskite — the same structure as
// the hero "Plate I", built from the same numbers wyckoff uses:
//
//   crystal(prototypes.perovskite("Sr", "Ti", "O", a: 3.905),
//           bonds: ((elements: ("Ti", "O"), max: 2.2),), polyhedra: ("Ti",),
//           colors: (Sr: #6485a6, Ti: #9aa0a6, O: #cc8963))
//
// Space group 221 (Pm-3m): Sr on the corners, Ti at the body centre, O at the
// face centres — which puts the six oxygens exactly at the vertices of the
// TiO6 octahedron around Ti. Everything below mirrors wyckoff's ball-and-stick
// build (wyckoff/src/figure.typ): sphere radius 0.45 x r-atom, bond width
// 0.16, bonds attached at the sphere surfaces and pre-split into two-tone
// halves at the midpoint, octahedron faces translucent, each cell edge split
// into 8 sub-edges so the depth sort interleaves them correctly with atoms.
// The scene is centred on the cell centre so rotation feels natural.
//
// Pure data, no DOM — render.js paints it, and the node smoke test feeds it
// straight into the wasm engine.

const A = 3.905; // SrTiO3 lattice parameter, Angstrom
const H = A / 2;

// Element palette — identical to the site's plates.
export const PALETTE = { Sr: "#6485a6", Ti: "#9aa0a6", O: "#cc8963" };

// Ball-and-stick: 0.45 x r-atom (wyckoff/data/elements.json: Sr 2.0, Ti 1.4, O 0.6).
const RADII = { Sr: 0.45 * 2.0, Ti: 0.45 * 1.4, O: 0.45 * 0.6 };
const BOND_W = 0.16; // world-units stroke width, wyckoff's ball-and-stick default

const sub = (p, q) => [p[0] - q[0], p[1] - q[1], p[2] - q[2]];
const mid = (p, q) => [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2];
const along = (p, dir, t) => [p[0] + dir[0] * t, p[1] + dir[1] * t, p[2] + dir[2] * t];
const norm = (v) => {
  const n = Math.hypot(v[0], v[1], v[2]);
  return [v[0] / n, v[1] / n, v[2] / n];
};

export function buildScene() {
  const prims = [];
  const styles = [];
  const faces = []; // {i, base} — render.js re-applies wyckoff's depth offset per frame
  const add = (prim, style) => { prims.push(prim); styles.push(style); };

  // --- atoms (centred: cell corners at (+-H, +-H, +-H)) ---------------------
  const atoms = [];
  for (const x of [-H, H])
    for (const y of [-H, H])
      for (const z of [-H, H]) atoms.push({ el: "Sr", c: [x, y, z] });
  atoms.push({ el: "Ti", c: [0, 0, 0] });
  const oSites = [
    [H, 0, 0], [-H, 0, 0],
    [0, H, 0], [0, -H, 0],
    [0, 0, H], [0, 0, -H],
  ];
  for (const c of oSites) atoms.push({ el: "O", c });

  // Push order mirrors wyckoff (spheres, bonds, faces, edges) — the engine's
  // stable sort uses emission order as the tie-break, exactly like Typst.
  for (const a of atoms) {
    add({ k: "sphere", c: a.c, r: RADII[a.el] }, { kind: "atom", color: PALETTE[a.el] });
  }

  // --- Ti-O bonds, surface-attached, pre-split into two-tone halves ---------
  const ti = [0, 0, 0];
  for (const o of oSites) {
    const dir = norm(sub(o, ti));
    const a = along(ti, dir, RADII.Ti);          // Ti sphere surface
    const b = along(o, dir, -RADII.O);           // O sphere surface
    const m = mid(a, b);                         // split at midpoint of attached ends
    add({ k: "seg", a, b: m, w: BOND_W }, { kind: "bond", color: PALETTE.Ti });
    add({ k: "seg", a: m, b, w: BOND_W }, { kind: "bond", color: PALETTE.O });
  }

  // --- TiO6 coordination octahedron: 8 translucent triangles ----------------
  for (const sx of [-1, 1])
    for (const sy of [-1, 1])
      for (const sz of [-1, 1]) {
        const base = [[sx * H, 0, 0], [0, sy * H, 0], [0, 0, sz * H]];
        faces.push({ i: prims.length, base });
        add({ k: "face", pts: base.map((p) => p.slice()), opaque: false },
            { kind: "poly", color: PALETTE.Ti });
      }

  // --- unit-cell edges, each split into 8 (wyckoff parity) ------------------
  const corner = (m) => [m & 1 ? H : -H, m & 2 ? H : -H, m & 4 ? H : -H];
  for (let m = 0; m < 8; m++)
    for (const bit of [1, 2, 4]) {
      if (m & bit) continue; // each edge once, from the low corner
      const ea = corner(m), eb = corner(m | bit);
      for (let t = 0; t < 8; t++) {
        const p = along(ea, sub(eb, ea), t / 8);
        const q = along(ea, sub(eb, ea), (t + 1) / 8);
        add({ k: "edge", a: p, b: q }, { kind: "cell" });
      }
    }

  return {
    prims,
    styles,
    faces,
    // Rotation-invariant screen bound: no projected point ever leaves a disk of
    // this radius (in world units) around the origin, so the fit never pumps
    // while the scene spins.
    bound: Math.sqrt(3) * H + RADII.Sr,
    legend: [
      { label: "Sr", color: PALETTE.Sr },
      { label: "Ti", color: PALETTE.Ti },
      { label: "O", color: PALETTE.O },
    ],
  };
}
