using Pkg
Pkg.activate(".")
Pkg.instantiate()

using EPPAinJulia
using MPSGE: solve!
using Dates

casefile = isempty(ARGS) ? joinpath(@__DIR__, "active", "refcalib.jl") : ARGS[1]
if !isabspath(casefile)
    named = joinpath(@__DIR__, "active", basename(casefile))
    casefile = isfile(casefile) ? abspath(casefile) : named
end
include(casefile)
casename = splitext(basename(casefile))[1]

function stamp(msg)
    println("[", Dates.format(now(), "HH:MM:SS"), "] ", msg)
    flush(stdout)
end

here = joinpath(@__DIR__, "data")
stamp("starting data preparation")
t_prepare = @elapsed data = prepare(
    joinpath(here, "eppa8data_2017.dat"),
    joinpath(here, "eppa8data_elec_2017.dat"),
    joinpath(here, "satellite.xlsx"),
)
stamp("finished data preparation in $(round(t_prepare; digits = 2)) s")
println("regions ", length(data.REGIONS))

println("\n================ base-year calibration check ================")
flush(stdout)
stamp("starting EPPA_model build")
t_build = @elapsed MGE = EPPA_model(data, -1; simu)
stamp("finished EPPA_model build in $(round(t_build; digits = 2)) s")
stamp("starting zero-iteration benchmark solve")
t_bench = @elapsed solve!(MGE, cumulative_iteration_limit = 0)
stamp("finished zero-iteration benchmark solve in $(round(t_bench; digits = 2)) s")
out = joinpath(@__DIR__, "results")
mkpath(out)
path = joinpath(out, casename * ".xlsx")
policy = isdefined(@__MODULE__, :policy) ? policy : :ref
rer_fn = isdefined(@__MODULE__, :rer) ? rer : (r, t) -> 1.0
MGE, st, rows, eesec_ts, sco2_ts, ftotco2_ts, aeei_ts = run_scenario(data; simu, scenario = casename, policy, rer = rer_fn)
write_report(path, rows, eesec_ts, sco2_ts, ftotco2_ts, aeei_ts)
println("wrote ", path)

if simu == 1 && isfile(joinpath(out, "refcalib.xlsx"))
    dprod, dgdp, dtarget = replication_error(joinpath(out, "refcalib.xlsx"), path)
    println("replication max |gprod_ref - gprod_refcalib| ", dprod)
    println("replication max |rgdp_ref / rgdp_refcalib - 1| ", dgdp)
    println("replication max |rgdp_ref / GDP target - 1| ", dtarget)
    flush(stdout)
end
