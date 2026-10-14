"""
    active_blocks(B)

Sector, technology, and trade indexes with positive benchmark output.
"""
function active_blocks(B)
    g = B.g
    ge = B.ge
    R = REGIONS
    I = SECTORS
    y_na = [(i, r) for i in NOT_AENOE for r in R if g("xp0", (r, i)) > 0]
    y_ei = [(i, r) for i in [:eint] for r in R if g("xp0", (r, i)) > 0]
    y_ag = [(i, r) for i in AGRI for r in R if g("xp0", (r, i)) > 0]
    y_en = [(i, r) for i in ENOE for r in R if g("xp0", (r, i)) > 0]
    y_el = [r for r in R if g("xp0", (r, :elec)) > 0]
    y_d = vcat(
        [(:na, i, r) for (i, r) in y_na],
        [(:ei, i, r) for (i, r) in y_ei],
        [(:ag, i, r) for (i, r) in y_ag],
        [(:en, i, r) for (i, r) in y_en],
        [(:el, :elec, r) for r in y_el],
    )
    y_f = [(i_, r) for i_ in TECH_F for r in R if ge("xp0_", (i_, r)) > 0]
    y_nhr = [(i_, r) for i_ in TECH_NHR for r in R if ge("xp0_", (i_, r)) > 0 && get(B.ffact_e, (i_, r), 0.0) > 0]
    y_n = [(i_, r) for i_ in TECH_N for r in R if ge("xp0_", (i_, r)) > 0]
    y_tech = [(i_, r) for i_ in [:tele] for r in R if ge("xp0_", (i_, r)) > 0]
    y_de = vcat(
        [(:ef, :elec, r) for r in R],
        [(:f, i_, r) for (i_, r) in y_f],
        [(:nhr, i_, r) for (i_, r) in y_nhr],
        [(:n, i_, r) for (i_, r) in y_n],
        [(:tech, i_, r) for (i_, r) in y_tech],
    )
    return (;
        y_na,
        y_ei,
        y_ag,
        y_en,
        y_d,
        y_el,
        y_f,
        y_nhr,
        y_n,
        y_tech,
        y_de,
        y_arm = [(i, r) for i in I if i != :oil for r in R if B.a0[(r, i)] != 0],
        y_m = [(i, r) for i in I if i != :oil for r in R if g("xm0", (r, i)) > 0],
        y_hm = [r for r in R if B.homm0[r] > 0],
        y_hx = [r for r in R if B.homx0[r] > 0],
    )
end

"""
    na_block(B, i, r)

Output split, output tax, and elasticities for a non-energy sector.
"""
function na_block(B, i, r)
    g = B.g
    xp = g("xp0", (r, i))
    return (;
        td = B.td[(r, i)],
        qpd = (i == :food && r != :bra) ? xp - B.tbo[r] : xp,
        qpdb = (i == :food && r != :bra) ? B.tbo[r] : 0.0,
        sigu = get(B.sigu, (i, r), 0.0),
        es = get(B.esup, (i, r), 0.0),
        pn = i in AGRI ? 0.7 : 0.0,
        ekl = B.elas(i, :e_kl, r),
        lk = B.elas(i, :l_k, r),
        noe = B.elas(i, :noe_el, r),
        esb = get(B.esube, (i, r), 0.0),
    )
end

"""
    ei_block(B, i, r)

Output split, output tax, and elasticities for energy-intensive industry.
"""
function ei_block(B, i, r)
    g = B.g
    xp = g("xp0", (r, i))
    return (;
        td = B.td[(r, i)],
        qpd = r == :bra ? xp - B.tbo[r] : xp,
        qpdb = r == :bra ? B.tbo[r] : 0.0,
        sigu = get(B.sigu, (i, r), 0.0),
        es = get(B.esup, (i, r), 0.0),
        ekl = B.elas(i, :e_kl, r),
        lk = B.elas(i, :l_k, r),
        noe = B.elas(i, :noe_el, r),
        esb = get(B.esube, (i, r), 0.0),
    )
end

