// expected: cannot auto-attach sphere
#import "/lib.typ": sphere, seg, build-scene, camera-2d, resolve-scene
#let scene = build-scene(
  sphere((0, 0), 1, name: "a"),
  sphere((0, 0), 1, name: "b"),
  seg("a", "b", name: "bond"),
)
#resolve-scene(scene, camera-2d())
