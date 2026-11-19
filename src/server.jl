# A small HTTP/1.1 server on the standard library's Sockets. It serves the
# page and a two-route JSON API (local mode), or the files of an exported
# site (static mode). It listens on 127.0.0.1 only.

const CONTENT_TYPES = Dict(".html" => "text/html; charset=utf-8", ".json" => "application/json",
                           ".js" => "text/javascript", ".css" => "text/css", ".svg" => "image/svg+xml",
                           ".png" => "image/png", ".txt" => "text/plain; charset=utf-8",
                           ".ico" => "image/x-icon", ".webmanifest" => "application/manifest+json")
const STATUS_TEXT = Dict(200 => "OK", 400 => "Bad Request", 404 => "Not Found",
                         405 => "Method Not Allowed", 500 => "Internal Server Error")

function respond(io::IO, status::Int, ctype::AbstractString, body; head::Bool = false)
    bytes = body isa AbstractVector{UInt8} ? body : Vector{UInt8}(string(body))
    write(io, "HTTP/1.1 $status $(STATUS_TEXT[status])\r\n",
              "Content-Type: $ctype\r\nContent-Length: $(length(bytes))\r\n",
              "Cache-Control: no-store\r\nConnection: close\r\n\r\n")
    head || write(io, bytes)
    flush(io)
    nothing
end

function unescape_url(s::AbstractString)
    out = IOBuffer(); bytes = codeunits(s); n = length(bytes); k = 1
    while k <= n
        b = bytes[k]
        if b == UInt8('%') && k + 2 <= n
            v = tryparse(UInt8, String(bytes[k+1:k+2]); base = 16)
            if v !== nothing
                write(out, v); k += 3; continue
            end
        end
        write(out, b == UInt8('+') ? UInt8(' ') : b); k += 1
    end
    String(take!(out))
end

function parse_target(target::AbstractString)
    path, q = occursin('?', target) ? split(target, '?'; limit = 2) : (target, "")
    query = Dict{String,String}()
    for part in split(q, '&'; keepempty = false)
        kv = split(part, '='; limit = 2)
        query[unescape_url(kv[1])] = length(kv) == 2 ? unescape_url(kv[2]) : ""
    end
    unescape_url(path), query
end

json_error(status, msg) = (status, CONTENT_TYPES[".json"], tojson((error = msg,)))

"Local mode: the page plus `/api/info.json` and `/api/new?level=…&seed=…`."
function route_local(path, query)
    if path in ("/", "/index.html")
        return 200, CONTENT_TYPES[".html"], read(page_path())
    elseif path == "/manifest.webmanifest"
        return 200, CONTENT_TYPES[".webmanifest"], read(web_path("manifest.webmanifest"))
    elseif startswith(path, "/icons/") && path[8:end] in ICONS
        return 200, CONTENT_TYPES[".png"], read(web_path("icons", path[8:end]))
    elseif path in ("/api/info", "/api/info.json")
        return 200, CONTENT_TYPES[".json"],
               tojson((mode = "local", levels = string.(collect(LEVELS)),
                       engine = string(pkgversion(Dojuboga)), format = FORMAT_VERSION))
    elseif path == "/api/new"
        lvl = Symbol(lowercase(get(query, "level", "medium")))
        lvl in LEVELS || return json_error(400, "level must be one of $(join(LEVELS, ", "))")
        sd = nothing
        if haskey(query, "seed")
            sd = tryparse(UInt64, query["seed"])
            sd === nothing && return json_error(400, "seed must be a non-negative integer")
        end
        return 200, CONTENT_TYPES[".json"], puzzle_json(lvl; seed = sd)
    end
    json_error(404, "not found: $path")
end

"Static mode: files under `site` (no API, so the page plays from its packs)."
function route_static(path, site)
    rel = path == "/" ? "index.html" : lstrip(path, '/')
    parts = split(rel, '/')
    any(p -> p in ("", ".", "..") || occursin('\\', p), parts) && return json_error(404, "not found")
    file = joinpath(site, parts...)
    isfile(file) || return json_error(404, "not found: $path")
    200, get(CONTENT_TYPES, lowercase(splitext(file)[2]), "application/octet-stream"), read(file)
end

function handle_connection(sock, site)
    try
        line = readline(sock)
        isempty(line) && return
        fields = split(line)
        length(fields) >= 2 || return respond(sock, json_error(400, "bad request")...)
        method, target = fields[1], fields[2]
        nheaders = 0
        while !eof(sock) && nheaders < 100                       # skip headers
            isempty(readline(sock)) && break
            nheaders += 1
        end
        method in ("GET", "HEAD") || return respond(sock, json_error(405, "only GET is supported")...)
        path, query = parse_target(target)
        status, ctype, body = site === nothing ? route_local(path, query) : route_static(path, site)
        respond(sock, status, ctype, body; head = method == "HEAD")
    catch err
        err isa Base.IOError || (try respond(sock, json_error(500, "internal error")...) catch end;
                                 @warn "request failed" exception = (err, catch_backtrace()))
    finally
        close(sock)
    end
end

function open_in_browser(url)
    cmd = Sys.isapple() ? `open $url` : Sys.iswindows() ? `cmd /c start "" $url` : `xdg-open $url`
    try
        run(pipeline(cmd; stdout = devnull, stderr = devnull); wait = false)
    catch
    end
    nothing
end

"""
    serve(; port=8000, site=nothing, open_browser=true, block=true)

Start the game's web server on `http://localhost:port/` (listening on
127.0.0.1 only) and open it in your browser.

* `site = nothing` — local mode: fresh puzzles generated on demand.
* `site = "dir"` — serve a site written by [`export_site`](@ref), to preview
  it exactly as a static host would.

With `block = true` (default) the call runs until interrupted (Ctrl-C).
With `block = false` it returns the listening server; `close(server)` stops it.
"""
function serve(; port::Integer = 8000, site = nothing, open_browser::Bool = true, block::Bool = true)
    site !== nothing && !isfile(joinpath(site, "index.html")) &&
        throw(ArgumentError("$site does not contain an exported site (no index.html)"))
    server = listen(ip"127.0.0.1", port)
    task = @async while isopen(server)
        sock = try
            accept(server)
        catch
            break
        end
        @async handle_connection(sock, site)
    end
    url = "http://localhost:$port/"
    println(site === nothing ? "Dojuboga is running at $url" :
                               "Serving the static site in $site at $url")
    open_browser && open_in_browser(url)
    block || return server
    println("Press Ctrl-C to stop.")
    try
        wait(task)
    catch err
        err isa InterruptException || rethrow()
    finally
        close(server)
    end
    nothing
end
