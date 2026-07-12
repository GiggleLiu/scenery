#import "/src/io.typ": _io, plugin-version

// version() round-trips a known string
#assert.eq(plugin-version(), "wyckoff-io 0.1.0")

// echo() round-trips arbitrary bytes
#assert.eq(str(_io.echo(bytes("scenery"))), "scenery")
