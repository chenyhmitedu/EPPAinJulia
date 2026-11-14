using DataFrames
using CSV
using JLD2
using XLSX
using CSVtoDIC

function Load_gtap_aggr()

    p = joinpath(@__DIR__, "../data/gtap/aggr/")
    data = CSVtoDIC.source(p)
    return data[1]

end

function Load_gtap_disa(data::Dict = Dict())
    p = joinpath(@__DIR__, "../data/gtap/disa/")
    disa_data = CSVtoDIC.source(p)[1]
    
    if !isempty(data)
        merge!(data, disa_data)
        return data
    else
        return disa_data
    end
end

function Load_satellite_data(data::Dict)

    path = joinpath(@__DIR__, "../data/others/satellite.xlsx")

    XLSX.openxlsx(path) do xf
        for sheet in XLSX.sheetnames(xf)[2:end]
            df = DataFrame(XLSX.readtable(path, sheet; first_row=3, header=false))
            if ncol(df) >= 3
                value_df = DataFrame(XLSX.readtable(path, sheet; first_row=4, header=false))
                header_df = DataFrame(XLSX.readtable(path, sheet; first_row=3, header=false))
                ncols = min(ncol(value_df), ncol(header_df))
                data[sheet] = Dict(
                    (
                        value_df[i, 1] isa Number ? value_df[i, 1] : Symbol(value_df[i, 1]),
                        header_df[1, j - 1] isa Number ? header_df[1, j - 1] : Symbol(header_df[1, j - 1])
                    ) => value_df[i, j]
                    for i in 1:nrow(value_df), j in 2:ncols+1
                )
            elseif ncol(df) == 2
                data[sheet] = Dict(
                    df[i, 1] => df[i, 2]
                    for i in 1:nrow(df)
                )
            else
                df = DataFrame(XLSX.readtable(path, sheet; first_row=2, header=false))
                data[sheet] = collect(df[!, 1])
            end
        end
    end

    return data

end
