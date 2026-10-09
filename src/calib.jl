# Benchmark accounts for the active v-ref structure.
# Vintage, backstops, land-use change, Stone-Geary and emissions are off.
# Emission pass-through nests are identities at a zero carbon price, so energy
# inputs use pa (phom for crude oil) directly.

const REGIONS = [:usa, :can, :mex, :jpn, :anz, :eur, :roe, :rus, :asi, :chn, :ind, :bra, :afr, :mes, :lam, :rea, :kor, :idz]
const SECTORS = [:crop, :live, :fors, :food, :coal, :oil, :roil, :gas, :elec, :eint, :othr, :serv, :tran, :dwe]
const NE = [:crop, :live, :fors, :food, :eint, :othr, :serv, :tran, :dwe]
const NENDT = [:crop, :live, :fors, :food, :eint, :othr, :serv]
const AENOE = [:coal, :oil, :gas, :roil, :crop, :live, :fors, :elec, :eint]
const AGRI = [:crop, :live, :fors]
const ENOE = [:coal, :oil, :gas, :roil]
const ENRE = [:coal, :oil, :gas]
const ENERGY = [:coal, :oil, :gas, :roil, :elec]
const FF = [:oil, :gas, :coal]
const TECH = [:cele, :gele, :oele, :hele, :nele, :rele, :sele, :wele, :tele]
const TECH_F = [:cele, :gele, :oele]
const TECH_NHR = [:nele, :hele, :rele]
const TECH_N = [:sele, :wele]
const TECH_D = [:cele, :gele, :oele, :hele, :nele, :rele]
const NOT_AENOE = [:food, :othr, :serv, :tran, :dwe]

const HTRNS = 0.3753
const PROPFRAC = 0.2
const DPE = 0.05
const ROR = 0.1

function load_gms_table(path)
    lines = readlines(path)
    body = String[]
    inside = false
    for ln in lines
        s = strip(ln)
        if !inside
            startswith(lowercase(s), "table ") && (inside = true)
            continue
        end
        startswith(s, ";") && break
        (isempty(s) || startswith(s, "*")) && continue
        push!(body, s)
    end
    isempty(body) && return Dict{Tuple,Float64}()
    data = Dict{Tuple,Float64}()
    header = nothing
    for ln in body
        toks = split(ln)
        vals = Float64[]
        while !isempty(toks)
            v = tryparse(Float64, toks[end])
            v === nothing && break
            push!(vals, v)
            pop!(toks)
        end
        reverse!(vals)
        if isempty(vals)
            labs = Symbol.(lowercase.(toks))
            if header === nothing && length(labs) >= 1
                header = labs
            end
            continue
        end
        header === nothing && continue
        length(vals) == length(header) || continue
        labs = Symbol[]
        for t in toks
            t == "." && continue
            push!(labs, Symbol(lowercase(t)))
        end
        isempty(labs) && continue
        for (j, reg) in enumerate(header)
            data[(labs..., reg)] = vals[j]
        end
    end
    return data
end

function load_assigns(path)
    data = Dict{Symbol,Float64}()
    rx = r"\(\s*\"([^\"]+)\"\s*\)\s*=\s*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)"
    for ln in readlines(path)
        m = match(rx, ln)
        m === nothing && continue
        data[Symbol(lowercase(m.captures[1]))] = parse(Float64, m.captures[2])
    end
    return data
end

