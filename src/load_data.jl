function Load_gtap_data()

    GTAPdata.io(joinpath(@__DIR__, "data"), joinpath(@__DIR__, "IO.jld2"))
    data = load("./src/IO.jld2")    
    return data

end