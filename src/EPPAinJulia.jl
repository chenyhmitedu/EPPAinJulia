"""
    EPPAinJulia

Recursive-dynamic MPSGE model of EPPA.

Active blocks are production by nest class, electricity technologies, Armington
and bilateral trade, homogeneous oil, household transport, welfare, and the
`GPROD` / `RGDP` closure. Vintage capital, backstops, land use, Stone-Geary
preferences, and emissions commodities are off.

Benchmark accounts follow the active v-ref structure. Emission pass-through
nests are identities at a zero carbon price, so energy inputs use `pa` (`phom`
for crude oil) directly.

Data readers parse the GAMS parameter dump and the satellite workbook.
"""
module EPPAinJulia

using JuMP
using JLD2
using MPSGE
using PATHSolver
using Serialization
using XLSX

export load_benchmark, prepare, build_model, EPPA_model, run_scenario, set_model_years!, record_eesec!, record_sco2!, record_ftotco2!, write_report, replication_error, gams_table

const PATH_LICENSE = "1259252040&Courtesy&&&USR&GEN2035&5_1_2026&1000&PATH&GEN&31_12_2035&0_0_0&6000&0_0"
const MOI = JuMP.MOI

include("load.jl")
include("calib.jl")
include("nests.jl")
include("smooth.jl")
include("modelcache.jl")
include("eppacore.jl")
include("eppaloop.jl")
include("report.jl")

"""
    gams_table(text) -> Dict{Tuple{Symbol,Int},Float64}

Read a GAMS-style table. The first line is the column headers (years). Each
later line is a row label and one number per column.
"""
function gams_table(text::AbstractString)
    lines = [strip(line) for line in split(text, '\n') if !isempty(strip(line)) && !startswith(lstrip(line), '*')]
    isempty(lines) && error("gams table is empty")
    years = [parse(Int, h) for h in split(lines[1])]
    out = Dict{Tuple{Symbol,Int},Float64}()
    for line in lines[2:end]
        parts = split(line)
        length(parts) == length(years) + 1 || error("row $(parts[1]) has $(length(parts) - 1) values, expected $(length(years))")
        r = Symbol(parts[1])
        for (t, v) in zip(years, parts[2:end])
            out[(r, t)] = parse(Float64, v)
        end
    end
    return out
end

function __init__()
    apply_smooth!()
    return nothing
end

function _level(x)
    v = try
        value(x)
    catch
        return NaN
    end
    return v
end

function _warm!(MGE)
    jm = jump_model(MGE)
    for v in all_variables(jm)
        x = try
            value(v)
        catch
            continue
        end
        isfinite(x) || continue
        set_start_value(v, x)
    end
    return nothing
end

function _snap(MGE)
    jm = jump_model(MGE)
    out = Dict{String,Float64}()
    for v in all_variables(jm)
        s = start_value(v)
        s === nothing && continue
        out[JuMP.name(v)] = s
    end
    return out
end

function _restore!(MGE, snap)
    jm = jump_model(MGE)
    for v in all_variables(jm)
        s = get(snap, JuMP.name(v), nothing)
        s === nothing && continue
        set_start_value(v, s)
    end
    return nothing
end

function _solve!(MGE; tol = 1e-5, iters = 20_000, proximal = 0.0, restarts = 3)
    jm = jump_model(MGE)
    if !haskey(JuMP.object_dictionary(jm), :z_p)
        was = MGE.silent
        MGE.silent = true
        solve!(MGE; cumulative_iteration_limit = 0, output = "no")
        MGE.silent = was
    end
    JuMP.unset_silent(jm)
    kw = unsafe_backend(jm).ext[:kwargs]
    empty!(kw)
    kw[:cumulative_iteration_limit] = iters
    kw[:minor_iteration_limit] = 100_000
    kw[:major_iteration_limit] = 400
    kw[:convergence_tolerance] = tol
    kw[:proximal_perturbation] = proximal
    kw[:restart_limit] = restarts
    kw[:output] = "yes"
    kw[:output_major_iterations] = "yes"
    kw[:output_major_iterations_frequency] = 1
    kw[:output_minor_iterations] = "yes"
    kw[:output_minor_iterations_frequency] = 500
    kw[:output_crash_iterations] = "yes"
    kw[:output_restart_log] = "yes"
    kw[:output_final_summary] = "yes"
    JuMP.optimize!(jm)
    flush(stdout)
    return termination_status(jm)
