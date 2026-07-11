#import "/src/data.typ": element-info

#let na = element-info("Na")
#assert(na.r-cov > 1.5 and na.r-cov < 1.8, message: "Na covalent radius ~1.66")
#assert(type(na.color) == color, message: "color must be a Typst color")
#let o = element-info("O")
#assert(o.r-cov < 0.8, message: "O covalent radius ~0.66")
#assert(element-info("Ti").r-atom > 1.0)
Data OK
