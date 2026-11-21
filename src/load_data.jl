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

"""
    load_period_set(lines)

Read the solve periods from a GAMS set, such as the `other_period` sheet.
"""
function load_period_set(lines)
    years = Int[]
    inside = false
    for ln in lines
        s = strip(ln)
        (isempty(s) || startswith(s, "*") || startswith(s, "#")) && continue
        if !inside
            s == "/" && (inside = true)
            continue
        end
        startswith(s, "/") && break
        token = replace(split(s)[1], "," => "")
        y = tryparse(Int, token)
        y === nothing && error("period set entry is not a year: $s")
        push!(years, y)
    end
    isempty(years) && error("no years in the other_period set")
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

function load_gams_dat(path)
    out = Dict{String,Dict{Tuple,Float64}}()
    name = ""
    open(path) do io
        for line in eachline(io)
            if startswith(line, "parameter ")
                name = split(strip(line), r"\s+|/")[2]
                get!(out, name, Dict{Tuple,Float64}())
                continue
            end
            isempty(name) && continue
            if startswith(line, "/;")
                name = ""
                continue
            end
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

Parse an xls2gms `table` whose rows are calendar years and whose header is region names.
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
    data = Dict{Tuple{Int,Symbol},Float64}()
    for ln in body[2:end]
        parts = split(strip(ln))
        length(parts) < 2 && continue
        year = tryparse(Int, parts[1])
        year === nothing && error("table row is not a year: $(parts[1])")
        vals = tryparse.(Float64, parts[2:end])
        n = min(length(vals), length(regions))
        for j in 1:n
            vals[j] === nothing && continue
            data[(year, regions[j])] = vals[j]
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

const SATELLITE_CACHE_VERSION = 4

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
            if cell === missing || cell === nothing || cell == ""
                push!(parts, "")
            else
                push!(parts, gms_token(cell))
            end
        end
        while !isempty(parts) && isempty(parts[end])
            pop!(parts)
        end
        if all(isempty, parts)
            push!(lines, "")
            continue
        end
        push!(lines, join(parts, '\t'))
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
    meta_version = get(meta, :version, nothing)
    meta_path = get(meta, :path, nothing)
    meta_size = get(meta, :size, nothing)
    meta_mtime = get(meta, :mtime, nothing)
    meta_names = get(meta, :names, nothing)
    sig = satellite_signature(path)
    want = collect(String.(names))
    return meta_version == SATELLITE_CACHE_VERSION &&
           meta_path == sig.path &&
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
        :version => SATELLITE_CACHE_VERSION,
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
function _xmltext(s)
    lt = "&" * "lt;"
    gt = "&" * "gt;"
    quot = "&" * "quot;"
    apos = "&" * "apos;"
    amp = "&" * "amp;"
    s = replace(s, lt => "<", gt => ">", quot => "\"", apos => "'")
    return replace(s, amp => "&")
end

function _colnum(letters)
    n = 0
    for c in letters
        n = 26n + (Int(c) - Int('A') + 1)
    end
    return n
end

function _shared_strings(xml)
    sst = String[]
    for m in eachmatch(r"<si\b[^>]*>(.*?)</si>"s, xml)
        parts = String[]
        for t in eachmatch(r"<t\b[^>]*>(.*?)</t>"s, m.captures[1])
            push!(parts, _xmltext(t.captures[1]))
        end
        push!(sst, join(parts))
    end
    return sst
end

function _sheet_lines(xml, sst)
    lines = String[]
    lastrow = 0
    for m in eachmatch(Regex("<row\\b[^>]*\\br=\"(\\d+)\"[^>]*>(.*?)</row>", "s"), xml)
        row = parse(Int, m.captures[1])
        cells = Dict{Int,String}()
        width = 0
        for c in eachmatch(Regex("<c\\b([^>/]*)(?:/>|>(.*?)</c>)", "s"), m.captures[2])
            attrs = c.captures[1]
            body = c.captures[2] === nothing ? "" : c.captures[2]
            ref = match(Regex("\\br=\"([A-Z]+)"), attrs)
            ref === nothing && continue
            col = _colnum(ref.captures[1])
            kind = match(Regex("\\bt=\"([A-Za-z]+)\""), attrs)
            t = kind === nothing ? "" : kind.captures[1]
            vm = match(r"<v[^>]*>(.*?)</v>"s, body)
            val = if t == "s" && vm !== nothing
                sst[parse(Int, vm.captures[1]) + 1]
            elseif t == "inlineStr" || t == "str"
                tm = match(r"<t\b[^>]*>(.*?)</t>"s, body)
                if tm !== nothing
                    _xmltext(tm.captures[1])
                elseif vm !== nothing
                    _xmltext(vm.captures[1])
                else
                    ""
                end
            elseif vm !== nothing
                vm.captures[1]
            else
                ""
            end
            cells[col] = strip(val)
            width = max(width, col)
        end
        for _ in (lastrow + 1):(row - 1)
            push!(lines, "")
        end
        lastrow = row
        if width == 0
            push!(lines, "")
            continue
        end
        parts = String[get(cells, j, "") for j in 1:width]
        while !isempty(parts) && isempty(parts[end])
            pop!(parts)
        end
        push!(lines, isempty(parts) ? "" : join(parts, '\t'))
    end
    return lines
