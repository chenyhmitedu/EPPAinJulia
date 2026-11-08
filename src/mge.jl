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
    _revive_cached_model!(MGE)
    return MGE, st
end

# A serialized WeakKeyDict is not a valid cache. Julia 1.12 crashes with
# EXCEPTION_ACCESS_VIOLATION on the next lookup, inside build_constraints!.
function _revive_cached_model!(MGE)
    jm = jump_model(MGE)
    setfield!(jm, :subexpressions, WeakKeyDict{Any,MOI.ScalarNonlinearFunction}())
    PATHSolver.c_api_License_SetString(PATH_LICENSE)
    return MGE
end

function _save_model_cache(key, simu, MGE, st)
    setfield!(jump_model(MGE), :subexpressions, WeakKeyDict{Any,MOI.ScalarNonlinearFunction}())
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

"""
    MGE_model(B; simu::Integer = 0)

Build the MPSGE model for benchmark `B`.

A previous build is reloaded from `cache/` when the Julia source, benchmark
files, period list, and `simu` are unchanged. The loaded JuMP subexpression
cache is discarded: a serialized `WeakKeyDict` crashes Julia 1.12 while the
benchmark constraints are created. A cache miss rebuilds with `Base.invokelatest`.
"""
function MGE_model(B; simu::Integer = 0)
    apply_smooth!()
    simu = Int(simu)
    key = _model_cache_key(simu)
    loaded = try
        _try_load_model_cache(key, simu)
    catch err
        println("model cache unreadable (", err, "); rebuilding")
        flush(stdout)
        nothing
    end
    if loaded !== nothing
        println("model cache hit")
        flush(stdout)
        return loaded
    end
    MGE, st = Base.invokelatest(_eppacore, B, simu)
    try
        _save_model_cache(key, simu, MGE, st)
    catch err
        println("model cache not saved (", err, ")")
        flush(stdout)
    end
    return MGE, st
end

"""
    EPPA_model(data, iter::Integer = -1; simu::Integer = 0)

Base-year model, before any endowment update.

`iter` must be `-1`. `solve!(MGE; cumulative_iteration_limit = 0)` then reports
the benchmark residual. Later years are solved by [`run_scenario`](@ref).
"""
function EPPA_model(data, iter::Integer = -1; simu::Integer = 0)
    iter == -1 || throw(ArgumentError(
        "EPPA_model(data, -1) is the base-year model. Later years are solved by run_scenario.",
    ))
    bau = simu == 1 ? _load_bau() : nothing
    MGE, st = MGE_model(data; simu)
    simu == 1 && _install_gprod!(st, bau, YEARS[1])
    return MGE
end



