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
const AC_SECTORS = [:industry, :htrn, :households]
const EJUSE_SECTORS = [filter(!=(:elec), SECTORS)..., TECH..., :households, :htrn]
const SCO2_ENERGY = [:coal, :gas, :roil]
const SCO2_SECTORS = [filter(!=(:elec), SECTORS)..., TECH..., :households, :htrn]
const PDE_DIM = [:dispgen, TECH_F..., TECH_N..., :tnd]
const NOT_AENOE = [:food, :othr, :serv, :tran, :dwe]

const HTRNS = 0.3753
const PROPFRAC = 0.2
const DPE = 0.05
const ROR = 0.1

"""
    prepare(dat_path, elec_path, satellite)

Build the benchmark accounts for the active v-ref structure.

Vintage capital, backstops, land-use change, Stone-Geary preferences, and
emissions are off. Emission pass-through nests are identities at a zero carbon
price, so energy inputs use `pa` (`phom` for crude oil) directly.

The `(sector, layer, region)` elasticity `noe_el` is tripled, as in `eppaelas.gms`.
The land tax is capitalized into the fixed-factor quantity, as in `eppaparm`.
Household transport is extracted from final demand, as in `eppacalib`. Crude oil
is treated as one homogeneous good; gas is not. The electricity resource split
follows `elecpower.gms` and rewrites local copies of `elecin`. A production
identity is checked for the non-electricity GTAP sectors.
"""
function prepare(dat_path, elec_path, satellite)
    _pt(msg) = (println("prepare: ", msg); flush(stdout))
    raw = load_prepare_inputs(dat_path, elec_path, satellite)
    p = raw.p
    xa0 = p["xa0"]
    e = raw.e
    g = raw.g
    ge = raw.ge
    selas = raw.selas
    esup = raw.esup
    esube = raw.esube
    sigu = raw.sigu
    delas = raw.delas
    crtable = raw.crtable
    bio = raw.bio
    nhreta = raw.nhreta
    wst = raw.wst
    os = raw.os
    esh = raw.esh
    mvh = raw.mvh
    ej_use_iea = raw.ej_use_iea
    eprod_iea = raw.eprod_iea
    epslon_raw = raw.epslon_raw
    hist = raw.hist
    ann = raw.ann
    pop = raw.pop
    aeeigr_raw = raw.aeeigr_raw

    elas(g, layer, r) = get(selas, (g, layer, r), 0.0)
    function cr(i, g, r)
        i == :roil || return 1.0
        val = get(crtable, (g, r), 0.0)
        return val == 0.0 ? 1.0 : val
    end
    epslon_map = Dict{Symbol,Float64}()
    for e in SCO2_ENERGY
        vals = [v for (k, v) in epslon_raw if !isempty(k) && first(k) == e]
        length(vals) == 1 || error("expected exactly one emissions coefficient for $(e) in other_epslon, got $(length(vals))")
        epslon_map[e] = vals[1]
    end
    epslon(e) = epslon_map[e]

    aeeigr = Dict{Tuple{Symbol,Symbol},Float64}()
    aeei = Dict{Tuple{Symbol,Symbol},Float64}()
    sco2coef = Dict{Symbol,Float64}()
    for r in REGIONS, i in SECTORS
        aeeigr[(i, r)] = get(aeeigr_raw, (i, r), get(aeeigr_raw, (r, i), 0.0))
        aeei[(i, r)] = 1.0
    end
    for e in SCO2_ENERGY
        sco2coef[e] = 100 * (44 / 12) * epslon(e)
    end

    _pt("start benchmark calibration assembly")
    t_assemble = @elapsed begin
    ffact = Dict{Tuple{Symbol,Symbol},Float64}()
    ffend0 = Dict{Tuple{Symbol,Symbol},Float64}()
    ffgprod0 = Dict{Tuple{Symbol,Symbol},Float64}()
    labd0 = Dict(k => v for (k, v) in p["labd0"])
    kapd0 = Dict(k => v for (k, v) in p["kapd0"])
    xaroila = Dict{Tuple{Symbol,Symbol},Float64}()
    xaroilc = Dict{Tuple{Symbol,Symbol},Float64}()
    for r in REGIONS, i in SECTORS
        ffact[(r, i)] = g("ffactd0", (r, i)) * (1 + g("tf", (:lnd, i, r)))
        ffend0[(r, i)] = i in FF ? ffact[(r, i)] : 0.0
        ffgprod0[(r, i)] = i in FF ? 0.0 : ffact[(r, i)]
    end

    a0 = Dict{Tuple{Symbol,Symbol},Float64}()
    d0 = Dict{Tuple{Symbol,Symbol},Float64}()
    dout_pd = Dict{Tuple{Symbol,Symbol},Float64}()
    dout_pdb = Dict{Tuple{Symbol,Symbol},Float64}()
    dout_phom = Dict{Tuple{Symbol,Symbol},Float64}()
    td = Dict{Tuple{Symbol,Symbol},Float64}()
    cons0 = Dict{Symbol,Float64}()
    inv0 = Dict{Symbol,Float64}()
    g0 = Dict{Symbol,Float64}()
    pwdem0 = Dict{Symbol,Float64}()
    govdem0 = Dict{Tuple{Symbol,Symbol},Float64}()
    govoil0 = Dict{Symbol,Float64}()
    invdem0 = Dict{Tuple{Symbol,Symbol},Float64}()
    invoil0 = Dict{Symbol,Float64}()
    trnvst0 = Dict{Symbol,Float64}()
    ytout0 = 0.0
    for r in REGIONS
        cons0[r] = g("cons0", (r,))
        inv0[r] = sum(g("xdi0", (r, i)) + g("xmi0", (r, i)) for i in SECTORS)
        pwdem0[r] = cons0[r] + inv0[r]
        govoil0[r] = g("xdg0", (r, :oil)) + g("xmg0", (r, :oil))
        invoil0[r] = g("xdi0", (r, :oil)) + g("xmi0", (r, :oil))
        trnvst0[r] = g("vst", (:tran, r))
        ytout0 += trnvst0[r]
        g0[r] = g("kapdg0", (r,)) + g("labdg0", (r,)) + g("trg0", (r,)) +
                sum(g("xdg0", (r, i)) + g("xmg0", (r, i)) for i in SECTORS)
        for i in SECTORS
            a0[(r, i)] = g("xp0", (r, i)) - g("es0", (r, i)) + g("xm0", (r, i)) - g("vst", (i, r))
            d0[(r, i)] = g("xp0", (r, i)) - g("es0", (r, i)) - g("vst", (i, r))
            xp = g("xp0", (r, i))
            dout_pd[(r, i)] = xp
            dout_pdb[(r, i)] = 0.0
            dout_phom[(r, i)] = 0.0
            if i == :oil
                dout_pd[(r, i)] = 0.0
                dout_phom[(r, i)] = xp
            end
            td[(r, i)] = xp == 0 ? 0.0 : g("ptxy0", (r, i)) / xp
            govdem0[(r, i)] = i == :oil ? 0.0 : g("xdg0", (r, i)) + g("xmg0", (r, i))
            invdem0[(r, i)] = i == :oil ? 0.0 : g("xdi0", (r, i)) + g("xmi0", (r, i))
            labd0[(r, i)] = get(labd0, (r, i), 0.0)
            kapd0[(r, i)] = get(kapd0, (r, i), 0.0)
            xaroil = get(xa0, (r, :roil, i), 0.0)
            xaroila[(r, i)] = xaroil * (1 - cr(:roil, i, r))
            xaroilc[(r, i)] = xaroil * cr(:roil, i, r)
            for j in SECTORS
                xa0[(r, j, i)] = get(xa0, (r, j, i), 0.0)
            end
        end
    end
    xm0 = Dict(k => v for (k, v) in p["xm0"])
    wtflow = Dict(k => v for (k, v) in p["wtflow0"])
    mvtwr = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    for r in REGIONS, i in SECTORS
        xm0[(r, i)] = get(xm0, (r, i), 0.0)
        for rr in REGIONS
            wtflow[(r, rr, i)] = get(wtflow, (r, rr, i), 0.0)
        end
    end

    xdc = Dict(k => v for (k, v) in p["xdc0"])
    xmc = Dict(k => v for (k, v) in p["xmc0"])
    purtrn = Dict{Symbol,Float64}()
    tbo = Dict{Symbol,Float64}()
    tfo = Dict{Symbol,Float64}()
    toi = Dict{Symbol,Float64}()
    tse = Dict{Symbol,Float64}()
    own = Dict{Symbol,Float64}()
    hhwedge = Dict{Symbol,Float64}()
    tottrn = Dict{Symbol,Float64}()
    xh = Dict{Tuple{Symbol,Symbol},Float64}()
    ence = Dict{Tuple{Symbol,Symbol},Float64}()
    encep = Dict{Tuple{Symbol,Symbol},Float64}()
    pac0 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
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
        hhwedge[r] = (pcR - g("pc0", (foodp, r))) * tbo[r]
        xdc[(r, :roil)] = g("xdc0", (r, :roil)) - tfo[r]
        xdc[(r, foodp)] = g("xdc0", (r, foodp)) - tbo[r]
        xdc[(r, :othr)] = g("xdc0", (r, :othr)) - toi[r]
        xdc[(r, :serv)] = g("xdc0", (r, :serv)) - tse[r]
        for i in NENDT
            xh[(i, r)] = max(get(xdc, (r, i), 0.0) + get(xmc, (r, i), 0.0), 0.0)
        end
        xh[(:dwe, r)] = max(get(xdc, (r, :dwe), 0.0) + get(xmc, (r, :dwe), 0.0), 0.0)
        for i in ENERGY
            ence[(i, r)] = g("xdc0", (r, i)) + g("xmc0", (r, i))
        end
        ence[(:roil, r)] -= tfo[r]
        for i in ENERGY
            encep[(i, r)] = max(ence[(i, r)], 0.0)
        end
    end

    for r in REGIONS
        dout_pd[(r, :food)] -= tbo[r]
        dout_pdb[(r, :food)] = tbo[r]
        if r == :bra
            dout_pd[(r, :food)] += tbo[r]
            dout_pdb[(r, :food)] = 0.0
            dout_pd[(r, :eint)] -= tbo[r]
            dout_pdb[(r, :eint)] = tbo[r]
        end
    end

    armqout = Dict{Tuple{Symbol,Symbol},Float64}()
    armqdom = Dict{Tuple{Symbol,Symbol},Float64}()
    for r in REGIONS, i in SECTORS
        armqout[(r, i)] = a0[(r, i)]
        armqdom[(r, i)] = d0[(r, i)]
        if (i == :food && r != :bra) || (i == :eint && r == :bra)
            armqout[(r, i)] -= tbo[r]
            armqdom[(r, i)] -= tbo[r]
        end
        for rr in REGIONS
            mvtwr[(r, rr, i)] = sum(g("vtwr", (j, i, rr, r)) for j in SECTORS)
        end
    end


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

    elecin = Dict(k => v for (k, v) in e["elecin"])
    elecint = Dict(k => v for (k, v) in e["elecint"])
    ffact_e = Dict{Tuple{Symbol,Symbol},Float64}()
    nhrsigma = Dict{Tuple{Symbol,Symbol},Float64}()
    elexp0 = Dict{Symbol,Float64}()
    sele0 = Dict{Symbol,Float64}()
    dispgen0 = Dict{Symbol,Float64}()
    wele0 = Dict{Symbol,Float64}()
    tele0 = Dict{Symbol,Float64}()
    efout0 = Dict{Symbol,Float64}()
    techxp0 = Dict{Tuple{Symbol,Symbol},Float64}()
    sav0 = Dict{Symbol,Float64}()
    eesec0 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    eusecoef0 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    eeseccoef = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
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

    for r in REGIONS, t in TECH, inp in (NE..., :oil, :gas, :coal, :elec, :roil, :lab, :cap, :res)
        elecin[(t, inp, r)] = get(elecin, (t, inp, r), 0.0)
        elecint[(t, inp, r)] = get(elecint, (t, inp, r), 0.0)
    end

    gv = g
    ejadj = Dict{Tuple{Symbol,Symbol},Float64}()
    sco20 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    for r in REGIONS
        coalden = sum(gv("eind", (:coal, g, r)) for g in SECTORS) + gv("efd", (:coal, r))
        gasden = sum(gv("eind", (:gas, g, r)) for g in SECTORS) + gv("efd", (:gas, r))
        oilden = sum(gv("eind", (:oil, g, r)) for g in SECTORS) + gv("efd", (:oil, r))
        elecden = sum(gv("eind", (:elec, g, r)) for g in SECTORS) + gv("efd", (:elec, r))
        elecnum = sum(get(eprod_iea, (t, r), 0.0) for t in TECH)
        ejadj[(:coal, r)] = coalden == 0 ? 1.0 : get(ej_use_iea, (:coal, r), 0.0) / coalden
        ejadj[(:gas, r)] = gasden == 0 ? 1.0 : get(ej_use_iea, (:gas, r), 0.0) / gasden
        oiladj = oilden == 0 ? 1.0 : get(ej_use_iea, (:oil, r), 0.0) / oilden
        ejadj[(:oil, r)] = oiladj
        ejadj[(:roil, r)] = oiladj
        ejadj[(:elec, r)] = elecden == 0 ? 1.0 : elecnum / elecden
    end

    for r in REGIONS, g in SECTORS, e in ENERGY
        eesec0[(e, g, r)] = ejadj[(e, r)] * gv("eind", (e, g, r)) * (e == :roil ? cr(:roil, g, r) : 1.0)
        if g == :elec
            eusecoef0[(e, g, r)] = sum(elecin[(t, e, r)] for t in TECH)
        else
            eusecoef0[(e, g, r)] = xa0[(r, e, g)]
        end
        denom = eusecoef0[(e, g, r)]
        eeseccoef[(e, g, r)] = denom == 0 ? 0.0 : eesec0[(e, g, r)] / denom
    end

    for r in REGIONS, e in ENERGY
        eesec0[(e, :households, r)] = ejadj[(e, r)] * (e == :roil ? (1 - os[r]) * gv("efd", (:roil, r)) * cr(:roil, :final, r) : gv("efd", (e, r)))
        eesec0[(e, :htrn, r)] = ejadj[(e, r)] * (e == :roil ? os[r] * gv("efd", (:roil, r)) * cr(:roil, :final, r) : 0.0)
        eusecoef0[(e, :households, r)] = encep[(e, r)]
        eusecoef0[(e, :htrn, r)] = e == :roil ? tfo[r] : 0.0
        denom = eusecoef0[(e, :households, r)]
        eeseccoef[(e, :households, r)] = denom == 0 ? 0.0 : eesec0[(e, :households, r)] / denom
        denom = eusecoef0[(e, :htrn, r)]
        eeseccoef[(e, :htrn, r)] = denom == 0 ? 0.0 : eesec0[(e, :htrn, r)] / denom
    end

    for r in REGIONS, i_ in TECH, e in ENERGY
        eesec0[(e, i_, r)] = e == :roil ? eeseccoef[(e, :elec, r)] * elecin[(i_, :roil, r)] : eeseccoef[(e, :elec, r)] * elecin[(i_, e, r)]
        eusecoef0[(e, i_, r)] = e == :roil ? elecin[(i_, :roil, r)] * cr(:roil, :elec, r) : elecin[(i_, e, r)]
        denom = eusecoef0[(e, i_, r)]
        eeseccoef[(e, i_, r)] = denom == 0 ? 0.0 : eesec0[(e, i_, r)] / denom
    end

    for r in REGIONS, e in ENERGY
        industry = 0.0
        for g in SECTORS
            g == :elec && continue
            industry += e == :roil ? xaroilc[(r, g)] : xa0[(r, e, g)]
        end
        industry += e == :roil ? sum(elecin[(t, :roil, r)] * cr(:roil, :elec, r) for t in TECH) : sum(elecin[(t, e, r)] for t in TECH)
        pac0[(e, :industry, r)] = industry
        pac0[(e, :households, r)] = e == :roil ? encep[(e, r)] * cr(:roil, :final, r) : encep[(e, r)]
        pac0[(e, :htrn, r)] = e == :roil ? tfo[r] * cr(:roil, :final, r) : 0.0
    end

    for r in REGIONS
        elexp0[r] = g("xp0", (r, :elec))
        sele0[r] = ge("xp0_", (:sele, r))
        dispgen0[r] = sum(ge("xp0_", (i_, r)) for i_ in TECH_D)
        wele0[r] = ge("xp0_", (:wele, r))
        tele0[r] = ge("xp0_", (:tele, r))
        efout0[r] = sum(ge("xp0_", (i_, r)) for i_ in TECH_F)
        for i_ in TECH
            techxp0[(i_, r)] = ge("xp0_", (i_, r))
        end
    end

    rgdp0 = Dict{Symbol,Float64}()
    for r in REGIONS
        sav0[r] = g("savf0", (r,))
        for t in TECH_NHR
            ffact_e[(t, r)] = get(ffact_e, (t, r), 0.0)
        end
    end

    for r in REGIONS
        exports = 0.0
        imports = 0.0
        for rr in REGIONS, i in SECTORS
            i == :oil && continue
            exports += (1 + g("tx", (i, r, rr))) * g("wtflow0", (rr, r, i))
            imports += (1 + g("tx", (i, rr, r))) * g("wtflow0", (r, rr, i))
        end
        rgdp0[r] = cons0[r] + inv0[r] + g0[r] + exports - imports + homx0[r] - homm0[r]
    end

    gap = 0.0
    for r in REGIONS, i in SECTORS
        i == :elec && continue
        xp = g("xp0", (r, i))
        xp == 0 && continue
        cost = ffact[(r, i)]
        cost += g("labd0", (r, i)) * (1 + g("tf", (:lab, i, r)))
        cost += g("kapd0", (r, i)) * (1 + g("tf", (:cap, i, r)))
        for j in SECTORS
            cost += g("xa0", (r, j, i)) * (1 + g("ti", (j, i, r)))
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

    for r in REGIONS, g in SECTORS
        g == :elec && continue
        for e in SCO2_ENERGY
            sco20[(e, g, r)] = sco2coef[e] * eesec0[(e, g, r)]
        end
    end

    for r in REGIONS, i_ in TECH, e in SCO2_ENERGY
        sco20[(e, i_, r)] = sco2coef[e] * eesec0[(e, i_, r)]
    end

    for r in REGIONS, e in SCO2_ENERGY
        sco20[(e, :households, r)] = sco2coef[e] * eesec0[(e, :households, r)]
        sco20[(e, :htrn, r)] = sco2coef[e] * eesec0[(e, :htrn, r)]
    end

    end
    _pt("finished benchmark calibration assembly in $(round(t_assemble; digits = 2)) s")
    return (;
        p, g, ge, REGIONS, SECTORS, hist, ann, pop,
        elas, esup, esube, sigu, delas, cr, wst,
        a0, d0, dout_pd, dout_pdb, dout_phom, td, cons0, inv0, g0, pwdem0, govdem0, govoil0, invdem0, invoil0, ytout0, trnvst0, ffact, ffend0, ffgprod0, xa0, xaroila, xaroilc, labd0, kapd0,
        xdc, xmc, xm0, wtflow, mvtwr, armqout, armqdom,
        purtrn, tbo, tfo, toi, tse, own, hhwedge, tottrn, xh, ence, encep, pac0,
        homm0, homx0, homt0, vhomm0, vhomx0, txhom, tmhom, homadj, trnadj,
        elecin, elecint, ffact_e, nhrsigma, elexp0, sele0, dispgen0, wele0, tele0, efout0, techxp0, sav0, aeeigr, aeei, eesec0, eusecoef0, eeseccoef, sco2coef, sco20, kapital, labor, rgdp0,
    )
