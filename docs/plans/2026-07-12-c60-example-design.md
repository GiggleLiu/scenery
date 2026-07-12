# C60 ball-and-stick example

## Goal

Add a self-contained Scenery example that constructs and renders the C60
fullerene as a scientifically legible ball-and-stick molecule. The example must
demonstrate the package rather than depend on an external molecular file or an
offline generator.

## Geometry

Construct the molecule as a truncated icosahedron. Begin with the 12 analytic
icosahedron vertices formed from cyclic coordinate families using the golden
ratio. Identify the 30 icosahedron edges from their common length.

For each undirected edge `(u, v)`, create the two directed truncation points

```text
(2u + v) / 3
(u + 2v) / 3
```

The resulting 60 unique points are the carbon sites. Infer C-C bonds from the
common nearest-neighbour distance of the truncated solid. This yields the 90
edges of a truncated icosahedron: every site has degree three, and its local
rings assemble into 12 pentagons and 20 hexagons.

Keep the construction in `scenery/examples/c60.typ` using Scenery's exported
linear-algebra helpers. Assert the structural invariants in the example:

- 12 base vertices and 30 base edges;
- 60 carbon sites and 90 bonds;
- degree three at every carbon site;
- one shared bond length within a numerical tolerance.

Compilation is therefore both the demo and a topology regression test.

## Visual design

Render each carbon site as a moderately sized shaded sphere and each bond as a
slim round-capped segment. Use one restrained charcoal-blue atom colour and a
neutral bond colour on white. The camera is orthographic and oriented so both a
pentagonal and hexagonal region are apparent without strong foreshortening.

Do not draw axes: molecular orientation is arbitrary, and axes would compete
with the cage topology. Add only a compact C60 caption below the molecule. The
renderer handles sphere/segment occlusion, so bonds may be specified
centre-to-centre without manual endpoint trimming.

## Artifacts and verification

Generate `scenery/images/c60.png` through the package's existing `make images`
target and add the figure to the Scenery README gallery. Verify the example with
`make -C scenery examples`, then inspect the full-resolution PNG for balanced
framing, visible ring topology, correct bond occlusion, a single subdued colour
family, and no label or object overlap. Run the full monorepo test and example
suites before committing the implementation.
