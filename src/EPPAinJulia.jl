module EPPAinJulia

    using CSV
    using JLD2
    using MPSGE
    using GTAPdata

    include("load_data.jl")
    export Load_gtap_data
    export Load_satellite_data

    include("uno_data.jl")
    export Uno_data

    include("eppacore.jl")
    export EPPACore

    include("eppa_model.jl")
    export EPPA_model

end # module EPPAinJulia
