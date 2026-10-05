# Simplified recursive EPPA for GDP calibration.
#
# Resolution matches the GTAP aggregation in EPPAinJulia:
# 18 regions, 14 commodities, factors lnd / lab / cap / fix.
# One CES production block and a high-elasticity Armington nest replace
# the deep energy nest. TFP is an output-augmenting parameter, updated
# outside PATH until real consumption hits the exogenous GDP path.

using JuMP, MPSGE, PATHSolver, JLD2, XLSX, DataFrames

const ES_ARM = 6.0
const ES_VA = 2.0
const ES_OUT = 4.0

function load_flows(io_path, sat_path)
    data = load(io_path)
    regions = data["set_r"]
    goods = data["set_i"]
    factors = data["set_f"]
    final = [:c, :g, :i]

    out = Dict{Tuple{Symbol,Symbol},Float64}()
    ex = Dict{Tuple{Symbol,Symbol},Float64}()
    im = Dict{Tuple{Symbol,Symbol},Float64}()
    fin = Dict{Tuple{Symbol,Symbol},Float64}()
    inv = Dict{Tuple{Symbol,Symbol},Float64}()
    inter = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    fac = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()

    for r in regions, i in goods
        ex[(i, r)] = max(sum(data["vxmd"][i, r, s] for s in regions), 0.0)
        im[(i, r)] = max(sum(data["vxmd"][i, s, r] for s in regions), 0.0)
        fin[(i, r)] = max(sum(data["vdfm"][i, j, r] + data["vifm"][i, j, r] for j in final), 0.0)
        inv[(i, r)] = max(data["vdfm"][i, :i, r] + data["vifm"][i, :i, r], 0.0)
        for k in goods
            inter[(k, i, r)] = max(data["vdfm"][k, i, r] + data["vifm"][k, i, r], 1e-6)
        end
        for f in factors
            fac[(f, i, r)] = max(data["vfm"][f, i, r], 1e-6)
        end
        out[(i, r)] = sum(inter[(k, i, r)] for k in goods) + sum(fac[(f, i, r)] for f in factors)
    end

    gr = Dict{Tuple{Int,Symbol},Float64}()
    pop = Dict{Tuple{Int,Symbol},Float64}()
    XLSX.openxlsx(sat_path) do xf
        gdf = DataFrame(XLSX.readtable(sat_path, "argdpgrrate"))
        pdf = DataFrame(XLSX.readtable(sat_path, "popa_eppa"))
        for row in eachrow(gdf), r in regions
            gr[(Int(row.year), r)] = Float64(row[r])
        end
        for row in eachrow(pdf), r in regions
            pop[(Int(row.year), r)] = Float64(row[r])
        end
    end

    gdp0 = Dict(r => sum(max(fin[(i, r)], 1e-8) for i in goods) for r in regions)
    lab0 = Dict(r => sum(fac[(:lab, i, r)] for i in goods) for r in regions)
    cap0 = Dict(r => sum(fac[(:cap, i, r)] for i in goods) for r in regions)
    return (; data, regions, goods, factors, out, ex, im, fin, inv, inter, fac, gr, pop, gdp0, lab0, cap0)
end

