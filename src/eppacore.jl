function MGE_model(data::Dict)

#    set_i      = data["set_i"]
#    set_g      = data["set_g"]
#    set_r      = data["set_r"]
#    set_f      = data["set_f"]
#    set_sf     = data["set_sf"]
#    set_mf     = data["set_mf"]
#    set_fe     = data["set_fe"]
#    set_elec   = data["set_elec"]
#    set_ne     = data["set_ne"]
#    set_tr     = data["set_tr"]
#    set_cgi   = data["set_cgi"]

    MGE  = MPSGEModel()

    @parameters(MGE, begin
        rtfd[i=data["set_i"], g=data["set_g"], r=data["set_r"]],    data["rtfd0"][i, g, r], (description = "Firms' domestic tax rates")
        rtfi[i=data["set_i"], g=data["set_g"], r=data["set_r"]],    data["rtfi0"][i, g, r], (description = "Firms' import tax rates")
        rtms[i=data["set_i"], r=data["set_r"], s=data["set_r"]],    data["rtms0"][i, r, s], (description = "Import tax rates")
        rtxs[i=data["set_i"], r=data["set_r"], s=data["set_r"]],    data["rtxs0"][i, r, s], (description = "Export subsidy rates")
        rto[g=data["set_g"], r=data["set_r"]],                      data["rto0"][g, r],     (description = "Output subsidy rates")              
        rtf[f=data["set_f"], i=data["set_i"], r=data["set_r"]],     data["rtf0"][f, i, r],  (description = "Primary factor tax rates")
    end)

    @sectors(MGE, begin
        Y[g=data["set_g"], r=data["set_r"]],          (description = "Supply")
        M[i=data["set_i"], r=data["set_r"]],          (description = "Imports")
        YT[i=data["set_i"]],                  (description = "Transportation services")
        E[i=data["set_i"], r=data["set_r"], s=data["set_r"]], (description = "Subsidy and transport service included exports")
        A[i=data["set_i"], g=data["set_g"], r=data["set_r"]], (description = "Armington good")
    end)

    @commodities(MGE, begin
        P[g=data["set_g"], r=data["set_r"]],             (description = "Domestic output price")
        PM[i=data["set_i"], r=data["set_r"]],            (description = "Import price")
        PT[i=data["set_i"]],                     (description = "Transportation services")
        PF[mf=data["set_mf"], r=data["set_r"]],          (description = "Non-sector-specific primary factor rent")
        PS[sf=data["set_sf"], g=data["set_g"], r=data["set_r"]], (description = "Sector-specific primary factor rent")  
        PX[i=data["set_i"], r=data["set_r"], s=data["set_r"]],   (description = "Price index for exports (include subsidy and transport service)")
        PA[i=data["set_i"], g=data["set_g"], r=data["set_r"]],   (description = "Price index for Armington good")
        PE[i=data["set_i"], r=data["set_r"]],            (description = "Price index for exports (exclude subsidy and transport service)")
    end)

    @consumers(MGE, begin
        RA[r=data["set_r"]],              (description = "Representative agent")
    end)

    #for i ∈ data["set_i"], g ∈ data["set_g"], r ∈ data["set_r"]
        @production(MGE, A[i=data["set_i"], g=data["set_g"], r=data["set_r"]], [t = 0, s = data["esubd"][i]], begin
            @output(PA[i, g, r],    data["vafm"][i, g, r],  t)
            @input(P[i, r],         data["vdfm"][i, g, r],  s,   taxes = [Tax(RA[r], rtfd[i, g, r])],   reference_price = 1 + data["rtfd0"][i, g, r])
            @input(PM[i, r],        data["vifm"][i, g, r],  s,   taxes = [Tax(RA[r], rtfi[i, g, r])],   reference_price = 1 + data["rtfi0"][i, g, r])  
        end)
    #end

    #for g ∈ data["set_i"], r ∈ data["set_r"]
        @production(MGE, Y[g=data["set_i"], r=data["set_r"]], [t = data["etadx"][g], s = data["esub"][g], sn => s = data["esubn"][g], sve => sn = data["esubve"][g], sva => sve = data["esubva"][g], sef => sve = data["esubef"][g], sf => sef = data["esubf"][g]], begin
            @output(P[g, r],        data["vhm"][g, r], t, taxes = [Tax(RA[r], rto[g, r])], reference_price = 1-data["rto0"][g, r])
            @output(PE[g, r],       data["vxm"][g, r], t, taxes = [Tax(RA[r], rto[g, r])], reference_price = 1-data["rto0"][g, r])    
            @input(PA[i=data["set_fe"], g, r],    data["vafm"][i, g, r], sf)
            @input(PA[i=data["set_elec"], g, r],    data["vafm"][i, g, r], sef)
            @input(PA[i=data["set_ne"], g, r],    data["vafm"][i, g, r], sn)
            @input(PS[sf=data["set_sf"], g, r],   data["vfm"][sf, g, r],  s, taxes = [Tax(RA[r], rtf[sf, g, r])],   reference_price = 1 + data["rtf0"][sf, g, r])    
            @input(PF[mf=data["set_mf"], r],      data["vfm"][mf, g, r],  sva, taxes = [Tax(RA[r], rtf[mf, g, r])],   reference_price = 1 + data["rtf0"][mf, g, r])    
        end)
    #end

    for g ∈ data["set_cgi"], r ∈ data["set_r"]
        @production(MGE, Y[g, r], [t = 0, s = data["esub"][g], sn => s = data["esubn"][g], sef => sn = data["esubef"][g], sf => sef = data["esubf"][g]], begin
            @output(P[g, r],        data["vom"][g, r], t, taxes = [Tax(RA[r], rto[g, r])])
            @input(PA[i=data["set_fe"], g, r],     data["vafm"][i, g, r], sf)
            @input(PA[i=data["set_elec"], g, r],     data["vafm"][i, g, r], sef)
            @input(PA[i=data["set_ne"], g, r],     data["vafm"][i, g, r], sn)
        end)
    end

    #for j ∈ data["set_i"]
        @production(MGE, YT[j=data["set_i"]], [t = 0, s = 1], begin
            @output(PT[j],          data["vtw"][j],         t)
            @input(PE[j, r=data["set_r"]],       data["vst"][j, r],      s)
        end)
    #end

    #for i ∈ data["set_i"], r ∈ data["set_r"]
        @production(MGE, M[i=data["set_i"], r=data["set_r"]], [t = 0, s = data["esubm"][i]], begin
            @output(PM[i, r],       data["vim"][i, r],      t)
            @input(PX[i, s=data["set_r"], r], data["vxmd"][i, s, r]*(1 - data["rtxs0"][i, s, r]) + sum(data["vtwr"][j, i, s, r] for j ∈ data["set_tr"]), s, taxes = [Tax(RA[r], rtms[i, s, r])], reference_price = data["pvtwr"][i, s, r])
        end)
    #end

    # vxmr = Dict((i, s, r) => vxmd[i, s, r]*(1 - rtxs0[i, s, r]) + sum(vtwr[j, i, s, r] for j ∈ data["set_tr"])

    #for i ∈ data["set_i"], s ∈ data["set_r"], r ∈ data["set_r"]
        @production(MGE, E[i=data["set_i"], s=data["set_r"], r=data["set_r"]], [t = 0, s = 0], begin
            @output(PX[i, s, r], data["vxmd"][i, s, r]*(1 - data["rtxs0"][i, s, r]) + sum(data["vtwr"][j, i, s, r] for j ∈ data["set_tr"]), t)
            @input(PE[i, s],        data["vxmd"][i, s, r], s,   taxes = [Tax(RA[s], -rtxs[i, s, r])],   reference_price = 1 - data["rtxs0"][i, s, r])
            @input(PT[j=data["set_i"]],          data["vtwr"][j, i, s, r], s)
        end)
    #end

    #for r ∈ data["set_r"] 
        @demand(MGE, RA[r=data["set_r"]], begin
            @final_demand(P[:c, r],     data["vom"][:c, r])
            @endowment(P[:c, :USA],     data["vb"][r])
            @endowment(P[:g, r],        -data["vom"][:g, r])
            @endowment(P[:i, r],        -data["vom"][:i, r])
            @endowment(PF[f=data["set_mf"], r],       data["evom"][f, r])
            @endowment(PS[f=data["set_sf"], j=data["set_i"], r],    data["vfm"][f, j, r])
        end)
    #end

    fix(P[:c, :USA], 1)

    return MGE

end

