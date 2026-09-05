function Uno_data(data::Dict)

#       Model specific sets

# Vectors below may be changed depending on the sectoral names and resolution
data["set_fe"]      = [:coa, :gas, :p_c, :oil]
data["set_elec"]    = [:elec]
data["set_e"]       = union(data["set_fe"], data["set_elec"])
data["set_ne"]      = setdiff(data["set_i"], data["set_e"])
data["set_roil"]    = [:p_c]
data["set_othr"]    = [:othr]
data["set_serv"]    = [:serv]
data["set_food"]   = [:food]
data["set_eint"]   = [:eint]
data["set_fnr"]    = setdiff(data["set_fe"], data["set_roil"])

data["set_tr"]      = [:tran]
data["set_con"]       = [:c]
data["set_gov"]     = [:g]
data["set_inv"]     = [:i]

data["set_fix"]     = [:fix]
data["set_lnd"]     = setdiff(data["set_sf"], data["set_fix"])
data["set_cg"]      = setdiff(data["set_fe"], data["set_roil"])
data["set_rest"]    = setdiff(data["set_ne"], union(data["set_serv"], data["set_othr"], data["set_food"], data["set_eint"]))

data["set_br"]      = [:BRA]
data["set_nbr"]     = setdiff(data["set_r"], data["set_br"])

#       EPPA parameters notation

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
            den = data["xd0"][r, i, j] + data["xm0"][r, i, j]
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
    (r, s, i) => data["vxmd"][i, s, r]*(1 - data["rtxs0"][i, s, r]) + sum(data["vtwr"][j, i, s, r] for j ∈ data["set_tr"])
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

#       Household transportation

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

data["cr"]  = Dict(
    (i, g, r) => 0.9
    for i ∈ data["set_roil"], g ∈ data["set_g"], r ∈ data["set_r"]
)



return data

end