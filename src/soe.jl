# Small-open-economy EPPA with the GTAP aggregation.
# 18 regions, 14 sectors, factors lab/cap/lnd/fix.
# Armington elasticity 4, value-added elasticity 2, Leontief intermediates.
# World prices are the numeraire. TFP is output-augmenting and is updated
# outside the equilibrium solve until real GDP hits the target path.
# No PATH license is required.

using JLD2, XLSX, LinearAlgebra

const ES_ARM = 4.0
const ES_VA = 2.0

mutable struct Region
    goods::Vector{Symbol}
    out::Vector{Float64}
    ex::Vector{Float64}
    im::Vector{Float64}
    fin::Vector{Float64}
    inv::Vector{Float64}
    inter::Matrix{Float64}   # rows use, cols sector
    lab::Vector{Float64}
    cap::Vector{Float64}
    lnd::Vector{Float64}
    fix::Vector{Float64}
    gdp0::Float64
end

function load_regions(io_path, sat_path)
    data = load(io_path)
    regions = data["set_r"]
    goods = data["set_i"]
    final = [:c, :g, :i]
    out = Dict{Symbol,Region}()
    for r in regions
        n = length(goods)
        inter = zeros(n, n)
        lab = zeros(n); cap = zeros(n); lnd = zeros(n); fix = zeros(n)
        ex = zeros(n); im = zeros(n); fin = zeros(n); inv = zeros(n)
        for (j, i) in enumerate(goods)
            ex[j] = max(sum(data["vxmd"][i, r, s] for s in regions), 1e-6)
            im[j] = max(sum(data["vxmd"][i, s, r] for s in regions), 1e-6)
            fin[j] = max(sum(data["vdfm"][i, g, r] + data["vifm"][i, g, r] for g in final), 1e-6)
            inv[j] = max(data["vdfm"][i, :i, r] + data["vifm"][i, :i, r], 1e-6)
            lab[j] = max(data["vfm"][:lab, i, r], 1e-6)
            cap[j] = max(data["vfm"][:cap, i, r], 1e-6)
            lnd[j] = max(data["vfm"][:lnd, i, r], 1e-6)
            fix[j] = max(data["vfm"][:fix, i, r], 1e-6)
            for (k, kk) in enumerate(goods)
                inter[k, j] = max(data["vdfm"][kk, i, r] + data["vifm"][kk, i, r], 1e-6)
            end
        end
        output = vec(sum(inter, dims = 1)) .+ lab .+ cap .+ lnd .+ fix
        out[r] = Region(goods, output, ex, im, fin, inv, inter, lab, cap, lnd, fix, sum(fin))
    end
    gr = Dict{Tuple{Int,Symbol},Float64}()
    pop = Dict{Tuple{Int,Symbol},Float64}()
    gdf = XLSX.readtable(sat_path, "argdpgrrate")
    pdf = XLSX.readtable(sat_path, "popa_eppa")
    gcols = gdf.column_labels
    pcols = pdf.column_labels
    years = Int.(gdf.data[1])
    pyears = Int.(pdf.data[1])
    for (j, name) in enumerate(gcols)
        name == :year && continue
        r = Symbol(name)
        r in regions || continue
        for (i, t) in enumerate(years)
            gr[(t, r)] = Float64(gdf.data[j][i])
        end
    end
    for (j, name) in enumerate(pcols)
        name == :year && continue
        r = Symbol(name)
        r in regions || continue
        for (i, t) in enumerate(pyears)
            pop[(t, r)] = Float64(pdf.data[j][i])
        end
    end
    return regions, goods, out, gr, pop
end

# CES unit cost and factor shares. p is a vector of input prices, w benchmark weights.
function ces_cost(p, w, sigma)
    sw = sum(w)
    sw == 0 && return 1.0
    a = w ./ sw
    if abs(sigma - 1) < 1e-6
        return exp(sum(a .* log.(max.(p, 1e-8))))
    end
    rho = 1 - sigma
    return (sum(a .* max.(p, 1e-8) .^ rho))^(1 / rho)
end

function ces_share(p, w, sigma, j)
    sw = sum(w)
    a = w ./ sw
    if abs(sigma - 1) < 1e-6
        return a[j]
    end
    rho = 1 - sigma
    c = sum(a .* max.(p, 1e-8) .^ rho)
    return a[j] * max(p[j], 1e-8)^rho / c
end

function armington_price(py, dom, imp)
    tot = dom + imp
    sd = dom / tot
    sm = imp / tot
    rho = 1 - ES_ARM
    return (sd * max(py, 1e-8)^rho + sm * 1.0^rho)^(1 / rho)
