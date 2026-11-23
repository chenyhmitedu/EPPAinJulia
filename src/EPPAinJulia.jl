module EPPAinJulia

    using CSV
    using JLD2
    using MPSGE
    using JuMP

    include("load_data.jl")
    export Load_gtap_aggr
    export Load_gtap_disa
    export Load_satellite_data
    
    include("uno.jl")
    export Uno_data

    include("eppacore.jl")
    export EPPACore

    include("build.jl")
    export Build

end # module EPPAinJulia
