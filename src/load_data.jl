
using DataFrames
using CSV
using JLD2
using XLSX

function Load_gtap_aggr()

    GTAPdata.io(joinpath(@__DIR__, "data/gtap/aggr/"), joinpath(@__DIR__, "IO.jld2"))
    data = load("./src/IO.jld2")    
    return data

end

function Load_gtap_disa()

    GTAPdata.io(joinpath(@__DIR__, "data/gtap/disa/"), joinpath(@__DIR__, "IO_.jld2"))
    data = load("./src/IO_.jld2")
#    merge!(data, data_)    
    return data

end

#=
function Load_satellite_data(data::Dict)

    df = DataFrame(XLSX.readtable(joinpath(@__DIR__, "data/others/satellite.xlsx"), "parameters"))

    d = Dict(
    df.parameter[i] => Dict(Symbol(names(df)[j]) => df[i, j] for j ∈ 2:ncol(df))
    for i in 1:nrow(df)
    )
    merge!(data, d)

    return data

end
=#

function Load_satellite_data(data::Dict)

    path = joinpath(@__DIR__, "data/others/satellite.xlsx")

    XLSX.openxlsx(path) do xf
        for sheet in XLSX.sheetnames(xf)
            df = DataFrame(XLSX.readtable(path, sheet))

            if eltype(df[!, 1]) <: AbstractString
                merge!(data, Dict(
                    df[i, 1] => Dict(Symbol(names(df)[j]) => df[i, j] for j ∈ 2:ncol(df))
                    for i in 1:nrow(df)
                ))
            else
                data[sheet] = Dict(
                    (Int(df[i, 1]), Symbol(names(df)[j])) => df[i, j]
                    for i in 1:nrow(df), j in 2:ncol(df)
                )
            end
        end
    end

    return data

end

