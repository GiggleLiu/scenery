# Render visibility and performance hardening

## Goal

Harden the orthographic renderer before the first package registration. Preserve
the pure typed-scene architecture while improving line/object visibility,
scientific mesh presentation, and scaling for atom-and-bond scenes.

The renderer remains an illustration engine rather than a general rasterizing
3D engine. Perspective projection, a z-buffer, and BSP splitting for cyclic
transparent geometry stay outside this change.

## Unified line visibility

`seg`, `edge`, and `arrow` use one visibility pipeline. Each line-like primitive
is represented internally by its endpoints and parameter interval `[0, 1]`, then
reconstructed with its original style after clipping.

Sphere clipping retains the existing exact orthographic calculation. Camera
projections of sphere centers and line endpoints are cached for the visibility
pass. Before solving the quadratic intersection, a screen-space bounding-box
test rejects sphere/line pairs whose projected bounds do not overlap. Hidden
intervals and silhouette cuts are merged and traversed with a linear sweep.
This keeps exact results while reducing repeated projection and interval scans;
the worst case remains proportional to lines times spheres, but sparse scenes
avoid most exact intersection work.

Arrows are clipped like other lines. Only the visible fragment containing the
original `to` endpoint retains the arrowhead. Other fragments render as the
arrow shaft, so clipping never duplicates marks. If an occluder hides the tip,
the arrowhead is hidden as well. Existing automatic sphere attachment normally
places a named arrow endpoint on the intended silhouette.

Opaque planar `face` and exploded mesh faces also occlude line intervals. The
projected line is cut at polygon-boundary intersections and at a line/face depth
crossing. A midpoint-in-polygon test classifies each resulting interval; an
interval inside the polygon is removed only when the planar face is closer to
the camera. Degenerate edge-on faces are ignored as occluders. Translucent faces
do not erase lines: exact ordering for cyclic transparency requires BSP splitting
and remains a documented limitation.

## Adaptive mesh visibility

Mesh faces gain an adaptive culling policy:

- Opaque meshes cull back faces by default.
- Translucent meshes retain front and back faces.
- A mesh or face may explicitly set `cull: none`, `cull: "back"`, or
  `cull: "front"`.

Front/back classification uses the projected polygon winding, with degenerate
edge-on faces retained unless an explicit policy says otherwise. Culling happens
after mesh explosion and before depth sorting.

Translucent meshes may provide `hidden-stroke` for rear-facing faces. If omitted,
the renderer derives a quieter rear stroke from the ordinary stroke by reducing
contrast and opacity. This prevents hidden Brillouin-zone edges from competing
with the visible outline while preserving the conventional transparent-cell
view. `hidden-stroke: none` suppresses rear edges entirely. Opaque meshes do not
need a hidden stroke because their back faces are culled by default.

The adaptive default is intentionally a pre-1.0 visual improvement. Explicit
`cull: none` preserves the old all-faces behavior when required.

## Anchor-export cost

`scene-group` gains `register-anchors: true`. Direct composition inside a shared
CeTZ canvas keeps the current behavior and therefore remains source-compatible.

`render-scene` calls `scene-group` with `register-anchors: false`. A standalone
canvas cannot be followed by CeTZ commands that reference its internal names,
so exporting every logical anchor there provides no capability. Skipping those
groups is especially important for named sphere collections, where each sphere
currently creates all compass and world-direction anchors.

Anchor resolution, `anchor-of`, and the scene's logical anchor table are
unchanged. Only CeTZ node emission is optional.

## Compatibility and errors

Primitive constructors remain plain dictionaries and accept the new visibility
hooks through their existing style sink. Invalid `cull` values fail with a clear
renderer error. A non-planar polygon is still rendered but is not used for exact
line occlusion because a single face-depth plane is undefined.

Existing public helpers retain their contracts. `_clip-lines` stays available to
the test suite, although its internal representation may change. Default sphere,
segment, edge, and arrow appearance remains unchanged except where visibility
was previously incorrect.

## Verification

Pure tests cover:

- arrow shafts clipped by one and multiple spheres;
- exactly one arrowhead on the terminal visible fragment;
- screen-space broad-phase rejection without changing exact intervals;
- an opaque polygon hiding only the rear portion of a changing-depth line;
- translucent polygons preserving line geometry;
- adaptive opaque culling, explicit culling overrides, and quiet rear strokes;
- standalone rendering without CeTZ anchor export and `scene-group` composition
  with anchors still addressable.

A compact regression scene combines a sphere, an opaque face, and a sloped line
or arrow so incorrect overlap is visually obvious. All examples and the manual
are rebuilt, the Brillouin and Wyckoff galleries are inspected at full
resolution, and the synthetic performance cases from the audit are rerun. The
full monorepo test suite must pass before implementation is committed.
