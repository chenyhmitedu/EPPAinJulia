using Pkg
Pkg.activate(".")
Pkg.instantiate()

using EPPAinJulia
using MPSGE: solve!

casefile = isempty(ARGS) ? joinpath(@__DIR__, "active", "refcalib.jl") : ARGS[1]
if !isabspath(casefile)
    named = joinpath(@__DIR__, "active", basename(casefile))
    casefile = isfile(casefile) ? abspath(casefile) : named
end
include(casefile)
casename = splitext(basename(casefile))[1]

root = joinpath(@__DIR__, "..", "EPPA8")
data = prepare(
    joinpath(root, "data", "eppa8data_2017.dat"),
    joinpath(root, "data", "eppa8data_elec_2017.dat"),
    joinpath(root, "data", "extracted"),
)
println("regions ", length(data.REGIONS))

println("\n================ base-year calibration check ================")
flush(stdout)
MGE = EPPA_model(data, -1; simu)
solve!(MGE, cumulative_iteration_limit = 0)

out = joinpath(@__DIR__, "results")
mkpath(out)
path = joinpath(out, casename * ".csv")
MGE, st, rows = recursive(data; simu, csv = path, scenario = casename)
open(path, "w") do io
    println(io, "year,region,gprod,rgdp,target,status")
    for row in rows
        println(io, row.year, ",", row.region, ",", row.gprod, ",", row.rgdp, ",", row.target, ",", row.status)
    end
end
println("wrote ", path)

function replication_error(calib_path, sim_path)
    loadrows(p) = begin
        outd = Dict{Tuple{Int,Symbol},NamedTuple}()
        for (i, line) in enumerate(eachline(p))
            i == 1 && continue
            y, r, g, rg, tg, stt = split(line, ",")
            outd[(parse(Int, y), Symbol(r))] = (
                gprod = parse(Float64, g),
                rgdp = parse(Float64, rg),
                target = parse(Float64, tg),
            )
        end
        return outd
    end
    a = loadrows(calib_path)
    b = loadrows(sim_path)
    dprod = 0.0
    dgdp = 0.0
    dtarget = 0.0
    for (k, va) in a
        vb = b[k]
        dprod = max(dprod, abs(vb.gprod - va.gprod))
        dgdp = max(dgdp, abs(vb.rgdp / va.rgdp - 1))
        dtarget = max(dtarget, abs(vb.rgdp / va.target - 1))
    end
    return dprod, dgdp, dtarget
end

if simu == 1 && isfile(joinpath(out, "refcalib.csv"))
    dprod, dgdp, dtarget = replication_error(joinpath(out, "refcalib.csv"), path)
    println("replication max |gprod_ref - gprod_refcalib| ", dprod)
    println("replication max |rgdp_ref / rgdp_refcalib - 1| ", dgdp)
    println("replication max |rgdp_ref / GDP target - 1| ", dtarget)
    flush(stdout)
end