end

function _residual(MGE)
    jm = jump_model(MGE)
    b = unsafe_backend(jm)
    opt = b
    if hasproperty(b, :optimizer)
        inner = getfield(b, :optimizer)
        inner === nothing || (opt = inner)
    end
    sol = try
        PATHSolver.solution(opt)
    catch
        nothing
    end
    sol === nothing && return NaN
    return sol.info.residual
end

_ok(st) = st in (MOI.LOCALLY_SOLVED, MOI.ALMOST_LOCALLY_SOLVED, MOI.OPTIMAL)

function _good(stt, res, gap)
    stt == MOI.LOCALLY_SOLVED && return true
    return isfinite(res) && res <= 1e-4 && gap <= 1e-4
end

function _gdp_gap(st)
    gap = 0.0
    for r in st.R
        tg = _level(st.gdp0[r])
        rg = _level(st.RGDP[r])
        (isfinite(tg) && isfinite(rg) && tg != 0) || return Inf
        gap = max(gap, abs(rg / tg - 1))
    end
    return gap
end

function _bau_path()
    return normpath(joinpath(@__DIR__, "..", "data", "bau.jld2"))
end

function _save_bau(rows, ftotco2_ts)
    bau = Dict{Tuple{Symbol,Int},Dict{Symbol,Float64}}()
    for row in rows
        slot = get!(bau, (:gprod, row.year), Dict{Symbol,Float64}())
        slot[row.region] = row.gprod
    end
    for ((year, r), v) in ftotco2_ts
        slot = get!(bau, (:ftotco20, year), Dict{Symbol,Float64}())
        slot[r] = v
    end
    mkpath(dirname(_bau_path()))
    JLD2.save(_bau_path(), "bau", bau)
    println("wrote ", _bau_path())
    flush(stdout)
    return bau
end

function _load_bau()
    path = _bau_path()
    isfile(path) || error("missing ", path, "; run active/refcalib.jl (simu = 0) first")
    return JLD2.load(path, "bau")
end

function _refcalib_book()
    return normpath(joinpath(@__DIR__, "..", "results", "refcalib.xlsx"))
end

"""
    _ftotco20_from_refcalib()

Read reference `FTOTCO2` by region and year from `results/refcalib.xlsx`.
Uses the `FTOTCO2` sheet when it is present, otherwise the sum of `SCO2`.
"""
function _ftotco20_from_refcalib()
    path = _refcalib_book()
    isfile(path) || return Dict{Int,Dict{Symbol,Float64}}()
    xf = XLSX.readxlsx(path)
    names = XLSX.sheetnames(xf)
    out = Dict{Int,Dict{Symbol,Float64}}()
    if "FTOTCO2" in names
        data = xf["FTOTCO2"][:]
        for i in 2:size(data, 1)
            year, region, val = data[i, 1], data[i, 2], data[i, 3]
            (year === nothing || region === nothing || val === nothing) && continue
            slot = get!(out, Int(year), Dict{Symbol,Float64}())
            slot[Symbol(region)] = Float64(val)
        end
        return out
    end
    "SCO2" in names || return out
    data = xf["SCO2"][:]
    for i in 2:size(data, 1)
        year, region, val = data[i, 1], data[i, 4], data[i, 5]
        (year === nothing || region === nothing || val === nothing) && continue
        y = Int(year)
        slot = get!(out, y, Dict{Symbol,Float64}())
        slot[Symbol(region)] = get(slot, Symbol(region), 0.0) + Float64(val)
    end
    return out
end

