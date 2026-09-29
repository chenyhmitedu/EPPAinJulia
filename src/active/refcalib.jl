# Reference calibration
setting    = 1    # (0 = GDP exogenous; others = GDP endogenous)

# Population and GDP growth

years   = union([2023], collect(2025:5:2100))
pr_t    = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ years, r ∈ data["set_r"])  
gr_t    = Dict{Tuple{Int,Symbol}, Float64}((t, r) => 0.0 for t ∈ years, r ∈ data["set_r"])  

data["dpr"]         = 0.05              # Depreciation rate
data["ror"]         = 0.15              # Rate of return for capital
