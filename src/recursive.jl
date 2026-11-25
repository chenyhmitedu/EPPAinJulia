import PATHSolver

function save_point(m, path)

    jm = jump_model(m)
    levels = Dict{String,Float64}()

    for v in all_variables(jm)
        n = JuMP.name(v)
        isempty(n) && continue
        x = try
            JuMP.value(v)
        catch
            continue
        end
        isfinite(x) || continue
        levels[n] = x
    end

    JLD2.jldsave(path; levels)
    return path

end

function load_point!(m, path)

    levels = JLD2.load(path, "levels")
    jm = jump_model(m)

    for v in all_variables(jm)
        n = JuMP.name(v)
        haskey(levels, n) || continue
        JuMP.set_start_value(v, levels[n])
    end

    MPSGE.update_internal_start_values!(m)
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

# GDP target and the labor ratio used to scale the GPROD start.
# Capital, government, and the trade balance are not advanced: AI_01's demand
# block keeps those endowments at the benchmark constants, and this core would
# change the MCP if k0, l0, grg, or bop moved.

function solve_mcp!(MGE; tol = 1e-5, iters = 20_000, proximal = 0.0, restarts = 3)
    jm = jump_model(MGE)
    if !haskey(JuMP.object_dictionary(jm), :z_p)
        was = MGE.silent
        MGE.silent = true
        MPSGE.solve!(MGE; cumulative_iteration_limit = 0, output = "no")
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
    res = sol === nothing ? NaN : sol.info.residual
    return termination_status(jm), res
end

function advance!(MGE, B, year, next, simu)

    years = B.year
    regular = length(years) >= 3 ? years[3] - years[2] : years[2] - years[1]
    span(y) = (j = findfirst(==(y), years); j < length(years) ? years[j + 1] - years[j] : regular)
    out = Dict{Symbol,NamedTuple}()
    for r in REGIONS
        pop0 = B.popa_eppa[(year, r)]
        pr = pop0 == 0 ? 1.0 : B.popa_eppa[(next, r)] / pop0
        grow(y) = (1 + B.argdpgrrate[(y, r)])^span(y)
        L = _level(MGE[:l0][r])
        G = _level(MGE[:gdp0][r])
        out[r] = (
            L = L,
            G = G,
            Ln = max(L * pr, 1e-8),
            Gn = G * grow(year),
        )
    end

    jm = jump_model(MGE)
    base = Dict{String,Float64}()
    for v in all_variables(jm)
        s = start_value(v)
        s === nothing && continue
        base[JuMP.name(v)] = s
    end
    copy_starts!(store) = begin
        for v in all_variables(jm)
            s = get(store, JuMP.name(v), nothing)
            s === nothing && continue
            set_start_value(v, s)
        end
    end
    warm!() = begin
        for v in all_variables(jm)
            x = try
                value(v)
            catch
                continue
            end
            isfinite(x) || continue
            set_start_value(v, x)
        end
    end
    gdp_gap() = begin
        g = 0.0
        for r in REGIONS
            tg = _level(MGE[:gdp0][r])
            rg = _level(MGE[:RGDP][r])
            (isfinite(tg) && isfinite(rg) && tg != 0) || return Inf
            g = max(g, abs(rg / tg - 1))
        end
        return g
    end
    usable(stt, res, g) = stt == JuMP.MOI.LOCALLY_SOLVED || (isfinite(res) && res <= 1e-4 && g <= 1e-4) || (isfinite(res) && isfinite(g) && g <= 1e-5 && res <= 1.0)
    prox = simu == 1 && isdefined(Main, :policy) && Main.policy == :cpq ? 0.0 : 1e-4

    for r in REGIONS
        set_value!(MGE[:gdp0][r], out[r].Gn)
    end

    stt, res = solve_mcp!(MGE; proximal = prox, restarts = 3, iters = 30_000)
    g = gdp_gap()
    if !usable(stt, res, g)
        println("  warm ", stt, " res ", res, " gap ", g)
        flush(stdout)
        copy_starts!(base)
        stt, res = solve_mcp!(MGE; proximal = prox, restarts = 2, iters = 20_000)
        g = gdp_gap()
        println("  scaled ", stt, " res ", res, " gap ", g)
        flush(stdout)
    end
    if usable(stt, res, g)
        warm!()
        return stt, res
    end
    origin = Dict{String,Float64}()
    for v in all_variables(jm)
        s = start_value(v)
        s === nothing && continue
        origin[JuMP.name(v)] = s
    end
    stt_last, res_last = stt, res
    for w in (0.8, 0.6, 0.4, 0.2)
        println("  damp ", w)
        flush(stdout)
        copy_starts!(base)
        
        for r in REGIONS
            set_value!(MGE[:gdp0][r], out[r].Gn)
        end

        for v in all_variables(jm)
            JuMP.is_fixed(v) && continue
            n = JuMP.name(v)
            (startswith(n, "P") || startswith(n, "RA")) && set_start_value(v, 1.0)
        end
        stt_last, res_last = solve_mcp!(MGE; proximal = prox, restarts = 1, iters = 10_000)
        failed = false
        for a in range(w + 0.2, 1.0; step = 0.2)
            g = gdp_gap()
            println("    anchor ", a, " ", stt_last, " res ", res_last, " gap ", g)
            flush(stdout)
            if !usable(stt_last, res_last, g)
                failed = true
                break
            end
            copy_starts!(origin)
            
            for r in REGIONS
                set_value!(MGE[:gdp0][r], out[r].Gn)
            end

            stt_last, res_last = solve_mcp!(MGE; proximal = prox, restarts = 1, iters = 10_000)
            g = gdp_gap()
            if !usable(stt_last, res_last, g)
                println("    fail ", a, " ", stt_last, " res ", res_last, " gap ", g)
                flush(stdout)
                failed = true
                break
            end
            warm!()
        end
        if !failed
            
            for r in REGIONS
                set_value!(MGE[:gdp0][r], out[r].Gn)
            end

            stt_last = stt_last in (JuMP.MOI.LOCALLY_SOLVED, JuMP.MOI.ALMOST_LOCALLY_SOLVED, JuMP.MOI.OPTIMAL) ? stt_last : JuMP.MOI.ALMOST_LOCALLY_SOLVED
            return stt_last, res_last
        end
    end
    copy_starts!(origin)
    
    for r in REGIONS
        set_value!(MGE[:gdp0][r], out[r].Gn)
    end

    return stt_last, res_last
