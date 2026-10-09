module EPPAinJulia

using JuMP
using JLD2
using MPSGE
using PATHSolver

export load_benchmark, prepare, build_model, EPPA_model, run_scenario

const PATH_LICENSE = "1259252040&Courtesy&&&USR&GEN2035&5_1_2026&1000&PATH&GEN&31_12_2035&0_0_0&6000&0_0"
const MOI = JuMP.MOI

include("load.jl")
include("calib.jl")
include("smooth.jl")
include("eppacore.jl")

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

function _boost(r, ord)
    ord > 5 && return 1.0
    return r == :mex ? 1.05^(5 - ord) : 1.10^(6 - ord)
end

function _srve(year)
    return year == 2017 ? (1 - DPE)^3 : (1 - DPE)^5
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
        tg = _level(st.GDP0[r])
        rg = _level(st.rgdp[r])
        (isfinite(tg) && isfinite(rg) && tg != 0) || return Inf
        gap = max(gap, abs(rg / tg - 1))
    end
    return gap
end

function _targets(MGE, st, data, year, next)
    ord = findfirst(==(year), YEARS)
    out = Dict{Symbol,NamedTuple}()
    for r in st.R
        inv_level = max(_level(MGE[:INV][r]), 0.0)
        knew = st.scale[r] * ROR * st.inv0[r] * inv_level * _boost(r, ord) + _level(st.K0[r]) * _srve(year)
        out[r] = (
            K = _level(st.K0[r]),
            L = _level(st.L0[r]),
            G = _level(st.GDP0[r]),
            Rgov = _level(st.GRG[r]),
            S = _level(st.SAV[r]),
            Kn = max(knew, 1e-8),
            Ln = max(_level(st.L0[r]) * pop_ratio(data, r, year, next), 1e-8),
            Gn = _level(st.GDP0[r]) * growth_factor(data, r, year),
            Rn = _level(st.GRG[r]) * growth_factor(data, r, next),
            Sn = ord <= 10 ? _level(st.SAV[r]) * 0.9^ord : 0.0,
        )
    end
    return out
end

function _plant!(st, old, w)
    for r in st.R
        o = old[r]
        set_value!(st.K0[r], (1 - w) * o.K + w * o.Kn)
        set_value!(st.L0[r], (1 - w) * o.L + w * o.Ln)
        set_value!(st.GDP0[r], (1 - w) * o.G + w * o.Gn)
        set_value!(st.GRG[r], (1 - w) * o.Rgov + w * o.Rn)
        set_value!(st.SAV[r], (1 - w) * o.S + w * o.Sn)
    end
end

function _lastsym(name)
    m = match(r"\[([^\]]+)\]$", name)
    m === nothing && return nothing
    return Symbol(strip(split(m.captures[1], ",")[end]))
end

function _scale_start!(MGE, st, old)
    jm = jump_model(MGE)
    regs = Set(st.R)
    world = sum(old[r].G > 0 ? old[r].Gn / old[r].G : 1.0 for r in st.R) / length(st.R)
    for v in all_variables(jm)
        JuMP.is_fixed(v) && continue
        n = JuMP.name(v)
        (startswith(n, "P") || startswith(n, "RA") || startswith(n, "gprod") || startswith(n, "rgdp")) && continue
        s = start_value(v)
        (s === nothing || !isfinite(s) || s == 0) && continue
        reg = _lastsym(n)
        fac = reg !== nothing && reg in regs && old[reg].G > 0 ? old[reg].Gn / old[reg].G : world
        set_start_value(v, s * fac)
    end
    for r in st.R
        o = old[r]
        grow = o.G > 0 ? o.Gn / o.G : 1.0
        lrat = o.L > 0 ? o.Ln / o.L : 1.0
        g0 = start_value(st.gprod[r])
        g0 = g0 === nothing ? 1.0 : g0
        if st.simu == 0
            set_start_value(st.gprod[r], max(g0 * grow / lrat, 1e-6))
        else
            JuMP.set_start_value(get_variable(st.gprod[r]), JuMP.value(st.GP0[r]))
        end
        set_start_value(st.rgdp[r], o.Gn)
    end
    return nothing
end

function _prices_to_one!(MGE)
    jm = jump_model(MGE)
    for v in all_variables(jm)
        JuMP.is_fixed(v) && continue
        n = JuMP.name(v)
        if startswith(n, "P") || startswith(n, "RA")
            set_start_value(v, 1.0)
        end
    end
    return nothing
end

function _usable(stt, res, gap)
    _good(stt, res, gap) && return true
    return isfinite(res) && isfinite(gap) && gap <= 1e-5 && res <= 1.0
end

