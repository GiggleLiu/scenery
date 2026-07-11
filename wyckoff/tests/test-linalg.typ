#import "@preview/scenery:0.1.0": vadd, vsub, vdot, vcross, vlen, vnorm, mvec, lerp

#assert(vadd((1,2,3), (4,5,6)) == (5,7,9))
#assert(vsub((4,5,6), (1,2,3)) == (3,3,3))
#assert(vdot((1,2,3), (4,5,6)) == 32)
#assert(vcross((1,0,0), (0,1,0)) == (0,0,1))
#assert(calc.abs(vlen((3,4,0)) - 5) < 1e-9)
#assert(vnorm((0,0,2)) == (0,0,1))
#assert(mvec(((1,0,0),(0,0,-1),(0,1,0)), (1,2,3)) == (1,-3,2))
#assert(lerp((0,0,0), (2,4,6), 0.5) == (1,2,3))
Linalg OK
