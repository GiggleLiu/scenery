#import "@preview/cetz:0.5.2"
#import "/lib.typ": sphere, seg, edge, arrow, face, mesh, label, build-scene
#import "/lib.typ": camera, camera-2d, project, anchor-ref, anchor-of, anchor-names, resolve-scene
#import "/lib.typ": group as scene-group-transform, translate, scene-group
#import "/lib.typ": scale
#import "/src/style.typ": style-hooks
#import "/src/render.typ": _clip-lines, _record
#import "/src/style.typ": default-theme

#let close(a, b, eps: 1e-8) = range(3).all(i => calc.abs(a.at(i) - b.at(i)) < eps)
#let cam0 = camera(azimuth: 0deg, elevation: 0deg)

// Forward references resolve from the complete registry, and sphere compass
// anchors lie on the camera-relative silhouette.
#let linked = build-scene(
  seg("a.east", "b.west", name: "bond"),
  label("bond.mid", [d], name: "caption", text-anchor: "south"),
  sphere((0, 0, 0), 1, name: "a"),
  sphere((4, 0, 0), 1, name: "b"),
  // This foreground sphere fragments the logical bond at render preparation.
  sphere((2, 1, 0), 0.5, name: "blocker"),
)
#assert(linked.bbox == none, message: "unresolved scene must defer its bbox")
#let resolved = resolve-scene(linked, cam0)
#let bond = resolved.objects.at("bond")
#assert(close(bond.a, (1, 0, 0)))
#assert(close(bond.b, (3, 0, 0)))
#assert(close(anchor-of(linked, cam0, "bond.mid"), (2, 0, 0)))
#assert(close(anchor-of(linked, cam0, "a.north"), (0, 0, 1)))
#assert(anchor-names(linked, cam0, "bond") == ("default", "start", "mid", "end"))
#let bond-fragments = _clip-lines(resolved.prims, cam0).filter(
  p => p.kind == "seg" and p.at("name", default: none) == "bond"
)
#assert(bond-fragments.len() == 2, message: "occluding sphere must fragment the named bond")
#assert(close(anchor-of(linked, cam0, "bond.mid"), (2, 0, 0)),
  message: "logical midpoint must survive render fragmentation")

// The same compass name follows the selected camera, not fixed world x/y.
#let cam90 = camera(azimuth: 90deg, elevation: 0deg)
#assert(close(anchor-of(linked, cam90, "a.east"), (0, 1, 0)))
#assert(close(anchor-of(resolved, cam90, "a.east"), (0, 1, 0)))
#let diagonal = anchor-of(linked, cam0, anchor-ref("a", anchor: 45deg))
#assert(close(diagonal, (calc.sqrt(0.5), 0, calc.sqrt(0.5))))
#let tilted = camera(azimuth: 20deg, elevation: 35deg)
#let tilted-center = project(tilted, anchor-of(linked, tilted, "a.center"))
#let tilted-north = project(tilted, anchor-of(linked, tilted, "a.north"))
#assert(calc.abs(tilted-north.sx - tilted-center.sx) < 1e-8)
#assert(calc.abs(tilted-north.sy - tilted-center.sy - 1) < 1e-8)
#assert(calc.abs(tilted-north.depth - tilted-center.depth) < 1e-8)

// Every primitive family exposes its documented logical anchors.
#let kinds = build-scene(
  edge((0, 0, 0), (2, 0, 0), name: "edge"),
  arrow((0, 0, 0), (0, 0, 2), name: "arrow"),
  face(((0, 0, 0), (2, 0, 0), (0, 0, 2)), name: "face"),
  mesh(
    ((0, 0, 0), (2, 0, 0), (0, 2, 0), (0, 0, 2)),
    ((0, 1, 2), (0, 1, 3)),
    name: "mesh",
  ),
  label((3, 0, 0), [x], name: "label"),
)
#assert(close(anchor-of(kinds, cam0, "edge.start"), (0, 0, 0)))
#assert(close(anchor-of(kinds, cam0, "edge.end"), (2, 0, 0)))
#assert(close(anchor-of(kinds, cam0, "arrow.mid"), (0, 0, 1)))
#assert(close(anchor-of(kinds, cam0, "face.centroid"), (2 / 3, 0, 2 / 3)))
#assert(close(anchor-of(kinds, cam0, "face.vertex-1"), (2, 0, 0)))
#assert(close(anchor-of(kinds, cam0, "mesh.center"), (1, 1, 1)))
#assert(close(anchor-of(kinds, cam0, "mesh.vertex-3"), (0, 0, 2)))
#assert(close(anchor-of(kinds, cam0, "label"), (3, 0, 0)))

// Affine transforms on unresolved references are applied after resolution.
#let transformed = build-scene(
  sphere((0, 0, 0), 1, name: "origin"),
  scene-group-transform(scale(2),
    scene-group-transform(translate((0, 0, 1)),
      label("origin.east", [shifted], name: "shifted"))),
)
#assert(close(anchor-of(transformed, cam0, "shifted"), (2, 0, 2)))

// Names are structural metadata, not styling hooks.
#assert("name" not in style-hooks(resolved.objects.at("a")))
#let caption-record = _record(cam0, 1, default-theme, resolved.objects.at("caption"))
#assert(caption-record.anchor == "south", message: "label text-anchor was not forwarded")

// A reversed dependency chain exercises forward references and the topological
// cache without recursively recomputing every prefix.
#let chain = (label((7, 0), [root], name: "n0"),)
#for i in range(1, 40) {
  chain.push(label("n" + str(i - 1), [node], name: "n" + str(i)))
}
#let chain-scene = build-scene(..chain.rev())
#assert(close(anchor-of(chain-scene, camera-2d(), "n39"), (7, 0, 0)))

Named anchors OK

// Content-level composition: logical anchors are registered in CeTZ even when
// the named bond is later fragmented by sphere occlusion.
#cetz.canvas(length: 1cm, {
  scene-group(linked, cam0, unit: 1)
  import cetz.draw: circle, line
  circle("a.north", radius: 0.08, fill: black)
  circle("bond.mid", radius: 0.06, fill: black)
  line("a.east", "b.west", stroke: (paint: black, thickness: 0.4pt))
})
