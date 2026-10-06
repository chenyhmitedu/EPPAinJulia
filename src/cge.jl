# MPSGE CGE for GDP calibration.
# gprod is endogenous and complementary to the GDP target.
# Capital follows EPPA8: ror = 0.10, dpe = 0.05, no vintaging, so
# new capital service = scale * ror * inv0 * INV, with scale from eppaloop.gms.

using JuMP, MPSGE, PATHSolver, JLD2, XLSX

const ES_ARM = 0.0
const ES_VA = 1.0

function load_flows(io_path, sat_path)
    data = load(io_path)
    R = data["set_r"]
    I = data["set_i"]
    final = [:c, :g, :i]
    out = Dict{Tuple{Symbol,Symbol},Float64}()
    ex = Dict{Tuple{Symbol,Symbol},Float64}()
    im = Dict{Tuple{Symbol,Symbol},Float64}()
    fin = Dict{Tuple{Symbol,Symbol},Float64}()
    inv = Dict{Tuple{Symbol,Symbol},Float64}()
    inter = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    fac = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    for r in R, i in I
        ex[(i, r)] = max(sum(data["vxmd"][i, r, s] for s in R), 1e-4)
        im[(i, r)] = max(sum(data["vxmd"][i, s, r] for s in R), 1e-4)
        inv[(i, r)] = max(data["vdfm"][i, :i, r] + data["vifm"][i, :i, r], 1e-4)
        for k in I
            inter[(k, i, r)] = max(data["vdfm"][k, i, r] + data["vifm"][k, i, r], 1e-4)
        end
        for f in (:lab, :cap, :lnd, :fix)
            fac[(f, i, r)] = max(data["vfm"][f, i, r], 1e-4)
        end
        out[(i, r)] = sum(inter[(k, i, r)] for k in I) + sum(fac[(f, i, r)] for f in (:lab, :cap, :lnd, :fix))
    end
    # Domestic sales cannot exceed output. Final Armington demand clears the local market.
    dom = Dict{Tuple{Symbol,Symbol},Float64}()
    for r in R, i in I
        ex[(i, r)] = min(ex[(i, r)], 0.8 * out[(i, r)])
        dom[(i, r)] = out[(i, r)] - ex[(i, r)]
        used = sum(inter[(i, k, r)] for k in I)
        inv[(i, r)] = min(inv[(i, r)], 0.5 * (dom[(i, r)] + im[(i, r)]))
        fin[(i, r)] = max(dom[(i, r)] + im[(i, r)] - used - inv[(i, r)], 1e-4)
    end
    gr = Dict{Tuple{Int,Symbol},Float64}()
    pop = Dict{Tuple{Int,Symbol},Float64}()
    gdf = XLSX.readtable(sat_path, "argdpgrrate")
    pdf = XLSX.readtable(sat_path, "popa_eppa")
    years = Int.(gdf.data[1])
    pyears = Int.(pdf.data[1])
    for (j, name) in enumerate(gdf.column_labels)
        name == :year && continue
        r = Symbol(name)
        r in R || continue
        for (i, t) in enumerate(years)
            gr[(t, r)] = Float64(gdf.data[j][i])
        end
    end
    for (j, name) in enumerate(pdf.column_labels)
        name == :year && continue
        r = Symbol(name)
        r in R || continue
        for (i, t) in enumerate(pyears)
            pop[(t, r)] = Float64(pdf.data[j][i])
        end
    end
    gdp0 = Dict(r => sum(fin[(i, r)] for i in I) for r in R)
    lab0 = Dict(r => sum(fac[(:lab, i, r)] for i in I) for r in R)
    cap0 = Dict(r => sum(fac[(:cap, i, r)] for i in I) for r in R)
    return (; R, I, out, ex, im, dom, fin, inv, inter, fac, gr, pop, gdp0, lab0, cap0)
end

