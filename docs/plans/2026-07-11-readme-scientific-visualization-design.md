# README scientific visualization refresh

## Scope

Refresh the checked-in README gallery demos without changing the packages'
public default palettes. Correct line/sphere occlusion in the shared renderer so
the demos and downstream figures do not show bonds or construction lines through
opaque spherical objects.

## Considered approaches

1. **Restyle screenshots only.** This is small, but it leaves the rendering bug
   in the library and lets the source examples drift from their checked-in PNGs.
2. **Draw every sphere after every line.** This reliably hides lines at markers,
   but destroys valid 3D depth relationships when a line is genuinely in front
   of a more distant sphere.
3. **Clip only the hidden portions of projected lines (selected).** For each
   segment or edge, compute where its orthographic projection lies behind the
   visible surface of each sphere, merge those parameter intervals, and render
   the remaining fragments with their own depth keys. This preserves legitimate
   foreground crossings while removing lines that incorrectly show through
   opaque objects.

## Visual design

README demos use a small, color-vision-safe semantic palette: one muted blue and
one muted orange for primary categorical contrast, charcoal and mid-gray for
structure, and at most one quiet accent where a third state is necessary.
Continuous values use a perceptually ordered single-hue scale rather than a
rainbow. Shape, position, labels, and luminance carry information before color.
Backgrounds remain white, outlines are thin and neutral, translucent faces stay
light enough that internal geometry remains legible, and annotation furniture
does not compete with the data.

The package-level default palette and crystallographic element table remain
unchanged for compatibility. Example-only color overrides are introduced where
needed, and every README PNG is regenerated from its linked Typst source.

## Renderer and verification

The renderer keeps `sort-prims` as a sorting-only public helper. A new pure
preparation step clips `seg` and `edge` primitives against spheres before the
normal depth sort. Occlusion is evaluated in camera coordinates: projected line
parts behind the sphere center are hidden across the sphere disk, while parts in
front of the center are hidden only when they are inside the sphere surface.
Lines are also split at every sphere-silhouette boundary so a visible foreground
piece receives its own depth key. Visible fragments retain the original style.

Focused tests cover a center-to-outside bond, a fully hidden rear line, a valid
foreground line, and a line crossing multiple spheres. Existing compile tests
guard all draw branches. Verification then rebuilds package examples and images,
inspects every image embedded in the root and package READMEs, and runs the full
monorepo test suite.