function build_model(F)
    MGE = MPSGEModel()
    R = F.regions
    I = F.goods

    @parameters(MGE, begin
        tfp[r=R], 1.0, (description = "Output-augmenting TFP, set outside PATH")
        lab[r=R], 1.0, (description = "Labor endowment index")
        cap[r=R], 1.0, (description = "Capital endowment index")
        qy[i=I, r=R], F.out[(i, r)]
        qa[i=I, r=R], max(F.out[(i, r)] - F.ex[(i, r)], 1e-6) + max(F.im[(i, r)], 1e-6)
        qd[i=I, r=R], max(F.out[(i, r)] - F.ex[(i, r)], 1e-6)
        qm[i=I, r=R], max(F.im[(i, r)], 1e-6)
        qe[i=I, r=R], max(F.ex[(i, r)], 1e-6)
        qi[k=I, i=I, r=R], F.inter[(k, i, r)]
        qf[f=[:lab, :cap, :lnd, :fix], i=I, r=R], F.fac[(f, i, r)]
        qc[i=I, r=R], max(F.fin[(i, r)], 1e-8)
        qn[i=I, r=R], max(F.inv[(i, r)], 1e-8)
        qC[r=R], F.gdp0[r]
        qI[r=R], sum(max(F.inv[(i, r)], 1e-8) for i in I)
        qlab[r=R], F.lab0[r]
        qcap[r=R], F.cap0[r]
        qfx[r=R], sum(F.im[(i, r)] - F.ex[(i, r)] for i in I)
        qgap[r=R], F.gdp0[r] + sum(max(F.inv[(i, r)], 1e-8) for i in I) - F.lab0[r] - F.cap0[r] - sum(F.fac[(:lnd, i, r)] + F.fac[(:fix, i, r)] for i in I) - sum(F.im[(i, r)] - F.ex[(i, r)] for i in I)
    end)

    @sectors(MGE, begin
        Y[i=I, r=R], (description = "Sectoral supply")
        A[i=I, r=R], (description = "Armington composite")
        E[i=I, r=R], (description = "Exports")
        M[i=I, r=R], (description = "Imports")
        C[r=R], (description = "Consumption bundle, real GDP")
        INV[r=R], (description = "Investment bundle")
    end)

    @commodities(MGE, begin
        PY[i=I, r=R], (description = "Domestic output price")
        PA[i=I, r=R], (description = "Armington price")
        PM[i=I, r=R], (description = "Import price")
        PFX[r=R], (description = "Foreign exchange")
        PL[r=R], (description = "Labor")
        PK[r=R], (description = "Capital")
        PN[i=I, r=R], (description = "Land")
        PX[i=I, r=R], (description = "Sector-specific fixed factor")
        PU[r=R], (description = "Consumption price")
        PI[r=R], (description = "Investment price")
    end)

    @consumers(MGE, begin
        RA[r=R]
    end)

    @production(MGE, Y[i=I, r=R], [t = 0, s = ES_OUT, va => s = ES_VA], begin
        @output(PY[i, r], qy[i, r] * tfp[r], t)
        @input(PA[k=I, r], qi[k, i, r], s)
        @input(PL[r], qf[:lab, i, r], va)
        @input(PK[r], qf[:cap, i, r], va)
        @input(PN[i, r], qf[:lnd, i, r], va)
        @input(PX[i, r], qf[:fix, i, r], va)
    end)

    @production(MGE, A[i=I, r=R], [t = 0, s = ES_ARM], begin
        @output(PA[i, r], qa[i, r], t)
        @input(PY[i, r], qd[i, r], s)
        @input(PM[i, r], qm[i, r], s)
    end)

    @production(MGE, M[i=I, r=R], [t = 0, s = 0], begin
        @output(PM[i, r], qm[i, r], t)
        @input(PFX[r], qm[i, r], s)
    end)

    @production(MGE, E[i=I, r=R], [t = 0, s = ES_OUT], begin
        @output(PFX[r], qe[i, r], t)
        @input(PY[i, r], qe[i, r], s)
    end)

    @production(MGE, C[r=R], [t = 0, s = 1.0], begin
        @output(PU[r], qC[r], t)
        @input(PA[i=I, r], qc[i, r], s)
    end)

    @production(MGE, INV[r=R], [t = 0, s = 0.5], begin
        @output(PI[r], qI[r], t)
        @input(PA[i=I, r], qn[i, r], s)
    end)

    @demand(MGE, RA[r=R], begin
        @final_demand(PU[r], qC[r])
        @endowment(PL[r], qlab[r] * lab[r])
        @endowment(PK[r], qcap[r] * cap[r])
        @endowment(PN[i=I, r], qf[:lnd, i, r])
        @endowment(PX[i=I, r], qf[:fix, i, r])
        @endowment(PI[r], -qI[r])
        @endowment(PFX[r], qfx[r])
        @endowment(PU[r], qgap[r])
    end)
    return MGE
end

function _solved(st)
    st in (MOI.LOCALLY_SOLVED, MOI.ALMOST_LOCALLY_SOLVED, MOI.OPTIMAL)
end

function _solve!(MGE)
    solve!(MGE;
        cumulative_iteration_limit = 20_000,
        minor_iteration_limit = 4_000,
        convergence_tolerance = 1e-4,
        proximal_perturbation = 0.0,
    )
    return termination_status(jump_model(MGE))
end

function real_gdp(MGE, F)
    return Dict(r => value(MGE[:C][r]) * F.gdp0[r] for r in F.regions)
end

