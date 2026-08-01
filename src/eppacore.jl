
function EPPACore(MGE, data, setting)

    @parameters(MGE, begin
        tm[i=data["set_i"],     r=data["set_r"], s=data["set_r"]],  data["rtms0"][i, r, s], (description = "Import tax rates")
        tx[i=data["set_i"],     r=data["set_r"], s=data["set_r"]],  data["rtxs0"][i, r, s], (description = "Export subsidy rates")
        td[r=data["set_r"],     g=data["set_g"]],                   data["rto0"][g, r],     (description = "Output tax or subsidy rates")
        ta[i=data["set_i"],     g=data["set_g"], r=data["set_r"]],  data["ta0"][i, g, r],   (description = "Tax rate on Armington good")
        tf[f=data["set_f"],     i=data["set_i"], r=data["set_r"]],  data["rtf0"][f, i, r],  (description = "Primary factor tax rates")
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

    @production(MGE, D[g=data["set_i"], r=data["set_r"]], [t = 0, s = data["esub"][g], sn => s = data["esubn"][g], sve => sn = data["esubve"][g], sva => sve = data["esubva"][g], sef => sve = data["esubef"][g], sf => sef = data["esubf"][g]], begin
        @output(PD[g, r],                       data["xp0"][r, g], t,       taxes = [Tax(RA[r], td[r, g])], reference_price = 1-data["rto0"][g, r])    
        @input(PE[i=data["set_fe"], g, r],      data["xa0"][r, i, g],       taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sf)
        @input(PE[i=data["set_elec"], g, r],    data["xa0"][r, i, g],       taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sef)
        @input(PA[i=data["set_ne"], r],         data["xa0"][r, i, g],       taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sn)
        @input(PS[sf=data["set_sf"], g, r],     data["vfm"][sf, g, r],  s,  taxes = [Tax(RA[r], tf[sf, g, r])],   reference_price = 1 + data["rtf0"][sf, g, r])    
        @input(PF[mf=data["set_mf"], r],        data["vfm"][mf, g, r],  sva, taxes = [Tax(RA[r], tf[mf, g, r])],   reference_price = 1 + data["rtf0"][mf, g, r])    
    end)

    for g ∈ data["set_con"], r ∈ data["set_r"]
        @production(MGE, Z[r], [t = 0, s = data["esub"][g], sn => s = data["esubn"][g], sef => sn = data["esubef"][g], sf => sef = data["esubf"][g]], begin
            @output(PU[r],                      data["cons0"][r], t,    taxes = [Tax(RA[r], td[r, g])])
            @input(PE[i=data["set_fe"], g, r],  data["xa0"][r, i, g],   taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sf)
            @input(PE[i=data["set_elec"], g, r],data["xa0"][r, i, g],   taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sef)
            @input(PA[i=data["set_ne"], r],     data["xa0"][r, i, g],   taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sn)
        end)
    end

    for g ∈ data["set_gov"], r ∈ data["set_r"]
        @production(MGE, GOV[r], [t = 0, s = data["esub"][g], sn => s = data["esubn"][g], sef => sn = data["esubef"][g], sf => sef = data["esubf"][g]], begin
            @output(PG[r],                      data["g0"][r], t,       taxes = [Tax(RA[r], td[r, g])])
            @input(PE[i=data["set_fe"], g, r],  data["xa0"][r, i, g],   taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sf)
            @input(PE[i=data["set_elec"], g, r],data["xa0"][r, i, g],   taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sef)
            @input(PA[i=data["set_ne"], r],     data["xa0"][r, i, g],   taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sn)
        end)
    end

    for g ∈ data["set_inv"], r ∈ data["set_r"]
        @production(MGE, INV[r], [t = 0, s = data["esub"][g], sn => s = data["esubn"][g], sef => sn = data["esubef"][g], sf => sef = data["esubf"][g]], begin
            @output(PI[r],                      data["inv0"][r], t,   taxes = [Tax(RA[r], td[r, g])])
            @input(PE[i=data["set_fe"], g, r],  data["xa0"][r, i, g],   taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sf)
            @input(PE[i=data["set_elec"], g, r],data["xa0"][r, i, g],   taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sef)
            @input(PA[i=data["set_ne"], r],     data["xa0"][r, i, g],   
            taxes = [Tax(RA[r], ta[i, g, r])], reference_price = 1+data["ta0"][i, g, r], sn)
        end)
    end

    @production(MGE, YT[j=data["set_i"]], [t = 0, s = 1], begin
        @output(PT[j],                          data["vtw"][j],         t)
        @input(PD[j, r=data["set_r"]],          data["vst"][j, r],      s)
    end)

    @production(MGE, M[i=data["set_i"], r=data["set_r"]], [t = 0, s = data["esubm"][i]], begin
        @output(PM[i, r],                       data["vim"][i, r],      t)
        @input(PX[i, s=data["set_r"], r],       data["x0"][r, s, i],    s, taxes = [Tax(RA[r], tm[i, s, r])], reference_price = data["pvtwr"][i, s, r])
    end)

    @production(MGE, X[i=data["set_i"], s=data["set_r"], r=data["set_r"]], [t = 0, s = 0], begin
        @output(PX[i, s, r], data["x0"][r, s, i], t)
        @input(PD[i, s],                        data["wtflow0"][r, s, i], s,   taxes = [Tax(RA[s], -tx[i, s, r])],   reference_price = 1 - data["rtxs0"][i, s, r])
        @input(PT[j=data["set_i"]],             data["vtwr"][j, i, s, r], s)
    end)

    @demand(MGE, RA[r=data["set_r"]], begin
        @final_demand(PU[r],                                    data["cons0"][r])
        @endowment(PU[:USA],                                    data["vb"][r])
        @endowment(PG[r],                                      -data["g0"][r])
        @endowment(PI[r],                                      -data["inv0"][r])
        @endowment(PF[f=data["set_mf"], r],                     data["evom"][f, r])
        @endowment(PS[f=data["set_sf"], j=data["set_i"], r],    data["vfm"][f, j, r])
    end)

    fix(PU[:USA], 1)

    return MGE

end