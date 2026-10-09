# Keep CES / Cobb-Douglas / Shephard's lemma finite at a zero price.
# At benchmark prices the perturbation is ~1e-8. Without it, PATH's Jacobian
# is NaN once a price sits on its bound and calibration dies after 2060.
const _smooth_announced = Ref(false)

function apply_smooth!()
    @eval MPSGE begin
        function _soft(x)
            return 0.5 * (x + (x * x + 1e-8)^0.5)
        end

        function cobb_douglas(N::Node; depth = -1)
            return prod(_soft(unit_cost_function(child; depth = depth))^(quantity(child) / quantity(N)) for child in children(N); init = 1)
        end

        function CES(N::Node; depth = -1)
            sign = netput_sign(N)
            if isempty(children(N))
                return 0
            end
            p = 1 + sign * elasticity(N)
            return sum(
                begin
                    uc = unit_cost_function(child; depth = depth)
                    quantity(child) / quantity(N) * _soft(uc)^p
                end
                for child in children(N)
            )^(1 / p)
        end

        function compensated_demand(N::Netput; depth = -1)
            sign = -netput_sign(N)
            parent_chain = get_parent_chain(N)
            elasticities = [0, elasticity.(parent_chain[2:end])..., 0]
            sigma = elasticities[1:end-1] .- elasticities[2:end]
            factors = zip(parent_chain, sigma) |>
                collect |>
                x -> filter(y -> y[2] != 0, x) .|>
                x -> _soft(unit_cost_function(x[1]; depth = depth))^(sign * x[2])
            return @expression(jump_model(model(commodity(N))), sign * base_quantity(N) * prod(factors; init = 1))
        end

        function demand(H::Consumer, C::Commodity)
            if !is_demand(H, C)
                return 0
            end
            jm = jump_model(model(H))
            D = demand(H)
            total_quantity = quantity(D)
            DF = final_demands(D)[C]
            total_income = []
            for d in DF
                cvar = get_variable(C)
                safe = 0.5 * (cvar + (cvar * cvar + 1e-8)^0.5)
                if !(isa(elasticity(D), Real))
                    income = @expression(jm,
                        quantity(d) / total_quantity * get_variable(H) / safe *
                        ifelse(1 * elasticity(D) == 1, 1, (expenditure(D) * reference_price(d) / safe)^(elasticity(D) - 1))
                    )
                elseif elasticity(D) == 1
                    income = quantity(d) / total_quantity * get_variable(H) / safe
                else
                    income = quantity(d) / total_quantity * get_variable(H) / safe *
                        (expenditure(D) * reference_price(d) / safe)^(elasticity(D) - 1)
                end
                push!(total_income, income)
            end
            return sum(total_income; init = 0)
        end
    end
    if !_smooth_announced[]
        println("CES/Cobb-Douglas price smoothing is on")
        _smooth_announced[] = true
    end
    return nothing
end
