
function EPPACore(MGE, data, setting)

    @parameters(MGE, begin
        tm[i=data["set_i"],     r=data["set_r"], s=data["set_r"]],  data["rtms0"][i, r, s], (description = "Import tax rates")
        tx[i=data["set_i"],     r=data["set_r"], s=data["set_r"]],  data["rtxs0"][i, r, s], (description = "Export subsidy rates")
        td[r=data["set_r"],     g=data["set_g"]],                   data["rto0"][g, r],     (description = "Output tax or subsidy rates")
        ta[i=data["set_i"],     g=data["set_g"], r=data["set_r"]],  data["ta0"][i, g, r],   (description = "Tax rate on Armington good")
        tf[f=data["set_f"],     i=data["set_i"], r=data["set_r"]],  data["rtf0"][f, i, r],  (description = "Primary factor tax rates")
        tb[r=data["set_r"]],                                        data["tb0"][r],         (description = "Tax rate on biofuels used by HHT")
    end)

    @sectors(MGE, begin
        D[i=data["set_i"], r=data["set_r"]],                       (description = "Supply")
        M[i=data["set_i"], r=data["set_r"]],                       (description = "Imports")
        YT[i=data["set_i"]],                                       (description = "Transportation services")
        X[i=data["set_i"], r=data["set_r"], s=data["set_r"]],      (description = "Subsidy and transport service included exports")
        A[i=data["set_i"], g=data["set_g"], r=data["set_r"]],      (description = "Armington good")
        Z[r=data["set_r"]],                                        (description = "Aggregate private consumption")
        GOV[r=data["set_r"]],                                      (description = "Aggregate government consumption")
        INV[r=data["set_r"]],                                      (description = "Investment")
        HHT[r=data["set_r"]],                                      (description = "Household transportation")
        B[r=data["set_r"]],                                        (description = "Conversion to traditional biofuels")
    end)

    @commodities(MGE, begin
        PD[i=data["set_i"], r=data["set_r"]],                      (description = "Domestic output price")
        PM[i=data["set_i"], r=data["set_r"]],                      (description = "Import price")
        PT[i=data["set_i"]],                                       (description = "Transportation services")
        PF[mf=data["set_mf"], r=data["set_r"]],                    (description = "Non-sector-specific primary factor rent")
        PS[sf=data["set_sf"], g=data["set_g"], r=data["set_r"]],   (description = "Sector-specific primary factor rent")  
        PX[i=data["set_i"], r=data["set_r"], s=data["set_r"]],     (description = "Price index for exports (include subsidy and transport service)")
        PA[i=data["set_ne"], r=data["set_r"]],                     (description = "Price index for Armington good")
        PE[i=data["set_e"], g=data["set_g"], r=data["set_r"]],     (description = "Price index for Armington energy good: carbon-penalty-inclusive")        
        PG[r=data["set_r"]],                                       (description = "Price index for aggregate government expenditure")
        PU[r=data["set_r"]],                                       (description = "Price index for aggregate consumption")
        PI[r=data["set_r"]],                                       (description = "Price index for investment")
        PH[r=data["set_r"]],                                       (description = "Price index for household transportation")
        PB[r=data["set_r"]],                                       (description = "Price index for traditional biofuels")
    end)

    @consumers(MGE, begin
        RA[r=data["set_r"]],                                       (description = "Representative agent")
    end)

    @production(MGE, A[i=data["set_ne"], g=data["set_g"], r=data["set_r"]], [t = 0, s = data["esubd"][i]], begin
        @output(PA[i, r],                       data["xa0"][r, i, g],   t)
        @input(PD[i, r],                        data["xd0"][r, i, g],   s)
        @input(PM[i, r],                        data["xm0"][r, i, g],   s)  
    end)
    
    @production(MGE, A[i=data["set_elec"], g=data["set_g"], r=data["set_r"]], [t = 0, s = data["esubd"][i]], begin
        @output(PE[i, g, r],                    data["xa0"][r, i, g],   t)
        @input(PD[i, r],                        data["xd0"][r, i, g],   s)
        @input(PM[i, r],                        data["xm0"][r, i, g],   s)  
    end)

    @production(MGE, A[i=data["set_fe"], g=data["set_g"], r=data["set_r"]], [t = 0, s = data["esubd"][i]], begin
        @output(PE[i, g, r],                    data["xa0"][r, i, g],   t)
        @input(PD[i, r],                        data["xd0"][r, i, g],   s)
        @input(PM[i, r],                        data["xm0"][r, i, g],   s)  
    end)

    @production(MGE, D[g=data["set_i"], r=data["set_r"]], [t= 0, s = 0.3, nl => s = 0.3, nv => nl = 0.1, va => nv = 1, ne => nv = 0.1, nn => ne = 0.1, ee => ne = 1.5, fe => ee = 1.0], begin
        @output(PD[g, r],                       data["xp0"][r, g],      t,      taxes = [Tax(RA[r], td[r, g])],     reference_price = 1-data["rto0"][g, r])    
        @input(PE[i=data["set_fe"], g, r],      data["xa0"][r, i, g],   fe,     taxes = [Tax(RA[r], ta[i, g, r])],  reference_price = 1+data["ta0"][i, g, r])
        @input(PE[i=data["set_elec"], g, r],    data["xa0"][r, i, g],   ee,     taxes = [Tax(RA[r], ta[i, g, r])],  reference_price = 1+data["ta0"][i, g, r])
        @input(PA[i=data["set_ne"], r],         data["xa0"][r, i, g],   nn,     taxes = [Tax(RA[r], ta[i, g, r])],  reference_price = 1+data["ta0"][i, g, r])
        @input(PS[sf=data["set_fix"], g, r],    data["vfm"][sf, g, r],  s,      taxes = [Tax(RA[r], tf[sf, g, r])], reference_price = 1 + data["rtf0"][sf, g, r])    
        @input(PS[sf=data["set_lnd"], g, r],    data["vfm"][sf, g, r],  nl,     taxes = [Tax(RA[r], tf[sf, g, r])], reference_price = 1 + data["rtf0"][sf, g, r])    
        @input(PF[mf=data["set_mf"], r],        data["vfm"][mf, g, r],  va,     taxes = [Tax(RA[r], tf[mf, g, r])], reference_price = 1 + data["rtf0"][mf, g, r])    
    end)

    for g ∈ data["set_con"], r ∈ data["set_r"]
        @production(MGE, Z[r], [t = 0, s = data["esub"][g]], begin
            @output(PU[r],                      data["cons0"][r],       t,      taxes = [Tax(RA[r], td[r, g])])
            @input(PE[i=data["set_roil"], g, r],data["xa0_r"][r, i, g], s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PE[i=data["set_cg"], g, r],  data["xa0"][r, i, g],   s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PE[i=data["set_elec"], g, r],data["xa0"][r, i, g],   s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_rest"], r],   data["xa0"][r, i, g],   s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_serv"], r],   data["xa0_s"][r, i, g], s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_othr"], r],   data["xa0_o"][r, i, g], s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_food"], r],   data["xa0_f"][r, i, g], s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_eint"], r],   data["xa0_e"][r, i, g], s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PH[r],                       data["own"][r],         s)
        end)
    end
    
    for r ∈ data["set_r"]
        @production(MGE, HHT[r], [t = 0, s = 1], begin
            @output(PH[r],                      data["own"][r],         t)
            @input(PE[:p_c, :c, r],             data["tfo"][r],         s,      taxes = [Tax(RA[r], ta[:p_c, :c, r])], reference_price = 1+data["ta0"][:p_c, :c, r])
            @input(PA[:othr, r],                data["toi"][r],         s,      taxes = [Tax(RA[r], ta[:othr, :c, r])], reference_price = 1+data["ta0"][:othr, :c, r])
            @input(PA[:serv, r],                data["tse"][r],         s,      taxes = [Tax(RA[r], ta[:serv, :c, r])], reference_price = 1+data["ta0"][:serv, :c, r])
            @input(PB[r],                       data["tbo_r"][r],       s,      taxes = [Tax(RA[r], ta[:p_c, :c, r])], reference_price = 1+data["ta0"][:p_c, :c, r])
        end)
    end

    for r ∈ data["set_nbr"]
        @production(MGE, B[r], [t = 0, s = 0], begin
            @output(PB[r],                      data["tbo_r"][r],       t)
            @input(PA[:food, r],                data["tbo"][r],         s,      taxes = [Tax(RA[r], tb[r])], reference_price = 1+data["tb0"][r])
        end)
    end

    for r ∈ data["set_br"]
        @production(MGE, B[r], [t = 0, s = 0], begin
            @output(PB[r],                      data["tbo_r"][r],       t)
            @input(PA[:eint, r],                data["tbo"][r],         s,      taxes = [Tax(RA[r], tb[r])], reference_price = 1+data["tb0"][r])
        end)
    end

    for g ∈ data["set_gov"], r ∈ data["set_r"]
        @production(MGE, GOV[r], [t = 0, s = data["esub"][g]], begin
            @output(PG[r],                      data["g0"][r],          t,      taxes = [Tax(RA[r], td[r, g])])
            @input(PE[i=data["set_fe"], g, r],  data["xa0"][r, i, g],   s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PE[i=data["set_elec"], g, r],data["xa0"][r, i, g],   s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_ne"], r],     data["xa0"][r, i, g],   s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
        end)
    end

    for g ∈ data["set_inv"], r ∈ data["set_r"]
        @production(MGE, INV[r], [t = 0, s = data["esub"][g]], begin
            @output(PI[r],                      data["inv0"][r],        t,      taxes = [Tax(RA[r], td[r, g])])
            @input(PE[i=data["set_fe"], g, r],  data["xa0"][r, i, g],   s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PE[i=data["set_elec"], g, r],data["xa0"][r, i, g],   s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
            @input(PA[i=data["set_ne"], r],     data["xa0"][r, i, g],   s,      taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r])
        end)
    end

    @production(MGE, YT[j=data["set_i"]], [t = 0, s = 1], begin
        @output(PT[j],                          data["vtw"][j],         t)
        @input(PD[j, r=data["set_r"]],          data["vst"][j, r],      s)
    end)

    @production(MGE, M[i=data["set_i"], r=data["set_r"]], [t = 0, s = data["esubm"][i]], begin
        @output(PM[i, r],                       data["vim"][i, r],      t)
        @input(PX[i, s=data["set_r"], r],       data["x0"][r, s, i],    s,      taxes = [Tax(RA[r], tm[i, s, r])], reference_price = data["pvtwr"][i, s, r])
    end)

    @production(MGE, X[i=data["set_i"], s=data["set_r"], r=data["set_r"]], [t = 0, s = 0], begin
        @output(PX[i, s, r], data["x0"][r, s, i],                       t)
        @input(PD[i, s],                    data["wtflow0"][r, s, i],   s,    taxes = [Tax(RA[s], -tx[i, s, r])],   reference_price = 1 - data["rtxs0"][i, s, r])
        @input(PT[j=data["set_i"]],         data["vtwr"][j, i, s, r],   s)
    end)

    @demand(MGE, RA[r=data["set_r"]], begin
        @final_demand(PU[r],                                    data["cons0"][r])
        @endowment(PU[:USA],                                    data["vb"][r])
        @endowment(PG[r],                                      -data["g0"][r])
        @endowment(PI[r],                                      -data["inv0"][r])
        @endowment(PF[f=data["set_mf"], r],                     data["evom"][f, r])
        @endowment(PS[f=data["set_fix"], j=data["set_i"], r],   data["vfm"][f, j, r])
        @endowment(PS[f=data["set_lnd"], j=data["set_i"], r],   data["vfm"][f, j, r])
    end)

    fix(PU[:USA], 1)

    return MGE

end