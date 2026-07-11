#let scenery-version = version(0, 1, 0)

// Pure scene-core math: vector/matrix helpers and the orthographic camera.
#import "src/linalg.typ": vadd, vsub, vscale, vdot, vcross, vlen, vnorm, mvec, lerp
#import "src/camera.typ": camera, camera-2d, project

// Typed primitives, affine transforms and scene assembly (pure data, no cetz).
#import "src/scene.typ": sphere, seg, edge, arrow, face, mesh, label, affine, translate, scale, group, build-scene

// Shape generators: convex hull faces and parametric solid meshes.
#import "src/shape.typ": hull-faces, uv-sphere, cylinder, cone, prism

// Theme data and per-primitive style resolution (pure data, no cetz).
#import "src/style.typ": default-theme, resolve-style, palette-color

// Depth-sort (pure) and the cetz painter's-algorithm backend.
#import "src/render.typ": sort-prims, scene-group, render-scene