function build_model(F)
    MGE = MPSGEModel()
    R, I = F.R, F.I
    @parameters(MGE, begin
        tfp[r=R], 1.0
        lab[r=R], 1.0
        cap[r=R], 1.0
        tgt[r=R], F.gdp0[r]
        qy[i=I, r=R], F.out[(i, r)]
        qd[i=I, r=R], F.dom[(i, r)]
        qm[i=I, r=R], F.im[(i, r)]
        qe[i=I, r=R], F.ex[(i, r)]
        qi[k=I, i=I, r=R], F.inter[(k, i, r)]
        qf[f=[:lab, :cap, :lnd, :fix], i=I, r=R], F.fac[(f, i, r)]
        qc[i=I, r=R], F.fin[(i, r)]
        qn[i=I, r=R], F.inv[(i, r)]
        qC[r=R], F.gdp0[r]
        qI[r=R], sum(F.inv[(i, r)] for i in I)
        qlab[r=R], F.lab0[r]
        qcap[r=R], F.cap0[r]
        qfx[r=R], sum(F.im[(i, r)] - F.ex[(i, r)] for i in I)
        qgap[r=R], F.gdp0[r] + sum(F.inv[(i, r)] for i in I) - F.lab0[r] - F.cap0[r] - sum(F.fac[(:lnd, i, r)] + F.fac[(:fix, i, r)] for i in I) - sum(F.im[(i, r)] - F.ex[(i, r)] for i in I)
    end)
    @sectors(MGE, begin
        Y[i=I, r=R]
        A[i=I, r=R]
        E[i=I, r=R]
        M[i=I, r=R]
        C[r=R]
        INV[r=R]
    end)
    @commodities(MGE, begin
        PY[i=I, r=R]
        PA[i=I, r=R]
        PM[i=I, r=R]
        PFX[r=R]
        PL[r=R]
        PK[r=R]
        PN[i=I, r=R]
        PX[i=I, r=R]
        PU[r=R]
        PI[r=R]
    end)
    @consumers(MGE, begin
        RA[r=R]
    end)
    @auxiliary(MGE, gprod[r=R], start = 1.0)
    @production(MGE, Y[i=I, r=R], [t = 0, s = 0, va => s = ES_VA], begin
        @output(PY[i, r], qy[i, r], t)
        @input(PA[k=I, r], qi[k, i, r], s)
        @input(PL[r], qf[:lab, i, r], va)
        @input(PK[r], qf[:cap, i, r], va)
        @input(PN[i, r], qf[:lnd, i, r], va)
        @input(PX[i, r], qf[:fix, i, r], va)
    end)
    @production(MGE, A[i=I, r=R], [t = 0, s = ES_ARM], begin
        @output(PA[i, r], qd[i, r] + qm[i, r], t)
        @input(PY[i, r], qd[i, r], s)
        @input(PM[i, r], qm[i, r], s)
    end)
    @production(MGE, M[i=I, r=R], [t = 0, s = 0], begin
        @output(PM[i, r], qm[i, r], t)
        @input(PFX[r], qm[i, r], s)
    end)
    @production(MGE, E[i=I, r=R], [t = 0, s = 0], begin
        @output(PFX[r], qe[i, r], t)
        @input(PY[i, r], qe[i, r], s)
    end)
    @production(MGE, C[r=R], [t = 0, s = 1], begin
        @output(PU[r], qC[r], t)
        @input(PA[i=I, r], qc[i, r], s)
    end)
    @production(MGE, INV[r=R], [t = 0, s = 0], begin
        @output(PI[r], qI[r], t)
        @input(PA[i=I, r], qn[i, r], s)
    end)
    @demand(MGE, RA[r=R], begin
        @final_demand(PU[r], qC[r])
        @endowment(PL[r], qlab[r] * lab[r] * gprod[r])
        @endowment(PK[r], qcap[r] * cap[r] * gprod[r])
        @endowment(PN[i=I, r], qf[:lnd, i, r])
        @endowment(PX[i=I, r], qf[:fix, i, r])
        @endowment(PI[r], -qI[r])
        @endowment(PFX[r], qfx[r])
        @endowment(PU[r], qgap[r])
    end)
    for r in R
        @aux_constraint(MGE, gprod[r], C[r] * qC[r] - tgt[r])
    end
    return MGE
end

function solved(st)
    st in (MOI.LOCALLY_SOLVED, MOI.ALMOST_LOCALLY_SOLVED, MOI.OPTIMAL)
end

function reset_starts!(MGE)
    for v in all_variables(jump_model(MGE))
        set_start_value(v, 1.0)
    end
    return nothing
end

function snapshot_starts(MGE)
    jm = jump_model(MGE)
    out = Dict{String,Float64}()
    for v in all_variables(jm)
        x = try
            value(v)
        catch
            NaN
        end
        isfinite(x) && x > 1e-8 && (out[JuMP.name(v)] = x)
    end
    return out
end

