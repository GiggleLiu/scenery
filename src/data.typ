// Element and symmetry-group data access.
#let _elements = json("/data/elements.json")

#let element-info(symbol) = {
  assert(
    symbol in _elements,
    message: "wyckoff: unknown element '" + symbol + "'",
  )
  let e = _elements.at(symbol)
  (
    color: rgb(e.color),
    color-vesta: rgb(e.color-vesta),
    r-cov: e.r-cov,
    r-atom: e.r-atom,
  )
}
