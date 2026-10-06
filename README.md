# MPSGE CGE with GDP calibration

18 regions, 14 sectors, factors lab, cap, lnd, fix. PATH solves the MCP. TFP is an output-augmenting parameter updated outside PATH until real consumption hits the exogenous GDP path.

From this folder:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
include("main.jl")
```

`main.jl` sets the PATH license, then looks for `data/IO.jld2` and `data/satellite.xlsx`, then the same files under `../EPPAinJulia/src` and `../EPPAinJulia-dynamic/src`. Results go to `results/recursive_gdp.csv`.
