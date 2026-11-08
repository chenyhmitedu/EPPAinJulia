"""
    EPPAinJulia

Recursive-dynamic MPSGE model of EPPA.
"""
module EPPAinJulia

using JuMP
using JLD2
using MPSGE
using PATHSolver
using Serialization
using XLSX

export load_benchmark, load_data, prepare, MGE_model, EPPA_model, run_scenario, set_model_years!, record_eesec!, record_sco2!, record_ftotco2!, write_report, replication_error, gams_table

const PATH_LICENSE = "1259252040&Courtesy&&&USR&GEN2035&5_1_2026&1000&PATH&GEN&31_12_2035&0_0_0&6000&0_0"
const MOI = JuMP.MOI

include("load_data.jl")
include("uno_data.jl")
include("eppacore.jl")
include("mge.jl")
include("recursive.jl")
include("report.jl")

function __init__()
    apply_smooth!()
    return nothing
end

end