end

"""
    replication_error(calib_path, sim_path)

Largest gaps between a `simu = 0` workbook and a `simu = 1` workbook.

Returns the maximum absolute `gprod` gap, the maximum relative `rgdp` gap, and
the maximum relative gap between the `simu = 1` GDP and the calibration target.
"""
function replication_error(calib_path, sim_path)
    loadrows(p) = begin
        outd = Dict{Tuple{Int,Symbol},NamedTuple}()
        XLSX.openxlsx(p) do xf
            sh = xf["solve_status"]
            dim = XLSX.get_dimension(sh)
            last = dim === nothing ? 1 : dim.stop.row_number
            for i in 2:last
                y = sh[i, 1]
                r = sh[i, 2]
                g = sh[i, 3]
                rg = sh[i, 4]
                tg = sh[i, 5]
                if isnothing(y) || isnothing(r)
                    continue
                end
                outd[(Int(y), Symbol(r))] = (
                    gprod = Float64(g),
                    rgdp = Float64(rg),
                    target = Float64(tg),
                )
            end
        end
        return outd
    end
    a = loadrows(calib_path)
    b = loadrows(sim_path)
    dprod = 0.0
    dgdp = 0.0
    dtarget = 0.0
    for (k, va) in a
        vb = b[k]
        dprod = max(dprod, abs(vb.gprod - va.gprod))
        dgdp = max(dgdp, abs(vb.rgdp / va.rgdp - 1))
        dtarget = max(dtarget, abs(vb.rgdp / va.target - 1))
    end
    return dprod, dgdp, dtarget
end





