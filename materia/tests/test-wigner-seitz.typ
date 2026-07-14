#import "/src/reciprocal/reciprocal.typ": reciprocal-vectors
#import "/src/reciprocal/wigner-seitz.typ": bz-cell, bz-volume
#import "@preview/scenery:0.1.0": vcross, vdot, mesh

// Histogram of face polygon sizes: {vertex-count: number-of-faces}.
#let face-hist(cell) = {
  let h = (:)
  for f in cell.faces {
    let key = str(f.len())
    h.insert(key, h.at(key, default: 0) + 1)
  }
  h
}

// Reciprocal primitive-cell volume |det(b1,b2,b3)| — the invariant a BZ tiles.
#let det3(b) = calc.abs(vdot(b.at(0), vcross(b.at(1), b.at(2))))

// Assert bz-volume equals the reciprocal cell volume to 1e-6 relative.
#let check-volume(name, recip) = {
  let cell = bz-cell(recip)
  let want = det3(recip)
  let got = bz-volume(cell)
  assert(calc.abs(got - want) <= 1e-6 * want,
    message: name + " volume: got " + repr(got) + " want " + repr(want))
}

// --- fcc direct lattice: reciprocal is bcc -> truncated octahedron ------------
// 24 vertices, 14 faces = 8 hexagons + 6 squares.
#let fcc = reciprocal-vectors(((0, 2, 2), (2, 0, 2), (2, 2, 0)))
#let fcc-bz = bz-cell(fcc)
#assert(fcc-bz != none, message: "fcc BZ must exist")
#assert(fcc-bz.vertices.len() == 24,
  message: "fcc BZ (truncated octahedron): 24 vertices, got " + str(fcc-bz.vertices.len()))
#assert(fcc-bz.faces.len() == 14,
  message: "fcc BZ: 14 faces, got " + str(fcc-bz.faces.len()))
#assert(face-hist(fcc-bz) == ("6": 8, "4": 6),
  message: "fcc BZ face histogram (8 hexagons + 6 squares), got " + repr(face-hist(fcc-bz)))

// --- bcc direct lattice: reciprocal is fcc -> rhombic dodecahedron ------------
// 14 vertices, 12 rhombic (4-vertex) faces.
#let bcc = reciprocal-vectors(((-2, 2, 2), (2, -2, 2), (2, 2, -2)))
#let bcc-bz = bz-cell(bcc)
#assert(bcc-bz != none, message: "bcc BZ must exist")
#assert(bcc-bz.vertices.len() == 14,
  message: "bcc BZ (rhombic dodecahedron): 14 vertices, got " + str(bcc-bz.vertices.len()))
#assert(bcc-bz.faces.len() == 12,
  message: "bcc BZ: 12 faces, got " + str(bcc-bz.faces.len()))
#assert(face-hist(bcc-bz) == ("4": 12),
  message: "bcc BZ face histogram (12 rhombi), got " + repr(face-hist(bcc-bz)))

// --- simple cubic lattice -> cube --------------------------------------------
// 8 vertices, 6 square faces.
#let sc = reciprocal-vectors(((4, 0, 0), (0, 4, 0), (0, 0, 4)))
#let sc-bz = bz-cell(sc)
#assert(sc-bz != none, message: "cubic BZ must exist")
#assert(sc-bz.vertices.len() == 8,
  message: "cubic BZ (cube): 8 vertices, got " + str(sc-bz.vertices.len()))
#assert(sc-bz.faces.len() == 6,
  message: "cubic BZ: 6 faces, got " + str(sc-bz.faces.len()))
#assert(face-hist(sc-bz) == ("4": 6),
  message: "cubic BZ face histogram (6 squares), got " + repr(face-hist(sc-bz)))

// --- volume invariant: bz-volume == |det(b1,b2,b3)| for every case -----------
#check-volume("fcc", fcc)
#check-volume("bcc", bcc)
#check-volume("cubic", sc)
// plus a fully general triclinic lattice from the reciprocal fixture params
#let fx = json("/tests/fixtures/reciprocal.json")
#let triclinic-params = fx.cases.find(c => c.name == "triclinic").ltype-params
#check-volume("triclinic", reciprocal-vectors(triclinic-params))

// --- output is directly consumable as a scenery mesh -------------------------
#let m = mesh(sc-bz.vertices, sc-bz.faces)
#assert(m.kind == "mesh")
#assert(m.faces.all(f => f.all(ix => ix >= 0 and ix < m.vertices.len())),
  message: "every face index is a valid vertex index")

// --- negative control: coplanar reciprocal vectors -> sentinel `none` --------
// b3 = b1 + b2 makes the three vectors linearly dependent, so no bounded
// Wigner-Seitz cell exists. Like scenery's hull-faces, bz-cell returns `none`
// rather than aborting compilation.
#assert(bz-cell(((1, 0, 0), (0, 1, 0), (1, 1, 0))) == none,
  message: "coplanar reciprocal vectors must yield the `none` sentinel")

Wigner-Seitz OK
