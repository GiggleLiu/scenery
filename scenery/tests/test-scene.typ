#import "/src/scene.typ": sphere, seg, edge, arrow, face, mesh, label, translate, scale, affine, group, build-scene

// --- point normalisation: 2D points gain a z=0 component ---------------------
#assert(sphere((1, 2), 0.5).center == (1, 2, 0), message: "2D sphere centre -> (x,y,0)")
#assert(seg((0, 0), (3, 4)).a == (0, 0, 0) and seg((0, 0), (3, 4)).b == (3, 4, 0))
#assert(face(((0, 0), (1, 0), (1, 1))).pts == ((0, 0, 0), (1, 0, 0), (1, 1, 0)))
#assert(arrow((0, 0, 0), (1, 0, 0)).kind == "arrow")
#assert(label((0, 0), [X]).at == (0, 0, 0))

// styling hooks ride along verbatim
#assert(sphere((0, 0, 0), 1, color: red).color == red)

// mesh keeps its face-index arrays
#let m = mesh(((0, 0, 0), (1, 0, 0), (0, 1, 0)), ((0, 1, 2),), color: blue)
#assert(m.kind == "mesh" and m.faces == ((0, 1, 2),) and m.color == blue)

// --- build-scene: prim count and documented bbox -----------------------------
// Two spheres + one segment. Ground truth bbox (worked by hand):
//   sphere((0,0,0), 1)   -> x,y,z in [-1, 1]
//   sphere((2,0,0), 0.5) -> x in [1.5, 2.5], y,z in [-0.5, 0.5]
//   seg((0,0,0),(2,0,0)) -> inside the union already
//   => min = (-1, -1, -1), max = (2.5, 1, 1)
#let sc = build-scene(
  sphere((0, 0, 0), 1),
  sphere((2, 0, 0), 0.5),
  seg((0, 0, 0), (2, 0, 0)),
)
#assert(sc.prims.len() == 3, message: "got " + str(sc.prims.len()))
#assert(sc.bbox == (min: (-1, -1, -1), max: (2.5, 1, 1)), message: repr(sc.bbox))

// empty scene -> degenerate box at the origin
#assert(build-scene().bbox == (min: (0, 0, 0), max: (0, 0, 0)))

// --- group: an affine translation is applied and flattened -------------------
// A group translating a sphere by (1,0,0) yields one flat prim whose centre
// moved by exactly (1,0,0).
#let g = group(translate((1, 0, 0)), sphere((0, 0, 0), 1))
#assert(g.len() == 1 and g.first().center == (1, 0, 0), message: repr(g))
// the radius (a scalar size) is untouched by the transform
#assert(g.first().r == 1)

// nested groups compose left-to-right: (0,0,0) -> +x -> +y = (1,1,0)
#let nested = group(translate((0, 1, 0)), group(translate((1, 0, 0)), sphere((0, 0, 0), 1)))
#assert(nested.len() == 1 and nested.first().center == (1, 1, 0), message: repr(nested))

// a group flattens a mix of bare prims and nested groups
#let mixed = group(
  translate((0, 0, 1)),
  sphere((0, 0, 0), 1),
  group(translate((1, 0, 0)), seg((0, 0, 0), (0, 1, 0))),
)
#assert(mixed.len() == 2)
#assert(mixed.at(0).center == (0, 0, 1))
#assert(mixed.at(1).a == (1, 0, 1) and mixed.at(1).b == (1, 1, 1))

// scale moves positions but leaves scalar radius alone
#let s = group(scale(2), sphere((1, 1, 1), 3)).first()
#assert(s.center == (2, 2, 2) and s.r == 3)

// a general affine (here a 90-degree rotation about z) maps points correctly
#let rot = affine(matrix: ((0, -1, 0), (1, 0, 0), (0, 0, 1)))
#assert(group(rot, sphere((1, 0, 0), 1)).first().center == (0, 1, 0))

// build-scene also flattens groups passed as arguments
#let sc2 = build-scene(group(translate((5, 0, 0)), sphere((0, 0, 0), 1), sphere((1, 0, 0), 1)))
#assert(sc2.prims.len() == 2 and sc2.prims.first().center == (5, 0, 0))

Scene OK
