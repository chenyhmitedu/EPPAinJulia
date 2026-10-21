"""
    load_years(path)

Read the solve periods from a text file. Blank lines and lines that start with `*` or `#` are ignored.
"""
function load_years(path)
    years = Int[]
    for ln in eachline(path)
        s = strip(ln)
        (isempty(s) || startswith(s, "*") || startswith(s, "#")) && continue
        push!(years, parse(Int, split(s)[1]))
    end
    (length(years) >= 2 && issorted(years) && allunique(years)) ||
        error("period list in $path must be at least two increasing years")
    return years
end

function model_years(path = normpath(joinpath(@__DIR__, "..", "data", "years.txt")))
    return isfile(path) ? load_years(path) : Int[]
end

const YEARS = model_years()

function set_model_years!(years)
    vals = collect(Int, years)
    (length(vals) >= 2 && issorted(vals) && allunique(vals)) ||
        error("period list must be at least two increasing years")
    empty!(YEARS)
    append!(YEARS, vals)
    return YEARS
end

"""
    step_years(i::Integer)

Years between period `i` and the next period.
"""
function step_years(i::Integer)
    1 <= i < length(YEARS) || error("period $i has no following year")
    return YEARS[i + 1] - YEARS[i]
end

"""
    regular_step()

Length of a normal step, after the short opening step. Benchmark capital
survival uses this, as `srve(r,"t0")` does in EPPA.
"""
function regular_step()
    return length(YEARS) >= 3 ? step_years(2) : step_years(1)
end

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

"""
    load_t_table(lines)

Parse an xls2gms `table` whose rows are `%tNNN%` and whose header is region names.
`lines` are the text rows of one satellite sheet.
"""
function load_t_table(lines)
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
    isempty(body) && error("no table body in satellite sheet")
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

"""
    gms_token(cell)

Text of one satellite cell, in the form the GAMS table parsers expect.
"""
function gms_token(cell)
    if cell isa Integer
        return string(cell)
    elseif cell isa AbstractFloat
        return string(cell)
    else
        return strip(string(cell))
    end
end

"""
    gms_lines(sheet)

Join the non-empty cells of one satellite sheet into text rows.
"""
function gms_lines(sheet)
    lines = String[]
    data = XLSX.getdata(sheet)
    for row in eachrow(data)
        parts = String[]
        for cell in row
            (cell === missing || cell === nothing || cell == "") && continue
            push!(parts, gms_token(cell))
        end
        isempty(parts) && continue
        push!(lines, join(parts, " "))
    end
    return lines
end

function satellite_cache_path(path)
    return path * ".cache.jld2"
end

function satellite_signature(path)
    st = stat(path)
    return (
        path = abspath(path),
        size = st.size,
        mtime = Float64(mtime(path)),
    )
end

function satellite_cache_valid(meta, path, names)
    meta === nothing && return false
    meta_path = get(meta, :path, nothing)
    meta_size = get(meta, :size, nothing)
    meta_mtime = get(meta, :mtime, nothing)
    meta_names = get(meta, :names, nothing)
    sig = satellite_signature(path)
    want = collect(String.(names))
    return meta_path == sig.path &&
           meta_size == sig.size &&
           meta_mtime == sig.mtime &&
           meta_names == want
end

function satellite_cache_read(cache_path, path, names)
    isfile(cache_path) || return nothing
    data = try
        JLD2.load(cache_path)
    catch
        return nothing
    end
    meta = get(data, "meta", nothing)
    satellite_cache_valid(meta, path, names) || return nothing
    book = get(data, "book", nothing)
    book isa Dict || return nothing
    return Dict(String(k) => Vector{String}(v) for (k, v) in pairs(book))
end

function satellite_cache_write(cache_path, path, names, book)
    meta = Dict(
        :path => abspath(path),
        :size => stat(path).size,
        :mtime => Float64(mtime(path)),
        :names => collect(String.(names)),
    )
    try
        JLD2.save(cache_path, "meta", meta, "book", book)
    catch
    end
    return nothing
