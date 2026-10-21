function _aeei_factor(data, i, r, year)
    base = YEARS[1]
    years = max(year - base, 0)
    gr = get(data.aeeigr, (i, r), 0.0)
    return (1 + gr)^(-years)
end

function _set_aeei!(st, data, year)
    for r in st.R, i in SECTORS
        set_value!(st.aeei[i, r], _aeei_factor(data, i, r, year))
    end
    return nothing
end
function _boost(r, ord)
    ord > 5 && return 1.0
    return r == :mex ? 1.05^(5 - ord) : 1.10^(6 - ord)
end

function _srve(year)
    i = findfirst(==(year), YEARS)
    i === nothing && error("year $year is not an EPPA period")
    n = i == 1 ? step_years(1) : regular_step()
    return (1 - DPE)^n
end

function _next_state(MGE, st, data, year, next)
    ord = findfirst(==(year), YEARS)
    out = Dict{Symbol,NamedTuple}()
    for r in st.R
        inv_level = max(_level(MGE[:INV][r]), 0.0)
        knew = st.scale[r] * ROR * st.inv0[r] * inv_level * _boost(r, ord) + _level(st.k0[r]) * _srve(year)
        out[r] = (
            K = _level(st.k0[r]),
            L = _level(st.l0[r]),
            G = _level(st.gdp0[r]),
            Rgov = _level(st.grg[r]),
            S = _level(st.sav[r]),
            Kn = max(knew, 1e-8),
            Ln = max(_level(st.l0[r]) * pop_ratio(data, r, year, next), 1e-8),
            Gn = _level(st.gdp0[r]) * growth_factor(data, r, year),
            Rn = _level(st.grg[r]) * growth_factor(data, r, next),
            Sn = ord <= 10 ? _level(st.sav[r]) * 0.9^ord : 0.0,
        )
    end
    return out
end

function _plant!(st, old, w)
    for r in st.R
        o = old[r]
        set_value!(st.k0[r], (1 - w) * o.K + w * o.Kn)
        set_value!(st.l0[r], (1 - w) * o.L + w * o.Ln)
        set_value!(st.gdp0[r], (1 - w) * o.G + w * o.Gn)
        set_value!(st.grg[r], (1 - w) * o.Rgov + w * o.Rn)
        set_value!(st.sav[r], (1 - w) * o.S + w * o.Sn)
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
        (startswith(n, "P") || startswith(n, "RA") || startswith(n, "GPROD") || startswith(n, "RGDP")) && continue
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
        g0 = start_value(st.GPROD[r])
        g0 = g0 === nothing ? 1.0 : g0
        if st.simu == 0
            set_start_value(st.GPROD[r], max(g0 * grow / lrat, 1e-6))
        else
            JuMP.set_start_value(get_variable(st.GPROD[r]), JuMP.value(st.gp0[r]))
        end
        set_start_value(st.RGDP[r], o.Gn)
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
    old = _next_state(MGE, st, data, year, next)
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
        return stt
    end

    origin = _snap(MGE)
    for w in (0.8, 0.6, 0.4, 0.2)
        println("  damp ", w)
        flush(stdout)
        _restore!(MGE, base)
        _plant!(st, old, w)
        _prices_to_one!(MGE)
        stt_last = _solve!(MGE; proximal = 1e-4, restarts = 1, iters = 10_000)
        failed = false
        for a in range(w + 0.2, 1.0; step = 0.2)
            res = _residual(MGE)
            gap = _gdp_gap(st)
            println("    anchor ", a, " ", stt_last, " res ", res, " gap ", gap)
            flush(stdout)
            if !_usable(stt_last, res, gap)
                failed = true
                break
            end
            _restore!(MGE, origin)
            _plant!(st, old, a)
            stt_last = _solve!(MGE; proximal = 1e-4, restarts = 1, iters = 10_000)
            if !_usable(stt_last, _residual(MGE), _gdp_gap(st))
                println("    fail ", a, " ", stt_last, " res ", _residual(MGE), " gap ", _gdp_gap(st))
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



