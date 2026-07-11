// expected: has no anchor
#import "/lib.typ": sphere, label, build-scene, camera-2d, resolve-scene
#let scene = build-scene(
  sphere((0, 0), 1, name: "a"),
  label("a.start", [bad]),
)
#resolve-scene(scene, camera-2d())