end

function _sheet_targets(reader)
    wb = XLSX.ZipArchives.zip_readentry(reader, "xl/workbook.xml", String)
    rels = XLSX.ZipArchives.zip_readentry(reader, "xl/_rels/workbook.xml.rels", String)
    target = Dict{String,String}()
    for m in eachmatch(Regex("Id=\"([^\"]+)\"[^>]*Target=\"([^\"]+)\""), rels)
        path = m.captures[2]
        target[m.captures[1]] = startswith(path, "xl/") ? path : "xl/" * lstrip(path, '/')
    end
    names = Dict{String,String}()
    for m in eachmatch(Regex("<sheet\\b[^>]*name=\"([^\"]+)\"[^>]*r:id=\"([^\"]+)\""), wb)
        haskey(target, m.captures[2]) || continue
        names[m.captures[1]] = target[m.captures[2]]
    end
    return names
end

"""
    satellite_lines(path, names)

Text rows of the named sheets in `satellite.xlsx`. Only those sheets are
unzipped. A cache is used when the workbook path, size, modification time,
and requested sheet names still match.
"""
function satellite_lines(path, names)
    cache_path = satellite_cache_path(path)
    cached = satellite_cache_read(cache_path, path, names)
    cached !== nothing && return cached
    reader = XLSX.ZipArchives.ZipReader(read(path))
    targets = _sheet_targets(reader)
    sst = String[]
    if XLSX.ZipArchives.zip_findlast_entry(reader, "xl/sharedStrings.xml") !== nothing
        sst = _shared_strings(XLSX.ZipArchives.zip_readentry(reader, "xl/sharedStrings.xml", String))
    end
    book = Dict{String,Vector{String}}()
    for name in names
        key = String(name)
        haskey(targets, key) || error("satellite workbook has no sheet $key")
        xml = XLSX.ZipArchives.zip_readentry(reader, targets[key], String)
        book[key] = _sheet_lines(xml, sst)
    end
    satellite_cache_write(cache_path, path, names, book)
    return book
end

function load_benchmark(source)
    p = source.dat
    regions = sort!(unique(first.(keys(p["cons0"]))))
    sectors = sort!(unique(last.(keys(p["xp0"]))))
    ann = load_t_table(source.satellite["eppatrend_argdpgrrate"])
    pop = load_t_table(source.satellite["eppatrend_popa_eppa"])
    return (; p, regions, sectors, ann, pop)
end

"""
    growth_factor(data, r, year)

Exogenous GDP growth applied when leaving `year`.

Every step uses the annual rate in `eppatrend_argdpgrrate`. The rate is
compounded over the length of that step, including the shorter opening step.
"""
function growth_factor(data, r, year)
    i = findfirst(==(year), YEARS)
    i === nothing && error("year $year is not an EPPA period")
    n = i < length(YEARS) ? step_years(i) : regular_step()
    return (1 + data.ann[(year, r)])^n
end

function pop_ratio(data, r, year, next)
    a = data.pop[(year, r)]
    b = data.pop[(next, r)]
    return a == 0 ? 1.0 : b / a
end