function apply_starts!(MGE, snap)
    jm = jump_model(MGE)
    for v in all_variables(jm)
        n = JuMP.name(v)
        haskey(snap, n) && set_start_value(v, snap[n])
    end
    return nothing
end

function solve_mcp!(MGE; reset::Bool = false)
    if reset
        reset_starts!(MGE)
    end
    solve!(MGE;
        cumulative_iteration_limit = 100_000,
        major_iteration_limit = 200,
        minor_iteration_limit = 10_000,
        convergence_tolerance = 1e-2,
        proximal_perturbation = 1e-4,
        # PATH's second restart sets this to 0 and aborts on Windows
        # with "Nonsingular variable obtained". One restart stays safe.
        restart_limit = 1,
    )
    return termination_status(jump_model(MGE))
end

function real_gdp(MGE, F)
    Dict(r => value(MGE[:C][r]) * F.gdp0[r] for r in F.R)
end

function match_tfp!(MGE, F, target; tol = 1e-2, iters = 20)
    prev_t = Dict(r => value(MGE[:tfp][r]) for r in F.R)
    prev_g = Dict(r => NaN for r in F.R)
    elas = Dict(r => 0.6 for r in F.R)
    st = MOI.OPTIMIZE_NOT_CALLED
    for k in 1:iters
        st = solve_mcp!(MGE; reset = false)
        println("    pass ", k, "  ", st)
        flush(stdout)
        if !solved(st)
            println("    retry from benchmark starts")
            flush(stdout)
            st = solve_mcp!(MGE; reset = true)
            println("    pass ", k, " retry  ", st)
            flush(stdout)
        end
        solved(st) || return st
        gdp = real_gdp(MGE, F)
        gap = maximum(abs(gdp[r] / target[r] - 1) for r in F.R)
        worst = argmax(r -> abs(gdp[r] / target[r] - 1), F.R)
        println("    max |GDP/target-1| ", round(gap, digits = 5), "  worst ", worst, "  ", round(gdp[worst] / target[worst] - 1, digits = 5))
        flush(stdout)
        gap <= tol && return st
        for r in F.R
            g = gdp[r]
            tv = value(MGE[:tfp][r])
            e = elas[r]
            if k > 1 && prev_g[r] > 0 && abs(log(tv / prev_t[r])) > 1e-4
                e = clamp(log(g / prev_g[r]) / log(tv / prev_t[r]), 0.2, 1.2)
                elas[r] = e
            end
            step = clamp((target[r] / g)^(1 / e), 0.94, 1.06)
            prev_t[r] = tv
            prev_g[r] = g
            set_value!(MGE[:tfp][r], clamp(tv * step, 0.05, 25.0))
        end
    end
    return st
end

function write_csv(path, store)
    try
        open(path, "w") do io
            println(io, "series,t,r,value")
            for (name, d) in store
                for ((t, r), v) in sort(collect(d), by = kv -> (kv[1][1], string(kv[1][2])))
                    println(io, name, ",", t, ",", r, ",", v)
                end
            end
        end
        println("wrote ", path)
    catch err
        @warn "csv write failed" exception = err
    end
end

