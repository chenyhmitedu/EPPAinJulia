using Pkg
Pkg.activate(".")
Pkg.instantiate()

using EPPAinJulia
using MPSGE: solve!

root = joinpath(@__DIR__, "..", "EPPA8")
data = prepare(
    joinpath(root, "data", "eppa8data_2017.dat"),
    joinpath(root, "data", "eppa8data_elec_2017.dat"),
    joinpath(root, "data", "extracted"),
)
println("regions ", length(data.REGIONS))

println("\n================ base-year calibration check ================")
flush(stdout)
MGE = EPPA_model(data, -1)
solve!(MGE, cumulative_iteration_limit = 0)

out = joinpath(@__DIR__, "results")
mkpath(out)
path = joinpath(out, "gprod.csv")
MGE, st, rows = calibrate(data; csv = path)
open(path, "w") do io
    println(io, "year,region,gprod,rgdp,target,status")
    for row in rows
        println(io, row.year, ",", row.region, ",", row.gprod, ",", row.rgdp, ",", row.target, ",", row.status)
    end
end
println("wrote ", path)