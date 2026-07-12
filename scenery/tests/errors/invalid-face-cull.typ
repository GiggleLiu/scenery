// expected: face cull must be none
#import "/lib.typ": mesh, build-scene, camera, render-scene

#let bad = build-scene(mesh(
  ((0,0,0), (1,0,0), (0,1,0)),
  ((0,1,2),),
  cull: "sideways",
))

#render-scene(bad, camera())
