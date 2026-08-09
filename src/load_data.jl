
using DataFrames
using CSV
using JLD2
using XLSX

function Load_gtap_data()

    GTAPdata.io(joinpath(@__DIR__, "data/gtap"), joinpath(@__DIR__, "IO.jld2"))
    data = load("./src/IO.jld2")    
    return data

end

function Load_satellite_data(data::Dict)

    df = DataFrame(XLSX.readtable(joinpath(@__DIR__, "data/others/satellite.xlsx"), "parameters"))

    d = Dict(
    df.parameter[i] => Dict(Symbol(names(df)[j]) => df[i, j] for j ∈ 2:ncol(df))
    for i in 1:nrow(df)
    )
    merge!(data, d)

    return data

end