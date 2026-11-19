"""
    DojubogaWeb

Browser front end for Dojuboga. One web page (`web/index.html`) works two ways:

* **Local:** `serve()` runs a small web server on your machine and opens the
  game in your browser; every new puzzle is generated on demand.
* **Static:** `export_site(dir)` writes the page plus pre-generated puzzle
  packs, ready for GitHub Pages or any static host.

Built only on Dojuboga's public front-end API and the standard library.
"""
module DojubogaWeb

using Dojuboga
using Sockets

export serve, export_site, puzzle_json

include("json.jl")
include("export.jl")
include("server.jl")

end # module
