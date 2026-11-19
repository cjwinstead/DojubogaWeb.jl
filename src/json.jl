# A minimal JSON writer: enough for strings, numbers, booleans, nothing,
# vectors, tuples, named tuples and string-keyed dicts.

function writejson(io::IO, s::AbstractString)
    print(io, '"')
    for c in s
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        elseif c == '\t'
            print(io, "\\t")
        elseif c < ' '
            print(io, "\\u", string(UInt16(c); base = 16, pad = 4))
        else
            print(io, c)
        end
    end
    print(io, '"')
end
writejson(io::IO, s::Symbol) = writejson(io, string(s))
writejson(io::IO, x::Bool) = print(io, x ? "true" : "false")
writejson(io::IO, x::Integer) = print(io, x)
writejson(io::IO, x::AbstractFloat) = isfinite(x) ? print(io, x) : print(io, "null")
writejson(io::IO, ::Nothing) = print(io, "null")

function writejson(io::IO, v::Union{AbstractVector,Tuple})
    print(io, '[')
    for (k, x) in enumerate(v)
        k > 1 && print(io, ',')
        writejson(io, x)
    end
    print(io, ']')
end

function writejson(io::IO, nt::NamedTuple)
    print(io, '{')
    for (k, (key, x)) in enumerate(pairs(nt))
        k > 1 && print(io, ',')
        writejson(io, string(key)); print(io, ':'); writejson(io, x)
    end
    print(io, '}')
end

function writejson(io::IO, d::AbstractDict)
    print(io, '{')
    for (k, key) in enumerate(sort!(collect(keys(d)); by = string))
        k > 1 && print(io, ',')
        writejson(io, string(key)); print(io, ':'); writejson(io, d[key])
    end
    print(io, '}')
end

"Serialise `x` to a JSON string."
tojson(x) = sprint(writejson, x)
