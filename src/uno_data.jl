function Uno_data(data::Dict)

# Model specific sets

# Vectors below may be changed depending on the sectoral names and resolution
data["set_fe"]      = [:coa, :gas, :p_c, :oil]
data["set_elec"]    = [:elec]
data["set_e"]       = union(data["set_fe"], data["set_elec"])
data["set_ne"]      = setdiff(data["set_i"], data["set_e"])

data["set_tr"]      = [:tran]
data["set_con"]       = [:c]
data["set_gov"]     = [:g]
data["set_inv"]     = [:i]

data["set_fix"]     = [:fix]
data["set_lnd"]     = setdiff(data["set_sf"], data["set_fix"])

# EPPA parameters notation

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
    r => data["vom"][:c, r]
    for r ∈ data["set_r"]
)

# Value of tax-excluded government expenditure (td tax excluded)
data["g0"] = Dict(
    r => data["vom"][:g, r]
    for r ∈ data["set_r"]
)

# Value of tax-excluded government investment (td tax excluded)
data["inv0"] = Dict(
    r => data["vom"][:i, r]
    for r ∈ data["set_r"]
)

return data

end