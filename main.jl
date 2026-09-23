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
=#

#Pkg.develop(path="D:/work/MIT Dropbox/Yen-Heng Chen/Programming/Julia/CSVtoDIC")
#Pkg.develop(path="D:/work/MIT Dropbox/Yen-Heng Chen/Programming/Julia/GTAPdata")
#Pkg.add(path="https://github.com/chenyhmitedu/CSVtoDIC")
#Pkg.add(path="https://github.com/chenyhmitedu/GTAPdata")
#Pkg.update("GTAPdata")

Pkg.instantiate()

using EPPAinJulia
using JuMP
using MPSGE

import PATHSolver
PATHSolver.c_api_License_SetString("1259252040&Courtesy&&&USR&GEN2035&5_1_2026&1000&PATH&GEN&31_12_2035&0_0_0&6000&0_0")

# Load_data(): Read GTAP data (CSV to JLD2, and then to a dictionary)
# Uno_data(): Use the EPPA variable and parameter notations
# Uno_data without () refers to the function object itself. The |> operator expects a function on its RHS, not a function call.

# Uno_data now has two inputs: data and Load_gtap_disa()
Prepare_data() = Load_gtap_aggr() |> Load_satellite_data |> data -> Uno_data(data, Load_gtap_disa()) 
data = Prepare_data()

# MGE_model is defined in MGE.jl 
MGE = EPPA_model(data, -1)
solve!(MGE, cumulative_iteration_limit = 0)

#for i ∈ [:p_c, :coa, :gas], g ∈ data["set_g"], r ∈ [:USA]
#    set_value!(MGE[:ta][i, g, r], 0.05)
#end

MGE = EPPA_model(data, 2)

for r ∈ [:EUR]
    set_value!(MGE[:policy][r], true)
    set_value!(MGE[:rer][r], 0.9)
end

solve!(MGE, cumulative_iteration_limit = 1000, convergence_tolerance = 1e-4)

# copy current solution -> PATH starting point
set_start_values(jump_model(MGE))

_scalars(x) = x isa MPSGE.MPSGEIndexedVariable ? vec(MPSGE.extract_scalars(x)) : [x]

function copy_solution_to_start!(m)
    for v in all_variables(m)
        for s in _scalars(v)
            set_start_value(s, value(s); update_internal_start_values=false)
        end
    end

    # only sectors that actually have production trees
    MPSGE.update_internal_start_values!(m)

    set_start_values(jump_model(m))
    return nothing
end

copy_solution_to_start!(MGE)
solve!(MGE, cumulative_iteration_limit=0)


solver_status   = termination_status(jump_model(MGE))
model_status    = primal_status(jump_model(MGE))
ss              = Int(solver_status)
ms              = Int(model_status)

if (ss != 1 || ss != 4) && (ms != 1)
    solve!(MGE, cumulative_iteration_limit = 1000, convergence_tolerance = 5e-3)
end

df = generate_report(MGE)
dff = df[df.margin .> 1e-6, :]
println(dff)
#println(df)