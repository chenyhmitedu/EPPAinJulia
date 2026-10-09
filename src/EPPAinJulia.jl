module EPPAinJulia

using JuMP
using MPSGE
using PATHSolver

export load_benchmark, prepare, build_model, calibrate

const PATH_LICENSE = "1259252040&Courtesy&&&USR&GEN2035&5_1_2026&1000&PATH&GEN&31_12_2035&0_0_0&6000&0_0"
const MOI = JuMP.MOI

include("load.jl")
include("calib.jl")
include("smooth.jl")
include("model.jl")

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

function _warm!(M)
    jm = jump_model(M)
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

function _snap(M)
    jm = jump_model(M)
    out = Dict{String,Float64}()
    for v in all_variables(jm)
        s = start_value(v)
        s === nothing && continue
        out[JuMP.name(v)] = s
    end
    return out
end

function _restore!(M, snap)
    jm = jump_model(M)
    for v in all_variables(jm)
        s = get(snap, JuMP.name(v), nothing)
        s === nothing && continue
        set_start_value(v, s)
    end
    return nothing
end

function _solve!(M; tol = 1e-5, iters = 20_000, proximal = 0.0, restarts = 3)
    jm = jump_model(M)
    if !haskey(JuMP.object_dictionary(jm), :z_p)
        was = M.silent
        M.silent = true
        solve!(M; cumulative_iteration_limit = 0, output = "no")
        M.silent = was
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

function _residual(M)
    jm = jump_model(M)
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

function _targets(M, st, data, year, next)
    ord = findfirst(==(year), YEARS)
    out = Dict{Symbol,NamedTuple}()
    for r in st.R
        inv_level = max(_level(M[:INV][r]), 0.0)
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

function _scale_start!(M, st, old)
    jm = jump_model(M)
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
        set_start_value(st.gprod[r], max(g0 * grow / lrat, 1e-6))
        set_start_value(st.rgdp[r], o.Gn)
    end
    return nothing
end

function _prices_to_one!(M)
    jm = jump_model(M)
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

function _advance_and_solve!(M, st, data, year, next)
    old = _targets(M, st, data, year, next)
    base = _snap(M)
    _plant!(st, old, 1.0)
    stt = _solve!(M; proximal = 1e-4, restarts = 3, iters = 30_000)
    res = _residual(M)
    gap = _gdp_gap(st)
    if !_usable(stt, res, gap)
        println("  warm ", stt, " res ", res, " gap ", gap)
        flush(stdout)
        _restore!(M, base)
        _scale_start!(M, st, old)
        stt = _solve!(M; proximal = 1e-4, restarts = 2, iters = 20_000)
        res = _residual(M)
        gap = _gdp_gap(st)
        println("  scaled ", stt, " res ", res, " gap ", gap)
        flush(stdout)
    end
    if _usable(stt, res, gap)
        _warm!(M)
        return _ok(stt) ? stt : MOI.ALMOST_LOCALLY_SOLVED
    end
    if isfinite(gap) && gap <= 1e-4 && isfinite(res) && res <= 5
        println("  polish ", res)
        flush(stdout)
        _warm!(M)
        stt2 = _solve!(M; proximal = 1e-4, restarts = 0, tol = 1e-4, iters = 8_000)
        res2 = _residual(M)
        gap2 = _gdp_gap(st)
        println("  polished ", stt2, " res ", res2, " gap ", gap2)
        flush(stdout)
        if isfinite(res2) && res2 <= max(res, 1.0) && gap2 <= 1e-4
            _warm!(M)
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
        _restore!(M, origin)
        failed = false
        stt_last = MOI.OPTIMIZE_NOT_CALLED
        for s in 1:nstep
            _plant!(st, old, s / nstep)
            stt_last = _solve!(M; proximal = 1e-4, tol = 1e-4, restarts = 2, iters = 12_000)
            res = _residual(M)
            gap = _gdp_gap(st)
            if !(_usable(stt_last, res, gap) || (gap <= 5e-3 && isfinite(res) && res < 2))
                println("    step ", s, " ", stt_last, " res ", res, " gap ", gap)
                flush(stdout)
                failed = true
                break
            end
            _warm!(M)
        end
        if !failed
            _plant!(st, old, 1.0)
            return _ok(stt_last) ? stt_last : MOI.ALMOST_LOCALLY_SOLVED
        end
    end
    _restore!(M, origin)
    _plant!(st, old, 1.0)
    return stt_last
end


function calibrate(data; iter0 = true, stop = 2100, csv = "")
    M, st = build_model(data)
    M.silent = false
    JuMP.unset_silent(jump_model(M))
    rows = NamedTuple[]
    if !isempty(csv)
        open(csv, "w") do io
            println(io, "year,region,gprod,rgdp,target,status")
        end
    end
    years = [y for y in YEARS if y <= stop]
    if iter0
        println("\n================ ", years[1], " (benchmark) ================")
        flush(stdout)
        stt = _solve!(M; iters = 200, tol = 1e-5, proximal = 0.0, restarts = 2)
        println("benchmark ", stt, " res ", _residual(M), " gap ", _gdp_gap(st))
        flush(stdout)
        _warm!(M)
    end
    for (k, year) in enumerate(years)
        if iter0 && k == 1
            stt = termination_status(jump_model(M))
        elseif k == 1
            println("\n================ ", year, " ================")
            flush(stdout)
            stt = _solve!(M)
            _warm!(M)
        else
            println("\n================ ", year, " ================")
            flush(stdout)
            stt = _advance_and_solve!(M, st, data, years[k - 1], year)
        end
        gap = _gdp_gap(st)
        res = _residual(M)
        if !_ok(stt) && gap <= 1e-4 && isfinite(res) && res <= 1e-3
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
        if !(_ok(stt) || (isfinite(res) && res <= 1.0 && gap <= 1e-4))
            println("stop: GDP target not met in ", year)
            break
        end
    end
    return M, st, rows
end

end
