cd(@__DIR__)    # Set the working directory at where this file is located
using Pkg
Pkg.activate(".")
#Pkg.add(["CSV", "DataFrames", "JLD2", "JuMP", "MPSGE", "PATHSolver", "XLSX"])
Pkg.add(path="https://github.com/chenyhmitedu/CSVtoDIC")

Pkg.instantiate()
using EPPAinJulia, JuMP, MPSGE, DataFrames, XLSX

import PATHSolver
PATHSolver.c_api_License_SetString("1259252040&Courtesy&&&USR&GEN2035&5_1_2026&1000&PATH&GEN&31_12_2035&0_0_0&6000&0_0")

Prepare_data() = Load_gtap_aggr() |> Load_gtap_disa |> Load_satellite_data
data = Prepare_data()
x = uno_data(data)

B = (; (Symbol(k) => v for (k, v) in data)...)
