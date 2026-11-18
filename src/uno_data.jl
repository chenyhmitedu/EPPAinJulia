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
const EJUSE_SECTORS = [filter(!=(:elec), SECTORS)..., TECH..., :households, :htrn]
const SCO2_ENERGY = [:coal, :gas, :roil]
const SCO2_SECTORS = [filter(!=(:elec), SECTORS)..., TECH..., :households, :htrn]
const PDE_DIM = [:dispgen, TECH_F..., TECH_N..., :tnd]
const NOT_AENOE = [:food, :othr, :serv, :tran, :dwe]
const LCR = [:lab, :cap, :res]

const HTRNS = 0.3753
const PROPFRAC = 0.2
const DPE = 0.05
const ROR = 0.1

"""
    prepare(source)

Build the benchmark accounts for the active v-ref structure. `source` is the
object returned by `load_data`.

Vintage capital, backstops, land-use change, Stone-Geary preferences, and
emissions are off. Emission pass-through nests are identities at a zero carbon
price, so energy inputs use `pa` (`phom` for crude oil) directly.

The `(sector, layer, region)` elasticity `noe_el` is tripled, as in `eppaelas.gms`.
The land tax is capitalized into the fixed-factor quantity, as in `eppaparm`.
Household transport is extracted from final demand, as in `eppacalib`. Crude oil
is treated as one homogeneous good; gas is not. The electricity resource split
follows `elecpower.gms` and rewrites local copies of `elecin`. A production
identity is checked for the non-electricity GTAP sectors. Solve periods are
the GAMS set on the `other_period` sheet.
"""
function prepare(source)
    raw = load_prepare_inputs(source)
    set_model_years!(raw.years)
    println("periods ", join(YEARS, " "))
    p = raw.p
    xa0 = p["xa0"]
    elec = raw.e
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
    epslon_raw = raw.epslon_raw
    ann = raw.ann
    pop = raw.pop
    aeeigr_raw = raw.aeeigr_raw
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

    ffact = Dict{Tuple{Symbol,Symbol},Float64}()
    ffend0 = Dict{Tuple{Symbol,Symbol},Float64}()
    ffgprod0 = Dict{Tuple{Symbol,Symbol},Float64}()
    labd0 = Dict(k => v for (k, v) in p["labd0"])
    kapd0 = Dict(k => v for (k, v) in p["kapd0"])
    xaroila = Dict{Tuple{Symbol,Symbol},Float64}()
    xaroilc = Dict{Tuple{Symbol,Symbol},Float64}()
    for r in REGIONS, i in SECTORS
        ffact[(r, i)] = get(p["ffactd0"], (r, i), 0.0) * (1 + get(p["tf"], (:lnd, i, r), 0.0))
        ffend0[(r, i)] = i in FF ? ffact[(r, i)] : 0.0
        ffgprod0[(r, i)] = i in FF ? 0.0 : ffact[(r, i)]
    end

    a0 = Dict{Tuple{Symbol,Symbol},Float64}()
    xp0 = Dict{Tuple{Symbol,Symbol},Float64}()
    d0 = Dict{Tuple{Symbol,Symbol},Float64}()
    xp0_pdb = Dict{Tuple{Symbol,Symbol},Float64}()
    xp0_phom = Dict{Tuple{Symbol,Symbol},Float64}()
    td = Dict{Tuple{Symbol,Symbol},Float64}()
    td_ = Dict{Tuple{Symbol,Symbol},Float64}()
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
        cons0[r] = get(p["cons0"], (r,), 0.0)
        inv0[r] = sum(get(p["xdi0"], (r, i), 0.0) + get(p["xmi0"], (r, i), 0.0) for i in SECTORS)
        pwdem0[r] = cons0[r] + inv0[r]
        govoil0[r] = get(p["xdg0"], (r, :oil), 0.0) + get(p["xmg0"], (r, :oil), 0.0)
        invoil0[r] = get(p["xdi0"], (r, :oil), 0.0) + get(p["xmi0"], (r, :oil), 0.0)
        trnvst0[r] = get(p["vst"], (:tran, r), 0.0)
        ytout0 += trnvst0[r]
        g0[r] = get(p["kapdg0"], (r,), 0.0) + get(p["labdg0"], (r,), 0.0) + get(p["trg0"], (r,), 0.0) +
                sum(get(p["xdg0"], (r, i), 0.0) + get(p["xmg0"], (r, i), 0.0) for i in SECTORS)
        for i in SECTORS
            a0[(r, i)] = get(p["xp0"], (r, i), 0.0) - get(p["es0"], (r, i), 0.0) + get(p["xm0"], (r, i), 0.0) - get(p["vst"], (i, r), 0.0)
            d0[(r, i)] = get(p["xp0"], (r, i), 0.0) - get(p["es0"], (r, i), 0.0) - get(p["vst"], (i, r), 0.0)
            xp = get(p["xp0"], (r, i), 0.0)
            xp0[(r, i)] = xp
            xp0_pdb[(r, i)] = 0.0
            xp0_phom[(r, i)] = 0.0
            if i == :oil
                xp0[(r, i)] = 0.0
                xp0_phom[(r, i)] = xp
            end
            td[(r, i)] = xp == 0 ? 0.0 : get(p["ptxy0"], (r, i), 0.0) / xp
            govdem0[(r, i)] = i == :oil ? 0.0 : get(p["xdg0"], (r, i), 0.0) + get(p["xmg0"], (r, i), 0.0)
            invdem0[(r, i)] = i == :oil ? 0.0 : get(p["xdi0"], (r, i), 0.0) + get(p["xmi0"], (r, i), 0.0)
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

    for r in REGIONS, t in TECH
        td_[(r, t)] = get(elec["td_"], (r, t), 0.0)
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
    ence1 = Dict{Tuple{Symbol,Symbol},Float64}()
    pac0 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    for r in REGIONS
        purtrn[r] = get(p["xdc0"], (r, :tran), 0.0) + get(p["xmc0"], (r, :tran), 0.0)
        xdc[(r, :tran)] = 0.0
        xmc[(r, :tran)] = 0.0
        ence0 = get(p["xdc0"], (r, :roil), 0.0) + get(p["xmc0"], (r, :roil), 0.0)
        efd = get(p["efd"], (:roil, r), 0.0)
        pbio = efd == 0 ? 0.0 : ence0 / efd
        ebio = pbio * get(bio, (r, Symbol("bio-fg")), 0.0)
        pcR = get(p["pc0"], (:roil, r), 0.0)
        tbo[r] = pcR == 0 ? 0.0 : ebio / pcR
        tfo[r] = os[r] * ence0
        toi[r] = mvh[r]
        owntrn = esh[r] * get(p["cons0"], (r,), 0.0)
        foodp = r == :bra ? :eint : :food
        tottrn[r] = purtrn[r] * get(p["pc0"], (:tran, r), 0.0) + owntrn + (pcR - get(p["pc0"], (foodp, r), 0.0)) * tbo[r]
        tse[r] = (owntrn - tfo[r] * pcR - toi[r] * get(p["pc0"], (:othr, r), 0.0) - tbo[r] * get(p["pc0"], (foodp, r), 0.0)) / get(p["pc0"], (:serv, r), 0.0)
        own[r] = pcR * (tfo[r] + tbo[r]) + get(p["pc0"], (:othr, r), 0.0) * toi[r] + get(p["pc0"], (:serv, r), 0.0) * tse[r]
        hhwedge[r] = (pcR - get(p["pc0"], (foodp, r), 0.0)) * tbo[r]
        xdc[(r, :roil)] = get(p["xdc0"], (r, :roil), 0.0) - tfo[r]
        xdc[(r, foodp)] = get(p["xdc0"], (r, foodp), 0.0) - tbo[r]
        xdc[(r, :othr)] = get(p["xdc0"], (r, :othr), 0.0) - toi[r]
        xdc[(r, :serv)] = get(p["xdc0"], (r, :serv), 0.0) - tse[r]
        for i in NENDT
            xh[(i, r)] = max(get(xdc, (r, i), 0.0) + get(xmc, (r, i), 0.0), 0.0)
        end
        xh[(:dwe, r)] = max(get(xdc, (r, :dwe), 0.0) + get(xmc, (r, :dwe), 0.0), 0.0)
        for i in ENERGY
            ence[(i, r)] = get(p["xdc0"], (r, i), 0.0) + get(p["xmc0"], (r, i), 0.0)
        end
        ence[(:roil, r)] -= tfo[r]
        for i in ENERGY
            ence1[(i, r)] = max(ence[(i, r)], 0.0)
        end
    end

    for r in REGIONS
        xp0[(r, :food)] -= tbo[r]
        xp0_pdb[(r, :food)] = tbo[r]
        if r == :bra
            xp0[(r, :food)] += tbo[r]
            xp0_pdb[(r, :food)] = 0.0
            xp0[(r, :eint)] -= tbo[r]
            xp0_pdb[(r, :eint)] = tbo[r]
        end
    end

    xat0 = Dict{Tuple{Symbol,Symbol},Float64}()
    xd0 = Dict{Tuple{Symbol,Symbol},Float64}()
    for r in REGIONS, i in SECTORS
        xat0[(r, i)] = a0[(r, i)]
        xd0[(r, i)] = d0[(r, i)]
        if (i == :food && r != :bra) || (i == :eint && r == :bra)
            xat0[(r, i)] -= tbo[r]
            xd0[(r, i)] -= tbo[r]
        end
        for rr in REGIONS
            mvtwr[(r, rr, i)] = sum(get(p["vtwr"], (j, i, rr, r), 0.0) for j in SECTORS)
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
        imp = sum(get(p["wtflow0"], (r, rr, :oil), 0.0) * (1 + get(p["tx"], (:oil, rr, r), 0.0)) for rr in REGIONS)
        exp = sum(get(p["wtflow0"], (rr, r, :oil), 0.0) * (1 + get(p["tx"], (:oil, r, rr), 0.0)) for rr in REGIONS)
        homm0[r] = max(0.0, imp - exp)
        homx0[r] = max(0.0, -imp + exp)
        denx = sum(get(p["wtflow0"], (rr, r, :oil), 0.0) for rr in REGIONS)
        txhom[r] = denx == 0 ? 0.0 : sum(get(p["wtflow0"], (rr, r, :oil), 0.0) * get(p["tx"], (:oil, r, rr), 0.0) for rr in REGIONS) / denx
        vhomx0[r] = homx0[r] == 0 ? 0.0 : homx0[r] / (1 + txhom[r])
        denm = sum(get(p["wtflow0"], (r, rr, :oil), 0.0) * (1 + get(p["tx"], (:oil, rr, r), 0.0)) for rr in REGIONS)
        marg = sum(get(p["vtwr"], (:tran, :oil, rr, r), 0.0) for rr in REGIONS)
        tmargin = denm == 0 ? 0.0 : marg / denm
        homt0[r] = tmargin * homm0[r]
        den_tm = sum(get(p["wtflow0"], (r, rr, :oil), 0.0) * (1 + get(p["tx"], (:oil, rr, r), 0.0)) + get(p["vtwr"], (:tran, :oil, rr, r), 0.0) for rr in REGIONS)
        tmhom[r] = den_tm == 0 ? 0.0 : sum((get(p["wtflow0"], (r, rr, :oil), 0.0) * (1 + get(p["tx"], (:oil, rr, r), 0.0)) + get(p["vtwr"], (:tran, :oil, rr, r), 0.0)) * get(p["tm"], (:oil, rr, r), 0.0) for rr in REGIONS) / den_tm
        vhomm0[r] = (homm0[r] + homt0[r]) * (1 + tmhom[r])
        homadj[r] = a0[(r, :oil)] - (get(p["xp0"], (r, :oil), 0.0) + vhomm0[r] - vhomx0[r])
        trnadj[r] = homt0[r] - marg
    end

    elecin = Dict(k => v for (k, v) in elec["elecin"])
    elecint = Dict(k => v for (k, v) in elec["elecint"])
    ffact_e = Dict{Tuple{Symbol,Symbol},Float64}()
    nhrsigma = Dict{Tuple{Symbol,Symbol},Float64}()
    sele0 = Dict{Symbol,Float64}()
    dispgen0 = Dict{Symbol,Float64}()
    wele0 = Dict{Symbol,Float64}()
    tele0 = Dict{Symbol,Float64}()
    efout0 = Dict{Symbol,Float64}()
    xp0_ = Dict{Tuple{Symbol,Symbol},Float64}()
    eprod__over_xp0_ = Dict{Tuple{Symbol,Symbol},Float64}()
    eprod_over_xp0 = Dict{Symbol,Float64}()
    sav0 = Dict{Symbol,Float64}()
    ejuse0 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    ejuse_all0 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    ejuse_all = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    ejuse = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    euse0 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    ejuse_over_euse = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    kapital = Dict(r => sum(get(p["kapd0"], (r, i), 0.0) for i in SECTORS) for r in REGIONS)
    labor = Dict(r => sum(get(p["labd0"], (r, i), 0.0) for i in SECTORS) + get(p["labdg0"], (r,), 0.0) for r in REGIONS)
    rshr = Dict(:nele => 0.15, :hele => 0.30, :rele => 0.15)
    for r in REGIONS, t in TECH_NHR
        xp = get(elec["xp0_"], (t, r), 0.0)
        tdr = td_[(r, t)]
        cap0 = get(elecin, (t, :cap, r), 0.0)
        lab0 = get(elecin, (t, :lab, r), 0.0)
        tc = get(elecint, (t, :cap, r), 0.0)
        tl = get(elecint, (t, :lab, r), 0.0)
        r0 = (1 + tc) == 0 ? 0.0 : rshr[t] * xp * (1 - tdr) / (1 + tc)
        elecinmr0 = cap0 - r0
        zshr = 0.0
        opelec = 1.0
        if elecinmr0 <= 0 && (cap0 + lab0) > 0
            opelec = ((1 + tc) * cap0 + (1 + tl) * lab0) / (cap0 + lab0)
            zshr = min(0.9, xp * (1 - tdr) / opelec * rshr[t] / (cap0 + lab0))
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
        den = (1 - tdr) * xp
        share = den == 0 ? 0.0 : res / den
        eta = get(nhreta, (t, r), 0.0)
        nhrsigma[(t, r)] = (1 - share) == 0 ? 0.0 : eta * share / (1 - share)
    end

    for r in REGIONS, t in TECH, inp in (NE..., :oil, :gas, :coal, :elec, :roil, :lab, :cap, :res)
        elecin[(t, inp, r)] = get(elecin, (t, inp, r), 0.0)
        elecint[(t, inp, r)] = get(elecint, (t, inp, r), 0.0)
    end

    ejadj = Dict{Tuple{Symbol,Symbol},Float64}()
    sco20 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()

    for r in REGIONS, g in SECTORS, e in ENERGY
        g == :elec && continue      # && evaluates the right-hand side only if the left-hand side is true
        ejuse0[(e, g, r)] = get(p["eind"], (e, g, r), 0.0) * (e == :roil ? cr(:roil, g, r) : 1.0)
        ejuse_all0[(e, g, r)] = get(p["eind"], (e, g, r), 0.0)
        euse0[(e, g, r)] = xa0[(r, e, g)]
        ejuse_over_euse[(e, g, r)] = 0.0
    end

    for r in REGIONS, e in ENERGY
        ejuse0[(e, :households, r)] = e == :roil ? (1 - os[r]) * get(p["efd"], (:roil, r), 0.0) * cr(:roil, :final, r) : get(p["efd"], (e, r), 0.0)
        ejuse0[(e, :htrn, r)] = e == :roil ? os[r] * get(p["efd"], (:roil, r), 0.0) * cr(:roil, :final, r) : 0.0
        ejuse_all0[(e, :households, r)] = e == :roil ? (1 - os[r]) * get(p["efd"], (:roil, r), 0.0) : get(p["efd"], (e, r), 0.0)
        ejuse_all0[(e, :htrn, r)] = e == :roil ? os[r] * get(p["efd"], (:roil, r), 0.0) : 0.0
        euse0[(e, :households, r)] = ence1[(e, r)]
        euse0[(e, :htrn, r)] = e == :roil ? tfo[r] : 0.0
        ejuse_over_euse[(e, :households, r)] = 0.0
        ejuse_over_euse[(e, :htrn, r)] = 0.0
    end

    for r in REGIONS, e in ENERGY
        elec_use = get(p["eind"], (e, :elec, r), 0.0) * (e == :roil ? cr(:roil, :elec, r) : 1.0)
        elec_use_all = get(p["eind"], (e, :elec, r), 0.0)
        fuel_in = sum(elecin[(i_, e, r)] for i_ in TECH)
        share = fuel_in == 0 ? 0.0 : elec_use / fuel_in
        share_all = fuel_in == 0 ? 0.0 : elec_use_all / fuel_in
        for i_ in TECH
            q = elecin[(i_, e, r)]
            euse0[(e, i_, r)] = e == :roil ? q * cr(:roil, :elec, r) : q
            ejuse0[(e, i_, r)] = share * q
            ejuse_all0[(e, i_, r)] = share_all * q
            ejuse_over_euse[(e, i_, r)] = 0.0
        end
    end

    ej_use_iea_level(e, r) = begin
        haskey(ej_use_iea, (e, r)) && return ej_use_iea[(e, r)]
        e == :roil && return get(ej_use_iea, (:oil, r), 0.0)
        return 0.0
    end
    for r in REGIONS, e in ENERGY
        total = e == :roil ?
            sum(ejuse_all0[(:oil, g, r)] for g in EJUSE_SECTORS) :
            sum(ejuse_all0[(e, g, r)] for g in EJUSE_SECTORS)
        ejadj[(e, r)] = e == :elec ? 1.0 : (total == 0 ? 0.0 : ej_use_iea_level(e, r) / total)
    end

    ejadj_level(e, r) = ejadj[(e, r)]
    for (key, value) in ejuse0
        e, _, r = key
        ejuse[key] = value * ejadj_level(e, r)
    end
    for (key, value) in ejuse_all0
        e, _, r = key
        ejuse_all[key] = value * ejadj_level(e, r)
    end
    for (key, value) in euse0
        ejuse_over_euse[key] = value == 0 ? 0.0 : ejuse[key] / value
    end

    for r in REGIONS, e in ENERGY
        for g in SECTORS
            g == :elec && continue
            pac0[(e, g, r)] = e == :roil ? xaroilc[(r, g)] : xa0[(r, e, g)]
        end
        for t in TECH
            pac0[(e, t, r)] = e == :roil ? elecin[(t, :roil, r)] * cr(:roil, :elec, r) : elecin[(t, e, r)]
        end
        pac0[(e, :households, r)] = e == :roil ? ence1[(e, r)] * cr(:roil, :final, r) : ence1[(e, r)]
        pac0[(e, :htrn, r)] = e == :roil ? tfo[r] * cr(:roil, :final, r) : 0.0
    end

    for r in REGIONS
        sele0[r] = get(elec["xp0_"], (:sele, r), 0.0)
        dispgen0[r] = sum(get(elec["xp0_"], (i_, r), 0.0) for i_ in TECH_D)
        wele0[r] = get(elec["xp0_"], (:wele, r), 0.0)
        tele0[r] = get(elec["xp0_"], (:tele, r), 0.0)
        efout0[r] = sum(get(elec["xp0_"], (i_, r), 0.0) for i_ in TECH_F)
        for i_ in TECH
            xp0_[(i_, r)] = get(elec["xp0_"], (i_, r), 0.0)
            xp = xp0_[(i_, r)]
            eprod__over_xp0_[(i_, r)] = xp == 0 ? 0.0 : get(elec["eprod_"], (i_, r), 0.0) / xp
        end
        eprod_sum = sum(get(elec["eprod_"], (i_, r), 0.0) for i_ in TECH)
        elec_out = xp0[(r, :elec)]
        eprod_over_xp0[r] = elec_out == 0 ? 0.0 : eprod_sum / elec_out
    end

    rgdp0 = Dict{Symbol,Float64}()
    for r in REGIONS
        sav0[r] = get(p["savf0"], (r,), 0.0)
        for t in TECH_NHR
            ffact_e[(t, r)] = get(ffact_e, (t, r), 0.0)
        end
    end

    for r in REGIONS
        exports = 0.0
        imports = 0.0
        for rr in REGIONS, i in SECTORS
            i == :oil && continue
            exports += (1 + get(p["tx"], (i, r, rr), 0.0)) * get(p["wtflow0"], (rr, r, i), 0.0)
            imports += (1 + get(p["tx"], (i, rr, r), 0.0)) * get(p["wtflow0"], (r, rr, i), 0.0)
        end
        rgdp0[r] = cons0[r] + inv0[r] + g0[r] + exports - imports + homx0[r] - homm0[r]
    end

    gap = 0.0
    for r in REGIONS, i in SECTORS
        i == :elec && continue
        xp = get(p["xp0"], (r, i), 0.0)
        xp == 0 && continue
        cost = ffact[(r, i)]
        cost += get(p["labd0"], (r, i), 0.0) * (1 + get(p["tf"], (:lab, i, r), 0.0))
        cost += get(p["kapd0"], (r, i), 0.0) * (1 + get(p["tf"], (:cap, i, r), 0.0))
        for j in SECTORS
            cost += get(p["xa0"], (r, j, i), 0.0) * (1 + get(p["ti"], (j, i, r), 0.0))
        end
        gap = max(gap, abs(xp - get(p["ptxy0"], (r, i), 0.0) - cost))
    end
    egap = 0.0
    for r in REGIONS, t in TECH
        xp = get(elec["xp0_"], (t, r), 0.0)
        xp == 0 && continue
        tdr = get(elec["td_"], (r, t), 0.0)
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
            sco20[(e, g, r)] = sco2coef[e] * ejuse[(e, g, r)]
        end
    end

    for r in REGIONS, i_ in TECH, e in SCO2_ENERGY
        sco20[(e, i_, r)] = sco2coef[e] * ejuse[(e, i_, r)]
    end

    for r in REGIONS, e in SCO2_ENERGY
        sco20[(e, :households, r)] = sco2coef[e] * ejuse[(e, :households, r)]
        sco20[(e, :htrn, r)] = sco2coef[e] * ejuse[(e, :htrn, r)]
    end

    for j in SECTORS, i in SECTORS, r in REGIONS
        p["ti"][(j, i, r)] = get(p["ti"], (j, i, r), 0.0)
    end
    for f in [:lab, :cap], i in SECTORS, r in REGIONS
        p["tf"][(f, i, r)] = get(p["tf"], (f, i, r), 0.0)
    end
    for i in SECTORS, r in REGIONS
        p["tg"][(i, r)] = get(p["tg"], (i, r), 0.0)
        p["tp"][(i, r)] = get(p["tp"], (i, r), 0.0)
        p["pc0"][(i, r)] = get(p["pc0"], (i, r), 0.0)
        p["pg0"][(i, r)] = get(p["pg0"], (i, r), 0.0)
        sigu[(i, r)] = get(sigu, (i, r), 0.0)
        esup[(i, r)] = get(esup, (i, r), 0.0)
        esube[(i, r)] = get(esube, (i, r), 0.0)
        selas[(i, :e_kl, r)] = get(selas, (i, :e_kl, r), 0.0)
        selas[(i, :l_k, r)] = get(selas, (i, :l_k, r), 0.0)
        selas[(i, :noe_el, r)] = get(selas, (i, :noe_el, r), 0.0)
        selas[(i, :sdm, r)] = get(selas, (i, :sdm, r), 0.0)
        selas[(i, :smm, r)] = get(selas, (i, :smm, r), 0.0)
    end
    for i in SECTORS, s in REGIONS, d in REGIONS
        p["tx"][(i, s, d)] = get(p["tx"], (i, s, d), 0.0)
        p["tm"][(i, s, d)] = get(p["tm"], (i, s, d), 0.0)
    end
    for r in REGIONS
        delas[(r,)] = get(delas, (r,), 0.0)
        selas[(:elec, :e_kl, r)] = get(selas, (:elec, :e_kl, r), 0.0)
        selas[(:elec, :l_k, r)] = get(selas, (:elec, :l_k, r), 0.0)
        selas[(:hh, :noe_el, r)] = get(selas, (:hh, :noe_el, r), 0.0)
        for t in TECH
            elec["td_"][(r, t)] = get(elec["td_"], (r, t), 0.0)
        end
        for t in TECH_N
            wst[(t, r)] = get(wst, (t, r), 0.0)
        end
    end
    return (;
        p, dat = p, elec = raw.e, satellite = raw.satellite, REGIONS, SECTORS, ann, pop,
        selas, esup, esube, sigu, delas, cr, wst,

        a0, xp0, d0, xp0_pdb, xp0_phom, td, cons0, inv0, g0, pwdem0, govdem0, govoil0, invdem0, invoil0, ytout0, trnvst0, ffact, ffend0, ffgprod0, xa0, xaroila, xaroilc, labd0, kapd0,
        xdc, xmc, xm0, wtflow, mvtwr, xat0, xd0,
        purtrn, tbo, tfo, toi, tse, own, hhwedge, tottrn, xh, ence, ence1, pac0,
        homm0, homx0, homt0, vhomm0, vhomx0, txhom, tmhom, homadj, trnadj,
        elecin, elecint, ffact_e, nhrsigma, sele0, dispgen0, wele0, tele0, efout0, xp0_, eprod__over_xp0_, eprod_over_xp0, sav0, aeeigr, aeei, ejadj, ejuse0, ejuse_all0, ejuse_all, ejuse, euse0, ejuse_over_euse, sco2coef, sco20, kapital, labor, rgdp0,
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