end
"""
    satellite_lines(path, names)

Text rows of the named sheets in `satellite.xlsx`. A cache is used when the
workbook path, size, modification time, and requested sheet names still match.
"""
function satellite_lines(path, names)
    cache_path = satellite_cache_path(path)
    cached = satellite_cache_read(cache_path, path, names)
    cached !== nothing && return cached
    xf = XLSX.readxlsx(path)
    book = Dict(String(name) => gms_lines(xf[String(name)]) for name in names)
    satellite_cache_write(cache_path, path, names, book)
    return book
end

function load_benchmark(dat_path, satellite)
    wanted = Set([
        "xp0", "es0", "xm0", "vst", "labd0", "kapd0", "ffactd0",
        "xdp0", "xmp0", "xdc0", "xmc0", "xdg0", "xmg0", "xdi0", "xmi0",
        "ti", "tf", "tp", "pg0", "ptxy0", "tx", "tm", "wtflow0", "vtwr",
        "savf0", "cons0", "kapdg0",
    ])
    p = load_gams_dat(dat_path, wanted)
    regions = sort!(unique(first.(keys(p["cons0"]))))
    sectors = sort!(unique(last.(keys(p["xp0"]))))
    book = satellite_lines(satellite, ("eppatrend_histrgdp", "eppatrend_argdpgrrate", "eppatrend_popa_eppa"))
    hist = load_t_table(book["eppatrend_histrgdp"])
    ann = load_t_table(book["eppatrend_argdpgrrate"])
    pop = load_t_table(book["eppatrend_popa_eppa"])
    return (; p, regions, sectors, hist, ann, pop)
end

"""
    growth_factor(data, r, year)

Exogenous GDP growth applied when leaving `year`.

The opening step uses the historical index over the actual gap. The second
period still uses that index. Later periods use the annual growth rate. Both
of the latter are compounded over a normal step.
"""
function growth_factor(data, r, year)
    i = findfirst(==(year), YEARS)
    i === nothing && error("year $year is not an EPPA period")
    if i == 1
        return data.hist[(tcode(year), r)]^step_years(1)
    elseif i == 2
        return data.hist[(tcode(year), r)]^regular_step()
    else
        return (1 + data.ann[(tcode(year), r)])^regular_step()
    end
end

function pop_ratio(data, r, year, next)
    a = data.pop[(tcode(year), r)]
    b = data.pop[(tcode(next), r)]
    return a == 0 ? 1.0 : b / a
end



function load_gms_table(lines)
    body = String[]
    inside = false
    for ln in lines
        s = strip(ln)
        if !inside
            startswith(lowercase(s), "table ") && (inside = true)
            continue
        end
        startswith(s, ";") && break
        (isempty(s) || startswith(s, "*")) && continue
        push!(body, s)
    end
    isempty(body) && return Dict{Tuple,Float64}()
    data = Dict{Tuple,Float64}()
    header = nothing
    for ln in body
        toks = split(ln)
        vals = Float64[]
        while !isempty(toks)
            v = tryparse(Float64, toks[end])
            v === nothing && break
            push!(vals, v)
            pop!(toks)
        end
        reverse!(vals)
        if isempty(vals)
            labs = Symbol.(lowercase.(toks))
            if header === nothing && length(labs) >= 1
                header = labs
            end
            continue
        end
        header === nothing && continue
        length(vals) == length(header) || continue
        labs = Symbol[]
        for t in toks
            t == "." && continue
            push!(labs, Symbol(lowercase(t)))
        end
        isempty(labs) && continue
        for (j, reg) in enumerate(header)
            data[(labs..., reg)] = vals[j]
        end
    end
    return data
end

function load_assigns(lines)
    data = Dict{Symbol,Float64}()
    rx = r"\(\s*\"([^\"]+)\"\s*\)\s*=\s*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)"
    for ln in lines
        m = match(rx, ln)
        m === nothing && continue
        data[Symbol(lowercase(m.captures[1]))] = parse(Float64, m.captures[2])
    end
    return data
end

