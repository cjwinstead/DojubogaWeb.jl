using DojubogaWeb, Dojuboga, Sockets, Test

const W = DojubogaWeb

"Minimal HTTP client: returns (status, headers::String, body::String)."
function http(port, path; method = "GET")
    sock = connect(ip"127.0.0.1", port)
    write(sock, "$method $path HTTP/1.1\r\nHost: localhost\r\n\r\n")
    raw = String(read(sock)); close(sock)
    head, body = split(raw, "\r\n\r\n"; limit = 2)
    parse(Int, split(head)[2]), head, body
end

function freeport()
    port, srv = listenany(ip"127.0.0.1", 20000)
    close(srv)
    Int(port)
end

@testset "DojubogaWeb" begin
    @testset "JSON writer" begin
        @test W.tojson("a\"b\\c\nd\u01") == "\"a\\\"b\\\\c\\nd\\u0001\""
        @test W.tojson((x = 1, y = (true, nothing, 2.5), z = "≠")) == "{\"x\":1,\"y\":[true,null,2.5],\"z\":\"≠\"}"
        @test W.tojson(Dict("b" => 1, "a" => 2)) == "{\"a\":2,\"b\":1}"
        @test W.tojson(NaN) == "null"
    end

    @testset "puzzle data" begin
        for lvl in LEVELS, sd in 1:3
            g = new_game(lvl; seed = sd)
            d = W.puzzle_data(g)
            n = length(d.cells)
            @test d.format == "dojuboga-puzzle" && d.version == 1 && d.level == string(lvl)
            @test d.seed == string(sd)
            @test n == ncells(g) && 2length(d.dominoes) == n
            @test all(0 <= r < d.rows && 0 <= c < d.cols for (r, c) in d.cells)
            @test sort(vcat([collect(reg.cells) for reg in d.regions]...)) == 0:n-1
            @test all((reg.color == 0) == (reg.label == "") for reg in d.regions)
            @test all(reg.ruleCell in reg.cells for reg in d.regions)
            # the exported solution covers the board and satisfies every exported rule
            vals = fill(-1, n)
            for s in d.solution
                a, b = d.dominoes[s.domino+1]
                vals[s.a+1] = a; vals[s.b+1] = b
                @test abs(d.cells[s.a+1][1] - d.cells[s.b+1][1]) + abs(d.cells[s.a+1][2] - d.cells[s.b+1][2]) == 1
            end
            @test all(>=(0), vals)
            kinds = Dict(v => k for (k, v) in W.KIND_NAMES)
            @test all(satisfies(Constraint(kinds[reg.rule.kind], reg.rule.k), vals[collect(reg.cells) .+ 1])
                      for reg in d.regions)
        end
        @test W.puzzle_json(:easy; seed = 5) == W.puzzle_json(new_game(:easy; seed = 5))
    end

    @testset "local server" begin
        port = freeport()
        srv = serve(port = port, open_browser = false, block = false)
        try
            st, head, body = http(port, "/")
            @test st == 200 && occursin("text/html", head) && occursin("Dojuboga", body)
            st, _, body = http(port, "/api/info.json")
            @test st == 200 && occursin("\"mode\":\"local\"", body)
            st, head, body = http(port, "/api/new?level=easy&seed=3")
            @test st == 200 && occursin("application/json", head)
            @test body == W.puzzle_json(:easy; seed = 3)
            @test http(port, "/api/new?level=nope")[1] == 400
            @test http(port, "/api/new?level=hard&seed=-1")[1] == 400
            @test http(port, "/nothing-here")[1] == 404
            st, head, _ = http(port, "/manifest.webmanifest")
            @test st == 200 && occursin("application/manifest+json", head)
            st, head, _ = http(port, "/icons/icon-192.png")
            @test st == 200 && occursin("image/png", head)
            @test http(port, "/icons/../Project.toml")[1] == 404
            @test http(port, "/sw.js")[1] == 404                         # no offline cache for the engine
            st, head, body = http(port, "/api/info"; method = "HEAD")
            @test st == 200 && isempty(body)
            @test http(port, "/"; method = "POST")[1] == 405
        finally
            close(srv)
        end
    end

    @testset "static site" begin
        dir = mktempdir()
        export_site(dir; per_level = 2, progress = false)
        @test isfile(joinpath(dir, "index.html")) && isfile(joinpath(dir, ".nojekyll"))
        @test all(isfile(joinpath(dir, "puzzles", "$l.json")) for l in LEVELS)
        @test occursin("\"mode\":\"static\"", read(joinpath(dir, "api", "info.json"), String))
        @test isfile(joinpath(dir, "manifest.webmanifest"))
        @test all(isfile(joinpath(dir, "icons", i)) for i in W.ICONS)
        sw = read(joinpath(dir, "sw.js"), String)
        @test !occursin("__VERSION__", sw) && !occursin("__FILES__", sw)
        files = ["./", "index.html", "manifest.webmanifest", ("icons/" .* W.ICONS)...,
                 ("puzzles/" .* string.(collect(LEVELS)) .* ".json")..., "puzzles/index.json", "api/info.json"]
        @test all(f -> occursin("\"" * f * "\"", sw), files)          # everything the game needs is cached
        @test all(f -> f == "./" || isfile(joinpath(dir, f)), files)
        version(d) = match(r"const VERSION = \"([0-9a-f]+)\"", read(joinpath(d, "sw.js"), String))[1]
        dir2 = export_site(mktempdir(); per_level = 2, progress = false)
        dir3 = export_site(mktempdir(); per_level = 3, progress = false)
        @test version(dir) == version(dir2)                              # same site, same version
        @test version(dir) != version(dir3)                              # changed site, new version
        pack = read(joinpath(dir, "puzzles", "hard.json"), String)
        @test occursin("\"format\":\"dojuboga-pack\"", pack)
        @test occursin(W.puzzle_json(:hard; seed = 2), pack)          # pack k uses seed k
        port = freeport()
        srv = serve(port = port, site = dir, open_browser = false, block = false)
        try
            @test http(port, "/")[1] == 200
            st, head, body = http(port, "/puzzles/easy.json")
            @test st == 200 && occursin("application/json", head) && body == read(joinpath(dir, "puzzles", "easy.json"), String)
            @test occursin("static", http(port, "/api/info.json")[3])
            st, head, _ = http(port, "/sw.js")
            @test st == 200 && occursin("text/javascript", head)
            @test occursin("application/manifest+json", http(port, "/manifest.webmanifest")[2])
            @test http(port, "/../Project.toml")[1] == 404
            @test http(port, "/puzzles/%2e%2e/index.html")[1] == 404
            @test http(port, "/api/new?level=easy")[1] == 404              # no engine in static mode
        finally
            close(srv)
        end
        @test_throws ArgumentError serve(site = mktempdir(), open_browser = false, block = false)
    end
end
