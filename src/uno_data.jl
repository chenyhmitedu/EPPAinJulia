function Uno_data(data::Dict, disa::Dict)

#### 1.0 Model specific sets ####

# Vectors below may be changed depending on the sectoral names and resolution
data["set_fe"]      = [:coa, :gas, :p_c, :oil]
data["set_elec"]    = [:elec]
data["set_note"]    = setdiff(data["set_i"], data["set_elec"])
data["set_gne"]     = setdiff(data["set_g"], data["set_elec"])
data["set_e"]       = union(data["set_fe"], data["set_elec"])
data["set_ne"]      = setdiff(data["set_i"], data["set_e"])
data["set_roil"]    = [:p_c]
data["set_othr"]    = [:othr]
data["set_serv"]    = [:serv]
data["set_food"]    = [:food]
data["set_eint"]    = [:eint]
data["set_fnr"]     = setdiff(data["set_fe"], data["set_roil"])
data["set_oil"]     = [:oil]
data["set_cg"]      = setdiff(data["set_fnr"], data["set_oil"])
data["set_nern"]    = union(data["set_ne"], data["set_roil"])
data["set_dwe"]     = [:dwe]
data["set_tran"]    = [:tran]

data["set_tr"]      = [:tran]
data["set_con"]     = [:c]
data["set_gov"]     = [:g]
data["set_inv"]     = [:i]

data["set_fix"]     = [:fix]
data["set_lnd"]     = setdiff(data["set_sf"], data["set_fix"])
data["set_rest"]    = setdiff(data["set_ne"], union(data["set_serv"], data["set_othr"], data["set_food"], data["set_eint"], data["set_tran"], data["set_dwe"]))

data["set_br"]      = [:BRA]
data["set_nbr"]     = setdiff(data["set_r"], data["set_br"])

# Take all elements in disa["set_i"] that are not in data["set_i"]
disa["set_v"]       = setdiff(disa["set_i"], data["set_i"])
data["set_v"]       = disa["set_v"]
data["set_gv"]      = data["set_g"] ∪ data["set_v"]

data["set_gnev"]    = data["set_gne"] ∪ data["set_v"]
data["set_tele"]    = [:tele]
data["set_vole"]    = setdiff(data["set_v"], data["set_tele"])

#### 2.0 Key EPPA parameters ####

