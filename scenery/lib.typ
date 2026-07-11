#let scenery-version = version(0, 1, 0)

// Pure scene-core math: vector/matrix helpers and the orthographic camera.
#import "src/linalg.typ": vadd, vsub, vscale, vdot, vcross, vlen, vnorm, mvec, lerp
#import "src/camera.typ": camera, camera-2d, project
