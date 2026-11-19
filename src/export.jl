# Puzzle → JSON (format "dojuboga-puzzle", version 1; see README.md).
# Everything is read through Dojuboga's public front-end API.

const FORMAT_VERSION = 1
const PALETTE_SIZE = 10        # region colours are indices 1:10 (0 = blank region)

const KIND_NAMES = Dict(NONE => "none", SUM => "sum", LESS => "less",
                        GREATER => "greater", EQUAL => "equal", NOTEQUAL => "notequal")

"""
    puzzle_data(game) -> NamedTuple

The puzzle as plain data, ready for JSON. All indices and coordinates are
0-based (JavaScript-friendly); the seed is a string (it exceeds 2^53).
"""
function puzzle_data(g::Game)
    (nr, nc) = board_size(g)
    colors = region_colors(g, PALETTE_SIZE)
    regions = map(1:nregions(g)) do r
        rule = region_rule(g, r)
        (cells = region_cells(g, r) .- 1,
         rule = (kind = KIND_NAMES[rule.kind], k = rule.k),
         label = rule_label(g, r),
         ruleCell = rule_cell(g, r) - 1,
         color = colors[r])
    end
    rt = rating(g)
    (format = "dojuboga-puzzle",
     version = FORMAT_VERSION,
     level = string(level(g)),
     seed = string(seed(g)),
     rating = (score = round(rt.score; digits = 1), level = string(rt.level)),
     rows = nr, cols = nc,
     cells = [[cell_coords(g, i)[1] - 1, cell_coords(g, i)[2] - 1] for i in 1:ncells(g)],
     regions = regions,
     dominoes = [[d.a, d.b] for d in dominoes(g)],
     solution = [(domino = p.domino - 1, a = p.c1 - 1, b = p.c2 - 1) for p in puzzle(g).solution])
end

"""
    puzzle_json(game) -> String
    puzzle_json(level; seed) -> String

The puzzle in the `dojuboga-puzzle` JSON format.
"""
puzzle_json(g::Game) = tojson(puzzle_data(g))
puzzle_json(lvl::Symbol = :medium; seed = nothing) = puzzle_json(new_game(lvl; seed = seed))

"Path of a bundled web file (`index.html`, `manifest.webmanifest`, `sw.js`, `icons/…`)."
web_path(parts...) = joinpath(@__DIR__, "..", "web", parts...)
page_path() = web_path("index.html")
const ICONS = ["icon-192.png", "icon-512.png", "icon-maskable-512.png", "apple-touch-icon.png"]

"""
    export_site(dir; per_level=200, levels=LEVELS, first_seed=1, progress=true) -> dir

Write a static version of the game to `dir`, ready for GitHub Pages or any
static host (no server needed):

* `index.html`, the game page
* `puzzles/<level>.json`, one puzzle pack per level, and `puzzles/index.json`
* `api/info.json`, which tells the page it is running without an engine
* `manifest.webmanifest`, `icons/` and `sw.js`, which make the site an
  installable app that plays offline (on a host that serves it over HTTPS)

Pack `k` of a level is generated from seed `first_seed + k - 1`, so the same
arguments reproduce the same site.
"""
function export_site(dir::AbstractString; per_level::Integer = 200, levels = LEVELS,
                     first_seed::Integer = 1, progress::Bool = true)
    per_level >= 1 || throw(ArgumentError("per_level must be at least 1"))
    for lvl in levels
        lvl in LEVELS || throw(ArgumentError("unknown level $lvl"))
    end
    mkpath(joinpath(dir, "puzzles")); mkpath(joinpath(dir, "api")); mkpath(joinpath(dir, "icons"))
    cp(page_path(), joinpath(dir, "index.html"); force = true)
    cp(web_path("manifest.webmanifest"), joinpath(dir, "manifest.webmanifest"); force = true)
    for icon in ICONS
        cp(web_path("icons", icon), joinpath(dir, "icons", icon); force = true)
    end
    touch(joinpath(dir, ".nojekyll"))                 # GitHub Pages: serve files as-is
    counts = Dict{String,Int}()
    for lvl in levels
        puzzles = Vector{Any}(undef, per_level)
        for k in 1:per_level
            puzzles[k] = puzzle_data(new_game(lvl; seed = first_seed + k - 1))
            progress && (k == per_level || k % 25 == 0) &&
                print("\r  $lvl: $k / $per_level puzzles")
        end
        progress && println()
        open(joinpath(dir, "puzzles", "$lvl.json"), "w") do io
            writejson(io, (format = "dojuboga-pack", version = FORMAT_VERSION,
                           level = string(lvl), puzzles = puzzles))
        end
        counts[string(lvl)] = per_level
    end
    open(joinpath(dir, "puzzles", "index.json"), "w") do io
        writejson(io, (format = "dojuboga-index", version = FORMAT_VERSION, levels = counts))
    end
    open(joinpath(dir, "api", "info.json"), "w") do io      # answers the page's engine probe
        writejson(io, (mode = "static", levels = [string(l) for l in levels], format = FORMAT_VERSION))
    end
    write_service_worker(dir, levels)
    progress && println("Static site written to ", abspath(dir))
    dir
end

"""
Write `sw.js`: the list of files to keep on the device, and a version that is
a fingerprint of their contents (so a changed site replaces the old copy).
"""
function write_service_worker(dir, levels)
    files = ["index.html", "manifest.webmanifest", ["icons/" * i for i in ICONS]...,
             ["puzzles/$l.json" for l in levels]..., "puzzles/index.json", "api/info.json"]
    ctx = SHA.SHA256_CTX()
    for f in files
        SHA.update!(ctx, Vector{UInt8}(f)); SHA.update!(ctx, read(joinpath(dir, f)))
    end
    version = bytes2hex(SHA.digest!(ctx))[1:16]
    template = read(web_path("sw.js"), String)
    js = replace(template, "\"__VERSION__\"" => tojson(version), "__FILES__" => tojson(["./"; files]))
    write(joinpath(dir, "sw.js"), js)
    version
end
