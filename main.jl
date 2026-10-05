include(joinpath(@__DIR__, "src", "soe.jl"))

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

println("IO  ", IO)
println("SAT ", SAT)
worst = run_path(IO, SAT, OUT)
println("EXIT ", worst)

