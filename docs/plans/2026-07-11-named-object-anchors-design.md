# Named object anchors

## Goal

Add scenery-native object names and anchors, borrowing CeTZ's familiar
`"object.anchor"` coordinate syntax while preserving correct behavior through
3D projection, depth sorting, and line fragmentation.

## Public model

Every primitive may carry an optional unique `name:`. Names are structural
metadata, must be non-empty strings, and cannot contain `.`. Concrete points and
named references can be mixed:

```typst
sphere((0, 0, 0), 0.5, name: "a")
sphere((2, 0, 0), 0.5, name: "b")
seg("a.east", "b.west", name: "bond")
label("bond.mid", [distance])
```

Initial anchors are:

- sphere: `center` (default), compass directions, and angle border anchors;
- segment and edge: `start`, `mid` (default), and `end`;
- arrow: `start`, `mid` (default), and `end`;
- face: `centroid` (default) and `vertex-N`;
- mesh: bounding-box `center` (default) and `vertex-N`;
- label: `center` (default), meaning its attachment point.

Compass and angle anchors on spheres are camera-relative points on the rendered
silhouette. `anchor-ref(name, anchor:)` represents anchors that cannot be written
as a string, especially angles. `anchor-of(scene, camera, reference)` exposes
the same resolver and returns a concrete 3D point.

## Architecture and data flow

A pure coordinate layer recognizes concrete points, string/dictionary
references, and internally transformed reference expressions. Affine groups
transform concrete points immediately and defer transforms on references until
resolution. Names are scene-global in this release.

`build-scene` validates names and coordinate syntax, builds the complete object
registry, and retains unresolved geometry. Rendering then:

1. resolves the name dependency graph for the selected camera;
2. computes concrete primitives, anchors, and bounding boxes;
3. applies existing line/sphere occlusion and fragmentation;
4. depth-sorts and emits anonymous geometry.

Logical anchors are computed before fragmentation, so a named bond keeps stable
`start`, `mid`, and `end` anchors regardless of how many visible pieces it
produces.

`scene-group` registers an invisible named CeTZ group containing each logical
object's projected anchors, then draws geometry anonymously. Later CeTZ commands
inside the same canvas may therefore reference `"a.east"` without duplicate
names from fragmented objects. `render-scene` remains a self-contained canvas;
`scene-group` is the composition surface.

## Errors and compatibility

Concrete-coordinate scenes retain their current output. `name` is removed from
style resolution; other extra constructor arguments remain styling hooks. Labels
gain `text-anchor:` for CeTZ content alignment without overloading an object's
reference anchor.

Resolution supports forward references. It reports actionable errors for
duplicate or malformed names, unknown objects, unsupported anchors, invalid
vertex indices, malformed coordinates, and dependency cycles, including the
referring object's name where available.

## Verification

Pure tests cover all primitive anchors, multiple camera orientations, angle
anchors, forward and transformed references, validation failures, and cycles.
Rendering tests cover stable logical anchors through occlusion fragmentation,
CeTZ composition using `"name.anchor"`, and label alignment. Existing package
tests, examples, manual compilation, and README link checks remain the regression
suite. Documentation gains a compact example and an anchor table.
