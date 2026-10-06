import PATHSolver
PATHSolver.c_api_License_SetString("1259252040&Courtesy&&&USR&GEN2035&5_1_2026&1000&PATH&GEN&31_12_2035&0_0_0&6000&0_0")

include(joinpath(@__DIR__, "src", "cge.jl"))

function first_existing(paths)
    for p in paths
        isfile(p) && return p
    end
    error("none of these files exist:\n" * join(paths, "\n"))
end

const IO = first_existing([
    joinpath(@__DIR__, "data", "IO.jld2"),
    joinpath(@__DIR__, "..", "EPPAinJulia-dynamic", "src", "IO.jld2"),
    joinpath(@__DIR__, "..", "EPPAinJulia", "src", "IO.jld2"),
])
const SAT = first_existing([
    joinpath(@__DIR__, "data", "satellite.xlsx"),
    joinpath(@__DIR__, "..", "EPPAinJulia-dynamic", "src", "data", "others", "satellite.xlsx"),
    joinpath(@__DIR__, "..", "EPPAinJulia", "src", "data", "others", "satellite.xlsx"),
])
const OUT = joinpath(@__DIR__, "results", "recursive_gdp.csv")
mkpath(joinpath(@__DIR__, "results"))
println("IO  ", IO)
println("SAT ", SAT)
st = run_path(IO, SAT, OUT)
println("EXIT")
for (t, s) in sort(collect(st))
    println(t, " ", s)
end
