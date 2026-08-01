function Uno_data(data::Dict)

# Model specific sets

# Vectors below may be changed depending on the sectoral names and resolution
data["set_fe"]      = [:coa, :gas, :p_c]
data["set_elec"]    = [:elec]
data["set_ne"]      = setdiff(data["set_i"], union(data["set_fe"], data["set_elec"]))
data["set_tr"]      = [:tran]

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

# xap0(r,i,j)	= vdfm(i,j,r)*(1+rtfd(i,j,r))+vifm(i,j,r)*(1+rtfi(i,j,r));
data["xa0"] = Dict(
    (r, i, j) => data["vafm"][i, j, r]
    for r ∈ data["set_r"], i ∈ data["set_i"], j ∈ data["set_g"]
)

return data

end