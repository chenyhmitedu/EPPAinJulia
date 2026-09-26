function Recursive(data::Dict, setting::Int64)

    tp      = collect(2025:5:2030)
    tfp     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])  
    gdp     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    inv     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    ken     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    len     = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    gindex  = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    tco2    = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ tp, r ∈ data["set_r"])
    st      = Dict{Int, Enum}()

    MGE = EPPA_model(data, setting)

    for t ∈ tp

        if t == tp[1]
            for r ∈ data["set_r"]
                ken[t, r] = value(MGE[:evom][:cap, r])
                len[t, r] = value(MGE[:evom][:lab, r]) 
            end
        end

        if t > tp[1]
            for r ∈ data["set_r"]
                if setting == 0
                    #gdp[t, r] = gdp[t-5, r]*(1+data["gr_t"][t-5, r])^5
                    #set_value!(MGE[:gdp][r], gdp[t, r])
                else
                    #bau = load("./src/data/bau.jld2")  
                    #set_value!(MGE[:tfp][r], bau["tfp"][t, r])
                    #set_value!(MGE[:tco2][r], bau["tco2"][t, r])
                end
            end

            for r ∈ data["set_r"]
                ken[t, r] = ken[t-5, r]*(1-data["dpr"])^5 + data["ror"]*data["vom"][:i, r]*inv[t-5, r]
                len[t, r] = len[t-5, r]*(1+data["pr_t"][t-5, r])

                set_value!(MGE[:evom][:cap, r], ken[t, r])
                set_value!(MGE[:evom][:lab, r], len[t, r])
            end  
            
            # every JuMP variable: start := current value (previous period's solve)
            set_start_values(jump_model(MGE))

            # MPSGE nest / unit-cost virtuals
            #MPSGE.update_internal_start_values!(MGE)
            
        end

        solve!(MGE, cumulative_iteration_limit = 5000, convergence_tolerance = 1e-4)
        
        for r ∈ data["set_r"]
            tfp[t, r]   = value(MGE[:TFP][r])
            gdp[t, r]   = value(MGE[:GDP][r])
            inv[t, r]   = value(MGE[:INV][r])
            gindex[t, r] = value(MGE[:GDPINDEX][r])
            tco2[t, r]  = value(MGE[:TCO2][r])
            st[t] = termination_status(MGE.jump_model)
        end
        
#        set_value!(MGE[:INV][r], inv[t, r])

    end

    if setting == 0
        #JLD2.@save joinpath(@__DIR__, "./data", "bau.jld2") tfp tco2

        function save_point(m, path)
            jm = jump_model(m)
            levels = Dict{String,Float64}()
            for v in all_variables(jm)
                n = JuMP.name(v)
                isempty(n) && continue
                levels[n] = JuMP.value(v)
            end
            JLD2.jldsave(path; levels)
            return path
        end

        save_point(MGE, joinpath(@__DIR__, "data/ref_2025.jld2"))
    end

    return gdp, tfp, tco2, inv, st
end
