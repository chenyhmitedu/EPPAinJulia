using Pkg
Pkg.activate(".")
Pkg.instantiate()

using EPPAinJulia
using MPSGE: solve!
using XLSX

casefile = isempty(ARGS) ? joinpath(@__DIR__, "active", "refcalib.jl") : ARGS[1]
if !isabspath(casefile)
    named = joinpath(@__DIR__, "active", basename(casefile))
    casefile = isfile(casefile) ? abspath(casefile) : named
end
include(casefile)
casename = splitext(basename(casefile))[1]

here = joinpath(@__DIR__, "data")
data = prepare(
    joinpath(here, "eppa8data_2017.dat"),
    joinpath(here, "eppa8data_elec_2017.dat"),
    joinpath(here, "satellite.xlsx"),
)
println("regions ", length(data.REGIONS))

println("\n================ base-year calibration check ================")
flush(stdout)
MGE = EPPA_model(data, -1; simu)
solve!(MGE, cumulative_iteration_limit = 0)

out = joinpath(@__DIR__, "results")
mkpath(out)
path = joinpath(out, casename * ".xlsx")
MGE, st, rows, eesec_ts = run_scenario(data; simu, scenario = casename)

XLSX.openxlsx(path, mode = "w") do xf
    ej = XLSX.addsheet!(xf, "EESEC")
    ej[1, 1] = "year"
    ej[1, 2] = "energy"
    ej[1, 3] = "user"
    ej[1, 4] = "region"
    ej[1, 5] = "eesec"
    for (i, (key, value)) in enumerate(sort!(collect(eesec_ts); by = x -> x.first))
        year, energy, user, region = key
        row = i + 1
        ej[row, 1] = year
        ej[row, 2] = String(energy)
        ej[row, 3] = String(user)
        ej[row, 4] = String(region)
        ej[row, 5] = value
    end

    stsheet = XLSX.addsheet!(xf, "solve_status")
    stsheet[1, 1] = "year"
    stsheet[1, 2] = "region"
    stsheet[1, 3] = "gprod"
    stsheet[1, 4] = "rgdp"
    stsheet[1, 5] = "target"
    stsheet[1, 6] = "status"
    for (i, row) in enumerate(rows)
        r = i + 1
        stsheet[r, 1] = row.year
        stsheet[r, 2] = String(row.region)
        stsheet[r, 3] = row.gprod
        stsheet[r, 4] = row.rgdp
        stsheet[r, 5] = row.target
        stsheet[r, 6] = row.status
    end
end
println("wrote ", path)

function replication_error(calib_path, sim_path)
    loadrows(p) = begin
        outd = Dict{Tuple{Int,Symbol},NamedTuple}()
        XLSX.openxlsx(p) do xf
            sh = xf["solve_status"]
            for i in 2:XLSX.nrow(sh)
                y = sh[i, 1]
                r = sh[i, 2]
                g = sh[i, 3]
                rg = sh[i, 4]
                tg = sh[i, 5]
                if isnothing(y) || isnothing(r)
                    continue
                end
                outd[(Int(y), Symbol(r))] = (
                    gprod = Float64(g),
                    rgdp = Float64(rg),
                    target = Float64(tg),
                )
            end
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

if simu == 1 && isfile(joinpath(out, "refcalib.xlsx"))
    dprod, dgdp, dtarget = replication_error(joinpath(out, "refcalib.xlsx"), path)
    println("replication max |gprod_ref - gprod_refcalib| ", dprod)
    println("replication max |rgdp_ref / rgdp_refcalib - 1| ", dgdp)
    println("replication max |rgdp_ref / GDP target - 1| ", dtarget)
    flush(stdout)
end


