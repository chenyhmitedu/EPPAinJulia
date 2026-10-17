"""
    build_model(B; simu::Integer = 0)

Build the MPSGE model for benchmark `B`.

New methods are invisible to the call frame that loaded this file, so the model
is rebuilt with `Base.invokelatest`.
"""
function build_model(B; simu::Integer = 0)
    apply_smooth!()
    return Base.invokelatest(_build_model, B, Int(simu))
end

"""
    EPPA_model(data, iter::Integer = -1; simu::Integer = 0)

Base-year model, before any endowment update.

`iter` must be `-1`. `solve!(MGE; cumulative_iteration_limit = 0)` then reports
the benchmark residual. Later years are solved by [`run_scenario`](@ref).
"""
function EPPA_model(data, iter::Integer = -1; simu::Integer = 0)
    iter == -1 || throw(ArgumentError(
        "EPPA_model(data, -1) is the base-year model. Later years are solved by run_scenario.",
    ))
    bau = simu == 1 ? _load_bau() : nothing
    MGE, st = build_model(data; simu)
    simu == 1 && _install_gprod!(st, bau, YEARS[1])
    return MGE
end

"""
    _build_model(B, simu::Integer = 0)

Declare the active EPPA blocks.

Production is split by nest class:

  - non-energy (`not aenoe`): food, othr, serv, tran, dwe
  - energy intensive (`sa = 1`, with the Brazil biofuel split)
  - agriculture: materials sit under the energy/value nest, and the fixed factor is on `fx`
  - coal, oil, gas, and refined oil; crude oil output is the homogeneous good
  - electricity aggregation and technologies

Household transport omits identity layers that have a single input. `htrn` buys
the two conventional streams directly.

`gp0` is the calibrated productivity used when `simu = 1`. It is not created
when `simu = 0`. In that case `GPROD` meets the GDP target. When `simu = 1`,
`GPROD` is held at the calibrated value.
"""
function _build_model(B, simu::Integer = 0)
    PATHSolver.c_api_License_SetString(PATH_LICENSE)
    MGE = MPSGEModel()
    R = REGIONS
    I = SECTORS
    g = B.g
    ge = B.ge
    (; y_na, y_ei, y_ag, y_en, y_d, y_el, y_f, y_nhr, y_n, y_tech, y_de, y_arm, y_m, y_hm, y_hx) = active_blocks(B)

    @parameters(MGE, begin
        k0[r=R], B.kapital[r],                                  (description = "Endowment: capital")
        l0[r=R], B.labor[r],                                    (description = "Endowment: labor")
        ff0[i=I, r=R], B.ffact[(r, i)],                         (description = "Endowment: fixed factor and land in agri")
        ffe[i_=TECH_NHR, r=R], get(B.ffact_e, (i_, r), 0.0),    (description = "Endowment: fixed factor for nele, hele and rele")
        sav[r=R], g("savf0", (r,)),                             (description = "Endowment: negative base-year trade balance")
        grg[r=R], B.g0[r],                                      (description = "Base-year government expenditure")
        gdp0[r=R], B.rgdp0[r],                                  (description = "Base-year GDP")
        gp0[r=R], 1.0,                                          (description = "Calibrated productivity target")                               
    end)

    @commodities(MGE, begin
        PD[i=I, r=R],                                           (description = "Price index for domestic output")
        PA[i=I, r=R],                                           (description = "Price index for Armington good")
        PHOM[r=R],                                              (description = "Domestic price index for homogenous good")
        PM[i=I, r=R],                                           (description = "Imported good price index")
        PDB[i=[:food, :eint], r=R],                             (description = "Price index for existing biofuels (regional)")             
        PK[r=R],                                                (description = "Price index for capital service")
        PL[r=R],                                                (description = "Price index for labor")
        PF[i=I, r=R],                                           (description = "Price index for fixed factor") 
        PF_[i_=TECH, r=R],                                      (description = "Price index for fixed factor: power subsector")     
        PDE[i_=PDE_DIM, r=R],                                   (description = "Price index for electricity generation and delivery")
        PG[r=R],                                                (description = "Price index for government output")
        PINV[r=R],                                              (description = "Price index for investment")
        PT,                                                     (description = "Price index for international transport")
        PU[r=R],                                                (description = "Price index for aggregation consumption")
        PW[r=R],                                                (description = "Price index for welfare: including savings")
        PTRN[r=R],                                              (description = "Price index for household transport including purchased and own-supplied")
        PTNN[r=R],                                              (description = "Own-supplied household transport price index - new")
        PTNV[r=R],                                              (description = "Own-supplied household transport price index - vintaged")
        PTN[r=R],                                               (description = "Own-supplied household transport price index - aggregated")
        PTNS[r=R],                                              (description = "Own-supplied household transport price index ICE substitutable with EVs")
        PWH,                                                    (description = "World market price of homogenous goods")
    end)

    @sectors(MGE, begin
        D[i=y_d],                                               (description = "Activity level for domestic production")
        DE[i=y_de],                                             (description = "Activity level for power subsector and some aggregation")
        GOVT[r=R],                                              (description = "Activity level for aggregated government consumption")                                      
        INV[r=R],                                               (description = "Activity level for investment")                                      
        YT,                                                     (description = "Activity level for international transport")                              
        HTRN[r=R],                                              (description = "Activity level for household transport: including purchased & own-supplied")                                      
        HNEW[r=R],                                              (description = "Activity level for household transport: new & conventional")                                      
        HOLD[r=R],                                              (description = "Activity level for household transport: old & conventional")                                      
        HAGG[r=R],                                              (description = "Activity level for household transport: conventional")                                      
        Z[r=R],                                                 (description = "Activity level for consumption index")                                  
        W[r=R],                                                 (description = "Activity level for welfare: consumption & savings")                                  
        A[i=y_arm],                                             (description = "Activity level for Arminton goods")                                      
        M[i=y_m],                                               (description = "Activity level for imports")
        HOMM[r=y_hm],                                           (description = "Activity level for net import of homogeneous good")                                          
        HOMX[r=y_hx],                                           (description = "Activity level for net export of homogeneous good")
    end)

    @auxiliaries(MGE, begin
        GPROD[r=R],                                             (lower_bound = 0, start = 1, description = "Productivity index")
        RGDP[r=R],                                              (lower_bound = 0, start = B.rgdp0[r], description = "Real GDP")
    end)

    @consumers(MGE, begin
        RA[r=R],                                                (description = "Representative agent")
    end)

    for (i, r) in y_na
        q = na_block(B, i, r)
        @production(MGE, D[(:na, i, r)], [t=2, s=q.sigu, b=>s=q.es, a=>b=q.pn, ee=>a=q.ekl, va=>ee=q.lk, en=>ee=q.noe, en1=>en=q.esb, oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PD[i, r], q.qpd, t, taxes=[Tax(RA[r], q.td)])
            @output(PDB[:food, r], q.qpdb, t, taxes=[Tax(RA[r], q.td)])
            [@input(PA[j, r], g("xa0", (r, j, i)), a, taxes=[Tax(RA[r], g("ti", (j, i, r)))], reference_price=1 + g("ti", (j, i, r))) for j in NE]...
            [@input(PA[:roil, r], g("xa0", (r, :roil, i)) * (1 - B.cr(:roil, i, r)), a, taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            @input(PL[r], g("labd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:lab, i, r)))], reference_price=1 + g("tf", (:lab, i, r)))
            @input(PK[r], g("kapd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:cap, i, r)))], reference_price=1 + g("tf", (:cap, i, r)))
            @input(PF[i, r], B.ffact[(r, i)], b)
            [@input(PHOM[r], g("xa0", (r, :oil, i)), oil, taxes=[Tax(RA[r], g("ti", (:oil, i, r)))], reference_price=1 + g("ti", (:oil, i, r)))]...
            [@input(PA[:gas, r], g("xa0", (r, :gas, i)), gas, taxes=[Tax(RA[r], g("ti", (:gas, i, r)))], reference_price=1 + g("ti", (:gas, i, r)))]...
            [@input(PA[:coal, r], g("xa0", (r, :coal, i)), coal, taxes=[Tax(RA[r], g("ti", (:coal, i, r)))], reference_price=1 + g("ti", (:coal, i, r)))]...
            [@input(PA[:roil, r], g("xa0", (r, :roil, i)) * B.cr(:roil, i, r), roil, taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            [@input(PA[:elec, r], g("xa0", (r, :elec, i)), en, taxes=[Tax(RA[r], g("ti", (:elec, i, r)))], reference_price=1 + g("ti", (:elec, i, r)))]...
        end)
    end

    for (i, r) in y_ei
        q = ei_block(B, i, r)
        @production(MGE, D[(:ei, i, r)], [t=2, s=q.sigu, b=>s=q.es, a=>b=0, ee=>a=q.ekl, va=>ee=q.lk, en=>ee=q.noe, en1=>en=q.esb, oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PD[i, r], q.qpd, t, taxes=[Tax(RA[r], q.td)])
            @output(PDB[:eint, r], q.qpdb, t, taxes=[Tax(RA[r], q.td)])
            [@input(PA[j, r], g("xa0", (r, j, i)), a, taxes=[Tax(RA[r], g("ti", (j, i, r)))], reference_price=1 + g("ti", (j, i, r))) for j in NE]...
            [@input(PA[:roil, r], g("xa0", (r, :roil, i)) * (1 - B.cr(:roil, i, r)), a, taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            @input(PL[r], g("labd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:lab, i, r)))], reference_price=1 + g("tf", (:lab, i, r)))
            @input(PK[r], g("kapd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:cap, i, r)))], reference_price=1 + g("tf", (:cap, i, r)))
            @input(PF[i, r], B.ffact[(r, i)], b)
            [@input(PHOM[r], g("xa0", (r, :oil, i)), oil, taxes=[Tax(RA[r], g("ti", (:oil, i, r)))], reference_price=1 + g("ti", (:oil, i, r)))]...
            [@input(PA[:gas, r], g("xa0", (r, :gas, i)), gas, taxes=[Tax(RA[r], g("ti", (:gas, i, r)))], reference_price=1 + g("ti", (:gas, i, r)))]...
            [@input(PA[:coal, r], g("xa0", (r, :coal, i)), coal, taxes=[Tax(RA[r], g("ti", (:coal, i, r)))], reference_price=1 + g("ti", (:coal, i, r)))]...
            [@input(PA[:roil, r], g("xa0", (r, :roil, i)) * B.cr(:roil, i, r), roil, taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            [@input(PA[:elec, r], g("xa0", (r, :elec, i)), en, taxes=[Tax(RA[r], g("ti", (:elec, i, r)))], reference_price=1 + g("ti", (:elec, i, r)))]...
        end)
    end

    for (i, r) in y_ag
        q = ag_block(B, i, r)
        @production(MGE, D[(:ag, i, r)], [t=0, s=q.sigu, a=>s=0.7, va=>a=q.lk, fx=>a=q.es, e=>fx=q.ekl, ne=>e=0, en=>e=q.noe, en1=>en=q.esb, oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PD[i, r], q.xp, t, taxes=[Tax(RA[r], q.td)])
            [@input(PA[j, r], g("xa0", (r, j, i)), ne, taxes=[Tax(RA[r], g("ti", (j, i, r)))], reference_price=1 + g("ti", (j, i, r))) for j in NE]...
            [@input(PA[:roil, r], g("xa0", (r, :roil, i)) * (1 - B.cr(:roil, i, r)), ne, taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            @input(PL[r], g("labd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:lab, i, r)))], reference_price=1 + g("tf", (:lab, i, r)))
            @input(PK[r], g("kapd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:cap, i, r)))], reference_price=1 + g("tf", (:cap, i, r)))
            @input(PF[i, r], B.ffact[(r, i)], fx)
            [@input(PHOM[r], g("xa0", (r, :oil, i)), oil, taxes=[Tax(RA[r], g("ti", (:oil, i, r)))], reference_price=1 + g("ti", (:oil, i, r)))]...
            [@input(PA[:gas, r], g("xa0", (r, :gas, i)), gas, taxes=[Tax(RA[r], g("ti", (:gas, i, r)))], reference_price=1 + g("ti", (:gas, i, r)))]...
            [@input(PA[:coal, r], g("xa0", (r, :coal, i)), coal, taxes=[Tax(RA[r], g("ti", (:coal, i, r)))], reference_price=1 + g("ti", (:coal, i, r)))]...
            [@input(PA[:roil, r], g("xa0", (r, :roil, i)) * B.cr(:roil, i, r), roil, taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            [@input(PA[:elec, r], g("xa0", (r, :elec, i)), en, taxes=[Tax(RA[r], g("ti", (:elec, i, r)))], reference_price=1 + g("ti", (:elec, i, r)))]...
        end)
    end

    for (i, r) in y_en
        q = en_block(B, i, r)
        @production(MGE, D[(:en, i, r)], [t=0, s=0, b=>s=q.es, a=>b=q.pn, va=>a=q.lk, en=>a=q.noe, en1=>en=q.esb, oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PHOM[r], q.qhom, t, taxes=[Tax(RA[r], q.td)])
            @output(PD[i, r], q.qdom, t, taxes=[Tax(RA[r], q.td)])
            [@input(PA[j, r], g("xa0", (r, j, i)), a, taxes=[Tax(RA[r], g("ti", (j, i, r)))], reference_price=1 + g("ti", (j, i, r))) for j in NE]...
            [@input(PA[:roil, r], g("xa0", (r, :roil, i)) * (1 - B.cr(:roil, i, r)), a, taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            @input(PL[r], g("labd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:lab, i, r)))], reference_price=1 + g("tf", (:lab, i, r)))
            @input(PK[r], g("kapd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:cap, i, r)))], reference_price=1 + g("tf", (:cap, i, r)))
            @input(PF[i, r], B.ffact[(r, i)], b)
            [@input(PHOM[r], g("xa0", (r, :oil, i)), oil, taxes=[Tax(RA[r], g("ti", (:oil, i, r)))], reference_price=1 + g("ti", (:oil, i, r)))]...
            [@input(PA[:gas, r], g("xa0", (r, :gas, i)), gas, taxes=[Tax(RA[r], g("ti", (:gas, i, r)))], reference_price=1 + g("ti", (:gas, i, r)))]...
            [@input(PA[:coal, r], g("xa0", (r, :coal, i)), coal, taxes=[Tax(RA[r], g("ti", (:coal, i, r)))], reference_price=1 + g("ti", (:coal, i, r)))]...
            [@input(PA[:roil, r], g("xa0", (r, :roil, i)) * B.cr(:roil, i, r), roil, taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            [@input(PA[:elec, r], g("xa0", (r, :elec, i)), en, taxes=[Tax(RA[r], g("ti", (:elec, i, r)))], reference_price=1 + g("ti", (:elec, i, r)))]...
        end)
    end

    for r in y_el
        @production(MGE, D[(:el, :elec, r)], [t=0, s=0, s001=>s=1, s011=>s001=1], begin
            @output(PD[:elec, r], g("xp0", (r, :elec)), t)
            [@input(PDE[:sele, r], ge("xp0_", (:sele, r)), s001)]...
            [@input(PDE[:dispgen, r], sum(ge("xp0_", (i_, r)) for i_ in TECH_D), s011)]...
            [@input(PDE[:wele, r], ge("xp0_", (:wele, r)), s011)]...
            [@input(PDE[:tnd, r], ge("xp0_", (:tele, r)), s)]...
        end)
        @production(MGE, DE[(:ef, :elec, r)], [t=0, s=1.5], begin
            @output(PDE[:dispgen, r], sum(ge("xp0_", (i_, r)) for i_ in TECH_F), t)
            [@input(PDE[i_, r], ge("xp0_", (i_, r)), s) for i_ in TECH_F]...
        end)
    end

    for (i_, r) in y_f
        q = tech_block(B, i_, r)
        @production(MGE, DE[(:f, i_, r)], [t=0, s=0, bc=>s=0.6, ac=>bc=0, eec=>ac=q.ekl, curb=>eec=0, vac=>eec=q.lk], begin
            @output(PDE[i_, r], q.xp, t, taxes=[Tax(RA[r], q.td)])
            [@input(PA[j, r], qty, ac, taxes=[Tax(RA[r], rate)], reference_price=1 + rate) for (j, qty, rate) in q.mats]...
            @input(PHOM[r], get(B.elecin, (i_, :oil, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :oil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :oil, r), 0.0))
            @input(PA[:gas, r], get(B.elecin, (i_, :gas, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :gas, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :gas, r), 0.0))
            @input(PA[:coal, r], get(B.elecin, (i_, :coal, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :coal, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :coal, r), 0.0))
            @input(PA[:elec, r], get(B.elecin, (i_, :elec, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :elec, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :elec, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (i_, :roil, r), 0.0) * (1 - B.cr(:roil, :elec, r)), ac, taxes=[Tax(RA[r], get(B.elecint, (i_, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :roil, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (i_, :roil, r), 0.0) * B.cr(:roil, :elec, r), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :roil, r), 0.0))
            @input(PL[r], get(B.elecin, (i_, :lab, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (i_, :lab, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :lab, r), 0.0))
            @input(PK[r], get(B.elecin, (i_, :cap, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (i_, :cap, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :cap, r), 0.0))
            @input(PF_[i_, r], get(B.elecin, (i_, :res, r), 0.0), bc, taxes=[Tax(RA[r], get(B.elecint, (i_, :res, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :res, r), 0.0))
        end)
    end

    for (i_, r) in y_nhr
        q = nhr_block(B, i_, r)
        @production(MGE, DE[(:nhr, i_, r)], [t=0, s=0, bc=>s=q.sig, ac=>bc=0, eec=>ac=q.ekl, curb=>eec=0, vac=>eec=q.lk], begin
            @output(PDE[:dispgen, r], q.xp, t, taxes=[Tax(RA[r], q.td)])
            [@input(PA[j, r], qty, ac, taxes=[Tax(RA[r], rate)], reference_price=1 + rate) for (j, qty, rate) in q.mats]...
            @input(PHOM[r], get(B.elecin, (i_, :oil, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :oil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :oil, r), 0.0))
            @input(PA[:gas, r], get(B.elecin, (i_, :gas, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :gas, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :gas, r), 0.0))
            @input(PA[:coal, r], get(B.elecin, (i_, :coal, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :coal, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :coal, r), 0.0))
            @input(PA[:elec, r], get(B.elecin, (i_, :elec, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :elec, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :elec, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (i_, :roil, r), 0.0) * (1 - B.cr(:roil, :elec, r)), ac, taxes=[Tax(RA[r], get(B.elecint, (i_, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :roil, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (i_, :roil, r), 0.0) * B.cr(:roil, :elec, r), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :roil, r), 0.0))
            @input(PL[r], get(B.elecin, (i_, :lab, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (i_, :lab, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :lab, r), 0.0))
            @input(PK[r], get(B.elecin, (i_, :cap, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (i_, :cap, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :cap, r), 0.0))
            @input(PF_[i_, r], get(B.elecin, (i_, :res, r), 0.0), bc, taxes=[Tax(RA[r], get(B.elecint, (i_, :res, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :res, r), 0.0))
        end)
    end

    for (i_, r) in y_n
        q = renewable_block(B, i_, r)
        @production(MGE, DE[(:n, i_, r)], [t=0, s=0, s001=>s=q.sig, ac=>s001=0, eec=>ac=q.ekl, curb=>eec=0, vac=>eec=q.lk], begin
            @output(PDE[i_, r], q.xp, t, taxes=[Tax(RA[r], q.td)])
            [@input(PA[j, r], qty, ac, taxes=[Tax(RA[r], rate)], reference_price=1 + rate) for (j, qty, rate) in q.mats]...
            @input(PHOM[r], get(B.elecin, (i_, :oil, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :oil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :oil, r), 0.0))
            @input(PA[:gas, r], get(B.elecin, (i_, :gas, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :gas, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :gas, r), 0.0))
            @input(PA[:coal, r], get(B.elecin, (i_, :coal, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :coal, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :coal, r), 0.0))
            @input(PA[:elec, r], get(B.elecin, (i_, :elec, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :elec, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :elec, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (i_, :roil, r), 0.0) * (1 - B.cr(:roil, :elec, r)), ac, taxes=[Tax(RA[r], get(B.elecint, (i_, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :roil, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (i_, :roil, r), 0.0) * B.cr(:roil, :elec, r), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :roil, r), 0.0))
            @input(PL[r], get(B.elecin, (i_, :lab, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (i_, :lab, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :lab, r), 0.0))
            @input(PK[r], get(B.elecin, (i_, :cap, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (i_, :cap, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :cap, r), 0.0))
        end)
    end

    for (i_, r) in y_tech
        q = tech_block(B, i_, r)
        @production(MGE, DE[(:tech, i_, r)], [t=0, s=0, s001=>s=0.6, ac=>s001=0, eec=>ac=q.ekl, curb=>eec=0, vac=>eec=q.lk], begin
            @output(PDE[:tnd, r], q.xp, t, taxes=[Tax(RA[r], q.td)])
            [@input(PA[j, r], qty, ac, taxes=[Tax(RA[r], rate)], reference_price=1 + rate) for (j, qty, rate) in q.mats]...
            @input(PHOM[r], get(B.elecin, (i_, :oil, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :oil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :oil, r), 0.0))
            @input(PA[:gas, r], get(B.elecin, (i_, :gas, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :gas, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :gas, r), 0.0))
            @input(PA[:coal, r], get(B.elecin, (i_, :coal, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :coal, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :coal, r), 0.0))
            @input(PA[:elec, r], get(B.elecin, (i_, :elec, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :elec, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :elec, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (i_, :roil, r), 0.0) * (1 - B.cr(:roil, :elec, r)), ac, taxes=[Tax(RA[r], get(B.elecint, (i_, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :roil, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (i_, :roil, r), 0.0) * B.cr(:roil, :elec, r), curb, taxes=[Tax(RA[r], get(B.elecint, (i_, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :roil, r), 0.0))
            @input(PL[r], get(B.elecin, (i_, :lab, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (i_, :lab, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :lab, r), 0.0))
            @input(PK[r], get(B.elecin, (i_, :cap, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (i_, :cap, r), 0.0))], reference_price=1 + get(B.elecint, (i_, :cap, r), 0.0))
        end)
    end

    for r in R
        @production(MGE, GOVT[r], [t=0, s=0.5], begin
            @output(PG[r], B.g0[r], t)
            [@input(PA[i, r], i == :oil ? 0.0 : g("xdg0", (r, i)) + g("xmg0", (r, i)), s, taxes=[Tax(RA[r], g("tg", (i, r)))], reference_price=g("pg0", (i, r))) for i in I]...
            @input(PHOM[r], g("xdg0", (r, :oil)) + g("xmg0", (r, :oil)), s, taxes=[Tax(RA[r], g("tg", (:oil, r)))], reference_price=g("pg0", (:oil, r)))
        end)
        @production(MGE, INV[r], [t=0, s=5], begin
            @output(PINV[r], B.inv0[r], t)
            [@input(PA[i, r], i == :oil ? 0.0 : g("xdi0", (r, i)) + g("xmi0", (r, i)), s) for i in I]...
            @input(PHOM[r], g("xdi0", (r, :oil)) + g("xmi0", (r, :oil)), s)
        end)
    end

    @production(MGE, YT, [t=0, s=1], begin
        @output(PT, sum(g("vst", (:tran, r)) for r in R), t)
        [@input(PD[:tran, r], g("vst", (:tran, r)), s) for r in R]...
    end)

    for r in R
        h = hh_block(B, r)
        @production(MGE, HNEW[r], [t=0, s=0.1, a=>s=h.tn1, c=>a=0, b=>s=1], begin
            @output(PTNN[r], HTRNS * h.own, t)
            @input(PA[:roil, r], HTRNS * B.tfo[r], c, taxes=[Tax(RA[r], h.tpR)], reference_price=h.pcR)
            @input(PDB[h.foodp, r], HTRNS * B.tbo[r], c, taxes=[Tax(RA[r], h.tpR)], reference_price=h.pcR)
            @input(PA[:othr, r], HTRNS * B.toi[r] * PROPFRAC, a, taxes=[Tax(RA[r], g("tp", (:othr, r)))], reference_price=g("pc0", (:othr, r)))
            @input(PA[:othr, r], HTRNS * B.toi[r] * (1 - PROPFRAC), b, taxes=[Tax(RA[r], g("tp", (:othr, r)))], reference_price=g("pc0", (:othr, r)))
            @input(PA[:serv, r], HTRNS * B.tse[r], b, taxes=[Tax(RA[r], g("tp", (:serv, r)))], reference_price=g("pc0", (:serv, r)))
        end)
        @production(MGE, HOLD[r], [t=0, s=0], begin
            @output(PTNV[r], (1 - HTRNS) * h.own, t)
            @input(PA[:roil, r], (1 - HTRNS) * B.tfo[r], s, taxes=[Tax(RA[r], h.tpR)], reference_price=h.pcR)
            @input(PDB[h.foodp, r], (1 - HTRNS) * B.tbo[r], s, taxes=[Tax(RA[r], h.tpR)], reference_price=h.pcR)
            @input(PA[:othr, r], (1 - HTRNS) * B.toi[r], s, taxes=[Tax(RA[r], g("tp", (:othr, r)))], reference_price=g("pc0", (:othr, r)))
            @input(PA[:serv, r], (1 - HTRNS) * B.tse[r], s, taxes=[Tax(RA[r], g("tp", (:serv, r)))], reference_price=g("pc0", (:serv, r)))
        end)
        @production(MGE, HAGG[r], [t=4, s=0], begin
            @output(PTN[r], 0.2 * h.own, t)
            @output(PTNS[r], 0.8 * h.own, t)
            @input(PTNN[r], HTRNS * h.own, s)
            @input(PTNV[r], (1 - HTRNS) * h.own, s)
        end)
        @production(MGE, HTRN[r], [t=0, s=0.2, s1=>s=4], begin
            @output(PTRN[r], B.tottrn[r], t)
            @input(PA[:tran, r], B.purtrn[r], s, taxes=[Tax(RA[r], g("tp", (:tran, r)))], reference_price=g("pc0", (:tran, r)))
            @input(PTN[r], 0.2 * h.own, s1)
            @input(PTNS[r], 0.8 * h.own, s1)
        end)

        @production(MGE, Z[r], [t=0, s=0.5, u=>s=0.25, a=>u=h.delas, dw=>u=0.3, en=>dw=h.noe, oil=>en=0, gas=>en=0, coal=>en=0, roil=>en=0, elec=>en=0], begin
            @output(PU[r], g("cons0", (r,)) + h.wedge, t)
            @input(PTRN[r], B.tottrn[r], s)
            [@input(PA[i, r], max(get(B.xdc, (r, i), 0.0) + g("xmc0", (r, i)), 0.0), a, taxes=[Tax(RA[r], g("tp", (i, r)))], reference_price=g("pc0", (i, r))) for i in NENDT]...
            [@input(PA[:dwe, r], max(get(B.xdc, (r, :dwe), 0.0) + g("xmc0", (r, :dwe)), 0.0), dw, taxes=[Tax(RA[r], g("tp", (:dwe, r)))], reference_price=g("pc0", (:dwe, r)))]...
            @input(PHOM[r], max(B.ence[(:oil, r)], 0.0), oil, taxes=[Tax(RA[r], g("tp", (:oil, r)))], reference_price=g("pc0", (:oil, r)))
            @input(PA[:gas, r], max(B.ence[(:gas, r)], 0.0), gas, taxes=[Tax(RA[r], g("tp", (:gas, r)))], reference_price=g("pc0", (:gas, r)))
            @input(PA[:coal, r], max(B.ence[(:coal, r)], 0.0), coal, taxes=[Tax(RA[r], g("tp", (:coal, r)))], reference_price=g("pc0", (:coal, r)))
            @input(PA[:roil, r], max(B.ence[(:roil, r)], 0.0), roil, taxes=[Tax(RA[r], g("tp", (:roil, r)))], reference_price=g("pc0", (:roil, r)))
            @input(PA[:elec, r], max(B.ence[(:elec, r)], 0.0), elec, taxes=[Tax(RA[r], g("tp", (:elec, r)))], reference_price=g("pc0", (:elec, r)))
        end)
        @production(MGE, W[r], [t=0, s=0], begin
            @output(PW[r], g("cons0", (r,)) + B.inv0[r] + h.wedge, t)
            @input(PU[r], g("cons0", (r,)) + h.wedge, s)
            @input(PINV[r], B.inv0[r], s)
        end)
    end

    for (i, r) in y_arm
        q = arm_block(B, i, r)
        @production(MGE, A[(i, r)], [t=0, s=q.sdm], begin
            @output(PA[i, r], q.qout, t)
            @input(PD[i, r], q.qdom, s)
            @input(PM[i, r], g("xm0", (r, i)), s)
        end)
    end

    for (i, r) in y_m
        @production(MGE, M[(i, r)], [t=0, s=B.elas(i, :smm, r), src[rr=R]=>s=0], begin
            @output(PM[i, r], g("xm0", (r, i)), t)
            [@input(PD[i, rr], g("wtflow0", (r, rr, i)), src[rr], taxes=[Tax(RA[rr], g("tx", (i, rr, r))), Tax(RA[r], g("tm", (i, rr, r)) * (1 + g("tx", (i, rr, r))))], reference_price=(1 + g("tx", (i, rr, r))) * (1 + g("tm", (i, rr, r)))) for rr in R]...
            [@input(PT, sum(g("vtwr", (j, i, rr, r)) for j in I), src[rr], taxes=[Tax(RA[r], g("tm", (i, rr, r)))], reference_price=1 + g("tm", (i, rr, r))) for rr in R]...
        end)
    end

    for r in y_hm
        @production(MGE, HOMM[r], [t=0, s=0], begin
            @output(PHOM[r], B.vhomm0[r], t)
            @input(PWH, B.homm0[r], s, taxes=[Tax(RA[r], B.tmhom[r])])
            @input(PT, B.homt0[r], s, taxes=[Tax(RA[r], B.tmhom[r])])
        end)
    end
    for r in y_hx
        @production(MGE, HOMX[r], [t=0, s=0], begin
            @output(PWH, B.homx0[r], t)
            @input(PHOM[r], B.vhomx0[r], s, taxes=[Tax(RA[r], B.txhom[r])])
        end)
    end

    for r in R
        @demand(MGE, RA[r], begin
            @final_demand(PW[r], g("cons0", (r,)) + B.inv0[r])
            @endowment(PK[r], k0[r] * GPROD[r])
            @endowment(PL[r], l0[r] * GPROD[r])
            [@endowment(PF[i, r], (i in FF ? 1.0 : GPROD[r]) * ff0[i, r]) for i in I]...
            [@endowment(PF_[i_, r], 1.0 * ffe[i_, r]) for i_ in TECH_NHR]...
            @endowment(PU[:usa], 1.0 * sav[r])
            @endowment(PG[r], -grg[r])
            @endowment(PHOM[r], B.homadj[r])
            @endowment(PT, B.trnadj[r])
        end)
    end

    for r in R

        @aux_constraint(MGE, RGDP[r],
            PU[r] * RGDP[r] 
                - PU[r] * g("cons0", (r,)) * Z[r] 
                - B.inv0[r] * PINV[r] * INV[r] 
                - B.g0[r] * PG[r] * GOVT[r] 
                - sum((1 + g("tx", (i, r, rr))) * PD[i, r] * g("wtflow0", (rr, r, i)) 
                    for rr in R for i in I if i != :oil && g("wtflow0", (rr, r, i)) > 0; init=0) 
                - (B.homx0[r] > 0 ? PWH * B.homx0[r] * HOMX[r] : 0)
                + sum((1 + g("tx", (i, rr, r))) * PD[i, rr] * g("wtflow0", (r, rr, i)) 
                    for rr in R for i in I if i != :oil && g("wtflow0", (r, rr, i)) > 0; init=0) 
                + (B.homm0[r] > 0 ? PWH * B.homm0[r] * HOMM[r] : 0)
            )
        
        if simu == 0
            @aux_constraint(MGE, GPROD[r], RGDP[r] - gdp0[r])
        else
            @aux_constraint(MGE, GPROD[r], GPROD[r] - gp0[r])
        end
        
    end

    fix(PU[:usa], 1.0)

    gp0_param = nothing
    if simu == 1
        gp0_param = gp0
    end

    state = (; MGE, R, k0, l0, sav, grg, gdp0, GPROD, RGDP, gp0 = gp0_param, simu,
        kapital0 = copy(B.kapital), labor0 = copy(B.labor),
        labor_pre = Dict(r => sum(g("labd0", (r, i)) for i in I) + g("labdg0", (r,)) for r in R),
        inv0 = copy(B.inv0), scale = Dict{Symbol,Float64}())
    srve0 = (1 - DPE)^regular_step()
    for r in R
        state.scale[r] = (state.kapital0[r] - state.kapital0[r] * srve0) / (0.95 * ROR * state.inv0[r])
    end
    return MGE, state
end
