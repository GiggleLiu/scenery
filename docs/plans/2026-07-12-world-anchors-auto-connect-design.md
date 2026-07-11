# World-space anchors and automatic connections

## Goal

Extend named object anchors with true 3D sphere directions and CeTZ-style
automatic surface attachment for line-like primitives.

## World-space sphere anchors

Spheres gain six canonical anchors:

- `x+`, `x-`
- `y+`, `y-`
- `z+`, `z-`

They are fixed in world coordinates and independent of camera orientation. For
a sphere centered at `c` with radius `r`, `x+` is `c + (r, 0, 0)`.

`anchor-ref` also accepts an arbitrary 3-vector direction:

```typst
anchor-ref("atom", anchor: (1, 1, 1))
```

The direction is normalized and multiplied by the sphere radius. Zero vectors
and vectors whose length is not three are rejected. Existing string compass and
angle anchors remain camera-relative in the rendered screen plane. The six axis
anchors are registered with CeTZ; dynamic vector anchors are query/reference
expressions only.

Other primitives retain their existing 3D anchors (`start`, `end`, `centroid`,
and `vertex-N`). Mesh directional anchors are excluded because correct arbitrary
surface attachment requires ray-mesh intersection and closed-geometry
assumptions.

## Automatic connections

Bare object references at `seg`, `edge`, and `arrow` endpoints attach spheres to
the surface facing the opposite resolved endpoint:

```typst
seg("a", "b")          // automatic surface-to-surface connection
seg("a.center", "b")   // explicit center on A, automatic surface on B
seg("a.z+", "b.x-")    // fully explicit
```

Both endpoints first resolve to their defaults. A direct bare reference whose
target is a sphere is then replaced by the sphere point in the normalized 3D
direction toward the opposite endpoint. If only one endpoint is a sphere, it
attaches toward the other concrete/default point. Unsupported object types keep
their defaults. Coincident points are rejected because no direction exists.

The adjusted geometry defines the named line's logical `start`, `mid`, and `end`
anchors. Occlusion fragmentation occurs later and cannot change them.

Automatic attachment applies only to direct references. Deferred affine
reference expressions retain ordinary default resolution; explicit anchors are
required because nonuniform transformed-surface semantics would otherwise be
ambiguous.

## Integration and verification

The resolver performs automatic endpoint adjustment after named dependencies
are concrete but before bounding boxes, anchor tables, occlusion, and depth
sorting. Existing explicit anchors and non-line uses of bare references retain
their meanings.

Tests cover exact axes, arbitrary normalized directions, camera invariance,
`seg`/`edge`/`arrow` attachment, one-sided attachment, explicit overrides,
coincident and malformed directions, logical anchors through fragmentation, and
CeTZ `"atom.z+"` composition. README/manual examples prefer `seg("a", "b")` and
document the distinction between camera-relative and world-space anchors.