function prepare(dat_path, elec_path, extracted)
    wanted = Set([
        "xp0", "es0", "xm0", "vst", "labd0", "kapd0", "ffactd0",
        "xdp0", "xmp0", "xdc0", "xmc0", "xdg0", "xmg0", "xdi0", "xmi0",
        "ti", "tf", "tp", "tg", "pg0", "pc0", "pf0", "ptxy0",
        "tx", "tm", "wtflow0", "vtwr", "savf0", "cons0", "kapdg0", "labdg0", "trg0",
        "efd", "savh0",
    ])
    p = load_gams_dat(dat_path, wanted)
    e = load_gams_dat(elec_path, Set(["elecin", "elecint", "xp0_", "td_"]))
    g(name, key) = get(p[name], key, 0.0)
    ge(name, key) = get(e[name], key, 0.0)

    selas = load_gms_table(joinpath(extracted, "parameters_eppaelas_selas.inc"))
    for (k, v) in selas
        # (sector, layer, region); noe_el is tripled in eppaelas.gms
        if length(k) == 3 && k[2] == :noe_el
            selas[k] = 3v
        end
    end
    esup = load_gms_table(joinpath(extracted, "parameters_eppaelas_esup.inc"))
    esube = load_gms_table(joinpath(extracted, "parameters_eppaelas_esube.inc"))
    sigu = load_gms_table(joinpath(extracted, "parameters_eppaelas_sigu.inc"))
    delas_raw = Dict{Tuple,Float64}()
    open(joinpath(extracted, "parameters_eppaelas_d_elas.inc")) do io
        for ln in eachline(io)
            s = strip(ln)
            (isempty(s) || startswith(s, "*") || startswith(s, "/") || startswith(lowercase(s), "parameter")) && continue
            parts = split(s)
            length(parts) < 2 && continue
            v = tryparse(Float64, parts[end])
            v === nothing && continue
            delas_raw[(Symbol(lowercase(parts[1])),)] = v
        end
    end
    delas = delas_raw
    crtable = load_gms_table(joinpath(extracted, "core_eppacalib_crtable.inc"))
    bio = load_gms_table(joinpath(extracted, "core_readgtap_bio.inc"))
    nhreta = load_gms_table(joinpath(extracted, "core_elecpower_nhreta.inc"))
    wst = load_gms_table(joinpath(extracted, "core_elecpower_wstsigma.inc"))
    os = load_assigns(joinpath(extracted, "parameters_eppa_htrn_os.inc"))
    esh = load_assigns(joinpath(extracted, "parameters_eppa_htrn_es.inc"))
    mvh = load_assigns(joinpath(extracted, "parameters_eppa_htrn_mvh.inc"))
    hist = load_t_table(joinpath(extracted, "parameters_eppatrend_histrgdp.inc"))
    ann = load_t_table(joinpath(extracted, "parameters_eppatrend_argdpgrrate.inc"))
    pop = load_t_table(joinpath(extracted, "parameters_eppatrend_popa_eppa.inc"))

    elas(g, layer, r) = get(selas, (g, layer, r), 0.0)
    cr(i, g, r) = i == :roil ? get(crtable, (g, r), 0.0) : 1.0

    # Land tax is capitalized into the fixed-factor quantity (eppaparm).
    ffact = Dict{Tuple{Symbol,Symbol},Float64}()
    for r in REGIONS, i in SECTORS
        ffact[(r, i)] = g("ffactd0", (r, i)) * (1 + g("tf", (:lnd, i, r)))
    end

    a0 = Dict{Tuple{Symbol,Symbol},Float64}()
    d0 = Dict{Tuple{Symbol,Symbol},Float64}()
    td = Dict{Tuple{Symbol,Symbol},Float64}()
    inv0 = Dict{Symbol,Float64}()
    g0 = Dict{Symbol,Float64}()
    for r in REGIONS
        inv0[r] = sum(g("xdi0", (r, i)) + g("xmi0", (r, i)) for i in SECTORS)
        g0[r] = g("kapdg0", (r,)) + g("labdg0", (r,)) + g("trg0", (r,)) +
                sum(g("xdg0", (r, i)) + g("xmg0", (r, i)) for i in SECTORS)
        for i in SECTORS
            a0[(r, i)] = g("xp0", (r, i)) - g("es0", (r, i)) + g("xm0", (r, i)) - g("vst", (i, r))
            d0[(r, i)] = g("xp0", (r, i)) - g("es0", (r, i)) - g("vst", (i, r))
            xp = g("xp0", (r, i))
            td[(r, i)] = xp == 0 ? 0.0 : g("ptxy0", (r, i)) / xp
        end
    end

    # Household transport extraction (eppacalib), applied to copies of final demand.
    xdc = Dict(k => v for (k, v) in p["xdc0"])
    xmc = Dict(k => v for (k, v) in p["xmc0"])
    purtrn = Dict{Symbol,Float64}()
    tbo = Dict{Symbol,Float64}()
    tfo = Dict{Symbol,Float64}()
    toi = Dict{Symbol,Float64}()
    tse = Dict{Symbol,Float64}()
    own = Dict{Symbol,Float64}()
    tottrn = Dict{Symbol,Float64}()
    ence = Dict{Tuple{Symbol,Symbol},Float64}()
    for r in REGIONS
        purtrn[r] = g("xdc0", (r, :tran)) + g("xmc0", (r, :tran))
        xdc[(r, :tran)] = 0.0
        xmc[(r, :tran)] = 0.0
        ence0 = g("xdc0", (r, :roil)) + g("xmc0", (r, :roil))
        efd = g("efd", (:roil, r))
        pbio = efd == 0 ? 0.0 : ence0 / efd
        ebio = pbio * get(bio, (r, Symbol("bio-fg")), 0.0)
        pcR = g("pc0", (:roil, r))
        tbo[r] = pcR == 0 ? 0.0 : ebio / pcR
        tfo[r] = os[r] * ence0
        toi[r] = mvh[r]
        owntrn = esh[r] * g("cons0", (r,))
        foodp = r == :bra ? :eint : :food
        tottrn[r] = purtrn[r] * g("pc0", (:tran, r)) + owntrn + (pcR - g("pc0", (foodp, r))) * tbo[r]
        tse[r] = (owntrn - tfo[r] * pcR - toi[r] * g("pc0", (:othr, r)) - tbo[r] * g("pc0", (foodp, r))) / g("pc0", (:serv, r))
        own[r] = pcR * (tfo[r] + tbo[r]) + g("pc0", (:othr, r)) * toi[r] + g("pc0", (:serv, r)) * tse[r]
        xdc[(r, :roil)] = g("xdc0", (r, :roil)) - tfo[r]
        xdc[(r, foodp)] = g("xdc0", (r, foodp)) - tbo[r]
        xdc[(r, :othr)] = g("xdc0", (r, :othr)) - toi[r]
        xdc[(r, :serv)] = g("xdc0", (r, :serv)) - tse[r]
        for i in ENERGY
            ence[(i, r)] = g("xdc0", (r, i)) + g("xmc0", (r, i))
        end
        ence[(:roil, r)] -= tfo[r]
    end

    # Homogeneous crude oil (eppacalib). Gas is not in X.
    homm0 = Dict{Symbol,Float64}()
    homx0 = Dict{Symbol,Float64}()
    homt0 = Dict{Symbol,Float64}()
    vhomm0 = Dict{Symbol,Float64}()
    vhomx0 = Dict{Symbol,Float64}()
    txhom = Dict{Symbol,Float64}()
    tmhom = Dict{Symbol,Float64}()
    homadj = Dict{Symbol,Float64}()
    trnadj = Dict{Symbol,Float64}()
    for r in REGIONS
        imp = sum(g("wtflow0", (r, rr, :oil)) * (1 + g("tx", (:oil, rr, r))) for rr in REGIONS)
        exp = sum(g("wtflow0", (rr, r, :oil)) * (1 + g("tx", (:oil, r, rr))) for rr in REGIONS)
        homm0[r] = max(0.0, imp - exp)
        homx0[r] = max(0.0, -imp + exp)
        denx = sum(g("wtflow0", (rr, r, :oil)) for rr in REGIONS)
        txhom[r] = denx == 0 ? 0.0 : sum(g("wtflow0", (rr, r, :oil)) * g("tx", (:oil, r, rr)) for rr in REGIONS) / denx
        vhomx0[r] = homx0[r] == 0 ? 0.0 : homx0[r] / (1 + txhom[r])
        denm = sum(g("wtflow0", (r, rr, :oil)) * (1 + g("tx", (:oil, rr, r))) for rr in REGIONS)
        marg = sum(g("vtwr", (:tran, :oil, rr, r)) for rr in REGIONS)
        tmargin = denm == 0 ? 0.0 : marg / denm
        homt0[r] = tmargin * homm0[r]
        den_tm = sum(g("wtflow0", (r, rr, :oil)) * (1 + g("tx", (:oil, rr, r))) + g("vtwr", (:tran, :oil, rr, r)) for rr in REGIONS)
        tmhom[r] = den_tm == 0 ? 0.0 : sum((g("wtflow0", (r, rr, :oil)) * (1 + g("tx", (:oil, rr, r))) + g("vtwr", (:tran, :oil, rr, r))) * g("tm", (:oil, rr, r)) for rr in REGIONS) / den_tm
        vhomm0[r] = (homm0[r] + homt0[r]) * (1 + tmhom[r])
        homadj[r] = a0[(r, :oil)] - (g("xp0", (r, :oil)) + vhomm0[r] - vhomx0[r])
        trnadj[r] = homt0[r] - marg
    end

    # Electricity resource split (elecpower.gms). Mutates local copies of elecin.
    elecin = Dict(k => v for (k, v) in e["elecin"])
    elecint = Dict(k => v for (k, v) in e["elecint"])
    ffact_e = Dict{Tuple{Symbol,Symbol},Float64}()
    nhrsigma = Dict{Tuple{Symbol,Symbol},Float64}()
    kapital = Dict(r => sum(g("kapd0", (r, i)) for i in SECTORS) for r in REGIONS)
    labor = Dict(r => sum(g("labd0", (r, i)) for i in SECTORS) + g("labdg0", (r,)) for r in REGIONS)
    rshr = Dict(:nele => 0.15, :hele => 0.30, :rele => 0.15)
    for r in REGIONS, t in TECH_NHR
        xp = ge("xp0_", (t, r))
        td_ = ge("td_", (r, t))
        cap0 = get(elecin, (t, :cap, r), 0.0)
        lab0 = get(elecin, (t, :lab, r), 0.0)
        tc = get(elecint, (t, :cap, r), 0.0)
        tl = get(elecint, (t, :lab, r), 0.0)
        r0 = (1 + tc) == 0 ? 0.0 : rshr[t] * xp * (1 - td_) / (1 + tc)
        elecinmr0 = cap0 - r0
        zshr = 0.0
        opelec = 1.0
        if elecinmr0 <= 0 && (cap0 + lab0) > 0
            opelec = ((1 + tc) * cap0 + (1 + tl) * lab0) / (cap0 + lab0)
            zshr = min(0.9, xp * (1 - td_) / opelec * rshr[t] / (cap0 + lab0))
        end
        if elecinmr0 > 0
            elecin[(t, :cap, r)] = cap0 - r0
            elecin[(t, :res, r)] = r0
            elecint[(t, :res, r)] = tc
            ffact_e[(t, r)] = r0
            kapital[r] -= r0
        elseif elecinmr0 <= 0 && (cap0 + lab0) > 0
            elecin[(t, :cap, r)] = cap0 * (1 - zshr)
            elecin[(t, :lab, r)] = lab0 * (1 - zshr)
            elecin[(t, :res, r)] = zshr * (cap0 + lab0)
            elecint[(t, :res, r)] = opelec - 1
            ffact_e[(t, r)] = zshr * (cap0 + lab0)
            kapital[r] -= zshr * cap0
            labor[r] -= zshr * lab0
        else
            ffact_e[(t, r)] = 0.0
        end
        res = get(elecin, (t, :res, r), 0.0)
        den = (1 - td_) * xp
        share = den == 0 ? 0.0 : res / den
        eta = get(nhreta, (t, r), 0.0)
        nhrsigma[(t, r)] = (1 - share) == 0 ? 0.0 : eta * share / (1 - share)
    end

    rgdp0 = Dict{Symbol,Float64}()
    for r in REGIONS
        exports = 0.0
        imports = 0.0
        for rr in REGIONS, i in SECTORS
            i == :oil && continue
            exports += (1 + g("tx", (i, r, rr))) * g("wtflow0", (rr, r, i))
            imports += (1 + g("tx", (i, rr, r))) * g("wtflow0", (r, rr, i))
        end
        rgdp0[r] = g("cons0", (r,)) + inv0[r] + g0[r] + exports - imports + homx0[r] - homm0[r]
    end

    # Production identity check (non-electricity GTAP sectors).
    gap = 0.0
    for r in REGIONS, i in SECTORS
        i == :elec && continue
        xp = g("xp0", (r, i))
        xp == 0 && continue
        cost = ffact[(r, i)]
        cost += g("labd0", (r, i)) * (1 + g("tf", (:lab, i, r)))
        cost += g("kapd0", (r, i)) * (1 + g("tf", (:cap, i, r)))
        for j in SECTORS
            cost += (g("xdp0", (r, j, i)) + g("xmp0", (r, j, i))) * (1 + g("ti", (j, i, r)))
        end
        gap = max(gap, abs(xp - g("ptxy0", (r, i)) - cost))
    end
    egap = 0.0
    for r in REGIONS, t in TECH
        xp = ge("xp0_", (t, r))
        xp == 0 && continue
        tdr = ge("td_", (r, t))
        cost = 0.0
        for k in keys(elecin)
            k[1] == t && k[3] == r || continue
            inp = k[2]
            q = elecin[k]
            rate = get(elecint, (t, inp, r), 0.0)
            cost += q * (1 + rate)
        end
        egap = max(egap, abs(xp * (1 - tdr) - cost))
    end
    println("benchmark identity |xp-tax-cost|=", gap, " |elec xp*(1-td)-cost|=", egap)

    return (;
        p, g, ge, REGIONS, SECTORS, hist, ann, pop,
        elas, esup, esube, sigu, delas, cr, wst,
        a0, d0, td, inv0, g0, ffact, xdc, xmc,
        purtrn, tbo, tfo, toi, tse, own, tottrn, ence,
        homm0, homx0, homt0, vhomm0, vhomx0, txhom, tmhom, homadj, trnadj,
        elecin, elecint, ffact_e, nhrsigma, kapital, labor, rgdp0,
    )
end