"""
    _ensure_ftotco20!(bau)

Make sure `bau` contains `(:ftotco20, year)`. An older `bau.jld2` has only
`gprod`. In that case the series is taken from `results/refcalib.xlsx` and
written back into `bau.jld2`.
"""
function _ensure_ftotco20!(bau)
    any(k -> k[1] == :ftotco20, keys(bau)) && return bau
    series = _ftotco20_from_refcalib()
    isempty(series) && error("bau.jld2 has no ftotco20, and results/refcalib.xlsx has no FTOTCO2 or SCO2 sheet. Run active/refcalib.jl first.")
    for (year, col) in series
        bau[(:ftotco20, year)] = col
    end
    JLD2.save(_bau_path(), "bau", bau)
    println("added ftotco20 to ", _bau_path(), " from ", _refcalib_book())
    flush(stdout)
    return bau
end

function _install_gprod!(st, bau, year)
    col = bau[(:gprod, year)]
    for r in st.R
        gp = col[r]
        set_value!(st.gp0[r], gp)
        JuMP.set_start_value(get_variable(st.GPROD[r]), gp)
    end
    return nothing
end

function _savepoint_dir(scenario)
    d = normpath(joinpath(@__DIR__, "..", "savepoint", scenario))
    mkpath(d)
    return d
end

function _point_levels(MGE)
    jm = jump_model(MGE)
    out = Dict{String,Float64}()
    for v in all_variables(jm)
        JuMP.is_fixed(v) && continue
        x = try
            value(v)
        catch
            continue
        end
        isfinite(x) || continue
        out[JuMP.name(v)] = x
    end
    return out
end

function _save_point!(MGE, dir, year)
    isempty(dir) && return nothing
    path = joinpath(dir, string(year) * ".jld2")
    JLD2.save(path, "levels", _point_levels(MGE))
    println("savepoint ", path)
    flush(stdout)
    return path
end

function _load_point!(MGE, dir, year)
    isempty(dir) && return false
    path = joinpath(dir, string(year) * ".jld2")
    isfile(path) || return false
    levels = JLD2.load(path, "levels")
    jm = jump_model(MGE)
    n = 0
    for v in all_variables(jm)
        JuMP.is_fixed(v) && continue
        x = get(levels, JuMP.name(v), nothing)
        x === nothing && continue
        set_start_value(v, x)
        n += 1
    end
    println("loaded savepoint ", path, " (", n, " variables)")
    flush(stdout)
    return n > 0
end

function record_eesec!(store, MGE, year; energies = ENERGY, users = EJUSE_SECTORS, regions = REGIONS)
    for r in regions, g in users, e in energies
        store[(year, e, g, r)] = _level(MGE[:EESEC][e, g, r])
    end
    return store
end

function record_sco2!(store, MGE, year; energies = SCO2_ENERGY, users = SCO2_SECTORS, regions = REGIONS)
    for r in regions, g in users, e in energies
        store[(year, e, g, r)] = _level(MGE[:SCO2][e, g, r])
    end
    return store
end

function record_ftotco2!(store, MGE, year; regions = REGIONS)
    for r in regions
        store[(year, r)] = _level(MGE[:FTOTCO2][r])
    end
    return store
end

function record_co2p!(store, MGE, st, year; regions = REGIONS)
    for r in regions
        store[(year, r)] = _level(MGE[:CP][r]) / st.cscale[r] * 1e4
    end
    return store
end

function record_aeei!(store, st, year; sectors = SECTORS, regions = REGIONS)
    for r in regions, i in sectors
        store[(year, i, r)] = _level(st.aeei[i, r])
    end
    return store
end