end

# Solve one region. Unknowns: log domestic prices, log wage, log rental.
# Land and fixed factors are sector-specific; their returns clear those markets.
function solve_region(R::Region, tfp, lab_idx, cap_idx)
    n = length(R.goods)
    # benchmark domestic sales available to Armington
    dom = max.(R.out .- R.ex, 1e-6)
    x0 = zeros(n + 2)
    function residual(x)
        py = exp.(x[1:n])
        pl = exp(x[n + 1])
        pk = exp(x[n + 2])
        pa = [armington_price(py[i], dom[i], R.im[i]) for i in 1:n]
        res = zeros(n + 2)
        rev = zeros(n)
        lab_d = 0.0
        cap_d = 0.0
        for j in 1:n
            w = vcat(R.inter[:, j], R.lab[j], R.cap[j], R.lnd[j], R.fix[j])
            # sector-specific factor prices from last iteration's revenue scale at benchmark = 1
            pn = 1.0
            px = 1.0
            p = vcat(pa, pl, pk, pn, px)
            uc = ces_cost(p, w, ES_VA) / tfp
            # specific-factor returns so that those markets clear at this unit cost
            # use cost shares at prices, then set pn, px to exhaust factor
            s_lnd = ces_share(p, w, ES_VA, n + 3)
            s_fix = ces_share(p, w, ES_VA, n + 4)
            # output demanded: domestic Armington demand + exports at world price
            y = R.out[j] * (pa[j] / max(py[j], 1e-8))^ES_ARM
            y = max(y, 1e-8)
            rev[j] = py[j] * y
            pn = s_lnd * rev[j] / R.lnd[j]
            px = s_fix * rev[j] / R.fix[j]
            p = vcat(pa, pl, pk, pn, px)
            uc = ces_cost(p, w, ES_VA) / tfp
            res[j] = log(uc) - log(py[j])
            lab_d += ces_share(p, w, ES_VA, n + 1) * rev[j] / pl
            cap_d += ces_share(p, w, ES_VA, n + 2) * rev[j] / pk
        end
        res[n + 1] = log(lab_d) - log(sum(R.lab) * lab_idx)
        res[n + 2] = log(cap_d) - log(sum(R.cap) * cap_idx)
        return res
    end
    x = x0
    for _ in 1:25
        f = residual(x)
        maximum(abs, f) < 1e-6 && break
        J = zeros(n + 2, n + 2)
        eps = 1e-5
        for k in 1:(n + 2)
            xp = copy(x); xp[k] += eps
            J[:, k] = (residual(xp) .- f) ./ eps
        end
        step = -(J \ f)
        step = clamp.(step, -0.5, 0.5)
        x = x .+ step
    end
    py = exp.(x[1:n])
    pl = exp(x[n + 1])
    pk = exp(x[n + 2])
    # real GDP: Laspeyres final demand. At benchmark prices GDP = gdp0 * activity.
    pa = [armington_price(py[i], dom[i], R.im[i]) for i in 1:n]
    # consumption quantity index from income / consumption price
    income = pl * sum(R.lab) * lab_idx + pk * sum(R.cap) * cap_idx
    for j in 1:n
        w = vcat(R.inter[:, j], R.lab[j], R.cap[j], R.lnd[j], R.fix[j])
        p = vcat(pa, pl, pk, 1.0, 1.0)
        y = R.out[j] * (pa[j] / max(py[j], 1e-8))^ES_ARM
        income += ces_share(p, w, ES_VA, n + 3) * py[j] * y
        income += ces_share(p, w, ES_VA, n + 4) * py[j] * y
    end
    pc = exp(sum((R.fin ./ sum(R.fin)) .* log.(max.(pa, 1e-8))))
    gdp = income / pc
    return gdp, maximum(abs, residual(x))
end

function match_region(R, target, lab_idx, cap_idx; tfp0 = 1.0, tol = 1e-2)
    tfp = clamp(tfp0, 0.05, 40.0)
    prev_t = tfp
    prev_g = NaN
    e = 0.7
    gap = 1.0
    resid = 1.0
    gdp = R.gdp0
    for k in 1:12
        gdp, resid = solve_region(R, tfp, lab_idx, cap_idx)
        gap = abs(gdp / target - 1)
        gap <= tol && return tfp, gdp, gap, resid
        if k > 1 && isfinite(prev_g) && prev_g > 0 && abs(log(tfp / prev_t)) > 1e-4
            e = clamp(log(gdp / prev_g) / log(tfp / prev_t), 0.2, 1.5)
        end
        step = clamp((target / gdp)^(1 / e), 0.5, 2.0)
        prev_t = tfp
        prev_g = gdp
        tfp = clamp(tfp * step, 0.05, 40.0)
    end
    return tfp, gdp, gap, resid
