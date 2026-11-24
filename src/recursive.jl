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

function _level(x)
    v = try
        value(x)
    catch
        return NaN
    end
    return v
end

function Recursive(data::NamedTuple, setting::Int64)

    tp      = data.year     # Set in the case file 
    tfp     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ REGIONS)  
    gdp     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ REGIONS)
    inv     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ REGIONS)
    ken     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ REGIONS)
    len     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ REGIONS)
    gindex  = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ REGIONS)
    tco2    = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ REGIONS)
    st      = Dict{Int, Enum}()
    gdptar  = Dict{Tuple{Int64, Symbol}, Float64}() 


    MGE = Build(data, setting)

    for i in 1:length(tp)

        solve!(MGE, cumulative_iteration_limit = 10000, convergence_tolerance = 5e-4)

        # totalcap(r,t) = newcap(r,t) + kapital(r)*srve(r,t) - sum(i$vintg(i,r), theta(i,t)*dk.l(i,r)*srve(r,t))
        #                                                               - sum(bt$vintgbs(bt,r), thetab(bt,t)*b_k.l(bt,r)*srve(r,t));

        

    
    end

    return
end