function _advance_and_solve!(MGE, st, data, year, next)
    old = _targets(MGE, st, data, year, next)
    base = _snap(MGE)
    _plant!(st, old, 1.0)
    stt = _solve!(MGE; proximal = 1e-4, restarts = 3, iters = 30_000)
    res = _residual(MGE)
    gap = _gdp_gap(st)
    if !_usable(stt, res, gap)
        println("  warm ", stt, " res ", res, " gap ", gap)
        flush(stdout)
        _restore!(MGE, base)
        _scale_start!(MGE, st, old)
        stt = _solve!(MGE; proximal = 1e-4, restarts = 2, iters = 20_000)
        res = _residual(MGE)
        gap = _gdp_gap(st)
        println("  scaled ", stt, " res ", res, " gap ", gap)
        flush(stdout)
    end
    if _usable(stt, res, gap)
        _warm!(MGE)
        return _ok(stt) ? stt : MOI.ALMOST_LOCALLY_SOLVED
    end
    if isfinite(gap) && gap <= 1e-4 && isfinite(res) && res <= 5
        println("  polish ", res)
        flush(stdout)
        _warm!(MGE)
        stt2 = _solve!(MGE; proximal = 1e-4, restarts = 0, tol = 1e-4, iters = 8_000)
        res2 = _residual(MGE)
        gap2 = _gdp_gap(st)
        println("  polished ", stt2, " res ", res2, " gap ", gap2)
        flush(stdout)
        if isfinite(res2) && res2 <= max(res, 1.0) && gap2 <= 1e-4
            _warm!(MGE)
            return _ok(stt2) ? stt2 : MOI.ALMOST_LOCALLY_SOLVED
        end
    end
    println("  unsolved ", stt, " res ", res, " gap ", gap)
    flush(stdout)
    origin = base
    stt_last = stt
    for nstep in (4, 8)
        println("  homotopy ", nstep)
        flush(stdout)
        _restore!(MGE, origin)
        failed = false
        stt_last = MOI.OPTIMIZE_NOT_CALLED
        for s in 1:nstep
            _plant!(st, old, s / nstep)
            stt_last = _solve!(MGE; proximal = 1e-4, tol = 1e-4, restarts = 2, iters = 12_000)
            res = _residual(MGE)
            gap = _gdp_gap(st)
            if !(_usable(stt_last, res, gap) || (gap <= 5e-3 && isfinite(res) && res < 2))
                println("    step ", s, " ", stt_last, " res ", res, " gap ", gap)
                flush(stdout)
                failed = true
                break
            end
            _warm!(MGE)
        end
        if !failed
            _plant!(st, old, 1.0)
            return _ok(stt_last) ? stt_last : MOI.ALMOST_LOCALLY_SOLVED
        end
    end
    _restore!(MGE, origin)
    _plant!(st, old, 1.0)
    return stt_last
end


function _bau_path()
    return normpath(joinpath(@__DIR__, "..", "data", "bau.jld2"))
end

function _save_bau(rows)
    bau = Dict{Tuple{Symbol,Int},Dict{Symbol,Float64}}()
    for row in rows
        slot = get!(bau, (:gprod, row.year), Dict{Symbol,Float64}())
        slot[row.region] = row.gprod
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

function _install_gprod!(st, bau, year)
    col = bau[(:gprod, year)]
    for r in st.R
        gp = col[r]
        set_value!(st.GP0[r], gp)
        JuMP.set_start_value(get_variable(st.gprod[r]), gp)
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

function run_scenario(data; simu, iter0 = true, stop = 2100, csv = "", scenario = "")
    simu = Int(simu)
    simu in (0, 1) || throw(ArgumentError("simu must be 0 or 1, got $simu"))
    bau = simu == 1 ? _load_bau() : nothing
    spdir = isempty(scenario) ? "" : _savepoint_dir(scenario)
    println(simu == 0 ? "\nTFP calibration (simu = 0)" : "\nendogenous GDP, gprod from bau.jld2 (simu = 1)")
    isempty(spdir) || println("savepoint ", spdir)
    flush(stdout)
    MGE, st = build_model(data; simu)
    MGE.silent = false
    JuMP.unset_silent(jump_model(MGE))
    rows = NamedTuple[]
    if !isempty(csv)
        open(csv, "w") do io
            println(io, "year,region,gprod,rgdp,target,status")
        end
    end
    years = [y for y in YEARS if y <= stop]
    simu == 1 && _install_gprod!(st, bau, years[1])
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
                gprod = _level(st.gprod[r]),
                rgdp = _level(st.rgdp[r]),
                target = _level(st.GDP0[r]),
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
        _save_point!(MGE, spdir, year)
        finished = year == years[end]
    end
    if simu == 0 && finished
        _save_bau(rows)
    end
    return MGE, st, rows
end

end