function run_scenario(data; simu, iter0 = true, stop = YEARS[end], csv = "", scenario = "", policy = :ref, rer = (r, t) -> 1.0)
    simu = Int(simu)
    simu in (0, 1) || throw(ArgumentError("simu must be 0 or 1, got $simu"))
    policy == :cpq && simu != 1 && throw(ArgumentError("cpq uses the calibrated productivity, so simu must be 1"))
    bau = simu == 1 ? _load_bau() : nothing
    policy == :cpq && _ensure_ftotco20!(bau)
    spdir = isempty(scenario) ? "" : _savepoint_dir(scenario)
    println(simu == 0 ? "\nTFP calibration (simu = 0)" : policy == :cpq ? "\ncarbon cap, GPROD from bau.jld2 (cpq)" : "\nendogenous GDP, GPROD from bau.jld2 (simu = 1)")
    isempty(spdir) || println("savepoint ", spdir)
    flush(stdout)
    MGE, st = build_model(data; simu)
    st = (; st..., policy, rer, bau)
    MGE.silent = false
    JuMP.unset_silent(jump_model(MGE))
    rows = NamedTuple[]
    eesec_ts = Dict{Tuple{Int,Symbol,Symbol,Symbol},Float64}()
    sco2_ts = Dict{Tuple{Int,Symbol,Symbol,Symbol},Float64}()
    ftotco2_ts = Dict{Tuple{Int,Symbol},Float64}()
    co2p_ts = Dict{Tuple{Int,Symbol},Float64}()
    aeei_ts = Dict{Tuple{Int,Symbol,Symbol},Float64}()
    if !isempty(csv)
        open(csv, "w") do io
            println(io, "year,region,gprod,rgdp,target,status")
        end
    end
    years = [y for y in YEARS if y <= stop]
    simu == 1 && _install_gprod!(st, bau, years[1])
    _set_co2cap!(st, years[1])
    _load_point!(MGE, spdir, years[1])
    if iter0
        println("\n================ ", years[1], " (benchmark) ================")
        flush(stdout)
        stt = _solve!(MGE; iters = 200, tol = 1e-5, proximal = 0.0, restarts = 2)
        println("benchmark ", stt, " res ", _residual(MGE), " gap ", _gdp_gap(st))
        flush(stdout)
        _warm!(MGE)
    end
    finished = false
    for (k, year) in enumerate(years)
        if simu == 1 && !(iter0 && k == 1)
            _install_gprod!(st, bau, year)
        end
        _set_aeei!(st, data, year)
        _set_co2cap!(st, year)
        if iter0 && k == 1
            stt = termination_status(jump_model(MGE))
        elseif k == 1
            println("\n================ ", year, " ================")
            flush(stdout)
            _load_point!(MGE, spdir, year)
            stt = _solve!(MGE)
            _warm!(MGE)
        else
            println("\n================ ", year, " ================")
            flush(stdout)
            _load_point!(MGE, spdir, year)
            stt = _advance_and_solve!(MGE, st, data, years[k - 1], year)
        end
        gap = _gdp_gap(st)
        res = _residual(MGE)
        if simu == 0 && !_ok(stt) && gap <= 1e-4 && isfinite(res) && res <= 1e-3
            stt = MOI.ALMOST_LOCALLY_SOLVED
        end
        println(year, " ", stt, " res ", res, " gap ", gap)
        flush(stdout)
        chunk = NamedTuple[]
        for r in st.R
            row = (
                year = year,
                region = r,
                gprod = _level(st.GPROD[r]),
                rgdp = _level(st.RGDP[r]),
                target = _level(st.gdp0[r]),
                status = string(stt),
            )
            push!(rows, row)
            push!(chunk, row)
        end
        if !isempty(csv)
            open(csv, "a") do io
                for row in chunk
                    println(io, row.year, ",", row.region, ",", row.gprod, ",", row.rgdp, ",", row.target, ",", row.status)
                end
            end
        end
        passed = if simu == 0
            _ok(stt) || (isfinite(res) && res <= 1.0 && gap <= 1e-4)
        else
            _ok(stt) || (isfinite(res) && res <= 1e-4)
        end
        if !passed
            println(simu == 0 ? "stop: GDP target not met in " : "stop: period did not solve in ", year)
            break
        end
        record_eesec!(eesec_ts, MGE, year)
        record_sco2!(sco2_ts, MGE, year)
        record_ftotco2!(ftotco2_ts, MGE, year)
        record_co2p!(co2p_ts, MGE, st, year)
        record_aeei!(aeei_ts, st, year)
        _save_point!(MGE, spdir, year)
        finished = year == years[end]
    end
    if simu == 0 && finished
        _save_bau(rows, ftotco2_ts)
    end
    return MGE, st, rows, eesec_ts, sco2_ts, ftotco2_ts, aeei_ts, co2p_ts
end

end
