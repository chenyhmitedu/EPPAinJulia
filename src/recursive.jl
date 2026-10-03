function save_point(m, path)

jm = jump_model(m)                          # Get the underlying JuMP model where variables live
levels = Dict{String,Float64}()             # Empty dictionary: variable name → last solved level

    for v in all_variables(jm)              # Loop over every JuMP variable in the MCP
       n = JuMP.name(v)                     # JuMP.name(v) returns that variable’s string name in the JuMP model
       isempty(n) && continue               # Skip unnamed variables; the short form of "if isempty(n) continue end"
       levels[n] = JuMP.value(v)            # Store the current solution. Requires a completed solve!
    end 

    JLD2.jldsave(path; levels)              # Write the dict to disk under the key "levels"
    return path

end

function load_point!(m, path)               # Load a saved point into model m from file path. The ! means m is modified in place

    levels  = JLD2.load(path, "levels")     # Read the dict that save_point wrote (name => last level). Same keys as JuMP.name(v)
    jm      = jump_model(m)

    for v in all_variables(jm)
        n   = JuMP.name(v)
        haskey(levels, n) || continue       # Skip if this name was not in .jld2, otherwise do the next line. Same as if !haskey(levels, n); continue; end
        JuMP.set_start_value(v, levels[n])   
    end

    MPSGE.update_internal_start_values!(m)  # ucf(...) starts are recomputed from those prices
    #JuMP.set_start_values(jm)
    return nothing

end

function Recursive(data::Dict, setting::Int64)

    tp      = data["tp"]     # Set in the case file 
    tfp     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])  
    gdp     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    inv     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    ken     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    len     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    gindex  = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    tco2    = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    st      = Dict{Int, Enum}()
    gdptar  = Dict{Tuple{Int64, Symbol}, Float64}() 


    MGE = EPPA_model(data, setting)

    for i in 1:length(tp)

        t = tp[i]
        if t == tp[1]
            for r ∈ data["set_r"]
                ken[t, r] = value(MGE[:evom][:cap, r])
                len[t, r] = value(MGE[:evom][:lab, r])
                gdptar[t, r] = data["gdp0"][r] 
            end
        end

        if t > tp[1]
            tint = tp[i] - tp[i-1] 
            for r ∈ data["set_r"]
                #ken[t, r] = ken[t-5, r]*(1-data["dpr"])^5 + data["ror"]*data["vom"][:i, r]*inv[t-5, r]*5
                ken[t, r] = ken[t-tint, r]*(1-data["dpr"])^tint + data["ror"]*data["inv0"][r]*inv[t-tint, r] * (1 - (1-data["dpr"])^tint) / data["dpr"]
                len[t, r] = len[t-tint, r]*(1+data["pr_t"][t-tint, r])
                gdptar[t, r] = gdptar[t-tint, r] * (1+data["gr_t"][t-tint, r])^(tint)

                set_value!(MGE[:evom][:cap, r], ken[t, r])
                set_value!(MGE[:evom][:lab, r], len[t, r])
                set_value!(MGE[:gdp][r], gdptar[t, r])
            end  
            
        end

        fn = data["filename"]
        p = joinpath(@__DIR__, "data/savepoints", "$(fn)_$(t).jld2")

        if isfile(p)
            load_point!(MGE, p)
        end

        solve!(MGE, cumulative_iteration_limit = 10000, convergence_tolerance = 5e-4)
        st[t] = termination_status(MGE.jump_model)
   
        if st[t] == MOI.LOCALLY_SOLVED || st[t] == MOI.OPTIMAL
            # Do nothing
        else
            solve!(MGE, cumulative_iteration_limit = 10000, convergence_tolerance = 5e-3)
            st[t] = termination_status(MGE.jump_model)

            if st[t] == MOI.LOCALLY_SOLVED || st[t] == MOI.OPTIMAL
            # Do nothing
            else
                solve!(MGE, cumulative_iteration_limit = 10000, convergence_tolerance = 1e-2)
                st[t] = termination_status(MGE.jump_model)
            end
        end

        for r ∈ data["set_r"]
            tfp[t, r]   = value(MGE[:TFP][r])
            gdp[t, r]   = value(MGE[:GDP][r])
            inv[t, r]   = value(MGE[:INV][r])
            gindex[t, r] = value(MGE[:GDPINDEX][r])
            tco2[t, r]  = value(MGE[:TCO2][r])
            #st[t] = termination_status(MGE.jump_model)
        end
        
        save_point(MGE, p)

#        set_value!(MGE[:INV][r], inv[t, r])

    end

    return gdp, len, ken, st, gdptar
end
