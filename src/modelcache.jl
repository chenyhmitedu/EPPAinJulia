"""
    _model_cache_key(simu)

Fingerprint of the source, the benchmark files, the period list, and `simu`.
The model cache is reused only when this string is unchanged.
"""
function _model_cache_key(simu)
    root = normpath(joinpath(@__DIR__, ".."))
    h = UInt64(0xcbf29ce484222325)
    h = _fnv!(h, string(VERSION))
    h = _fnv!(h, string(Int(simu)))
    h = _fnv!(h, join(YEARS, ","))
    files = String[]
    for (dir, _, names) in walkdir(root)
        occursin("/.git", replace(dir, "\\" => "/")) && continue
        for name in names
            endswith(name, ".jl") || name in ("Project.toml", "Manifest.toml") || continue
            push!(files, joinpath(dir, name))
        end
    end
    for name in ("eppa8data_2017.dat", "eppa8data_elec_2017.dat", "satellite.xlsx")
        path = joinpath(root, "data", name)
        isfile(path) && push!(files, path)
    end
    for path in sort!(files)
        rel = replace(relpath(path, root), "\\" => "/")
        h = _fnv!(h, rel)
        h = _fnv!(h, read(path))
    end
    return string(h, base = 16)
end

function _model_cache_paths(simu)
    root = normpath(joinpath(@__DIR__, ".."))
    dir = joinpath(root, "cache")
    tag = "simu" * string(Int(simu))
    return joinpath(dir, "eppa_model_" * tag * ".key"), joinpath(dir, "eppa_model_" * tag * ".jls")
end

function _fnv!(h::UInt64, s::AbstractString)
    return _fnv!(h, codeunits(s))
end

function _fnv!(h::UInt64, data::AbstractVector{UInt8})
    @inbounds for b in data
        h = xor(h, UInt64(b)) * 0x100000001b3
    end
    return h
end

function _try_load_model_cache(key, simu)
    keypath, path = _model_cache_paths(simu)
    isfile(keypath) && isfile(path) || return nothing
    rstrip(read(keypath, String)) == key || return nothing
    MGE, st = deserialize(path)
    PATHSolver.c_api_License_SetString(PATH_LICENSE)
    return MGE, st
end

function _save_model_cache(key, simu, MGE, st)
    keypath, path = _model_cache_paths(simu)
    mkpath(dirname(path))
    tmp = path * ".tmp"
    serialize(tmp, (MGE, st))
    mv(tmp, path; force = true)
    write(keypath, key)
    println("model cache saved ", path)
    flush(stdout)
    return path
end
