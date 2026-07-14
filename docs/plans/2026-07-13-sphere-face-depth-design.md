# Sphere/face depth composition

## Problem

Coordination-polyhedron faces end at ligand atom centres. A face and its ligand
sphere therefore intersect, but scenery currently assigns the whole face its
centroid depth. Depending on the camera, that single key can paint the face over
the opaque sphere and produce triangular wedges through the atom. Shrinking the
atoms or changing the camera only hides the renderer defect.

## Design

Add an opt-in `depth-key` primitive field with three policies:

- `"center"` (default): preserve today's centre/midpoint/centroid key exactly.
- `"back"`: use the smallest camera depth among the primitive's support points.
- `"front"`: use the largest camera depth among the support points.

The default remains byte-compatible. Wyckoff coordination faces use
`depth-key: "back"` together with their existing `-0.01` camera-depth offset.
The support-point policy retains physical ordering among polyhedron faces; the
offset breaks the exact tie at a ligand centre so its opaque sphere paints
after the face. This is narrower and more truthful than a global "all atoms on
top" layer, which would hide genuinely foreground geometry. Exact polygon
subtraction against spherical silhouettes is rejected here: it requires curved
fragment geometry or a z-buffer and is disproportionate for intersections at
shared polyhedron vertices.

Both the pure Typst sorter and the Rust/WASM accelerator implement the same
policy. Invalid policies fail during Typst sorting with a focused message.

## Verification

- Pure renderer tests pin the default order, `back` order, `front` order, and
  invalid-policy failure.
- The Typst/Rust structural equivalence gate includes a non-default depth key.
- Wyckoff scene tests require all coordination faces to opt into `back`.
- `make test` and `make examples` pass.
- Regenerate `wyckoff/images/perovskite.png` and `site/assets/perovskite.png`,
  then inspect the result for clean O/Ti sphere silhouettes.