function load_gms_table(lines; duplicate = :last)
    body = String[]
    inside = false
    for ln in lines
        s = strip(ln)
        if !inside
            startswith(lowercase(s), "table ") && (inside = true)
            continue
        end
        startswith(s, ";") && break
        if isempty(s)
            !isempty(body) && break
            continue
        end
        startswith(s, "*") && continue
        push!(body, s)
    end
    isempty(body) && return Dict{Tuple,Float64}()
    data = Dict{Tuple,Float64}()
    header = nothing
    for ln in body
        toks = occursin('\t', ln) ? split(ln, '\t'; keepempty = true) : split(strip(ln))
        if header === nothing
            labs = Symbol[]
            for t in toks
                s = strip(t)
                isempty(s) && continue
                push!(labs, Symbol(lowercase(s)))
            end
            if header === nothing && length(labs) >= 1
                header = labs
            end
            continue
        end
        length(toks) >= length(header) || continue
        val_toks = toks[(end - length(header) + 1):end]
        vals = Vector{Union{Nothing,Float64}}(undef, length(header))
        for j in eachindex(val_toks)
            s = strip(val_toks[j])
            vals[j] = isempty(s) || s == "." ? nothing : tryparse(Float64, s)
        end
        all(v -> v === nothing, vals) && continue
        labs = Symbol[]
        for t in toks[1:(end - length(header))]
            s = strip(t)
            (isempty(s) || s == ".") && continue
            push!(labs, Symbol(lowercase(s)))
        end
        isempty(labs) && continue
        for (j, reg) in enumerate(header)
            vals[j] === nothing && continue
            key = (labs..., reg)
            if duplicate == :first && haskey(data, key)
                continue
            end
            data[key] = vals[j]
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

function load_prepare_inputs(source)
    p = source.dat
    xa0 = Dict{Tuple,Float64}()
    for (key, v) in p["xdp0"]
        xa0[key] = v
    end
    for (key, v) in p["xmp0"]
        xa0[key] = get(xa0, key, 0.0) + v
    end
    p["xa0"] = xa0
    e = source.elec
    book = source.satellite

    selas = load_gms_table(book["eppaelas_selas"])
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
    crtable = load_gms_table(book["eppacalib_crtable"]; duplicate = :first)
    bio = load_gms_table(book["readgtap_bio"])
    nhreta = load_gms_table(book["elecpower_nhreta"])
    wst = load_gms_table(book["elecpower_wstsigma"])
    os = load_assigns(book["eppa_htrn_os"])
    esh = load_assigns(book["eppa_htrn_es"])
    mvh = load_assigns(book["eppa_htrn_mvh"])
    ej_use_iea = load_gms_table(book["readgtap_ej_use_iea"])
    epslon_raw = load_gms_table(book["other_epslon"])
    ann = load_t_table(book["eppatrend_argdpgrrate"])
    pop = load_t_table(book["eppatrend_popa_eppa"])
    aeeigr_raw = load_gms_table(book["eppatrend_aeeigr"])
    years = load_period_set(book["other_period"])

    return (; p, e, satellite = book, selas, esup, esube, sigu, delas, crtable, bio, nhreta, wst, os, esh, mvh, ej_use_iea, epslon_raw, ann, pop, aeeigr_raw, years)
end

"""
    load_satellite(path)

Every worksheet of `satellite.xlsx`, as the text rows used by the GAMS table parsers.
"""
function load_satellite(path)
    reader = XLSX.ZipArchives.ZipReader(read(path))
    names = sort!(collect(keys(_sheet_targets(reader))))
    return satellite_lines(path, names)
end

"""
    load_data(dat_path, elec_path, satellite_path)

Read the benchmark GAMS dumps and every satellite sheet into one object.

`dat` and `elec` hold every parameter in the two `.dat` files.
`satellite` holds every worksheet.
"""
function load_data(dat_path, elec_path, satellite_path)
    return (
        dat = load_gams_dat(dat_path),
        elec = load_gams_dat(elec_path),
        satellite = load_satellite(satellite_path),
    )
end

"""
    gams_table(text) -> Dict{Tuple{Symbol,Int},Float64}

Read a GAMS-style table. The first line is the column headers (years). Each
later line is a row label and one number per column.
"""
function gams_table(text::AbstractString)
    lines = [strip(line) for line in split(text, '\n') if !isempty(strip(line)) && !startswith(lstrip(line), '*')]
    isempty(lines) && error("gams table is empty")
    years = [parse(Int, h) for h in split(lines[1])]
    out = Dict{Tuple{Symbol,Int},Float64}()
    for line in lines[2:end]
        parts = split(line)
        length(parts) == length(years) + 1 || error("row $(parts[1]) has $(length(parts) - 1) values, expected $(length(years))")
        r = Symbol(parts[1])
        for (t, v) in zip(years, parts[2:end])
            out[(r, t)] = parse(Float64, v)
        end
    end
    return out
end