function load_prepare_inputs(dat_path, elec_path, satellite; verbose = true)
    _pt(msg) = begin
        verbose || return nothing
        println("prepare: ", msg)
        flush(stdout)
        return nothing
    end
    wanted = Set([
        "xp0", "es0", "xm0", "vst", "labd0", "kapd0", "ffactd0",
        "xdp0", "xmp0", "xdc0", "xmc0", "xdg0", "xmg0", "xdi0", "xmi0",
        "ti", "tf", "tp", "tg", "pg0", "pc0", "pf0", "ptxy0",
        "tx", "tm", "wtflow0", "vtwr", "savf0", "cons0", "kapdg0", "labdg0", "trg0",
        "efd", "savh0", "eind",
    ])
    _pt("start reading main GAMS data")
    t_main = @elapsed p = load_gams_dat(dat_path, wanted)
    _pt("finished main GAMS data in $(round(t_main; digits = 2)) s")

    xa0 = Dict{Tuple,Float64}()
    for (key, v) in p["xdp0"]
        xa0[key] = v
    end
    for (key, v) in p["xmp0"]
        xa0[key] = get(xa0, key, 0.0) + v
    end
    p["xa0"] = xa0

    _pt("start reading electricity GAMS data")
    t_elec = @elapsed e = load_gams_dat(elec_path, Set(["elecin", "elecint", "xp0_", "td_"]))
    _pt("finished electricity GAMS data in $(round(t_elec; digits = 2)) s")

    _pt("start reading satellite workbook")
    t_xlsx = @elapsed book = satellite_lines(satellite, (
        "eppaelas_selas", "eppaelas_esup", "eppaelas_esube", "eppaelas_sigu", "eppaelas_d_elas",
        "eppacalib_crtable", "readgtap_bio", "elecpower_nhreta", "elecpower_wstsigma",
        "eppa_htrn_os", "eppa_htrn_es", "eppa_htrn_mvh",
        "readgtap_ej_use_iea", "readgtap_eprod_iea",
        "eppatrend_histrgdp", "eppatrend_argdpgrrate", "eppatrend_popa_eppa", "eppatrend_aeeigr",
    ))
    _pt("finished satellite workbook in $(round(t_xlsx; digits = 2)) s")

    _pt("start parsing satellite tables")
    t_tables = @elapsed begin
        selas = load_gms_table(book["eppaelas_selas"])
        for (k, v) in selas
            if length(k) == 3 && k[2] == :noe_el
                selas[k] = 3v
            end
        end
        esup = load_gms_table(book["eppaelas_esup"])
        esube = load_gms_table(book["eppaelas_esube"])
        sigu = load_gms_table(book["eppaelas_sigu"])
        delas_raw = Dict{Tuple,Float64}()
        for ln in book["eppaelas_d_elas"]
            s = strip(ln)
            (isempty(s) || startswith(s, "*") || startswith(s, "/") || startswith(lowercase(s), "parameter")) && continue
            parts = split(s)
            length(parts) < 2 && continue
            v = tryparse(Float64, parts[end])
            v === nothing && continue
            delas_raw[(Symbol(lowercase(parts[1])),)] = v
        end
        delas = delas_raw
        crtable = load_gms_table(book["eppacalib_crtable"])
        bio = load_gms_table(book["readgtap_bio"])
        nhreta = load_gms_table(book["elecpower_nhreta"])
        wst = load_gms_table(book["elecpower_wstsigma"])
        os = load_assigns(book["eppa_htrn_os"])
        esh = load_assigns(book["eppa_htrn_es"])
        mvh = load_assigns(book["eppa_htrn_mvh"])
        ej_use_iea = load_gms_table(book["readgtap_ej_use_iea"])
        eprod_iea = load_gms_table(book["readgtap_eprod_iea"])
        hist = load_t_table(book["eppatrend_histrgdp"])
        ann = load_t_table(book["eppatrend_argdpgrrate"])
        pop = load_t_table(book["eppatrend_popa_eppa"])
        aeeigr_raw = load_gms_table(book["eppatrend_aeeigr"])
    end
    _pt("finished parsing satellite tables in $(round(t_tables; digits = 2)) s")

    g(name, key) = get(p[name], key, 0.0)
    ge(name, key) = get(e[name], key, 0.0)
    return (; p, e, g, ge, selas, esup, esube, sigu, delas, crtable, bio, nhreta, wst, os, esh, mvh, ej_use_iea, eprod_iea, hist, ann, pop, aeeigr_raw)
end