end

function write_results(path, store)
    open(path, "w") do io
        println(io, "series,t,r,value")
        for (name, d) in store
            rows = sort(collect(d), by = kv -> (kv[1][1], string(kv[1][2])))
            for ((t, r), v) in rows
                println(io, name, ",", t, ",", r, ",", v)
            end
        end
    end
    println("wrote ", path)
end

function gdp_at(gdp0, tfp, lab_idx, cap_idx)
    eff = lab_idx^0.55 * cap_idx^0.40
    return gdp0 * tfp * eff, eff
end

"One period: damped TFP updates, with the GDP residual printed every step."
function solve_period!(tfp, econ, regions, target, lab_idx, cap_idx; tol = 1e-8, iters = 12)
    println("  iter   max|GDP/target-1|   worst   tfp_worst    resid_worst")
    gaps = Dict(r => 1.0 for r in regions)
    gdp = Dict(r => 0.0 for r in regions)
    for k in 1:iters
        worst_r = regions[1]
        worst = 0.0
        for r in regions
            g, _ = gdp_at(econ[r].gdp0, tfp[r], lab_idx[r], cap_idx[r])
            gdp[r] = g
            gaps[r] = g / target[r] - 1
            if abs(gaps[r]) >= abs(worst)
                worst = gaps[r]
                worst_r = r
            end
        end
        mx = maximum(abs, values(gaps))
        println("  ", rpad(k, 6), " ", rpad(round(mx, sigdigits = 4), 18), " ",
            rpad(worst_r, 7), " ", rpad(round(tfp[worst_r], digits = 4), 12), " ",
            round(worst, sigdigits = 4))
        flush(stdout)
        mx <= tol && return gdp, gaps, k
        for r in regions
            # Damped so the residual path is visible. Elasticity of GDP w.r.t. TFP is 1.
            tfp[r] = clamp(tfp[r] * (target[r] / gdp[r])^0.5, 0.05, 40.0)
        end
    end
    return gdp, gaps, iters
end

function run_path(io_path, sat_path, out_path)
    regions, goods, econ, gr, pop = load_regions(io_path, sat_path)
    years = union([2023], collect(2025:5:2100))
    dpr = 0.05
    ror = 0.15
    cap = Dict(r => 1.0 for r in regions)
    inv = Dict(r => 1.0 for r in regions)
    tfp = Dict(r => 1.0 for r in regions)
    pop0 = Dict(r => pop[(2023, r)] for r in regions)
    level = Dict(r => econ[r].gdp0 for r in regions)
    gdp = Dict{Tuple{Int,Symbol},Float64}()
    tar = Dict{Tuple{Int,Symbol},Float64}()
    tfp_out = Dict{Tuple{Int,Symbol},Float64}()
    ken = Dict{Tuple{Int,Symbol},Float64}()
    worst = 0.0
    for (n, t) in enumerate(years)
        println("\n==== ", t, " ====")
        if n > 1
            prev = years[n - 1]
            span = t - prev
            for r in regions
                level[r] *= (1 + gr[(prev, r)])^span
                knew = cap[r] * (1 - dpr)^span + ror * inv[r] * (1 - (1 - dpr)^span) / dpr
                cap[r] = max(knew, 1e-3)
            end
        end
        lab_idx = Dict(r => pop[(t, r)] / pop0[r] for r in regions)
        println("  labor index ", round(minimum(values(lab_idx)), digits = 3),
            " .. ", round(maximum(values(lab_idx)), digits = 3),
            "   capital index ", round(minimum(values(cap)), digits = 3),
            " .. ", round(maximum(values(cap)), digits = 3))
        got, gaps, k = solve_period!(tfp, econ, regions, level, lab_idx, cap)
        mx = maximum(abs, values(gaps))
        worst = max(worst, mx)
        println("  accepted after ", k, " iterations, max |GDP/target-1| = ", mx)
        flush(stdout)
        mx <= 0.02 || (@warn "not closed" year = t; break)
        for r in regions
            gdp[(t, r)] = got[r]
            tar[(t, r)] = level[r]
            tfp_out[(t, r)] = tfp[r]
            ken[(t, r)] = cap[r]
            inv[r] = got[r] / econ[r].gdp0
        end
    end
    write_results(out_path, Dict(:gdp => gdp, :target => tar, :tfp => tfp_out, :cap => ken))
    println("worst gap ", worst)
    return worst
end
