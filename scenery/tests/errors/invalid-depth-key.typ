// expected: depth-key must be "center", "back", or "front"
#import "/lib.typ": face, build-scene, camera, render-scene

#let bad = build-scene(face(
  ((0, 0, 0), (1, 0, 0), (0, 1, 0)),
  depth-key: "sideways",
))

#render-scene(bad, camera())