function match_tfp!(MGE, F, target; tol = 1e-2, iters = 8)
    elas = Dict(r => 0.6 for r in F.regions)
    prev_t = Dict(r => value(MGE[:tfp][r]) for r in F.regions)
    prev_g = Dict(r => NaN for r in F.regions)
    st = MOI.OPTIMIZE_NOT_CALLED
    for k in 1:iters
        st = _solve!(MGE)
        println("    tfp pass ", k, "  ", st)
        flush(stdout)
        _solved(st) || return st
        gdp = real_gdp(MGE, F)
        gap = maximum(abs(gdp[r] / target[r] - 1) for r in F.regions)
        println("    max |GDP/target-1| ", round(gap, digits = 4))
        flush(stdout)
        gap <= tol && return st
        for r in F.regions
            g = gdp[r]
            tv = value(MGE[:tfp][r])
            e = elas[r]
            if k > 1 && isfinite(prev_g[r]) && prev_g[r] > 0 && prev_t[r] > 0 && abs(log(tv / prev_t[r])) > 1e-4
                e = clamp(log(g / prev_g[r]) / log(tv / prev_t[r]), 0.15, 1.5)
                elas[r] = e
            end
            step = clamp((target[r] / g)^(1 / e), 0.6, 1.8)
            prev_t[r] = tv
            prev_g[r] = g
            set_value!(MGE[:tfp][r], clamp(tv * step, 0.05, 30.0))
        end
    end
    return st
end

function write_results(path, store)
    XLSX.openxlsx(path, mode = "w") do xf
        first = true
        for (name, d) in store
            rows = [(t = k[1], r = string(k[2]), value = v) for (k, v) in d]
            df = DataFrame(t = [x.t for x in rows], r = [x.r for x in rows], value = [x.value for x in rows])
            sort!(df, [:t, :r])
            first ? XLSX.rename!(xf[1], string(name)) : XLSX.addsheet!(xf, string(name))
            first = false
            XLSX.writetable!(xf[string(name)], df)
        end
    end
    println("wrote ", path)
    flush(stdout)
end

function run_path(io_path, sat_path, out_path)
    F = load_flows(io_path, sat_path)
    years = union([2023], collect(2025:5:2100))
    println("building")
    flush(stdout)
    MGE = build_model(F)
    println("built")
    flush(stdout)
    for r in F.regions
        set_value!(MGE[:tfp][r], 1.0)
        set_value!(MGE[:lab][r], 1.0)
        set_value!(MGE[:cap][r], 1.0)
    end
    dpr = 0.05
    ror = 0.15
    cap = Dict(r => 1.0 for r in F.regions)
    inv = Dict(r => 1.0 for r in F.regions)
    tfp = Dict{Tuple{Int,Symbol},Float64}()
    gdp = Dict{Tuple{Int,Symbol},Float64}()
    tar = Dict{Tuple{Int,Symbol},Float64}()
    ken = Dict{Tuple{Int,Symbol},Float64}()
    st = Dict{Int,Any}()
    pop0 = Dict(r => F.pop[(2023, r)] for r in F.regions)
    level = Dict(r => F.gdp0[r] for r in F.regions)

    for (n, t) in enumerate(years)
        println(t)
        flush(stdout)
        if n > 1
            prev = years[n - 1]
            span = t - prev
            for r in F.regions
                level[r] *= (1 + F.gr[(prev, r)])^span
                set_value!(MGE[:lab][r], F.pop[(t, r)] / pop0[r])
                knew = cap[r] * (1 - dpr)^span + ror * inv[r] * (1 - (1 - dpr)^span) / dpr
                cap[r] = max(knew, 1e-4)
                set_value!(MGE[:cap][r], cap[r])
            end
        end
        target = Dict(r => level[r] for r in F.regions)
        st[t] = match_tfp!(MGE, F, target)
        println(t, "  ", st[t])
        flush(stdout)
        _solved(st[t]) || (@warn "stop" year = t status = st[t]; break)
        got = real_gdp(MGE, F)
        gap = maximum(abs(got[r] / target[r] - 1) for r in F.regions)
        println("    accepted gap ", round(gap, digits = 4))
        gap <= 0.02 || (@warn "gdp not closed" year = t gap = gap; break)
        for r in F.regions
            gdp[(t, r)] = got[r]
            tar[(t, r)] = target[r]
            tfp[(t, r)] = value(MGE[:tfp][r])
            ken[(t, r)] = cap[r]
            inv[r] = value(MGE[:INV][r])
        end
        write_results(out_path, Dict(:gdp => gdp, :target => tar, :tfp => tfp, :cap => ken))
    end
    return st
end
