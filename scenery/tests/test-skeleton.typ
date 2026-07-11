// Skeleton test: proves the scenery entrypoint compiles and exports its version.
#import "/lib.typ": scenery-version

#assert.eq(
  scenery-version,
  version(0, 1, 0),
  message: "scenery-version must be 0.1.0",
)
