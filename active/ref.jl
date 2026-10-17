"""
Reference simulation. `gprod` is read from `data/bau.jld2`, so GDP is endogenous.
Run `active/refcalib.jl` first.
"""

include(joinpath(@__DIR__, "refcalib.jl"))
simu = 1
