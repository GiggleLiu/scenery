#import "/src/shape.typ": hull-faces, uv-sphere, cylinder, cone, prism
#import "/src/scene.typ": build-scene

// --- hull-faces: unit cube -> exactly 6 planar quads -------------------------
#let cube = (
  (0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1),
  (1, 1, 0), (1, 0, 1), (0, 1, 1), (1, 1, 1),
)
#let faces = hull-faces(cube)
#assert(faces.len() == 6, message: "cube has 6 faces, got " + str(faces.len()))
#assert(faces.all(f => f.vertices.len() == 4), message: "every cube face is a quad")
// the six outward normals are exactly the axis directions
#let norms = faces.map(f => f.plane.normal.map(x => calc.round(x, digits: 5)))
#for axis in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)) {
  assert(axis in norms, message: "missing hull normal " + repr(axis))
}
// spot-check one plane: the x=1 face has offset 1 and its four vertices on x=1
#let fx = faces.find(f => f.plane.normal.map(x => calc.round(x, digits: 5)) == (1, 0, 0))
#assert(calc.abs(fx.plane.offset - 1) < 1e-9)
#assert(fx.vertices.all(v => calc.abs(v.at(0) - 1) < 1e-9))

// --- hull-faces: tetrahedron -> 4 triangles ----------------------------------
#let tet = ((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1))
#let tfaces = hull-faces(tet)
#assert(tfaces.len() == 4, message: "tetrahedron has 4 faces, got " + str(tfaces.len()))
#assert(tfaces.all(f => f.vertices.len() == 3))

// --- negative control: degenerate input returns `none` -----------------------
// Typst asserts abort compilation and cannot be caught inside a test, so
// hull-faces returns the sentinel `none` for degenerate input (documented in
// shape.typ). Three collinear points are the canonical degenerate case.
#assert(hull-faces(((0, 0, 0), (1, 0, 0), (2, 0, 0))) == none, message: "3 collinear points are degenerate")
// further degenerate cases: too few points, and a flat (coplanar) square
#assert(hull-faces(((0, 0, 0), (1, 0, 0), (0, 1, 0))) == none, message: "3 points cannot bound a volume")
#assert(hull-faces(((0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0))) == none, message: "coplanar square is degenerate")

Hull OK

// --- parametric solids: mesh shape and index validity ------------------------
#let sph = uv-sphere((0, 0, 0), 1, segments: 12, rings: 6)
#assert(sph.kind == "mesh")
#assert(sph.vertices.len() == 12 * 7, message: "(rings+1) x segments vertices")
#assert(sph.faces.len() == 12 * 6, message: "rings x segments quads")

#let cyl = cylinder((0, 0, 0), (0, 0, 2), 1, segments: 8)
#assert(cyl.kind == "mesh")
#assert(cyl.vertices.len() == 16, message: "two rings of 8")
#assert(cyl.faces.len() == 8 + 2, message: "8 sides + 2 caps")

#let cn = cone((0, 0, 0), (0, 0, 2), 1, segments: 8)
#assert(cn.vertices.len() == 9, message: "8 base + 1 apex")
#assert(cn.faces.len() == 8 + 1, message: "8 sides + 1 base")

#let pr = prism(((0, 0), (1, 0), (1, 1), (0, 1)), (0, 0, 1))
#assert(pr.vertices.len() == 8, message: "square base extruded")
#assert(pr.faces.len() == 4 + 2, message: "4 sides + 2 caps")

// every face index is in range for every generated mesh
#for solid in (sph, cyl, cn, pr) {
  let n = solid.vertices.len()
  assert(solid.faces.all(f => f.all(i => i >= 0 and i < n)), message: "face index out of range")
}

// meshes drop straight into a scene; bbox of the unit sphere is [-1,1]^3
#let msc = build-scene(sph)
#assert(msc.prims.len() == 1)
#let bmin = msc.bbox.min.map(x => calc.round(x, digits: 5))
#let bmax = msc.bbox.max.map(x => calc.round(x, digits: 5))
#assert(bmin == (-1, -1, -1) and bmax == (1, 1, 1), message: repr(msc.bbox))

Shape OK
