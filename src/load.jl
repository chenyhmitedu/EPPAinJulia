# Readers for the GAMS parameter dump and the xls2gms tables used by this run.

const YEARS = [2017; 2020; collect(2025:5:2100)]

function tcode(year)
    i = findfirst(==(year), YEARS)
    i === nothing && error("year $year is not an EPPA period")
    return Symbol("t" * lpad(i, 3, '0'))
end

function load_gams_dat(path, wanted::Set{String})
    out = Dict{String,Dict{Tuple,Float64}}()
    for w in wanted
        out[w] = Dict{Tuple,Float64}()
    end
    name = ""
    open(path) do io
        for line in eachline(io)
            if startswith(line, "parameter ")
                name = split(strip(line), r"\s+|/")[2]
                continue
            end
            isempty(name) && continue
            if startswith(line, "/;")
                name = ""
                continue
            end
            haskey(out, name) || continue
            s = strip(line)
            (isempty(s) || startswith(s, "*") || startswith(s, "\$")) && continue
            parts = split(s)
            length(parts) < 2 && continue
            val = tryparse(Float64, parts[end])
            val === nothing && continue
            idx = Tuple(Symbol.(lowercase.(split(parts[1], '.'))))
            out[name][idx] = val
        end
    end
    return out
end

function getp(parms, name, key)
    get(parms[name], key, 0.0)
end

"""Parse an xls2gms `table` whose rows are `%tNNN%` and whose header is region names."""
function load_t_table(path)
    lines = readlines(path)
    body = String[]
    inside = false
    for ln in lines
        s = strip(ln)
        if !inside
            if startswith(s, "table ")
                inside = true
            end
            continue
        end
        startswith(s, ";") && break
        (isempty(s) || startswith(s, "*")) && continue
        push!(body, ln)
    end
    isempty(body) && error("no table body in $path")
    regions = Symbol.(lowercase.(split(strip(body[1]))))
    data = Dict{Tuple{Symbol,Symbol},Float64}()
    for ln in body[2:end]
        parts = split(strip(ln))
        length(parts) < 2 && continue
        row = Symbol(lowercase(replace(parts[1], "%" => "")))
        vals = tryparse.(Float64, parts[2:end])
        n = min(length(vals), length(regions))
        for j in 1:n
            vals[j] === nothing && continue
            data[(row, regions[j])] = vals[j]
        end
    end
    return data
end

function load_benchmark(dat_path, extracted_dir)
    wanted = Set([
        "xp0", "es0", "xm0", "vst", "labd0", "kapd0", "ffactd0",
        "xdp0", "xmp0", "xdc0", "xmc0", "xdg0", "xmg0", "xdi0", "xmi0",
        "ti", "tf", "tp", "pg0", "ptxy0", "tx", "tm", "wtflow0", "vtwr",
        "savf0", "cons0", "kapdg0",
    ])
    p = load_gams_dat(dat_path, wanted)
    regions = sort!(unique(first.(keys(p["cons0"]))))
    sectors = sort!(unique(last.(keys(p["xp0"]))))
    hist = load_t_table(joinpath(extracted_dir, "parameters_eppatrend_histrgdp.inc"))
    ann = load_t_table(joinpath(extracted_dir, "parameters_eppatrend_argdpgrrate.inc"))
    pop = load_t_table(joinpath(extracted_dir, "parameters_eppatrend_popa_eppa.inc"))
    return (; p, regions, sectors, hist, ann, pop)
end

function growth_factor(data, r, year)
    if year == 2017
        return data.hist[(:t001, r)]^3
    elseif year == 2020
        return data.hist[(:t002, r)]^5
    else
        return (1 + data.ann[(tcode(year), r)])^5
    end
end

function pop_ratio(data, r, year, next)
    a = data.pop[(tcode(year), r)]
    b = data.pop[(tcode(next), r)]
    return a == 0 ? 1.0 : b / a
end
