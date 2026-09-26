function EPPACore(MGE, data, setting)

    @parameters(MGE, begin
        tm[i=data["set_i"],     r=data["set_r"], s=data["set_r"]],  data["rtms0"][i, r, s], (description = "Import tax rates")
        tx[i=data["set_i"],     r=data["set_r"], s=data["set_r"]],  data["rtxs0"][i, r, s], (description = "Export subsidy rates")
        td[r=data["set_r"],     g=data["set_g"]],                   data["rto0"][g, r],     (description = "Output tax or subsidy rates")
        ta[i=data["set_i"],     g=data["set_g"], r=data["set_r"]],  data["ta0"][i, g, r],   (description = "Tax rate on Armington good")
        tf[f=data["set_f"],     i=data["set_i"], r=data["set_r"]],  data["rtf0"][f, i, r],  (description = "Primary factor tax rates")
        tb[r=data["set_r"]],                                        data["tb0"][r],         (description = "Tax rate on biofuels used by HOW")
        tde[r=data["set_r"],    g=data["set_v"]],                   data["rto0e"][g, r],    (description = "Output tax or subsidy rates")
        tae[i=data["set_i"],    g=data["set_v"], r=data["set_r"]],  data["ta0e"][i, g, r],  (description = "Tax rate on Armington good")
        tfe[f=data["set_f"],    i=data["set_v"], r=data["set_r"]],  data["rtf0e"][f, i, r], (description = "Primary factor tax rates")
        tfp[r=data["set_r"]],                                       1,                      (description = "Total factor productivity")
        gdp[r=data["set_r"]],                                       data["gdp0"][r],        (description = "Real GDP")
        tco2[r=data["set_r"]],                                      data["tco2"][r],        (description = "Baseline total CO2")
        rer[r=data["set_r"]],                                       1,                      (description = "Remaining emissions ratio")
        policy[r=data["set_r"]],                                    false,                  (description = "CO2 policy timing")
        evom[f=data["set_mf"], r=data["set_r"]],                    data["evom"][f, r],     (description = "Return to mobile endowment")
    end)

    @sectors(MGE, begin
        D[i=data["set_i"], r=data["set_r"]],                       (description = "Supply")
        DL[i=data["set_v"], r=data["set_r"]],                      (description = "Disaggregated power supply")
        M[i=data["set_i"], r=data["set_r"]],                       (description = "Imports")
        YT[i=data["set_i"]],                                       (description = "Transportation services")
        X[i=data["set_i"], r=data["set_r"], s=data["set_r"]],      (description = "Exports: Subsidy and transport service included")
        A[i=data["set_i"], g=data["set_gnev"], r=data["set_r"]],   (description = "Armington good: nonenergy and noncombusted p_c")
        EN[i=data["set_e"], g=data["set_gnev"], r=data["set_r"]],  (description = "Armington good: energy goods including all combusted and elec")
        Z[r=data["set_r"]],                                        (description = "Aggregate private consumption")
        GOV[r=data["set_r"]],                                      (description = "Aggregate government consumption")
        INV[r=data["set_r"]],                                      (description = "Investment")
        HOW[r=data["set_r"]],                                      (description = "Household transportation: Own-supplied")
        HHT[r=data["set_r"]],                                      (description = "Household transportation: Total")
        B[r=data["set_r"]],                                        (description = "Conversion to traditional biofuels")
        W[r=data["set_r"]],                                        (description = "Aggregate private consumption")
    end)

    @commodities(MGE, begin
        PD[i=data["set_i"], r=data["set_r"]],                      (description = "Domestic output price")
        PL[g=data["set_v"], r=data["set_r"]],                      (description = "Price index for each power subsector")  
        PM[i=data["set_i"], r=data["set_r"]],                      (description = "Import price")
        PT[i=data["set_i"]],                                       (description = "Transportation services")
        PF[mf=data["set_mf"], r=data["set_r"]],                    (description = "Non-sector-specific primary factor rent")
        PS[sf=data["set_sf"], g=data["set_gv"], r=data["set_r"]],  (description = "Sector-specific primary factor rent")
        PX[i=data["set_i"], r=data["set_r"], s=data["set_r"]],     (description = "Price index for exports (include subsidy and transport service)")
        PA[i=data["set_i"], r=data["set_r"]],                      (description = "Price index for Armington good")
        PE[i=data["set_e"], g=data["set_gv"], r=data["set_r"]],    (description = "Price index for Armington energy good: carbon-penalty-inclusive")
        PG[r=data["set_r"]],                                       (description = "Price index for aggregate government expenditure")
        PU[r=data["set_r"]],                                       (description = "Price index for aggregate consumption")
        PI[r=data["set_r"]],                                       (description = "Price index for investment")
        PN[r=data["set_r"]],                                       (description = "Price index for household transportation: Own-supplied")
        PH[r=data["set_r"]],                                       (description = "Price index for household transportation: Total")
        PW[r=data["set_r"]],                                       (description = "Price index for saving included welfare")
    end)

    @consumers(MGE, begin
        RA[r=data["set_r"]],                                       (description = "Representative agent")
    end)

    @auxiliaries(MGE, begin
        CTAXR[i=data["set_fe"], r=data["set_r"]],                  (description = "Carbon tax rate")
        PC[r=data["set_r"]],                                       (description = "Carbon price index (USD/t-CO2)")
        TCO2[r=data["set_r"]],                                     (description = "Total CO2 [billion t-CO2]")
        GDP[r=data["set_r"]],                                      (description = "Real GDP")
        TFP[r=data["set_r"]],                                      (description = "Total factor productivity")
        GDPINDEX[r=data["set_r"]],                                 (description = "Real GDP index with base year normalizing to one")
    end)

    for r ∈ data["set_r"]
        set_start_value(TCO2[r], data["tco2"][r])
        set_start_value(GDP[r], data["gdp0"][r])
        set_start_value(GDPINDEX[r], 1)
        set_start_value(TFP[r], 1)
        set_lower_bound(MGE[:PC][r], 0.0)
        set_lower_bound(MGE[:GDP][r], 0.0)
        set_lower_bound(MGE[:GDPINDEX][r], 0.0)
        set_lower_bound(MGE[:TFP][r], 0.0)
        for f ∈ data["set_mf"]
            set_lower_bound(MGE[:PF][f, r], 0.0)
        end
    end

    @production(MGE, A[i=data["set_i"], g=data["set_gnev"], r=data["set_r"]], [t = 0, s = 3], begin
        @output(PA[i, r],                       data["xa0a"][r, i, g],      t)
        @input(PD[i, r],                        data["xd0a"][r, i, g],      s)
        @input(PM[i, r],                        data["xm0a"][r, i, g],      s)
    end)

    @production(MGE, EN[i=data["set_elec"], g=data["set_gnev"], r=data["set_r"]], [t = 0, s = 0], begin
        @output(PE[i, g, r],                    data["xa0a"][r, i, g],      t)
        @input(PA[i, r],                        data["xa0a"][r, i, g],      s)
    end)

    @production(MGE, EN[i=data["set_fe"], g=data["set_gnev"], r=data["set_r"]], [t = 0, s = 0], begin
        @output(PE[i, g, r],                    data["xa0a_c"][r, i, g],    t)
        @input(PA[i, r],                        data["xa0a_c"][r, i, g],    s, taxes = [Tax(RA[r], CTAXR[i,r])])
    end)

    for g ∈ data["set_note"], r ∈ data["set_r"]
        @production(MGE, D[g, r], [t= 0, s = 0.3, nl => s = 0.3, nv => nl = 0.1, va => nv = 1, ne => nv = 0.1, nn => ne = 0.1, ee => ne = 1.5, fe => ee = 1.0], begin
            @output(PD[g, r],                       data["xp0"][r, g],          t,      taxes = [Tax(RA[r], td[r, g])],     reference_price = 1-data["rto0"][g, r])
            @input(PE[i=data["set_roil"], g, r],    data["xa0_c"][r, i, g],     fe,     taxes = [Tax(RA[r], ta[i, g, r])],  reference_price = 1+data["ta0"][i, g, r])
            @input(PE[i=data["set_fnr"], g, r],     data["xa0"][r, i, g],       fe,     taxes = [Tax(RA[r], ta[i, g, r])],  reference_price = 1+data["ta0"][i, g, r])
            @input(PE[i=data["set_elec"], g, r],    data["xa0"][r, i, g],       ee,     taxes = [Tax(RA[r], ta[i, g, r])],  reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_ne"], r],         data["xa0"][r, i, g],       nn,     taxes = [Tax(RA[r], ta[i, g, r])],  reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_roil"], r],       data["xa0_n"][r, i, g],     nn,     taxes = [Tax(RA[r], ta[i, g, r])],  reference_price = 1+data["ta0"][i, g, r])
            @input(PS[sf=data["set_fix"], g, r],    data["vfm"][sf, g, r],      s,      taxes = [Tax(RA[r], tf[sf, g, r])], reference_price = 1 + data["rtf0"][sf, g, r])
            @input(PS[sf=data["set_lnd"], g, r],    data["vfm"][sf, g, r],      nl,     taxes = [Tax(RA[r], tf[sf, g, r])], reference_price = 1 + data["rtf0"][sf, g, r])
            @input(PF[mf=data["set_mf"], r],        data["vfm"][mf, g, r],      va,     taxes = [Tax(RA[r], tf[mf, g, r])], reference_price = 1 + data["rtf0"][mf, g, r])
        end)
    end

    # The only way to use the same D[i, r] for data["set_note"] and data["set_elec"] is to use the for loop rather than using D[i=data[...], r=data[...]]
    for i ∈ data["set_elec"], r ∈ data["set_r"]
        @production(MGE, D[i, r], [t = 0, s = 0, s1 => s = 5], begin
            @output(PD[i, r],                       data["xp0"][r, i],          t)
            @input(PL[:tele, r],                    data["xp0e"][r, :tele],     s)
            @input(PL[g=data["set_vole"], r],       data["xp0e"][r, g],         s)
        end)
    end

    # Power subsector
    @production(MGE, DL[g=data["set_v"], r=data["set_r"]], [t= 0, s = 0.3, nl => s = 0.3, nv => nl = 0.1, va => nv = 1, ne => nv = 0.1, nn => ne = 0.1, ee => ne = 1.5, fe => ee = 1.0], begin
        @output(PL[g, r],                       data["xp0e"][r, g],         t,      taxes = [Tax(RA[r], tde[r, g])],     reference_price = 1-data["rto0e"][g, r])
        @input(PE[i=data["set_roil"], g, r],    data["xa0e_c"][r, i, g],    fe,     taxes = [Tax(RA[r], tae[i, g, r])],  reference_price = 1+data["ta0e"][i, g, r])
        @input(PE[i=data["set_fnr"], g, r],     data["xa0e"][r, i, g],      fe,     taxes = [Tax(RA[r], tae[i, g, r])],  reference_price = 1+data["ta0e"][i, g, r])
        @input(PE[i=data["set_elec"], g, r],    data["xa0e"][r, i, g],      ee,     taxes = [Tax(RA[r], tae[i, g, r])],  reference_price = 1+data["ta0e"][i, g, r])
        @input(PA[i=data["set_ne"], r],         data["xa0e"][r, i, g],      nn,     taxes = [Tax(RA[r], tae[i, g, r])],  reference_price = 1+data["ta0e"][i, g, r])
        @input(PA[i=data["set_roil"], r],       data["xa0e_n"][r, i, g],    nn,     taxes = [Tax(RA[r], tae[i, g, r])],  reference_price = 1+data["ta0e"][i, g, r])
        @input(PS[sf=data["set_fix"], g, r],    data["vfme"][sf, g, r],     s,      taxes = [Tax(RA[r], tfe[sf, g, r])], reference_price = 1 + data["rtf0e"][sf, g, r])
        @input(PS[sf=data["set_lnd"], g, r],    data["vfme"][sf, g, r],     nl,     taxes = [Tax(RA[r], tfe[sf, g, r])], reference_price = 1 + data["rtf0e"][sf, g, r])
        @input(PF[mf=data["set_mf"], r],        data["vfme"][mf, g, r],     va,     taxes = [Tax(RA[r], tfe[mf, g, r])], reference_price = 1 + data["rtf0e"][mf, g, r])
    end)

    for g ∈ data["set_con"], r ∈ data["set_r"]
        @production(MGE, Z[r], [t = 0, s = 0, nh => s = 0.5, ne => nh = 0.25, nn => ne = 0.25, nd => ne = 0.3, ee => nd = 1.5, fe => ee = 1.5], begin
            @output(PU[r],                      data["cons0"][r],           t,      taxes = [Tax(RA[r], td[r, g])])
            @input(PE[i=data["set_roil"], g, r],data["xa0_rc"][r, i, g],    fe,     taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PE[i=data["set_fnr"], g, r], data["xa0"][r, i, g],       fe,     taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PE[i=data["set_elec"], g, r],data["xa0"][r, i, g],       ee,     taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_rest"], r],   data["xa0"][r, i, g],       nn,     taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_serv"], r],   data["xa0_s"][r, i, g],     nn,     taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_othr"], r],   data["xa0_o"][r, i, g],     nn,     taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_food"], r],   data["xa0_f"][r, i, g],     nn,     taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_eint"], r],   data["xa0_e"][r, i, g],     nn,     taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_roil"], r],   data["xa0_rn"][r, i, g],    nn,     taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_dwe"], r],    data["xa0"][r, i, g],       nd,     taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PH[r],                       data["tottrn"][r],          nh)
        end)
    end

    for r ∈ data["set_r"], g ∈ data["set_con"]
        @production(MGE, HHT[r], [t = 0, s = 0.2], begin
            @output(PH[r],                      data["tottrn"][r],          t)
            @input(PN[r],                       data["own"][r],             s)
            @input(PA[i=data["set_tran"], r],   data["xa0"][r, i, g],       s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
        end)
    end

    for r ∈ data["set_r"]
        @production(MGE, HOW[r], [t = 0, s = 0.1, a => s = 0.75, c => a = 0.0, b => s = 1.0], begin
            @output(PN[r],                      data["own"][r],             t)
            @input(PE[:p_c, :c, r],             data["tfb_c"][r],           c,      taxes = [Tax(RA[r], ta[:p_c, :c, r])], reference_price = 1+data["ta0"][:p_c, :c, r])
            @input(PA[:p_c, r],                 data["tfo_n"][r],           c,      taxes = [Tax(RA[r], ta[:p_c, :c, r])], reference_price = 1+data["ta0"][:p_c, :c, r])
            @input(PA[:othr, r],                data["toi_prop"][r],        a,      taxes = [Tax(RA[r], ta[:othr, :c, r])], reference_price = 1+data["ta0"][:othr, :c, r])
            @input(PA[:othr, r],                data["toi_rest"][r],        b,      taxes = [Tax(RA[r], ta[:othr, :c, r])], reference_price = 1+data["ta0"][:othr, :c, r])
            @input(PA[:serv, r],                data["tse"][r],             b,      taxes = [Tax(RA[r], ta[:serv, :c, r])], reference_price = 1+data["ta0"][:serv, :c, r])
        end)
    end

    for r ∈ data["set_r"]
        @production(MGE, B[r], [t = 0, s = 0], begin
            @output(PE[:p_c, :c, r],            data["tbo_r"][r],           t)
            if r ∈ data["set_br"]
                @input(PA[:eint, r],            data["tbo"][r],             s,      taxes = [Tax(RA[r], tb[r])], reference_price = 1+data["tb0"][r])
            else
                @input(PA[:food, r],            data["tbo"][r],             s,      taxes = [Tax(RA[r], tb[r])], reference_price = 1+data["tb0"][r])
            end
        end)
    end

    for g ∈ data["set_gov"], r ∈ data["set_r"]
        @production(MGE, GOV[r], [t = 0, s = 0.5], begin
            @output(PG[r],                      data["g0"][r],              t,      taxes = [Tax(RA[r], td[r, g])])
            @input(PE[i=data["set_fe"], g, r],  data["xa0"][r, i, g],       s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PE[i=data["set_elec"], g, r],data["xa0"][r, i, g],       s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_ne"], r],     data["xa0"][r, i, g],       s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
        end)
    end

    for g ∈ data["set_inv"], r ∈ data["set_r"]
        @production(MGE, INV[r], [t = 0, s = 5], begin
            @output(PI[r],                      data["inv0"][r],            t,      taxes = [Tax(RA[r], td[r, g])])
            @input(PE[i=data["set_fe"], g, r],  data["xa0"][r, i, g],       s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PE[i=data["set_elec"], g, r],data["xa0"][r, i, g],       s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_ne"], r],     data["xa0"][r, i, g],       s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
        end)
    end

    @production(MGE, YT[j=data["set_i"]], [t = 0, s = 1], begin
        @output(PT[j],                          data["vtw"][j],             t)
        @input(PD[j, r=data["set_r"]],          data["vst"][j, r],          s)
    end)

    # Imports for region r
    @production(MGE, M[i=data["set_i"], r=data["set_r"]], [t = 0, s = 5], begin
        @output(PM[i, r],                       data["vim"][i, r],          t)
        @input(PX[i, s=data["set_r"], r],       data["x0"][s, r, i],        s,      taxes = [Tax(RA[r], tm[i, s, r])], reference_price = data["pvtwr"][i, s, r])
    end)

    # Exports for region s
    @production(MGE, X[i=data["set_i"], s=data["set_r"], r=data["set_r"]], [t = 0, s = 0], begin
        @output(PX[i, s, r], data["x0"][s, r, i],                           t)
        @input(PD[i, s],                        data["wtflow0"][r, s, i],   s,    taxes = [Tax(RA[s], -tx[i, s, r])],   reference_price = 1 - data["rtxs0"][i, s, r])
        @input(PT[j=data["set_i"]],             data["vtwr"][j, i, s, r],   s)
    end)

    @production(MGE, W[r=data["set_r"]], [t = 0, s = 0.5], begin
        @output(PW[r],                          data["w0"][r],              t)
        @input(PU[r],                           data["cons0"][r],           s)
        @input(PI[r],                           data["inv0"][r],            s)
    end)

    @demand(MGE, RA[r=data["set_r"]], begin
        @final_demand(PW[r],                                    data["w0"][r])
        @endowment(PU[:USA],                                    data["vb"][r]*GDPINDEX[r])
        @endowment(PG[r],                                      -data["g0"][r]*GDPINDEX[r])
        @endowment(PF[f=data["set_mf"], r],                     evom[f, r]*TFP[r])
        @endowment(PS[f=data["set_fix"], j=data["set_i"], r],   data["vfm"][f, j, r])
        @endowment(PS[f=data["set_lnd"], j=data["set_i"], r],   data["vfm"][f, j, r])
    end)

    for r ∈ data["set_r"]
        @aux_constraint(MGE, TCO2[r],
            TCO2[r] - sum(data["epslon"][i]*data["eind"][(i, g, r)]*data["cr"][(i, g, r)]*EN[i, g, r]
                          for i ∈ data["set_fe"], g ∈ data["set_gnev"])
        )
    end

    for i ∈ data["set_fe"], r ∈ data["set_r"]
        if setting == 2
            @aux_constraint(MGE, CTAXR[i, r],
                PA[i, r]*sum(data["xa0a_c"][r, i, g] for g ∈ data["set_gnev"])*CTAXR[i, r]
                - sum(data["eind"][i, g, r]*data["cr"][i, g, r] for g ∈ data["set_gnev"])*data["epslon"][i]*PC[r]*policy[r]
            )
        else
            @aux_constraint(MGE, CTAXR[i,r], CTAXR[i, r] - 0.0)
        end
    end

    for r ∈ data["set_r"]
        if setting == 2
            @aux_constraint(MGE, PC[r], tco2[r]*rer[r] - TCO2[r]*policy[r])
        else
            @aux_constraint(MGE, PC[r], PC[r] - 0)
        end
    end

    for r ∈ data["set_r"]
        @aux_constraint(MGE, GDP[r],
            GDP[r]  - PW[r]*data["w0"][r]*W[r] 
                    - data["g0"][r]*PG[r]*GDPINDEX[r]
                    - sum(data["x0"][r, s, i]*PX[i, r, s]*X[i, r, s] for i ∈ data["set_i"], s ∈ data["set_r"])
                    + sum(data["x0"][s, r, i]*PM[i, r]*M[i, r] for i ∈ data["set_i"], s ∈ data["set_r"])
        )
    end

    for r ∈ data["set_r"]
        @aux_constraint(MGE, GDPINDEX[r],
               GDP[r]/data["gdp0"][r] - GDPINDEX[r]
        )
    end

    # -1 is for benchmark calibration check
    for r ∈ data["set_r"]
        if setting == 0 || setting == -1
            @aux_constraint(MGE, TFP[r],
                GDP[r]  - gdp[r]
            )
        else
            @aux_constraint(MGE, TFP[r],
                TFP[r] - tfp[r]            
            )
        end
    end

    fix(PU[:USA], 1)

    return MGE
end