"""
    ag_block(B, i, r)

Output, output tax, and elasticities for an agricultural sector.
"""
function ag_block(B, i, r)
    g = B.g
    return (;
        xp = g("xp0", (r, i)),
        td = B.td[(r, i)],
        sigu = get(B.sigu, (i, r), 0.0),
        es = get(B.esup, (i, r), 0.0),
        ekl = B.elas(i, :e_kl, r),
        lk = B.elas(i, :l_k, r),
        noe = B.elas(i, :noe_el, r),
        esb = get(B.esube, (i, r), 0.0),
    )
end

"""
    en_block(B, i, r)

Output, output tax, and elasticities for coal, oil, gas, or refined oil.

Crude oil is delivered to `phom`. The other three fuels are delivered to `pd`.
"""
function en_block(B, i, r)
    g = B.g
    xp = g("xp0", (r, i))
    return (;
        td = B.td[(r, i)],
        qhom = i == :oil ? xp : 0.0,
        qdom = i == :oil ? 0.0 : xp,
        es = get(B.esup, (i, r), 0.0),
        pn = 0.0,
        lk = B.elas(i, :l_k, r),
        noe = B.elas(i, :noe_el, r),
        esb = get(B.esube, (i, r), 0.0),
    )
end

"""
    elec_inputs(B, i_, r)

Material inputs and the refined-oil split for an electricity technology.
"""
function elec_inputs(B, i_, r)
    mats = [(j, get(B.elecin, (i_, j, r), 0.0), get(B.elecint, (i_, j, r), 0.0)) for j in NE]
    fuels = []
    for j in ENERGY
        q = get(B.elecin, (i_, j, r), 0.0)
        rate = get(B.elecint, (i_, j, r), 0.0)
        if j == :roil
            push!(fuels, (:ac, j, q * (1 - B.cr(:roil, :elec, r)), rate))
            push!(fuels, (:curb, j, q * B.cr(:roil, :elec, r), rate))
        else
            push!(fuels, (:curb, j, q, rate))
        end
    end
    return mats, fuels
end

"""
    tech_block(B, i_, r)

Output, output tax, elasticities, and material inputs for an electricity technology.
"""
function tech_block(B, i_, r)
    mats, _ = elec_inputs(B, i_, r)
    return (;
        td = B.ge("td_", (r, i_)),
        xp = B.ge("xp0_", (i_, r)),
        ekl = B.elas(:elec, :e_kl, r),
        lk = B.elas(:elec, :l_k, r),
        mats,
    )
end

"""
    nhr_block(B, i_, r)

`tech_block` plus the resource-nest elasticity for the fixed-factor technologies.
"""
function nhr_block(B, i_, r)
    q = tech_block(B, i_, r)
    return (; q..., sig = B.nhrsigma[(i_, r)])
end

"""
    renewable_block(B, i_, r)

`tech_block` plus the top-nest elasticity for solar and wind.
"""
function renewable_block(B, i_, r)
    q = tech_block(B, i_, r)
    return (; q..., sig = get(B.wst, (i_, r), 0.0))
end

"""
    hh_block(B, r)

Own-supplied transport shares and the household elasticity for one region.
"""
function hh_block(B, r)
    g = B.g
    pcR = g("pc0", (:roil, r))
    foodp = r == :bra ? :eint : :food
    return (;
        own = B.own[r],
        pcR,
        tpR = g("tp", (:roil, r)),
        foodp,
        tn1 = (r == :usa || r == :eur) ? 0.75 : 1.0,
        wedge = (pcR - g("pc0", (foodp, r))) * B.tbo[r],
        delas = get(B.delas, (r,), 0.0),
        noe = B.elas(:hh, :noe_el, r),
    )
end

"""
    arm_block(B, i, r)

Armington output and domestic input after the biofuel quantity is removed.
"""
function arm_block(B, i, r)
    qout = B.a0[(r, i)]
    qdom = B.d0[(r, i)]
    if (i == :food && r != :bra) || (i == :eint && r == :bra)
        qout -= B.tbo[r]
        qdom -= B.tbo[r]
    end
    return (; qout, qdom, sdm = B.elas(i, :sdm, r))
end

