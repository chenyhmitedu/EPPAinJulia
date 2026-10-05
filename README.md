# Simplified recursive EPPA

Same GTAP resolution as EPPAinJulia: 18 regions, 14 sectors, factors `lnd`, `lab`, `cap`, `fix`.

This project does not use DataFrames or PATH. Dependencies are only JLD2 and XLSX.

From this folder, in a Julia REPL:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
include("main.jl")
```

`main.jl` looks for `data/IO.jld2` and `data/satellite.xlsx`, then for the same files under `../EPPAinJulia/src` and `../EPPAinJulia-dynamic/src`. Results go to `results/recursive_gdp.csv`.
