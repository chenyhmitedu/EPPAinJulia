cd(@__DIR__)    # Set the working directory at where this file is located
using Pkg

Pkg.activate(".")
Pkg.develop(path="D:/work/MIT Dropbox/Yen-Heng Chen/Programming/Julia/CSVtoDIC")
Pkg.develop(path="D:/work/MIT Dropbox/Yen-Heng Chen/Programming/Julia/GTAPdata")

#=
Pkg.add([
"CSV",
"DataFrames",
"JLD2",
"JuMP",
"MPSGE"
])
=#

Pkg.instantiate()

using EPPAinJulia
using DataFrames
using CSV
using JLD2
using JuMP
using MPSGE

# Load_data(): Read GTAP data (CSV to JLD2, and then to a dictionary)
# Uno_data(): Use the EPPA variable and parameter notations
# Uno_data without () refers to the function object itself. The |> operator expects a function on its RHS, not a function call.

Prepare_data() = Load_gtap_data() |> Uno_data
data = Prepare_data()

import PATHSolver
PATHSolver.c_api_License_SetString("1259252040&Courtesy&&&USR&GEN2035&5_1_2026&1000&PATH&GEN&31_12_2035&0_0_0&6000&0_0")

# MGE_model is defined in MGE.jl 
MGE = EPPA_model(data, -1)

solve!(MGE, cumulative_iteration_limit = 0)
