// expected: has no anchor
#import "/lib.typ": face, label, build-scene, camera-2d, resolve-scene
#let scene = build-scene(
  face(((0, 0), (1, 0), (0, 1)), name: "triangle"),
  label("triangle.vertex-9", [bad]),
)
#resolve-scene(scene, camera-2d())