end

function Recursive(B::NamedTuple, setting::Int64)

    simu = isdefined(Main, :simu) ? Int(Main.simu) : Int(setting)
    policy = isdefined(Main, :policy) ? Main.policy : :ref
    rer = isdefined(Main, :rer) ? Main.rer : (r, t) -> 1.0
    years = B.year
    bau_path = normpath(joinpath(@__DIR__, "..", "data", "bau.jld2"))
    bau = nothing
    if simu == 1
        isfile(bau_path) || error("missing ", bau_path, "; run active/refcalib.jl (simu = 0) first")
        bau = JLD2.load(bau_path, "bau")
        if policy == :cpq && !any(k -> k[1] == :ftotco20, keys(bau))
            error("bau.jld2 has no ftotco20; run active/refcalib.jl first")
        end
    end
    casename = isdefined(Main, :filename) ? splitext(basename(Main.filename))[1] : "refcalib"
    spdir = joinpath(@__DIR__, "..", "savepoint", casename)
    mkpath(spdir)

    println(simu == 0 ? "\nTFP calibration (simu = 0)" : policy == :cpq ? "\ncarbon cap, GPROD from bau.jld2 (cpq)" : "\nendogenous GDP, GPROD from bau.jld2 (simu = 1)")
    println("savepoint ", spdir)
    flush(stdout)

    MGE = Build(B, simu)
    MGE.silent = false
    JuMP.unset_silent(jump_model(MGE))

    rows = NamedTuple[]
    ftot = Dict{Tuple{Int,Symbol},Float64}()
    if simu == 1
        col = bau[(:gprod, years[1])]
        for r in REGIONS
            set_value!(MGE[:gprod0][r], col[r])
            JuMP.set_start_value(get_variable(MGE[:GPROD][r]), col[r])
        end
    end
    for r in REGIONS
        cap = policy == :cpq ? bau[(:ftotco20, years[1])][r] * float(rer(Symbol(lowercase(string(r))), years[1])) : 1.0e6 * B.ftotco20[r]
        set_value!(MGE[:co2cap][r], cap)
    end
    p0 = joinpath(spdir, string(years[1]) * ".jld2")
    isfile(p0) && load_point!(MGE, p0)
    println("\n================ ", years[1], " (benchmark) ================")
    flush(stdout)
    stt, res = solve_mcp!(MGE; iters = 200, tol = 1e-5, proximal = 0.0, restarts = 2)
    println("benchmark ", stt, " res ", res)
    flush(stdout)
    for v in all_variables(jump_model(MGE))
        x = try
            value(v)
        catch
            continue
        end
        isfinite(x) || continue
        set_start_value(v, x)
    end

    solved_ok(st) = st in (JuMP.MOI.LOCALLY_SOLVED, JuMP.MOI.ALMOST_LOCALLY_SOLVED, JuMP.MOI.OPTIMAL)
    finished = false
    for (k, year) in enumerate(years)
        if simu == 1 && k != 1
            col = bau[(:gprod, year)]
            for r in REGIONS
                set_value!(MGE[:gprod0][r], col[r])
                JuMP.set_start_value(get_variable(MGE[:GPROD][r]), col[r])
            end
        end
        for r in REGIONS, i in SECTORS
            gr = get(B.aeeigr, (i, r), 0.0)
            set_value!(MGE[:aeei][i, r], (1 + gr)^(-max(year - years[1], 0)))
        end
        for r in REGIONS
            cap = if policy == :cpq
                col = get(bau, (:ftotco20, year), nothing)
                col === nothing && error("bau.jld2 has no ftotco20 for $year; run active/refcalib.jl first")
                col[r] * float(rer(Symbol(lowercase(string(r))), year))
            else
                1.0e6 * B.ftotco20[r]
            end
            set_value!(MGE[:co2cap][r], cap)
        end
        if k != 1
            println("\n================ ", year, " ================")
            flush(stdout)
            pt = joinpath(spdir, string(year) * ".jld2")
            isfile(pt) && load_point!(MGE, pt)
            stt, res = advance!(MGE, B, years[k - 1], year, simu)
        end
        gap = 0.0
        for r in REGIONS
            tg = _level(MGE[:gdp0][r])
            rg = _level(MGE[:RGDP][r])
            if !(isfinite(tg) && isfinite(rg) && tg != 0)
                gap = Inf
                break
            end
            gap = max(gap, abs(rg / tg - 1))
        end
        if simu == 0 && !solved_ok(stt) && gap <= 1e-4 && isfinite(res) && res <= 1e-3
            stt = JuMP.MOI.ALMOST_LOCALLY_SOLVED
        end
        println(year, " ", stt, " res ", res, " gap ", gap)
        flush(stdout)
        for r in REGIONS
            push!(rows, (
                year = year,
                region = r,
                gprod = _level(MGE[:GPROD][r]),
                rgdp = _level(MGE[:RGDP][r]),
                target = _level(MGE[:gdp0][r]),
                status = string(stt),
            ))
            ftot[(year, r)] = _level(MGE[:FTOTCO2][r])
        end
        passed = simu == 0 ? (solved_ok(stt) || (isfinite(res) && res <= 1.0 && gap <= 1e-4)) : (solved_ok(stt) || (isfinite(res) && res <= 1e-4))
        if !passed
            println(simu == 0 ? "stop: GDP target not met in " : "stop: period did not solve in ", year)
            break
        end
        sp = joinpath(spdir, string(year) * ".jld2")
        save_point(MGE, sp)
        println("savepoint ", sp)
        flush(stdout)
        finished = year == years[end]
    end
    if simu == 0 && finished
        saved = Dict{Tuple{Symbol,Int},Dict{Symbol,Float64}}()
        for row in rows
            slot = get!(saved, (:gprod, row.year), Dict{Symbol,Float64}())
            slot[row.region] = row.gprod
        end
        for ((year, r), v) in ftot
            slot = get!(saved, (:ftotco20, year), Dict{Symbol,Float64}())
            slot[r] = v
        end
        mkpath(dirname(bau_path))
        JLD2.save(bau_path, "bau", saved)
        println("wrote ", bau_path)
        flush(stdout)
    end
    return MGE, rows
end
