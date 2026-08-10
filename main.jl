cd(@__DIR__)    # Set the working directory at where this file is located
using Pkg

Pkg.activate(".")

#=
Pkg.add([
"CSV",
"DataFrames",
"JLD2",
"JuMP",
"MPSGE",
"PATHSolver",
"XLSX"
])

Pkg.add(path="https://github.com/chenyhmitedu/CSVtoDIC")
Pkg.add(path="https://github.com/chenyhmitedu/GTAPdata")
=#

#Pkg.develop(path="D:/work/MIT Dropbox/Yen-Heng Chen/Programming/Julia/CSVtoDIC")
#Pkg.develop(path="D:/work/MIT Dropbox/Yen-Heng Chen/Programming/Julia/GTAPdata")

Pkg.instantiate()

using EPPAinJulia
using JuMP
using MPSGE

import PATHSolver
PATHSolver.c_api_License_SetString("1259252040&Courtesy&&&USR&GEN2035&5_1_2026&1000&PATH&GEN&31_12_2035&0_0_0&6000&0_0")

# Load_data(): Read GTAP data (CSV to JLD2, and then to a dictionary)
# Uno_data(): Use the EPPA variable and parameter notations
# Uno_data without () refers to the function object itself. The |> operator expects a function on its RHS, not a function call.

Prepare_data() = Load_gtap_data() |> Load_satellite_data |> Uno_data 
data = Prepare_data()

# MGE_model is defined in MGE.jl 
MGE = EPPA_model(data, -1)

solve!(MGE, cumulative_iteration_limit = 0)
df = generate_report(MGE)
dff = df[df.margin .> 1e-6, :]
println(dff)