module EPPAinJulia

    using CSV
    using JLD2
    using MPSGE
    using GTAPdata

    include("load_data.jl")
    export Load_gtap_data

    include("eppacore.jl")
    export MGE_model

end # module EPPAinJulia
