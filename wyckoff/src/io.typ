// Host-agnostic parsing bridge: loads the wyckoff-io WASM plugin and turns
// its JSON records into wyckoff structures. Path is resolved relative to this
// file so it works under any compilation root.
#let _io = plugin("../plugin/wyckoff_io.wasm")

/// Plugin version string (smoke check that the binary loads).
#let plugin-version() = str(_io.version())