function run_path(io_path, sat_path, out_path)
    F = load_flows(io_path, sat_path)
    years = union([2023], collect(2025:5:2100))
    # EPPA8 eppabench.gms / eppaloop.gms. No vintaging, so the 0.95 branch.
    # scale * ror * inv0 = (K0 - K0*srve_t0) / 0.95, with K0 = 1.
    ror, dpe = 0.10, 0.05
    srve_t0 = (1 - dpe)^5
    scale_new = (1 - srve_t0) / 0.95
    cap = Dict(r => 1.0 for r in F.R)
    lab = Dict(r => 1.0 for r in F.R)
    inv = Dict(r => 1.0 for r in F.R)
    tfp_now = Dict(r => 1.0 for r in F.R)
    pop0 = Dict(r => F.pop[(2023, r)] for r in F.R)
    level = Dict(r => F.gdp0[r] for r in F.R)
    gdp = Dict{Tuple{Int,Symbol},Float64}()
    tar = Dict{Tuple{Int,Symbol},Float64}()
    tfp = Dict{Tuple{Int,Symbol},Float64}()
    ken = Dict{Tuple{Int,Symbol},Float64}()
    st = Dict{Int,Any}()
    println("building MCP with endogenous gprod")
    flush(stdout)
    MGE = build_model(F)
    # A price numeraire, as in EPPA. Leaving income free lets a late-year
    # income (IDZ) become the numeraire and PATH's basis blows up on Windows.
    fix(MGE[:PU][:USA], 1.0)
    println("numeraire PU[USA] = 1")
    for (n, t) in enumerate(years)
        println("\n==== ", t, " ====")
        flush(stdout)
        if n > 1
            prevy = years[n - 1]
            span = t - prevy
            lab_old = copy(lab)
            cap_old = copy(cap)
            tgt_old = Dict(r => value(MGE[:tgt][r]) for r in F.R)
            snap = snapshot_starts(MGE)
            ordt = n - 1
            srve = ordt == 1 ? (1 - dpe)^3 : (1 - dpe)^5
            for r in F.R
                grew = (1 + F.gr[(prevy, r)])^span
                level[r] *= grew
                lab[r] = F.pop[(t, r)] / pop0[r]
                boost = 1.0
                if ordt <= 5
                    boost = r == :MEX ? 1.05^(5 - ordt) : 1.10^(6 - ordt)
                end
                newcap = scale_new * boost * inv[r]
                cap[r] = cap_old[r] * srve + newcap
            end
            jump = maximum(max(abs(lab[r] / max(lab_old[r], 1e-8) - 1), abs(cap[r] / max(cap_old[r], 1e-8) - 1)) for r in F.R)
            nstep = max(1, ceil(Int, jump / 0.05))
            println("    ror ", ror, " scale_new ", round(scale_new, digits = 4), " srve ", round(srve, digits = 4), " jump ", round(jump, digits = 3), " in ", nstep)
            flush(stdout)
            dw = 1.0 / nstep
            w = 0.0
            st[t] = MOI.OPTIMIZE_NOT_CALLED
            for _ in 1:40
                w >= 1 - 1e-9 && break
                trial = min(1.0, w + dw)
                for r in F.R
                    set_value!(MGE[:lab][r], (1 - trial) * lab_old[r] + trial * lab[r])
                    set_value!(MGE[:cap][r], (1 - trial) * cap_old[r] + trial * cap[r])
                    set_value!(MGE[:tgt][r], (1 - trial) * tgt_old[r] + trial * level[r])
                end
                st[t] = solve_mcp!(MGE)
                if st[t] == MOI.SLOW_PROGRESS
                    got = real_gdp(MGE, F)
                    step_tgt = Dict(r => (1 - trial) * tgt_old[r] + trial * level[r] for r in F.R)
                    step_gap = try
                        all(isfinite, values(got)) ? maximum(abs(got[r] / step_tgt[r] - 1) for r in F.R) : Inf
                    catch
                        Inf
                    end
                    println("    slow gap ", round(step_gap, digits = 5))
                    step_gap <= 0.03 && (st[t] = MOI.LOCALLY_SOLVED)
                end
                println("    w ", round(trial, digits = 3), "  ", st[t])
                flush(stdout)
                if solved(st[t])
                    w = trial
                else
                    dw /= 2
                    println("    step halved to ", round(dw, digits = 4))
                    flush(stdout)
                    if dw < 0.05
                        st[t] = MOI.OTHER_ERROR
                        break
                    end
                end
            end
            w < 1 - 1e-9 && (st[t] = MOI.OTHER_ERROR)
        else
            for r in F.R
                set_value!(MGE[:tgt][r], level[r])
            end
        end
        if n == 1
            st[t] = solve_mcp!(MGE)
        end
        println(t, "  ", st[t])
        flush(stdout)
        solved(st[t]) || (@warn "stop" year = t status = st[t]; break)
        got = real_gdp(MGE, F)
        gap = maximum(abs(got[r] / level[r] - 1) for r in F.R)
        println("  accepted gap ", round(gap, digits = 5), "  gprod USA ", round(value(MGE[:gprod][:USA]), digits = 4))
        flush(stdout)
        gap <= 0.03 || (@warn "gdp not closed" year = t gap = gap; break)
        for r in F.R
            gdp[(t, r)] = got[r]
            tar[(t, r)] = level[r]
            tfp[(t, r)] = value(MGE[:gprod][r])
            ken[(t, r)] = value(MGE[:cap][r])
            inv[r] = value(MGE[:INV][r])
        end
        write_csv(out_path, Dict(:gdp => gdp, :target => tar, :tfp => tfp, :cap => ken))
    end
    return st
end