# xdp0(r,i,j)	= vdfm(i,j,r);
data["xd0"] = Dict(
    (r, i, j) => data["vdfm"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_i"], j ∈ data["set_g"]
)

# xmp0(r,i,j)	= vifm(i,j,r);
data["xm0"] = Dict(
    (r, i, j) => data["vifm"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_i"], j ∈ data["set_g"]
)

# Tax rate on Armington input
data["ta0"] = Dict(
    (i, j, r) => 
        begin
            num = data["vdfm"][i, j, r] * data["rtfd0"][i, j, r] + data["vifm"][i, j, r] * data["rtfi0"][i, j, r]
            den = data["vdfm"][i, j, r] + data["vifm"][i, j, r]
            iszero(den) ? 0.0 : num / den
        end
        for i ∈ data["set_i"], j ∈ data["set_g"], r ∈ data["set_r"]
)

# Pre-tax Armington good;
data["xa0"] = Dict(
    (r, i, j) => data["vafm"][i, j, r]/(1+data["ta0"][i, j, r])
    for r ∈ data["set_r"], i ∈ data["set_i"], j ∈ data["set_g"]
)

# wtflow0(r,s,i)	= vxmd(i,s,r); i moves from s to r
data["wtflow0"] = Dict(
    (r, s, i) => data["vxmd"][i, s, r]
    for r ∈ data["set_r"], s ∈ data["set_r"], i ∈ data["set_i"]
)

# Transport margin and export subsidy inclusive export
data["x0"] = Dict(
    (s, r, i) => data["vxmd"][i, s, r]*(1 - data["rtxs0"][i, s, r]) + sum(data["vtwr"][j, i, s, r] for j ∈ data["set_tr"])
    for r ∈ data["set_r"], s ∈ data["set_r"], i ∈ data["set_i"]
)

# xp0(r,i)	= vom(i,r);
data["xp0"] = Dict(
    (r, i) => data["vom"][i, r]
    for r ∈ data["set_r"], i ∈ data["set_i"]
)

# cons0(r)	= sum(i, vdfm(i,"c",r)*(1+rtfd(i,"c",r)) + vifm(i,"c",r)*(1+rtfi(i,"c",r)));
data["cons0"] = Dict(
    r => data["vom"][g, r]
    for r ∈ data["set_r"], g ∈ data["set_con"]
)

# Value of tax-excluded government expenditure (td tax excluded)
data["g0"] = Dict(
    r => data["vom"][i, r]
    for r ∈ data["set_r"], i ∈ data["set_gov"]
)

# Value of tax-excluded government investment (td tax excluded)
data["inv0"] = Dict(
    r => data["vom"][i, r]
    for r ∈ data["set_r"], i ∈ data["set_inv"]
)

#### 3.0 Household transportation ####

# owntrn(r)        = es(r)*cons0(r); es(r) = own-supply expenditure share
data["owntrn"] = Dict(
    r => data["es"][r]*data["cons0"][r]
    for r ∈ data["set_r"]
)

# tfo(r)           = os(r)*ence("roil",r); ence("roil",r) = data["xa0"][r, :p_c, :c]
data["tfo"] = Dict(
    r => data["os"][r]*data["xa0"][r, i, g]
    for r ∈ data["set_r"], i ∈ data["set_roil"], g ∈ data["set_con"]
)

# pbio(r) = ence0("roil",r)/efd("roil",r);	  
data["pbio"] = Dict(
    r => data["xa0"][r, i, g]/data["eind"][i, g, r]
    for r ∈ data["set_r"], i ∈ data["set_roil"], g ∈ data["set_con"]
)

# ebio(r) = pbio(r)*bio_baseyear(r,"bio-fg");
data["ebio"] = Dict(
    r => data["pbio"][r]*data["bio_baseyear"][r]
    for r ∈ data["set_r"]
)

data["tb0"] = merge(

Dict(
    r => (data["ta0"][i, g, r]-data["ta0"][j, g, r])/(1+data["ta0"][j, g, r])
    for r ∈ data["set_nbr"], i ∈ data["set_food"], g ∈ data["set_con"], j ∈ data["set_roil"]
),

Dict(
    r => (data["ta0"][i, g, r]-data["ta0"][j, g, r])/(1+data["ta0"][j, g, r])
    for r ∈ data["set_br"], i ∈ data["set_eint"], g ∈ data["set_con"], j ∈ data["set_roil"]
)

)

# tbo(r)           = ebio(r)/pc0("roil",r);
data["tbo"] = Dict(
    r => data["ebio"][r]/(1+data["ta0"][i, g, r])
    for r ∈ data["set_r"], i ∈ data["set_roil"], g ∈ data["set_con"]
)

data["tbo_r"] = Dict(
    r => data["tbo"][r]*(1+data["tb0"][r])
    for r ∈ data["set_r"]
)

# tse(r)$(not bra(r))     = (owntrn(r)-tfo(r)*pc0("roil",r)-toi(r)*pc0("othr",r)-tbo(r)*pc0("food",r))/pc0("serv",r);
# tse(r)$(bra(r))	      = (owntrn(r)-tfo(r)*pc0("roil",r)-toi(r)*pc0("othr",r)-tbo(r)*pc0("eint",r))/pc0("serv",r);

data["tse"] = merge(

Dict(
    r => (data["owntrn"][r] - data["tfo"][r]*(1+data["ta0"][i, g, r]) - data["toi"][r]*(1+data["ta0"][j, g, r])
         - data["tbo"][r]*(1+data["ta0"][k, g, r]))/(1+data["ta0"][l, g, r])
    for r ∈ data["set_nbr"], i ∈ data["set_roil"], g ∈ data["set_con"], j ∈ data["set_othr"], k ∈ data["set_food"], l ∈ data["set_serv"]
    ),

Dict(
    r => (data["owntrn"][r] - data["tfo"][r]*(1+data["ta0"][i, g, r]) - data["toi"][r]*(1+data["ta0"][j, g, r])
         - data["tbo"][r]*(1+data["ta0"][k, g, r]))/(1+data["ta0"][l, g, r])
    for r ∈ data["set_br"], i ∈ data["set_roil"], g ∈ data["set_con"], j ∈ data["set_othr"], k ∈ data["set_eint"], l ∈ data["set_serv"]
    )
    
)

# own(r)                  = (pc0("roil",r)*tfo(r)+pc0("roil",r)*tbo(r)+pc0("othr",r)*toi(r)+pc0("serv",r)*tse(r));

data["own"] = merge(

Dict(
    r => (1+data["ta0"][i, g, r])*(data["tfo"][r]) 
    + (1+data["ta0"][j, g, r])*data["toi"][r] 
    + (1+data["ta0"][k, g, r])*data["tse"][r]
    + (1+data["ta0"][m, g, r])*data["tbo"][r]

    for r ∈ data["set_nbr"], g ∈ data["set_con"], i ∈ data["set_roil"], j ∈ data["set_othr"], k ∈ data["set_serv"], m ∈ data["set_food"]
),

Dict(
    r => (1+data["ta0"][i, g, r])*(data["tfo"][r]) 
    + (1+data["ta0"][j, g, r])*data["toi"][r] 
    + (1+data["ta0"][k, g, r])*data["tse"][r]
    + (1+data["ta0"][m, g, r])*data["tbo"][r]

    for r ∈ data["set_br"], g ∈ data["set_con"], i ∈ data["set_roil"], j ∈ data["set_othr"], k ∈ data["set_serv"], m ∈ data["set_eint"]
)

)

data["tottrn"] = Dict(
    r => data["own"][r] + data["xa0"][r, i, g]*(1+data["ta0"][i, g, r])
    for r ∈ data["set_r"], i ∈ data["set_tran"], g ∈ data["set_con"]
)

data["xa0_r"] = Dict(
    (r, i, g) => data["xa0"][r, i, g] - data["tfo"][r]
    for r ∈ data["set_r"], i ∈ data["set_roil"], g ∈ data["set_con"]
)

data["xa0_o"] = Dict(
    (r, i, g) => data["xa0"][r, i, g] - data["toi"][r]
    for r ∈ data["set_r"], i ∈ data["set_othr"], g ∈ data["set_con"]
)

data["xa0_s"] = Dict(
    (r, i, g) => data["xa0"][r, i, g] - data["tse"][r]
    for r ∈ data["set_r"], i ∈ data["set_serv"], g ∈ data["set_con"]
)

data["xa0_f"] = merge(

Dict(
    (r, i, g) => data["xa0"][r, i, g] - data["tbo"][r]
    for r ∈ data["set_nbr"], i ∈ data["set_food"], g ∈ data["set_con"]
),

Dict(
    (r, i, g) => data["xa0"][r, i, g]
    for r ∈ data["set_br"], i ∈ data["set_food"], g ∈ data["set_con"]
)

)

data["xa0_e"] = merge(

Dict(
    (r, i, g) => data["xa0"][r, i, g] 
    for r ∈ data["set_nbr"], i ∈ data["set_eint"], g ∈ data["set_con"]
),

Dict(
    (r, i, g) => data["xa0"][r, i, g] - data["tbo"][r]
    for r ∈ data["set_br"], i ∈ data["set_eint"], g ∈ data["set_con"]
)

)

# Combusted ratio of refined oil product p_c
data["cr"]  = merge(
Dict((i, g, r) => 1.0 for i ∈ data["set_cg"], g ∈ setdiff(data["set_g"], data["set_inv"]), r ∈ data["set_r"]),
Dict((i, g, r) => 0.9 for i ∈ data["set_roil"], g ∈ setdiff(data["set_g"], data["set_inv"]), r ∈ data["set_r"]),
Dict((i, g, r) => 0.0 for i ∈ data["set_oil"], g ∈ setdiff(data["set_g"], data["set_inv"]), r ∈ data["set_r"]),
Dict((i, g, r) => 0.0 for i ∈ data["set_fe"], g ∈ data["set_inv"], r ∈ data["set_r"])
)

# Revise data["cr"] so that the use by each disaggregated power is considered 
data["cr"] = merge(
    Dict((i, g, r) => data["cr"][i, g, r] for i ∈ data["set_fe"], g ∈ data["set_gne"], r ∈ data["set_r"]),        
    Dict((i, g, r) => 1.0 for i ∈ data["set_cg"], g ∈ disa["set_v"], r ∈ data["set_r"]),
    Dict((i, g, r) => 0.9 for i ∈ data["set_roil"], g ∈ disa["set_v"], r ∈ data["set_r"]),
    Dict((i, g, r) => 0.0 for i ∈ data["set_oil"], g ∈ disa["set_v"], r ∈ data["set_r"])
)

# Refined oil products combusted used by industry and final consumption 
data["xa0_c"] = Dict(
    (r, i, j) => data["xa0"][r, i, j]*data["cr"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ data["set_gne"] 
)

# Refined oil products noncombusted used by industry and final consumption 
data["xa0_n"] = Dict(
    (r, i, j) => data["xa0"][r, i, j]*(1-data["cr"][i, j, r])
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ data["set_gne"]
)

# Refined oil products combusted used by non-HHT private consumption
data["xa0_rc"] = Dict(
    (r, i, j) => data["xa0_r"][r, i, j]*data["cr"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ data["set_con"]
)

# Refined oil products noncombusted used by non-HHT private consumption
data["xa0_rn"] = Dict(
    (r, i, j) => data["xa0_r"][r, i, j]*(1-data["cr"][i, j, r])
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ data["set_con"]
)

# Refined oil products combusted used by HHT
data["tfo_c"] = Dict(
    r => data["tfo"][r]*data["cr"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ data["set_con"]
)

# Refined oil products noncombusted used by HHT
data["tfo_n"] = Dict(
    r => data["tfo"][r]*(1-data["cr"][i, j, r])
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ data["set_con"]
)

# Separate c and n parts of p_c's xd0 amd xm0
data["xd0_c"] = Dict(
    (r, i, j) => data["xd0"][r, i, j]*data["cr"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ data["set_gne"] 
)

data["xd0_n"] = Dict(
    (r, i, j) => data["xd0"][r, i, j]*(1-data["cr"][i, j, r])
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ data["set_gne"]
)

data["xm0_c"] = Dict(
    (r, i, j) => data["xm0"][r, i, j]*data["cr"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ data["set_gne"] 
)

data["xm0_n"] = Dict(
    (r, i, j) => data["xm0"][r, i, j]*(1-data["cr"][i, j, r])
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ data["set_gne"]
)

data["propfrac"] = Dict(
    r => 0.2
    for r ∈ data["set_r"]
)

data["toi_prop"] = Dict(
    r => data["toi"][r]*data["propfrac"][r]
    for r ∈ data["set_r"] 
)

data["toi_rest"] = Dict(
    r => data["toi"][r]*(1-data["propfrac"][r])
    for r ∈ data["set_r"] 
)

data["tfb_c"] = Dict(
    r => data["tfo_c"][r] + data["tbo_r"][r]
    for r ∈ data["set_r"]
)

data["w0"] = Dict(
    r => data["cons0"][r] + data["inv0"][r]
    for r ∈ data["set_r"]
)

#### 4.0 Disaggregated power sectors ####

data["vfme"]        = disa["vfm"]
data["rto0e"]       = disa["rto0"]
data["rtf0e"]       = disa["rtf0"]

# xp0(r,i)	= vom(i,r);
disa["xp0"] = Dict(
    (r, i) => disa["vom"][i, r]
    for r ∈ disa["set_r"], i ∈ disa["set_i"]
)

# Tax rate on Armington input
disa["ta0"] = Dict(
    (i, j, r) => 
        begin
            num = disa["vdfm"][i, j, r] * disa["rtfd0"][i, j, r] + disa["vifm"][i, j, r] * disa["rtfi0"][i, j, r]
            den = disa["vdfm"][i, j, r] + disa["vifm"][i, j, r]
            iszero(den) ? 0.0 : num / den
        end
        for i ∈ disa["set_i"], j ∈ disa["set_i"], r ∈ disa["set_r"]
)

# Pre-tax Armington good;
disa["xa0"] = Dict(
    (r, i, j) => disa["vafm"][i, j, r]/(1+disa["ta0"][i, j, r])
    for r ∈ disa["set_r"], i ∈ disa["set_i"], j ∈ disa["set_i"]
)

data["ta0e"] = merge(

Dict(
    (i, j, r) => 
        begin
            num = sum(disa["vdfm"][i, j, r] * disa["rtfd0"][i, j, r] + disa["vifm"][i, j, r] * disa["rtfi0"][i, j, r] for i ∈ disa["set_v"])
            den = sum(disa["vdfm"][i, j, r] + disa["vifm"][i, j, r] for i ∈ disa["set_v"])
            iszero(den) ? 0.0 : num / den
        end
    for i ∈ data["set_elec"], j ∈ disa["set_v"], r ∈ disa["set_r"]
    ),
Dict(
    (i, j, r) => disa["ta0"][i, j, r]
    for i ∈ data["set_note"], j ∈ disa["set_v"], r ∈ disa["set_r"]
    )
)

data["xp0e"] = Dict(
    (r, i) => disa["xp0"][r, i]
    for r ∈ data["set_r"], i ∈ disa["set_v"]
)

data["xa0e"] = merge(

Dict(
    (r, i, j) => sum(disa["vafm"][i, j, r] for i ∈ disa["set_v"])/(1+data["ta0e"][i, j, r])
    for r ∈ disa["set_r"], i ∈ data["set_elec"], j ∈ disa["set_v"]
),
Dict(
    (r, i, j) => disa["xa0"][r, i, j]
    for r ∈ disa["set_r"], i ∈ data["set_note"], j ∈ disa["set_v"]
)

)

# Refined oil products combusted used by industry and final consumption 
data["xa0e_c"] = Dict(
    (r, i, j) => data["xa0e"][r, i, j]*data["cr"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ disa["set_v"] 
)

# Refined oil products noncombusted used by industry and final consumption 
data["xa0e_n"] = Dict(
    (r, i, j) => data["xa0e"][r, i, j]*(1-data["cr"][i, j, r])
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ disa["set_v"]  
)

data["xd0e"] = merge(

Dict(
    (r, i, j) => sum(disa["vdfm"][i, j, r] for i ∈ disa["set_v"])
    for r ∈ disa["set_r"], i ∈ data["set_elec"], j ∈ disa["set_v"]
),
Dict(
    (r, i, j) => disa["vdfm"][i, j, r]
    for r ∈ disa["set_r"], i ∈ data["set_note"], j ∈ disa["set_v"]
)

)

# Refined oil products combusted used by industry and final consumption 
data["xd0e_c"] = Dict(
    (r, i, j) => data["xd0e"][r, i, j]*data["cr"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ disa["set_v"] 
)

# Refined oil products noncombusted used by industry and final consumption 
data["xd0e_n"] = Dict(
    (r, i, j) => data["xd0e"][r, i, j]*(1-data["cr"][i, j, r])
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ disa["set_v"] 
)

data["xm0e"] = merge(

Dict(
    (r, i, j) => sum(disa["vifm"][i, j, r] for i ∈ disa["set_v"])
    for r ∈ disa["set_r"], i ∈ data["set_elec"], j ∈ disa["set_v"]
),
Dict(
    (r, i, j) => disa["vifm"][i, j, r]
    for r ∈ disa["set_r"], i ∈ data["set_note"], j ∈ disa["set_v"]
)

)

# Refined oil products combusted used by industry and final consumption 
data["xm0e_c"] = Dict(
    (r, i, j) => data["xm0e"][r, i, j]*data["cr"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ disa["set_v"]
)

# Refined oil products noncombusted used by industry and final consumption 
data["xm0e_n"] = Dict(
    (r, i, j) => data["xm0e"][r, i, j]*(1-data["cr"][i, j, r])
    for r ∈ data["set_r"], i ∈ data["set_roil"], j ∈ disa["set_v"]
)

# xa0a data combine both set_v data and set_gne data
data["xa0a"] = copy(data["xa0e"])
data["xd0a"] = copy(data["xd0e"])
data["xm0a"] = copy(data["xm0e"])

for r ∈ data["set_r"], i ∈ data["set_i"], g ∈ data["set_gne"]
    data["xa0a"][r, i, g] = data["xa0"][r, i, g]
    data["xd0a"][r, i, g] = data["xd0"][r, i, g]
    data["xm0a"][r, i, g] = data["xm0"][r, i, g]
end

data["xa0a_c"] = copy(data["xa0e_c"])
data["xd0a_c"] = copy(data["xd0e_c"])
data["xm0a_c"] = copy(data["xm0e_c"])

for r ∈ data["set_r"], i ∈ data["set_roil"], g ∈ data["set_gne"]
    data["xa0a_c"][r, i, g] = data["xa0_c"][r, i, g]
    data["xd0a_c"][r, i, g] = data["xd0_c"][r, i, g]
    data["xm0a_c"][r, i, g] = data["xm0_c"][r, i, g]
end

data["xa0a_n"] = copy(data["xa0e_n"])
data["xd0a_n"] = copy(data["xd0e_n"])
data["xm0a_n"] = copy(data["xm0e_n"])

for r ∈ data["set_r"], i ∈ data["set_roil"], g ∈ data["set_gne"]
    data["xa0a_n"][r, i, g] = data["xa0_n"][r, i, g]
    data["xd0a_n"][r, i, g] = data["xd0_n"][r, i, g]
    data["xm0a_n"][r, i, g] = data["xm0_n"][r, i, g]
end

# Extend the notation of xa0a_c to also cover data["set_fnr"] in addition to data["set_roil"] for simplifying the produciton block
data["xa0a_c"] = merge(
Dict((r, i, g) => data["xa0a_c"][r, i, g] for r ∈ data["set_r"], i ∈ data["set_roil"], g ∈ data["set_gnev"]),
Dict((r, i, g) => data["xa0a"][r, i, g] for r ∈ data["set_r"], i ∈ data["set_fnr"], g ∈ data["set_gnev"])
)

# Add eind for i used by each disaggregated power sector in r

data["einde"] = Dict(
    (i, g, r) => disa["eind"][i, g, r]
    for i ∈ disa["set_i"], g ∈ disa["set_v"], r ∈ disa["set_r"]
)

# :elec used by each disaggregated power sector in r
data["eindea"] = Dict(
    (i, g, r) => sum(data["einde"][j, g, r] for j ∈ disa["set_v"])
    for i ∈ data["set_elec"], g ∈ disa["set_v"], r ∈ disa["set_r"]
)

# All inputs (including :elec) used by each disaggregated power sector in r
data["eindea"] = merge(

Dict((i, g, r) => data["einde"][i, g, r] for i ∈ data["set_note"], g ∈ data["set_v"], r ∈ data["set_r"]),
Dict((i, g, r) => data["eindea"][i, g, r] for i ∈ data["set_elec"], g ∈ data["set_v"], r ∈ data["set_r"])

)

# Replace g = :elec by g = the set of disaggregated power sector

data["eind"] = merge(

Dict((i, g, r) => data["eind"][i, g, r] for i ∈ data["set_i"], g ∈ data["set_gne"], r ∈ data["set_r"]),
Dict((i, g, r) => data["eindea"][i, g, r] for i ∈ data["set_i"], g ∈ data["set_v"], r ∈ data["set_r"])

)

#### 5.0 Emissions ####

# Benchmark total combusted CO2 emissions

data["fco2"]   = Dict(
        r => sum(data["epslon"][i]*data["cr"][(i, g, r)]*data["eind"][(i, g, r)] for i ∈ data["set_fe"], g ∈ data["set_gnev"])
        for r ∈ data["set_r"]
    )

data["tco2"]   = Dict(
        r => data["fco2"][r] 
        for r ∈ data["set_r"]
    )


return data

end