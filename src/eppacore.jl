# include("smooth.jl")

"""

"""
function EPPACore(MGE, B, simu::Integer = 0)

    @parameters(MGE, begin
        k0[r=REGIONS], B.kapital[r],                                                (description = "Endowment: capital")
        l0[r=REGIONS], B.labor[r],                                                  (description = "Endowment: labor")
        ff0[i=SECTORS, r=REGIONS], B.ffff0[r, i],                                   (description = "Endowment: fixed factor: fossil fuels")
        fn0[i=SECTORS, r=REGIONS], B.ffnf0[r, i],                                   (description = "Endowment: fixed factor: non-fossil fuels")
        ffe[i_=TECH_NHR, r=REGIONS], B.ffact[i_, r],                                (description = "Endowment: fixed factor for nele, hele and rele")
        grg[r=REGIONS], B.g0[r],                                                    (description = "Base-year government expenditure")
        gdp0[r=REGIONS], B.rgdp0[r],                                                (description = "Base-year GDP")
        gprod0[r=REGIONS], 1.0,                                                     (description = "Calibrated productivity target")
        aeei[i=SECTORS, r=REGIONS], B.aeei[(i, r)],                                 (description = "Autonomous energy efficiency factor")
        co2cap[r=REGIONS], B.ftotco20[r],                                           (description = "Upper bound on regional combusted CO2, updated each period")
        td[i=SECTORS, r=REGIONS], B.td[(r, i)],                                     (description = "Output tax")
        ti[j=SECTORS, i=SECTORS, r=REGIONS], B.ti[(j, i, r)],                       (description = "Intermediate input tax")
        tf[f=[:lab, :cap], i=SECTORS, r=REGIONS], B.tf[(f, i, r)],                  (description = "Factor tax on labor and capital")
        elecint[i_=TECH, j=[SECTORS..., LKR...], r=REGIONS], B.elecint[(i_, j, r)], (description = "Input tax on an electricity technology")
        tde[i_=TECH, r=REGIONS], B.td_[(r, i_)],                                    (description = "Output tax on an electricity technology")
        tg[i=SECTORS, r=REGIONS], B.tg[(i, r)],                                     (description = "Government consumption tax")
        tp[i=SECTORS, r=REGIONS], B.tp[(i, r)],                                     (description = "Private consumption tax")
        tx[i=SECTORS, s=REGIONS, d=REGIONS], B.tx[(i, s, d)],                       (description = "Export tax, from s to d")
        tm[i=SECTORS, s=REGIONS, d=REGIONS], B.tm[(i, s, d)],                       (description = "Import tariff, from s to d")
        txhom[r=REGIONS], B.txhom[r],                                               (description = "Export tax on the homogeneous good")
        tmhom[r=REGIONS], B.tmhom[r],                                               (description = "Import tariff on the homogeneous good")
        w0[r=REGIONS], B.pwdem0[r],                                                 (description = "Base-year welfare level")
        bop[r=REGIONS], -B.savf0[r],                                                (description = "Balance of payment")
    end)            

    @commodities(MGE, begin         
        PD[i=SECTORS, r=REGIONS],                                                   (description = "Price index for domestic output")
        PA[i=SECTORS, r=REGIONS],                                                   (description = "Price index for Armington good")
        PAC[e=ENERGY, r=REGIONS],                                                   (description = "Price index for combusted energy input")
        PHOM[r=REGIONS],                                                            (description = "Domestic price index for homogenous good")
        PM[i=SECTORS, r=REGIONS],                                                   (description = "Imported good price index")
        PDB[i=[:food, :eint], r=REGIONS],                                           (description = "Price index for existing biofuels (regional)")             
        PK[r=REGIONS],                                                              (description = "Price index for capital service")
        PL[r=REGIONS],                                                              (description = "Price index for labor")
        PF[i=SECTORS, r=REGIONS],                                                   (description = "Price index for fixed factor") 
        PF_[i_=TECH, r=REGIONS],                                                    (description = "Price index for fixed factor: power subsector")     
        PDE[i_=PDE_DIM, r=REGIONS],                                                 (description = "Price index for electricity generation and delivery")
        PG[r=REGIONS],                                                              (description = "Price index for government output")
        PINV[r=REGIONS],                                                            (description = "Price index for investment")
        PT,                                                                         (description = "Price index for international transport")
        PU[r=REGIONS],                                                              (description = "Price index for aggregation consumption")
        PW[r=REGIONS],                                                              (description = "Price index for welfare: including savings")
        PTRN[r=REGIONS],                                                            (description = "Price index for household transport: purchased and own-supplied")
        PTNN[r=REGIONS],                                                            (description = "Own-supplied household transport price index - new")
        PTNV[r=REGIONS],                                                            (description = "Own-supplied household transport price index - vintaged")
        PTN[r=REGIONS],                                                             (description = "Own-supplied household transport price index - aggregated")
        PTNS[r=REGIONS],                                                            (description = "Own-supplied household transport price index ICE substitutable with EVs")
        PWH,                                                                        (description = "World market price of homogenous goods")
    end)            

    @sectors(MGE, begin         
        D[i=SECTORS, r=REGIONS],                                                    (description = "Activity level for domestic production")
        DE[i=TECH ∪ [:elec], r=REGIONS],                                            (description = "Activity level for power subsector and some aggregation")
        AC[e=ENERGY, g=AC_SECTORS, r=REGIONS],                                   (description = "Activity level for combusted energy transformation by user group")
        GOVT[r=REGIONS],                                                            (description = "Activity level for aggregated government consumption")                                      
        INV[r=REGIONS],                                                             (description = "Activity level for investment")                                      
        YT,                                                                         (description = "Activity level for international transport")                              
        HTRN[r=REGIONS],                                                            (description = "Activity level for household transport: including purchased & own-supplied")                                      
        HNEW[r=REGIONS],                                                            (description = "Activity level for household transport: new & conventional")                                      
        HOLD[r=REGIONS],                                                            (description = "Activity level for household transport: old & conventional")                                      
        HAGG[r=REGIONS],                                                            (description = "Activity level for household transport: conventional")                                      
        Z[r=REGIONS],                                                               (description = "Activity level for consumption index")                                  
        W[r=REGIONS],                                                               (description = "Activity level for welfare: consumption & savings")                                  
        A[i=SECTORS, r=REGIONS],                                                    (description = "Activity level for Arminton goods")                                      
        M[i=SECTORS, r=REGIONS],                                                    (description = "Activity level for imports")
        HOMM[r=REGIONS],                                                            (description = "Activity level for net import of homogeneous good")                                          
        HOMX[r=REGIONS],                                                            (description = "Activity level for net export of homogeneous good")
    end)            

    @auxiliaries(MGE, begin         
        GPROD[r=REGIONS],                                                           (lower_bound = 0, start = 1, description = "Productivity index")
        RGDP[r=REGIONS],                                                            (lower_bound = 0, start = B.rgdp0[r], description = "Real GDP")
        EE[e=ENERGY, g=EJUSE_SECTORS, r=REGIONS],                                   (lower_bound = 0, start = B.ejuse[(e, g, r)], description = "Combusted energy use by energy, sector, and region in EJ")
        SCO2[e=SCO2_ENERGY, g=SCO2_SECTORS, r=REGIONS],                             (lower_bound = 0, start = B.sco20[(e, g, r)], description = "Sectoral combusted CO2 emissions by fossil energy, user, and region in MtCO2")
        FTOTCO2[r=REGIONS],                                                         (lower_bound = 0, start = B.ftotco20[r], description = "Total combusted CO2 by region in MtCO2")
        CP[r=REGIONS],                                                              (lower_bound = 0, start = 0, description = "Ad valorem (carbon) tax rate on the most carbon-intensive fuel in r")
        CT[e=SCO2_ENERGY, g=AC_SECTORS, r=REGIONS],                              (start = 0, description = "Carbon tax rate on coal, gas, and refined oil by user group and region")
    end)            

    @consumers(MGE, begin           
        RA[r=REGIONS],                                                              (description = "Representative agent")
    end)            

    for r in REGIONS, g in AC_SECTORS
        q(e) = sum(get(B.pac0, (e, u, r), 0.0) for u in EJUSE_SECTORS if ac_group(u) == g)
        @production(MGE, AC[:oil, g, r], [t=0, s=0], begin
            @output(PAC[:oil, r],      q(:oil),    t)
            @input(PHOM[r],            q(:oil),    s)
        end)
        @production(MGE, AC[:elec, g, r], [t=0, s=0], begin
            @output(PAC[:elec, r],     q(:elec),   t)
            @input(PA[:elec, r],       q(:elec),   s)
        end)
        for e in SCO2_ENERGY
            @production(MGE, AC[e, g, r], [t=0, s=0], begin
                @output(PAC[e, r],     q(e),       t)
                @input(PA[e, r],       q(e),       s, taxes=[Tax(RA[r], CT[e, g, r])])
            end)
        end
    end

    for i in NOT_AENOE, r in REGIONS
        B.xp[(r, i)] > 0 || continue
        @production(MGE, D[i, r], [t=2, s=B.sigu[(i, r)], b=>s=B.esup[(i, r)], a=>b=0, ee=>a=B.selas[(i, :e_kl, r)], va=>ee=B.selas[(i, :l_k, r)], en=>ee=B.selas[(i, :noe_el, r)], en1=>en=B.esube[(i, r)], oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PD[i, r],          B.xp[(r, i)],                     t,    taxes=[Tax(RA[r], td[i, r])])
            @output(PDB[:food, r],     B.xp_pdb[(r, i)],                 t,    taxes=[Tax(RA[r], td[i, r])])
            [@input(PA[j, r],          B.xa0[(r, j, i)],                  a,    taxes=[Tax(RA[r], ti[j, i, r])],      reference_price=1 + B.ti[(j, i, r)]) for j in NE]...
            @input(PA[:roil, r],      aeei[i, r] * B.xaroila[(r, i)],    a,    taxes=[Tax(RA[r], ti[:roil, i, r])],  reference_price=1 + B.ti[(:roil, i, r)])
            @input(PL[r],              B.labd0[(r, i)],                   va,   taxes=[Tax(RA[r], tf[:lab, i, r])],   reference_price=1 + B.tf[(:lab, i, r)])
            @input(PK[r],              B.kapd0[(r, i)],                   va,   taxes=[Tax(RA[r], tf[:cap, i, r])],   reference_price=1 + B.tf[(:cap, i, r)])
            @input(PF[i, r],           B.ffact[(i, r)],                   b)
            @input(PAC[:gas, r],      aeei[i, r] * B.xa0[(r, :gas, i)],  gas,  taxes=[Tax(RA[r], ti[:gas, i, r])],   reference_price=1 + B.ti[(:gas, i, r)])
            @input(PAC[:coal, r],     aeei[i, r] * B.xa0[(r, :coal, i)], coal, taxes=[Tax(RA[r], ti[:coal, i, r])],  reference_price=1 + B.ti[(:coal, i, r)])
            @input(PAC[:roil, r],     aeei[i, r] * B.xaroilc[(r, i)],    roil, taxes=[Tax(RA[r], ti[:roil, i, r])], reference_price=1 + B.ti[(:roil, i, r)])
            @input(PAC[:oil, r],      aeei[i, r] * B.xa0[(r, :oil, i)],  oil,  taxes=[Tax(RA[r], ti[:oil, i, r])],   reference_price=1 + B.ti[(:oil, i, r)])
            @input(PAC[:elec, r],     aeei[i, r] * B.xa0[(r, :elec, i)], en,   taxes=[Tax(RA[r], ti[:elec, i, r])],  reference_price=1 + B.ti[(:elec, i, r)])
        end)
    end

    for i in [:eint], r in REGIONS
        B.xp[(r, i)] > 0 || continue
        @production(MGE, D[i, r], [t=2, s=B.sigu[(i, r)], b=>s=B.esup[(i, r)], a=>b=0, ee=>a=B.selas[(i, :e_kl, r)], va=>ee=B.selas[(i, :l_k, r)], en=>ee=B.selas[(i, :noe_el, r)], en1=>en=B.esube[(i, r)], oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PD[i, r],          B.xp[(r, i)],                     t,    taxes=[Tax(RA[r], td[i, r])])
            @output(PDB[:eint, r],     B.xp_pdb[(r, i)],                 t,    taxes=[Tax(RA[r], td[i, r])])
            [@input(PA[j, r],          B.xa0[(r, j, i)],                  a,    taxes=[Tax(RA[r], ti[j, i, r])],      reference_price=1 + B.ti[(j, i, r)]) for j in NE]...
            @input(PA[:roil, r],      aeei[i, r] * B.xaroila[(r, i)],    a,    taxes=[Tax(RA[r], ti[:roil, i, r])],  reference_price=1 + B.ti[(:roil, i, r)])
            @input(PL[r],              B.labd0[(r, i)],                   va,   taxes=[Tax(RA[r], tf[:lab, i, r])],   reference_price=1 + B.tf[(:lab, i, r)])
            @input(PK[r],              B.kapd0[(r, i)],                   va,   taxes=[Tax(RA[r], tf[:cap, i, r])],   reference_price=1 + B.tf[(:cap, i, r)])
            @input(PF[i, r],           B.ffact[(i, r)],                   b)
            @input(PAC[:gas, r],      aeei[i, r] * B.xa0[(r, :gas, i)],  gas,  taxes=[Tax(RA[r], ti[:gas, i, r])],   reference_price=1 + B.ti[(:gas, i, r)])
            @input(PAC[:coal, r],     aeei[i, r] * B.xa0[(r, :coal, i)], coal, taxes=[Tax(RA[r], ti[:coal, i, r])],  reference_price=1 + B.ti[(:coal, i, r)])
            @input(PAC[:roil, r],     aeei[i, r] * B.xaroilc[(r, i)],    roil, taxes=[Tax(RA[r], ti[:roil, i, r])], reference_price=1 + B.ti[(:roil, i, r)])
            @input(PAC[:oil, r],      aeei[i, r] * B.xa0[(r, :oil, i)],  oil,  taxes=[Tax(RA[r], ti[:oil, i, r])],   reference_price=1 + B.ti[(:oil, i, r)])
            @input(PAC[:elec, r],     aeei[i, r] * B.xa0[(r, :elec, i)], en,   taxes=[Tax(RA[r], ti[:elec, i, r])],  reference_price=1 + B.ti[(:elec, i, r)])
        end)
    end

    for i in AGRI, r in REGIONS
        B.xp[(r, i)] > 0 || continue
        @production(MGE, D[i, r], [t=0, s=B.sigu[(i, r)], a=>s=0.7, va=>a=B.selas[(i, :l_k, r)], fx=>a=B.esup[(i, r)], e=>fx=B.selas[(i, :e_kl, r)], ne=>e=0, en=>e=B.selas[(i, :noe_el, r)], en1=>en=B.esube[(i, r)], oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PD[i, r],          B.xp[(r, i)],                     t,    taxes=[Tax(RA[r], td[i, r])])
            [@input(PA[j, r],          B.xa0[(r, j, i)],                  ne,   taxes=[Tax(RA[r], ti[j, i, r])],      reference_price=1 + B.ti[(j, i, r)]) for j in NE]...
            @input(PA[:roil, r],      aeei[i, r] * B.xaroila[(r, i)],    ne,   taxes=[Tax(RA[r], ti[:roil, i, r])],  reference_price=1 + B.ti[(:roil, i, r)])
            @input(PL[r],              B.labd0[(r, i)],                   va,   taxes=[Tax(RA[r], tf[:lab, i, r])],   reference_price=1 + B.tf[(:lab, i, r)])
            @input(PK[r],              B.kapd0[(r, i)],                   va,   taxes=[Tax(RA[r], tf[:cap, i, r])],   reference_price=1 + B.tf[(:cap, i, r)])
            @input(PF[i, r],           B.ffact[(i, r)],                   fx)
            @input(PAC[:gas, r],      aeei[i, r] * B.xa0[(r, :gas, i)],  gas,  taxes=[Tax(RA[r], ti[:gas, i, r])],   reference_price=1 + B.ti[(:gas, i, r)])
            @input(PAC[:coal, r],     aeei[i, r] * B.xa0[(r, :coal, i)], coal, taxes=[Tax(RA[r], ti[:coal, i, r])],  reference_price=1 + B.ti[(:coal, i, r)])
            @input(PAC[:roil, r],     aeei[i, r] * B.xaroilc[(r, i)],    roil, taxes=[Tax(RA[r], ti[:roil, i, r])], reference_price=1 + B.ti[(:roil, i, r)])
            @input(PAC[:oil, r],      aeei[i, r] * B.xa0[(r, :oil, i)],  oil,  taxes=[Tax(RA[r], ti[:oil, i, r])],   reference_price=1 + B.ti[(:oil, i, r)])
            @input(PAC[:elec, r],     aeei[i, r] * B.xa0[(r, :elec, i)], en,   taxes=[Tax(RA[r], ti[:elec, i, r])],  reference_price=1 + B.ti[(:elec, i, r)])
        end)
    end

    for i in ENOE, r in REGIONS
        (B.xp[(r, i)] > 0 || B.xp_phom[(r, i)] > 0) || continue
        @production(MGE, D[i, r], [t=0, s=0, b=>s=B.esup[(i, r)], a=>b=0, va=>a=B.selas[(i, :l_k, r)], en=>a=B.selas[(i, :noe_el, r)], en1=>en=B.esube[(i, r)], oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PHOM[r],           B.xp_phom[(r, i)],                t,    taxes=[Tax(RA[r], td[i, r])])
            @output(PD[i, r],          B.xp[(r, i)],                     t,    taxes=[Tax(RA[r], td[i, r])])
            [@input(PA[j, r],          B.xa0[(r, j, i)],                  a,    taxes=[Tax(RA[r], ti[j, i, r])],      reference_price=1 + B.ti[(j, i, r)]) for j in NE]...
            @input(PA[:roil, r],      aeei[i, r] * B.xaroila[(r, i)],    a,    taxes=[Tax(RA[r], ti[:roil, i, r])],  reference_price=1 + B.ti[(:roil, i, r)])
            @input(PL[r],              B.labd0[(r, i)],                   va,   taxes=[Tax(RA[r], tf[:lab, i, r])],   reference_price=1 + B.tf[(:lab, i, r)])
            @input(PK[r],              B.kapd0[(r, i)],                   va,   taxes=[Tax(RA[r], tf[:cap, i, r])],   reference_price=1 + B.tf[(:cap, i, r)])
            @input(PF[i, r],           B.ffact[(i, r)],                   b)
            @input(PAC[:gas, r],      aeei[i, r] * B.xa0[(r, :gas, i)],  gas,  taxes=[Tax(RA[r], ti[:gas, i, r])],   reference_price=1 + B.ti[(:gas, i, r)])
            @input(PAC[:coal, r],     aeei[i, r] * B.xa0[(r, :coal, i)], coal, taxes=[Tax(RA[r], ti[:coal, i, r])],  reference_price=1 + B.ti[(:coal, i, r)])
            @input(PAC[:roil, r],     aeei[i, r] * B.xaroilc[(r, i)],    roil, taxes=[Tax(RA[r], ti[:roil, i, r])], reference_price=1 + B.ti[(:roil, i, r)])
            @input(PAC[:oil, r],      aeei[i, r] * B.xa0[(r, :oil, i)],  oil,  taxes=[Tax(RA[r], ti[:oil, i, r])],   reference_price=1 + B.ti[(:oil, i, r)])
            @input(PAC[:elec, r],     aeei[i, r] * B.xa0[(r, :elec, i)], en,   taxes=[Tax(RA[r], ti[:elec, i, r])],  reference_price=1 + B.ti[(:elec, i, r)])
        end)
    end

    for r in REGIONS
        B.xp[(r, :elec)] > 0 || continue
        @production(MGE, D[:elec, r], [t=0, s=0, s001=>s=1, s011=>s001=1], begin
            @output(PD[:elec, r],      B.xp[(r, :elec)],   t)
            @input(PDE[:sele, r],     B.sele0[r],          s001)
            @input(PDE[:dispgen, r],  B.dispgen0[r],       s011)
            @input(PDE[:wele, r],     B.wele0[r],          s011)
            @input(PDE[:tnd, r],      B.tele0[r],          s)
        end)
        @production(MGE, DE[:elec, r], [t=0, s=1.5], begin
            @output(PDE[:dispgen, r],  B.efout0[r],        t)
            [@input(PDE[i_, r],        B.xp_[(i_, r)],    s) for i_ in TECH_F]...
        end)
    end

    for i_ in TECH_F, r in REGIONS
        B.xp_[(i_, r)] > 0 || continue
        @production(MGE, DE[i_, r], [t=0, s=0, bc=>s=0.6, ac=>bc=0, eec=>ac=B.selas[(:elec, :e_kl, r)], curb=>eec=0, vac=>eec=B.selas[(:elec, :l_k, r)]], begin
            @output(PDE[i_, r],        B.xp_[(i_, r)],                                           t,    taxes=[Tax(RA[r], tde[i_, r])])
            [@input(PA[j, r],          B.elecin[(i_, j, r)],                                     ac,   taxes=[Tax(RA[r], elecint[i_, j, r])],    reference_price=1 + B.elecint[(i_, j, r)]) for j in NE]...
            @input(PAC[:gas, r],       aeei[:elec, r] * B.elecin[(i_, :gas, r)],                curb, taxes=[Tax(RA[r], elecint[i_, :gas, r])],  reference_price=1 + B.elecint[(i_, :gas, r)])
            @input(PAC[:coal, r],      aeei[:elec, r] * B.elecin[(i_, :coal, r)],               curb, taxes=[Tax(RA[r], elecint[i_, :coal, r])], reference_price=1 + B.elecint[(i_, :coal, r)])
            @input(PAC[:roil, r],      aeei[:elec, r] * B.elecin[(i_, :roil, r)] * B.cr[:roil, :elec, r],       curb, taxes=[Tax(RA[r], elecint[i_, :roil, r])], reference_price=1 + B.elecint[(i_, :roil, r)])
            @input(PAC[:oil, r],       aeei[:elec, r] * B.elecin[(i_, :oil, r)],                curb, taxes=[Tax(RA[r], elecint[i_, :oil, r])],  reference_price=1 + B.elecint[(i_, :oil, r)])
            @input(PAC[:elec, r],      aeei[:elec, r] * B.elecin[(i_, :elec, r)],               curb, taxes=[Tax(RA[r], elecint[i_, :elec, r])], reference_price=1 + B.elecint[(i_, :elec, r)])
            @input(PA[:roil, r],       aeei[:elec, r] * B.elecin[(i_, :roil, r)] * (1 - B.cr[:roil, :elec, r]), ac,   taxes=[Tax(RA[r], elecint[i_, :roil, r])], reference_price=1 + B.elecint[(i_, :roil, r)])
            @input(PL[r],              B.elecin[(i_, :lab, r)],                                  vac,  taxes=[Tax(RA[r], elecint[i_, :lab, r])],  reference_price=1 + B.elecint[(i_, :lab, r)])
            @input(PK[r],              B.elecin[(i_, :cap, r)],                                  vac,  taxes=[Tax(RA[r], elecint[i_, :cap, r])],  reference_price=1 + B.elecint[(i_, :cap, r)])
            @input(PF_[i_, r],         B.elecin[(i_, :res, r)],                                  bc,   taxes=[Tax(RA[r], elecint[i_, :res, r])],  reference_price=1 + B.elecint[(i_, :res, r)])
        end)
    end

    for i_ in TECH_NHR, r in REGIONS
    B.xp_[(i_, r)] > 0 && B.ffact[(i_, r)] > 0 || continue
        @production(MGE, DE[i_, r], [t=0, s=0, bc=>s=B.nhrsigma[(i_, r)], ac=>bc=0, eec=>ac=B.selas[(:elec, :e_kl, r)], curb=>eec=0, vac=>eec=B.selas[(:elec, :l_k, r)]], begin
            @output(PDE[:dispgen, r],  B.xp_[(i_, r)],                                           t,    taxes=[Tax(RA[r], tde[i_, r])])
            [@input(PA[j, r],          B.elecin[(i_, j, r)],                                     ac,   taxes=[Tax(RA[r], elecint[i_, j, r])],    reference_price=1 + B.elecint[(i_, j, r)]) for j in NE]...
            @input(PAC[:gas, r],       aeei[:elec, r] * B.elecin[(i_, :gas, r)],                curb, taxes=[Tax(RA[r], elecint[i_, :gas, r])],  reference_price=1 + B.elecint[(i_, :gas, r)])
            @input(PAC[:coal, r],      aeei[:elec, r] * B.elecin[(i_, :coal, r)],               curb, taxes=[Tax(RA[r], elecint[i_, :coal, r])], reference_price=1 + B.elecint[(i_, :coal, r)])
            @input(PAC[:roil, r],      aeei[:elec, r] * B.elecin[(i_, :roil, r)] * B.cr[:roil, :elec, r],       curb, taxes=[Tax(RA[r], elecint[i_, :roil, r])], reference_price=1 + B.elecint[(i_, :roil, r)])
            @input(PAC[:oil, r],       aeei[:elec, r] * B.elecin[(i_, :oil, r)],                curb, taxes=[Tax(RA[r], elecint[i_, :oil, r])],  reference_price=1 + B.elecint[(i_, :oil, r)])
            @input(PAC[:elec, r],      aeei[:elec, r] * B.elecin[(i_, :elec, r)],               curb, taxes=[Tax(RA[r], elecint[i_, :elec, r])], reference_price=1 + B.elecint[(i_, :elec, r)])
            @input(PA[:roil, r],       aeei[:elec, r] * B.elecin[(i_, :roil, r)] * (1 - B.cr[:roil, :elec, r]), ac,   taxes=[Tax(RA[r], elecint[i_, :roil, r])], reference_price=1 + B.elecint[(i_, :roil, r)])
            @input(PL[r],              B.elecin[(i_, :lab, r)],                                  vac,  taxes=[Tax(RA[r], elecint[i_, :lab, r])],  reference_price=1 + B.elecint[(i_, :lab, r)])
            @input(PK[r],              B.elecin[(i_, :cap, r)],                                  vac,  taxes=[Tax(RA[r], elecint[i_, :cap, r])],  reference_price=1 + B.elecint[(i_, :cap, r)])
            @input(PF_[i_, r],         B.elecin[(i_, :res, r)],                                  bc,   taxes=[Tax(RA[r], elecint[i_, :res, r])],  reference_price=1 + B.elecint[(i_, :res, r)])
        end)
    end

    for i_ in TECH_N, r in REGIONS
        B.xp_[(i_, r)] > 0 || continue
        @production(MGE, DE[i_, r], [t=0, s=0, s001=>s=B.wst[(i_, r)], ac=>s001=0, eec=>ac=B.selas[(:elec, :e_kl, r)], curb=>eec=0, vac=>eec=B.selas[(:elec, :l_k, r)]], begin
            @output(PDE[i_, r],        B.xp_[(i_, r)],                                           t,    taxes=[Tax(RA[r], tde[i_, r])])
            [@input(PA[j, r],          B.elecin[(i_, j, r)],                                     ac,   taxes=[Tax(RA[r], elecint[i_, j, r])],    reference_price=1 + B.elecint[(i_, j, r)]) for j in NE]...
            @input(PAC[:gas, r],       aeei[:elec, r] * B.elecin[(i_, :gas, r)],                curb, taxes=[Tax(RA[r], elecint[i_, :gas, r])],  reference_price=1 + B.elecint[(i_, :gas, r)])
            @input(PAC[:coal, r],      aeei[:elec, r] * B.elecin[(i_, :coal, r)],               curb, taxes=[Tax(RA[r], elecint[i_, :coal, r])], reference_price=1 + B.elecint[(i_, :coal, r)])
            @input(PAC[:roil, r],      aeei[:elec, r] * B.elecin[(i_, :roil, r)] * B.cr[:roil, :elec, r],       curb, taxes=[Tax(RA[r], elecint[i_, :roil, r])], reference_price=1 + B.elecint[(i_, :roil, r)])
            @input(PAC[:oil, r],       aeei[:elec, r] * B.elecin[(i_, :oil, r)],                curb, taxes=[Tax(RA[r], elecint[i_, :oil, r])],  reference_price=1 + B.elecint[(i_, :oil, r)])
            @input(PAC[:elec, r],      aeei[:elec, r] * B.elecin[(i_, :elec, r)],               curb, taxes=[Tax(RA[r], elecint[i_, :elec, r])], reference_price=1 + B.elecint[(i_, :elec, r)])
            @input(PA[:roil, r],       aeei[:elec, r] * B.elecin[(i_, :roil, r)] * (1 - B.cr[:roil, :elec, r]), ac,   taxes=[Tax(RA[r], elecint[i_, :roil, r])], reference_price=1 + B.elecint[(i_, :roil, r)])
            @input(PL[r],              B.elecin[(i_, :lab, r)],                                  vac,  taxes=[Tax(RA[r], elecint[i_, :lab, r])],  reference_price=1 + B.elecint[(i_, :lab, r)])
            @input(PK[r],              B.elecin[(i_, :cap, r)],                                  vac,  taxes=[Tax(RA[r], elecint[i_, :cap, r])],  reference_price=1 + B.elecint[(i_, :cap, r)])
        end)
    end

    for i_ in [:tele], r in REGIONS
        B.xp_[(i_, r)] > 0 || continue
        @production(MGE, DE[i_, r], [t=0, s=0, s001=>s=0.6, ac=>s001=0, eec=>ac=B.selas[(:elec, :e_kl, r)], curb=>eec=0, vac=>eec=B.selas[(:elec, :l_k, r)]], begin
            @output(PDE[:tnd, r],      B.xp_[(i_, r)],                                           t,    taxes=[Tax(RA[r], tde[i_, r])])
            [@input(PA[j, r],          B.elecin[(i_, j, r)],                                     ac,   taxes=[Tax(RA[r], elecint[i_, j, r])],    reference_price=1 + B.elecint[(i_, j, r)]) for j in NE]...
            @input(PAC[:gas, r],       aeei[:elec, r] * B.elecin[(i_, :gas, r)],                curb, taxes=[Tax(RA[r], elecint[i_, :gas, r])],  reference_price=1 + B.elecint[(i_, :gas, r)])
            @input(PAC[:coal, r],      aeei[:elec, r] * B.elecin[(i_, :coal, r)],               curb, taxes=[Tax(RA[r], elecint[i_, :coal, r])], reference_price=1 + B.elecint[(i_, :coal, r)])
            @input(PAC[:roil, r],      aeei[:elec, r] * B.elecin[(i_, :roil, r)] * B.cr[:roil, :elec, r],       curb, taxes=[Tax(RA[r], elecint[i_, :roil, r])], reference_price=1 + B.elecint[(i_, :roil, r)])
            @input(PAC[:oil, r],       aeei[:elec, r] * B.elecin[(i_, :oil, r)],                curb, taxes=[Tax(RA[r], elecint[i_, :oil, r])],  reference_price=1 + B.elecint[(i_, :oil, r)])
            @input(PAC[:elec, r],      aeei[:elec, r] * B.elecin[(i_, :elec, r)],               curb, taxes=[Tax(RA[r], elecint[i_, :elec, r])], reference_price=1 + B.elecint[(i_, :elec, r)])
            @input(PA[:roil, r],       aeei[:elec, r] * B.elecin[(i_, :roil, r)] * (1 - B.cr[:roil, :elec, r]), ac,   taxes=[Tax(RA[r], elecint[i_, :roil, r])], reference_price=1 + B.elecint[(i_, :roil, r)])
            @input(PL[r],              B.elecin[(i_, :lab, r)],                                  vac,  taxes=[Tax(RA[r], elecint[i_, :lab, r])],  reference_price=1 + B.elecint[(i_, :lab, r)])
            @input(PK[r],              B.elecin[(i_, :cap, r)],                                  vac,  taxes=[Tax(RA[r], elecint[i_, :cap, r])],  reference_price=1 + B.elecint[(i_, :cap, r)])
        end)
    end

    for r in REGIONS
        @production(MGE, GOVT[r], [t=0, s=0.5], begin
            @output(PG[r],             B.g0[r],                                t)
            [@input(PA[i, r],          B.govdem0[(r, i)],                      s,                      taxes=[Tax(RA[r], tg[i, r])],                           reference_price=B.pg0[(i, r)]) for i in SECTORS]...
            @input(PHOM[r],            B.govoil0[r],                           s,                      taxes=[Tax(RA[r], tg[:oil, r])],                        reference_price=B.pg0[(:oil, r)])
        end)
        @production(MGE, INV[r], [t=0, s=5], begin
            @output(PINV[r],           B.inv0[r],                              t)
            [@input(PA[i, r],          B.invdem0[(r, i)],                      s) for i in SECTORS]...
            @input(PHOM[r],            B.invoil0[r],                           s)
        end)
    end

    @production(MGE, YT, [t=0, s=1], begin
        @output(PT,                    B.ytout0,                               t)
        [@input(PD[:tran, r],          B.trnvst0[r],                           s) for r in REGIONS]...
    end)

    for r in REGIONS
        foodp = r == :BRA ? :eint : :food
        @production(MGE, HNEW[r], [t=0, s=0.1, a=>s=(r == :USA || r == :EUR ? 0.75 : 1.0), c=>a=0, b=>s=1], begin
            @output(PTNN[r],           B.own[r] * HTRNS,                                t)
            @input(PAC[:roil, r],      B.tfo[r] * HTRNS * B.cr[:roil, :final, r],       c,              taxes=[Tax(RA[r], tp[:roil, r])],                            reference_price=B.pc0[(:roil, r)])
            @input(PA[:roil, r],       B.tfo[r] * HTRNS * (1 - B.cr[:roil, :final, r]), c,              taxes=[Tax(RA[r], tp[:roil, r])],                            reference_price=B.pc0[(:roil, r)])
            @input(PDB[foodp, r],      B.tbo[r] * HTRNS,                                c,              taxes=[Tax(RA[r], tp[:roil, r])],                            reference_price=B.pc0[(:roil, r)])
            @input(PA[:othr, r],       B.toi[r] * HTRNS * PROPFRAC,                     a,              taxes=[Tax(RA[r], tp[:othr, r])],                       reference_price=B.pc0[(:othr, r)])
            @input(PA[:othr, r],       B.toi[r] * HTRNS * (1 - PROPFRAC),               b,              taxes=[Tax(RA[r], tp[:othr, r])],                       reference_price=B.pc0[(:othr, r)])
            @input(PA[:serv, r],       B.tse[r] * HTRNS,                                b,              taxes=[Tax(RA[r], tp[:serv, r])],                       reference_price=B.pc0[(:serv, r)])
        end)
        @production(MGE, HOLD[r], [t=0, s=0], begin
            @output(PTNV[r],           (1 - HTRNS) * B.own[r],                          t)
            @input(PAC[:roil, r],      (1 - HTRNS) * B.tfo[r] * B.cr[:roil, :final, r], s,              taxes=[Tax(RA[r], tp[:roil, r])],                            reference_price=B.pc0[(:roil, r)])
            @input(PA[:roil, r],       (1 - HTRNS) * B.tfo[r] * (1 - B.cr[:roil, :final, r]), s,        taxes=[Tax(RA[r], tp[:roil, r])],                            reference_price=B.pc0[(:roil, r)])
            @input(PDB[foodp, r],      (1 - HTRNS) * B.tbo[r],                          s,              taxes=[Tax(RA[r], tp[:roil, r])],                            reference_price=B.pc0[(:roil, r)])
            @input(PA[:othr, r],       (1 - HTRNS) * B.toi[r],                          s,              taxes=[Tax(RA[r], tp[:othr, r])],                       reference_price=B.pc0[(:othr, r)])
            @input(PA[:serv, r],       (1 - HTRNS) * B.tse[r],                          s,              taxes=[Tax(RA[r], tp[:serv, r])],                       reference_price=B.pc0[(:serv, r)])
        end)
        @production(MGE, HAGG[r], [t=4, s=0], begin
            @output(PTN[r],            B.own[r] * 0.2,                                  t)
            @output(PTNS[r],           B.own[r] * 0.8,                                  t)
            @input(PTNN[r],            B.own[r] * HTRNS,                                s)
            @input(PTNV[r],            B.own[r] * (1 - HTRNS),                          s)
        end)            
        @production(MGE, HTRN[r], [t=0, s=0.2, s1=>s=4], begin          
            @output(PTRN[r],           B.tottrn[r],                                     t)
            @input(PA[:tran, r],       B.purtrn[r],                                     s,              taxes=[Tax(RA[r], tp[:tran, r])],                       reference_price=B.pc0[(:tran, r)])
            @input(PTN[r],             B.own[r] * 0.2,                                  s1)
            @input(PTNS[r],            B.own[r] * 0.8,                                  s1)
        end)

        @production(MGE, Z[r], [t=0, s=0.5, u=>s=0.25, a=>u=B.d_elas[r], dw=>u=0.3, en=>dw=B.selas[(:hh, :noe_el, r)], oil=>en=0, gas=>en=0, coal=>en=0, roil=>en=0, elec=>en=0], begin
            @output(PU[r],             B.cons0[r] + B.hhwedge[r],                 t)
            @input(PTRN[r],            B.tottrn[r],                                     s)
            [@input(PA[i, r],          B.xh[(i, r)],                                    a,              taxes=[Tax(RA[r], tp[i, r])],                           reference_price=B.pc0[(i, r)]) for i in NENDT]...
            @input(PA[:dwe, r],       B.xh[(:dwe, r)],                                 dw,             taxes=[Tax(RA[r], tp[:dwe, r])],                        reference_price=B.pc0[(:dwe, r)])
            @input(PAC[:oil, r],       B.ence1[(:oil, r)],                              oil,            taxes=[Tax(RA[r], tp[:oil, r])],                        reference_price=B.pc0[(:oil, r)])
            @input(PAC[:gas, r],       B.ence1[(:gas, r)],                              gas,            taxes=[Tax(RA[r], tp[:gas, r])],                        reference_price=B.pc0[(:gas, r)])
            @input(PAC[:coal, r],      B.ence1[(:coal, r)],                             coal,           taxes=[Tax(RA[r], tp[:coal, r])],                       reference_price=B.pc0[(:coal, r)])
            @input(PAC[:roil, r],      B.ence1[(:roil, r)] * B.cr[:roil, :final, r],    roil,           taxes=[Tax(RA[r], tp[:roil, r])],                       reference_price=B.pc0[(:roil, r)])
            @input(PA[:roil, r],       B.ence1[(:roil, r)] * (1 - B.cr[:roil, :final, r]), roil,        taxes=[Tax(RA[r], tp[:roil, r])],                       reference_price=B.pc0[(:roil, r)])
            @input(PAC[:elec, r],      B.ence1[(:elec, r)],                             elec,           taxes=[Tax(RA[r], tp[:elec, r])],                       reference_price=B.pc0[(:elec, r)])
        end)
        @production(MGE, W[r], [t=0, s=0], begin
            @output(PW[r],             B.cons0[r] + B.inv0[r] + B.hhwedge[r],           t)
            @input(PU[r],              B.cons0[r] + B.hhwedge[r],                       s)
            @input(PINV[r],            B.inv0[r],                                       s)
        end)
    end

    for i in SECTORS, r in REGIONS
        (i != :oil && B.a0[(r, i)] != 0) || continue
        @production(MGE, A[i, r], [t=0, s=B.selas[(i, :sdm, r)]], begin
            @output(PA[i, r],          B.xat0[r, i],                                    t)
            @input(PD[i, r],           B.xd0[(r, i)],                                   s)
            @input(PM[i, r],           B.xm0[(r, i)],                                   s)
        end)
    end

    for i in SECTORS, r in REGIONS
        (i != :oil && B.xm0[(r, i)] > 0) || continue
        @production(MGE, M[i, r], [t=0, s=B.selas[(i, :smm, r)], src[rr=REGIONS]=>s=0], begin
            @output(PM[i, r],          B.xm0[(r, i)],                                   t)
            [@input(PD[i, rr],         B.wtflow0[(r, rr, i)],                           src[rr],        taxes=[Tax(RA[rr], tx[i, rr, r]), Tax(RA[r], tm[i, rr, r] * (1 + tx[i, rr, r]))], reference_price=(1 + B.tx[(i, rr, r)]) * (1 + B.tm[(i, rr, r)])) for rr in REGIONS]...
            [@input(PT,                B.mvtwr[(r, rr, i)],                             src[rr],        taxes=[Tax(RA[r], tm[i, rr, r])],                                   reference_price=1 + B.tm[(i, rr, r)]) for rr in REGIONS]...
        end)
    end

    for r in REGIONS
        B.homm0[r] > 0 || continue
        @production(MGE, HOMM[r], [t=0, s=0], begin
            @output(PHOM[r],           B.vhomm0[r],                                     t)
            @input(PWH,                B.homm0[r],                                      s,              taxes=[Tax(RA[r], tmhom[r])])
            @input(PT,                 B.homt0[r],                                      s,              taxes=[Tax(RA[r], tmhom[r])])
        end)
    end

    for r in REGIONS
        B.homx0[r] > 0 || continue
        @production(MGE, HOMX[r], [t=0, s=0], begin
            @output(PWH,               B.homx0[r],                                      t)
            @input(PHOM[r],            B.vhomx0[r],                                     s,              taxes=[Tax(RA[r], txhom[r])])
        end)
    end

    for r in REGIONS
        @demand(MGE, RA[r], begin
            @final_demand(PW[r],       w0[r])
            @endowment(PK[r],          k0[r] * GPROD[r])
            @endowment(PL[r],          l0[r] * GPROD[r])
            [@endowment(PF[i, r],      ff0[i, r] + GPROD[r] * fn0[i, r]) for i in SECTORS]...
            [@endowment(PF_[i_, r],    ffe[i_, r]) for i_ in TECH_NHR]...
            @endowment(PU[:USA],       -bop[r])
            @endowment(PG[r],          -grg[r])
            @endowment(PHOM[r],        B.homadj[r])
            @endowment(PT,             B.trnadj[r])
        end)
    end

    for r in REGIONS, g in EJUSE_SECTORS, e in ENERGY
        expr = B.ejuse_over_euse[(e, g, r)] * B.euse0[(e, g, r)] * AC[e, ac_group(g), r]
        @aux_constraint(MGE, EE[e, g, r], EE[e, g, r] - expr)
    end

    for r in REGIONS, g in SCO2_SECTORS, e in SCO2_ENERGY
        @aux_constraint(MGE, SCO2[e, g, r], SCO2[e, g, r] - B.sco2coef[e] * EE[e, g, r])
    end

    for r in REGIONS
        # Calculate FTOTCO2[r]
        @aux_constraint(MGE, FTOTCO2[r],
            FTOTCO2[r] - sum(SCO2[e, g, r] for e in SCO2_ENERGY for g in SCO2_SECTORS))

        @aux_constraint(MGE, CP[r], 
            (co2cap[r] - FTOTCO2[r]) / max(B.ftotco20[r], 1.0))

        for e in SCO2_ENERGY, g in AC_SECTORS
            # the ratio B.cperv / B.cscale has no unit; CP is the tax rate on the most carbon-intensive fuel
            @aux_constraint(MGE, CT[e, g, r], 
                CT[e, g, r] - CP[r] * (B.cperv[(e, g, r)] / B.cscale[r]))
        end
    end

    for r in REGIONS

        @aux_constraint(MGE, RGDP[r],
            PU[r] * RGDP[r] 
                - PU[r] * B.cons0[r] * Z[r] 
                - B.inv0[r] * PINV[r] * INV[r] 
                - B.g0[r] * PG[r] * GOVT[r] 
                - sum((1 + B.tx[(i, r, rr)]) * PD[i, r] * B.wtflow0[(rr, r, i)] 
                    for rr in REGIONS for i in SECTORS if i != :oil && B.wtflow0[(rr, r, i)] > 0; init=0) 
                - (B.homx0[r] > 0 ? PWH * B.homx0[r] * HOMX[r] : 0)
                + sum((1 + B.tx[(i, rr, r)]) * PD[i, rr] * B.wtflow0[(r, rr, i)] 
                    for rr in REGIONS for i in SECTORS if i != :oil && B.wtflow0[(r, rr, i)] > 0; init=0) 
                + (B.homm0[r] > 0 ? PWH * B.homm0[r] * HOMM[r] : 0)
            )
        
        if simu == 0
            @aux_constraint(MGE, GPROD[r], RGDP[r] - gdp0[r])
        else
            @aux_constraint(MGE, GPROD[r], GPROD[r] - gprod0[r])
        end
        
    end

    fix(PU[:USA], 1.0)
    
    return MGE
end







