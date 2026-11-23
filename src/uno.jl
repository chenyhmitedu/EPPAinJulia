# Similar to set declarations in GAMS. Keep the scope global.

const REGIONS   = [:USA, :CAN, :MEX, :JPN, :ANZ, :EUR, :ROE, :RUS, :ASI, :CHN, :IND, :BRA, :AFR, :MES, :LAM, :REA, :KOR, :IDZ]
const SECTORS   = [:crop, :live, :fors, :food, :coal, :oil, :roil, :gas, :elec, :eint, :othr, :serv, :tran, :dwe]
const NE        = [:crop, :live, :fors, :food, :eint, :othr, :serv, :tran, :dwe]
const NENDT     = [:crop, :live, :fors, :food, :eint, :othr, :serv]
const AENOE     = [:coal, :oil, :gas, :roil, :crop, :live, :fors, :elec, :eint]
const AGRI      = [:crop, :live, :fors]
const ENOE      = [:coal, :oil, :gas, :roil]
const ENRE      = [:coal, :oil, :gas]
const ENERGY    = [:coal, :oil, :gas, :roil, :elec]
const FF        = [:oil, :gas, :coal]
const TECH      = [:cele, :gele, :oele, :hele, :nele, :rele, :sele, :wele, :tele]
const TECH_F    = [:cele, :gele, :oele]
const TECH_NHR  = [:nele, :hele, :rele]
const TECH_N    = [:sele, :wele]
const TECH_D    = [:cele, :gele, :oele, :hele, :nele, :rele]
const EJUSE_SECTORS = [filter(!=(:elec), SECTORS)..., TECH..., :households, :htrn]
const SCO2_ENERGY   = [:coal, :gas, :roil]
const FB        = SCO2_ENERGY ∪ [:bio]
const SCO2_SECTORS  = [filter(!=(:elec), SECTORS)..., TECH..., :households, :htrn]
const PDE_DIM   = [:dispgen, TECH_F..., TECH_N..., :tnd]
const NOT_AENOE = [:food, :othr, :serv, :tran, :dwe]
const LKR       = [:lab, :cap, :res]
const LK        = [:lab, :cap]
const PRIMARY   = [:lab, :cap, :lnd, :res]

const HTRNS     = 0.3753
const PROPFRAC  = 0.2
const DPE       = 0.05
const ROR       = 0.1

# Based on 1) parameters declared in eppacore.jl; 2) elecpower.gms


function Uno_data(data::Dict)
    # Preserve raw inputs and isolate returned dictionaries from the caller.
    datac = deepcopy(data)

    labor   = Dict(r => sum(get(data["labd0"], (r, i), 0.0) for i in SECTORS) + get(data["labdg0"], r, 0.0) for r in REGIONS)
    kapital = Dict(r => sum(get(data["kapd0"], (r, i), 0.0) for i in SECTORS) for r in REGIONS)
    ffact   = Dict((i, r) => get(data["ffactd0"], (r, i), 0.0) * (1 + get(data["tf"], (:lnd, i, r), 0.0)) for r in REGIONS, i in SECTORS)
    rshr    = Dict((i, r) => get(data["rshr"], (i, r), 0.0) for i in TECH, r in REGIONS)
    xp_     = Dict((i, r) => get(data["xp0_"], (i, r), 0.0) for i in TECH, r in REGIONS)
    td_     = Dict((i, r) => get(data["td_"], (r, i), 0.0) for r in REGIONS, i in TECH)
    elecint = Dict((i, x, r) => get(data["elecint"], (i, x, r), 0.0) for i in TECH, x in LKR ∪ SECTORS, r in REGIONS)
    r0      = Dict((i, r) => rshr[i, r] * xp_[i, r] * (1-td_[i, r]) / (1+elecint[i, :cap, r]) for i in TECH_NHR, r in REGIONS)
    elecin  = Dict((i, j, r) => get(data["elecin"], (i, j, r), 0.0) for i in TECH, j in LKR ∪ SECTORS, r in REGIONS)
    elecinmr0 = Dict((i, r) => elecin[i, :cap, r] - r0[i, r] for i in TECH_NHR, r in REGIONS)
    opelecint = Dict(
            (i, r) => (denom = sum(elecin[i, f, r] for f in LK);
                       denom == 0.0 ? 0.0 :
                       sum((1 + elecint[i, f, r]) * elecin[i, f, r] for f in LK) / denom)
            for i in TECH_NHR, r in REGIONS
    )

    zshr = Dict(
        (i, r) => begin
            val = if elecinmr0[i, r] <= 0
                denom = sum(elecin[i, f, r] for f in LK)
                denom == 0.0 ? 0.0 :
                (1 / denom) * xp_[i, r] * (1 - td_[i, r]) / opelecint[i, r] * rshr[i, r]
            else
                0.0
            end
            min(val, 0.9)          # cap at 0.9
        end
        for i in TECH_NHR, r in REGIONS
    )

    elecin0 = Dict(
        (i, f, r) => elecin[i, f, r] for i in TECH_NHR, f in LK, r in REGIONS
    )

    elecint0 = Dict(
        (i, f, r) => elecint[i, f, r] for i in TECH_NHR, f in LK, r in REGIONS
    )

    for i in TECH_NHR, r in REGIONS
        if elecinmr0[i, r] > 0
            elecin[i, :cap, r]  = elecin0[i, :cap, r] - r0[i, r]
            elecin[i, :res, r]  = r0[i, r]
            elecint[i, :res, r] = elecint0[i, :cap, r]
            ffact[i, r]         = r0[i, r]
        end
    end

    for r in REGIONS
        kapital[r] = kapital[r] - sum(get(ffact, (i, r), 0) for i in TECH_NHR)
    end

    for i in TECH_NHR, r in REGIONS
        if elecinmr0[i, r] <= 0
            for f in LK
                elecin[i, f, r]  = elecin0[i, f, r] * (1-zshr[i, r])
            end
            elecin[i, :res, r]  = zshr[i, r] * sum(elecin0[i, f, r] for f in LK)
            elecint[i, :res, r] = opelecint[i, r]-1
            ffact[i, r]         = zshr[i, r] * sum(elecin0[i, f, r] for f in LK)
        end
    end

    for r in REGIONS
        kapital[r]  = kapital[r] - sum(zshr[i, r] * elecin0[i, :cap, r] for i in TECH_NHR)
        labor[r]    = labor[r] - sum(zshr[i, r] * elecin0[i, :lab, r] for i in TECH_NHR)
    end

#    ffact0 = Dict((i, r) => ffact[i, r] for i in TECH_NHR, r in REGIONS)

    nhrshare = Dict(
        (i, r) => begin
            val = if xp_[i, r] != 0
                denom = (1-td_[i, r]) * xp_[i, r]
                denom == 0.0 ? 0.0 :
                elecin[i, :res, r] / denom
            else
                0.0
            end
        end
        for i in TECH_NHR, r in REGIONS
    )    

    nhrsigma = Dict(
        (i, r) => begin
            val = if (1-nhrshare[i, r]) != 0
                denom = 1-nhrshare[i, r]
                denom == 0.0 ? 0.0 :
                get(data["nhreta"], (i, r), 0) * nhrshare[i, r] / denom
            else
                0.0
            end
        end
        for i in TECH_NHR, r in REGIONS
    )    
    
    g0 = Dict(
        r => get(data["kapdg0"], r, 0.0) + get(data["labdg0"], r, 0.0) + get(data["trg0"], r, 0.0) 
         + sum(get(data["xdg0"], (r, i), 0.0)+ get(data["xmg0"], (r, i), 0.0) for i in SECTORS) 
         for r in REGIONS
    )
    cons0   = Dict(r => get(data["cons0"], r, 0.0) for r in REGIONS)
    inv0    = Dict(r => sum(get(data["xdi0"], (r, i), 0.0) + get(data["xmi0"], (r, i), 0.0) for i in SECTORS) for r in REGIONS)

    homm0 = Dict{Symbol,Float64}()
    homx0 = Dict{Symbol,Float64}()
    for r in REGIONS
        imp = sum(get(data["wtflow0"], (r, rr, :oil), 0.0) * (1 + get(data["tx"], (:oil, rr, r), 0.0)) for rr in REGIONS) 
        exp = sum(get(data["wtflow0"], (rr, r, :oil), 0.0) * (1 + get(data["tx"], (:oil, r, rr), 0.0)) for rr in REGIONS)
        homm0[r] = max(0.0, imp - exp)
        homx0[r] = max(0.0, -imp + exp)
    end

    rgdp0 = Dict{Symbol,Float64}()
    for r in REGIONS
        exports = 0.0
        imports = 0.0
        for rr in REGIONS, i in SECTORS
            i == :oil && continue
            exports += (1 + get(data["tx"], (i, r, rr), 0.0)) * get(data["wtflow0"], (rr, r, i), 0.0)
            imports += (1 + get(data["tx"], (i, rr, r), 0.0)) * get(data["wtflow0"], (r, rr, i), 0.0)
        end
        rgdp0[r] = cons0[r] + inv0[r] + g0[r] + exports - imports + homx0[r] - homm0[r]
    end

    aeei    = Dict((i, r) => 1 for i in SECTORS, r in REGIONS)
    sco2coef = Dict(
        e => 100 * (44 / 12) * data["epslon"][e] for e in FB
        )

    cr = Dict(
        (i, g, r) => begin
            val = if (i == :roil)
                data["crtable"][g, r]
            else
                1.0
            end
        end
        for i in SCO2_ENERGY, g in SECTORS ∪ [:final], r in REGIONS
    )        

    xa0 = Dict(
        (r, i, j) => get(data["xdp0"], (r, i, j), 0.0) + get(data["xmp0"], (r, i, j), 0.0)
        for r in REGIONS, i in SECTORS, j in SECTORS
    )

    purtrn = Dict{Symbol,Float64}()
    xdc = Dict(k => v for (k, v) in data["xdc0"])
    xmc = Dict(k => v for (k, v) in data["xmc0"])
    tbo = Dict{Symbol,Float64}()
    tfo = Dict{Symbol,Float64}()
    toi = Dict{Symbol,Float64}()
    tse = Dict{Symbol,Float64}()
    own = Dict{Symbol,Float64}()
    tottrn = Dict{Symbol,Float64}()
    hhwedge = Dict{Symbol,Float64}()
    xh = Dict{Tuple{Symbol,Symbol},Float64}()
    ence = Dict{Tuple{Symbol,Symbol},Float64}()
    ence1 = Dict{Tuple{Symbol,Symbol},Float64}()

    for r in REGIONS
        purtrn[r] = get(data["xdc0"], (r, :tran), 0.0) + get(data["xmc0"], (r, :tran), 0.0)
        xdc[(r, :tran)] = 0.0
        xmc[(r, :tran)] = 0.0
        ence0 = get(data["xdc0"], (r, :roil), 0.0) + get(data["xmc0"], (r, :roil), 0.0)
        efd = get(data["efd"], (:roil, r), 0.0)
        pbio = efd == 0 ? 0.0 : ence0 / efd
        ebio = pbio * get(data["bio"], r, 0.0)
        pcR = get(data["pc0"], (:roil, r), 0.0)
        tbo[r] = pcR == 0 ? 0.0 : ebio / pcR
        tfo[r] = data["os"][r] * ence0
        toi[r] = data["mvh"][r]
        owntrn = data["es"][r] * get(data["cons0"], r, 0.0)
        foodp = r == :BRA ? :eint : :food
        tottrn[r] = purtrn[r] * get(data["pc0"], (:tran, r), 0.0) + owntrn + (pcR - get(data["pc0"], (foodp, r), 0.0)) * tbo[r]
        tse[r] = (owntrn - tfo[r] * pcR - toi[r] * get(data["pc0"], (:othr, r), 0.0) - tbo[r] * get(data["pc0"], (foodp, r), 0.0)) / get(data["pc0"], (:serv, r), 0.0)
        own[r] = pcR * (tfo[r] + tbo[r]) + get(data["pc0"], (:othr, r), 0.0) * toi[r] + get(data["pc0"], (:serv, r), 0.0) * tse[r]
        hhwedge[r] = (pcR - get(data["pc0"], (foodp, r), 0.0)) * tbo[r]
        xdc[r, :roil] = get(data["xdc0"], (r, :roil), 0.0) - tfo[r]
        xdc[r, foodp] = get(data["xdc0"], (r, foodp), 0.0) - tbo[r]
        xdc[r, :othr] = get(data["xdc0"], (r, :othr), 0.0) - toi[r]
        xdc[r, :serv] = get(data["xdc0"], (r, :serv), 0.0) - tse[r]
        
        for i in NENDT ∪ [:dwe]
            xh[i, r] = max(get(xdc, (r, i), 0.0) + get(xmc, (r, i), 0.0), 0.0)
        end

        for i in ENERGY
            ence[(i, r)] = get(data["xdc0"], (r, i), 0.0) + get(data["xmc0"], (r, i), 0.0)
        end
        
        ence[(:roil, r)] -= tfo[r]
        for i in ENERGY
            ence1[(i, r)] = max(ence[(i, r)], 0.0)
        end

    end

    euse0 = Dict(
        (e, g, r) => begin
            val = if (g in SECTORS)
                xa0[r, e, g]
            elseif ( g in TECH)
                val = if (e == :roil)
                    get(data["elecin"], (g, e, r), 0) * cr[e, :elec, r]
                else
                    get(data["elecin"], (g, e, r), 0)
                end
            elseif (g == :households)
                    ence1[e, r]
            else
                    e == :roil ? tfo[r] : 0.0
            end
        end                
        for r in REGIONS, e in ENERGY, g in EJUSE_SECTORS
    )

    elec_use = Dict(
        (e, r) => begin
            val = if (e == :roil)
                get(data["eind"], (e, :elec, r), 0.0) * cr[e, :elec, r]
            else
                get(data["eind"], (e, :elec, r), 0.0)
            end
        end
        for e in ENERGY, r in REGIONS
    )

    elec_use_all = Dict(
        (e, r) => begin
            get(data["eind"], (e, :elec, r), 0.0)
        end
        for e in ENERGY, r in REGIONS
    )

    fuel_in = Dict(
        (e, r) => sum(elecin[(i_, e, r)] for i_ in TECH)
        for e in ENERGY, r in REGIONS
    )

    ejod = Dict(
        (e, r) => begin
            val = if (fuel_in[e, r] == 0)
                0.0
            else
                elec_use[e, r]/fuel_in[e, r]
            end
        end
        for e in ENERGY, r in REGIONS
    )

    ejod_all = Dict(
        (e, r) => begin
            val = if (fuel_in[e, r] == 0)
                0.0
            else
                elec_use_all[e, r]/fuel_in[e, r]
            end
        end
        for e in ENERGY, r in REGIONS
    )

    ejuse0 = Dict(
        (e, g, r) => begin
            val = if (g in SECTORS)
                get(data["eind"], (e, g, r), 0.0) * (e == :roil ? cr[:roil, g, r] : 1.0)
            elseif ( g in TECH)
                ejod[e, r] * elecin[g, e, r]
            elseif (g == :households)
                e == :roil ? (1 - data["os"][r]) * get(data["efd"], (:roil, r), 0.0) * cr[:roil, :final, r] : get(data["efd"], (e, r), 0.0)
            else
                e == :roil ? data["os"][r] * get(data["efd"], (:roil, r), 0.0) * cr[:roil, :final, r] : 0.0
            end
        end                
        for r in REGIONS, e in ENERGY, g in EJUSE_SECTORS
    )

    ejuse_all0 = Dict(
        (e, g, r) => begin
            val = if (g in SECTORS)
                get(data["eind"], (e, g, r), 0.0)
            elseif ( g in TECH)
                ejod_all[e, r] * elecin[g, e, r]
            elseif (g == :households)
                e == :roil ? (1 - data["os"][r]) * get(data["efd"], (:roil, r), 0.0) : get(data["efd"], (e, r), 0.0)
            else
                e == :roil ? data["os"][r] * get(data["efd"], (:roil, r), 0.0) : 0.0
            end
        end                
        for r in REGIONS, e in ENERGY, g in EJUSE_SECTORS
    )

    ejadj = Dict(
        (e, r) => begin
            val = if (e ==:roil)
                sum(ejuse_all0[:oil, g, r] for g in EJUSE_SECTORS) == 0 ? 
                0.0 : data["ejuse_iea"][:oil, r] / sum(ejuse_all0[:oil, g, r] for g in EJUSE_SECTORS)
            elseif (e == :elec)
                1.0
            else
                sum(ejuse_all0[e, g, r] for g in EJUSE_SECTORS) == 0 ? 
                0.0 : data["ejuse_iea"][e, r] / sum(ejuse_all0[e, g, r] for g in EJUSE_SECTORS)
            end
        end
        for r in REGIONS, e in ENERGY
    )

    ejuse = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    for (key, value) in ejuse0
        e, _, r = key
        ejuse[key] = value * ejadj[e, r]
    end

    ejuse_over_euse = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    for (key, value) in euse0
        ejuse_over_euse[key] = value == 0 ? 0.0 : ejuse[key] / value
    end

    a0 = Dict{Tuple{Symbol,Symbol},Float64}()
    for i in SECTORS, r in REGIONS
        a0[r, i] = get(data["xp0"], (r, i), 0.0) - get(data["es0"], (r, i), 0.0) + get(data["xm0"], (r, i), 0.0) - get(data["vst"], (i, r), 0.0)
    end

    dispgen0 = Dict(
        r => sum(get(data["xp0_"], (i_, r), 0.0) for i_ in TECH_D)
        for r in REGIONS
    )

    efout0 = Dict(
        r => sum(get(data["xp0_"], (i_, r), 0.0) for i_ in TECH_F)
        for r in REGIONS
    )

    td_ = Dict(
        (r, i) => get(data["td_"], (r, i), 0)
        for r in REGIONS, i in TECH
    )

    ffend0 = Dict(
        (r, i) => begin
            val = if (i in FF)
                ffact[i, r]
            else
                0.0
            end
        end
        for r in REGIONS, i in SECTORS
    )

    ffgprod0 = Dict(
        (r, i) => begin
            val = if (i in FF)
                0.0 
            else
                ffact[i, r]
            end
        end
        for r in REGIONS, i in SECTORS
    )

    govdem0 = Dict(
        (r, i) => begin
            val = if (i == :oil)
                0.0 
            else
                get(data["xdg0"], (r, i), 0.0) + get(data["xmg0"], (r, i), 0.0)
            end
        end
        for r in REGIONS, i in SECTORS
    )

    govoil0 = Dict(
        r => get(data["xdg0"], (r, :oil), 0.0) + get(data["xmg0"], (r, :oil), 0.0)
        for r in REGIONS
    )

    homm0 = Dict{Symbol,Float64}()
    homx0 = Dict{Symbol,Float64}()
    homt0 = Dict{Symbol,Float64}()
    vhomm0 = Dict{Symbol,Float64}()
    vhomx0 = Dict{Symbol,Float64}()
    txhom = Dict{Symbol,Float64}()
    tmhom = Dict{Symbol,Float64}()
    homadj = Dict{Symbol,Float64}()
    trnadj = Dict{Symbol,Float64}()

    for r in REGIONS
        imp = sum(get(data["wtflow0"], (r, rr, :oil), 0.0) * (1 + get(data["tx"], (:oil, rr, r), 0.0)) for rr in REGIONS)
        exp = sum(get(data["wtflow0"], (rr, r, :oil), 0.0) * (1 + get(data["tx"], (:oil, r, rr), 0.0)) for rr in REGIONS)
        homm0[r] = max(0.0, imp - exp)
        homx0[r] = max(0.0, -imp + exp)
        denx = sum(get(data["wtflow0"], (rr, r, :oil), 0.0) for rr in REGIONS)
        txhom[r] = denx == 0 ? 0.0 : sum(get(data["wtflow0"], (rr, r, :oil), 0.0) * get(data["tx"], (:oil, r, rr), 0.0) for rr in REGIONS) / denx
        vhomx0[r] = homx0[r] == 0 ? 0.0 : homx0[r] / (1 + txhom[r])
        denm = sum(get(data["wtflow0"], (r, rr, :oil), 0.0) * (1 + get(data["tx"], (:oil, rr, r), 0.0)) for rr in REGIONS)
        marg = sum(get(data["vtwr"], (:tran, :oil, rr, r), 0.0) for rr in REGIONS)
        tmargin = denm == 0 ? 0.0 : marg / denm
        homt0[r] = tmargin * homm0[r]
        den_tm = sum(get(data["wtflow0"], (r, rr, :oil), 0.0) * (1 + get(data["tx"], (:oil, rr, r), 0.0)) + get(data["vtwr"], (:tran, :oil, rr, r), 0.0) for rr in REGIONS)
        tmhom[r] = den_tm == 0 ? 0.0 : sum((get(data["wtflow0"], (r, rr, :oil), 0.0) * (1 + get(data["tx"], (:oil, rr, r), 0.0)) + get(data["vtwr"], (:tran, :oil, rr, r), 0.0)) * get(data["tm"], (:oil, rr, r), 0.0) for rr in REGIONS) / den_tm
        vhomm0[r] = (homm0[r] + homt0[r]) * (1 + tmhom[r])
        homadj[r] = a0[(r, :oil)] - (get(data["xp0"], (r, :oil), 0.0) + vhomm0[r] - vhomx0[r])
        trnadj[r] = homt0[r] - marg
    end

    pwdem0 = Dict(
        r => cons0[r] + inv0[r] for r in REGIONS
    )

    invoil0 = Dict(
        r => get(data["xdi0"], (r, :oil), 0.0) + get(data["xmi0"], (r, :oil), 0.0)
        for r in REGIONS
    )

    trnvst0 = Dict(
        r => get(data["vst"], (:tran, r), 0.0) for r in REGIONS
    )
  
    ytout0 = sum(trnvst0[r] for r in REGIONS)

    d0 = Dict(
        (r, i) => get(data["xp0"], (r, i), 0.0) - get(data["es0"], (r, i), 0.0) - get(data["vst"], (i, r), 0.0)
        for r in REGIONS, i in SECTORS
    )

    xp_phom = Dict(
        (r, i) => begin
            val = if (i == :oil)
                get(data["xp0"], (r, i), 0)
            else
                0.0
            end
        end
        for r in REGIONS, i in SECTORS
    )

    xp = Dict(
        (r, i) => begin
            val = if (i == :oil)
                0.0
            elseif (i == :food && r != :BRA)
                get(data["xp0"], (r, i), 0) - tbo[r]
            elseif (i == :food && r == :BRA)
                get(data["xp0"], (r, i), 0)
            elseif (i == :eint && r != :BRA)
                get(data["xp0"], (r, i), 0)
            elseif (i == :eint && r == :BRA)
                get(data["xp0"], (r, i), 0) - tbo[r]
            else
                get(data["xp0"], (r, i), 0)
            end
        end
        for r in REGIONS, i in SECTORS
    )

    xp_pdb = Dict(
        (r, i) => begin
            val = if (i == :food && r != :BRA)
                tbo[r]
            elseif (i == :food && r == :BRA)
                0.0
            elseif (i == :eint && r != :BRA)
                0.0
            elseif (i == :eint && r == :BRA)
                tbo[r]
            else
                0.0        
            end
        end
        for r in REGIONS, i in SECTORS
    )

    td = Dict(
        (r, i) => begin
            val = if (get(data["xp0"], (r, i), 0) == 0)
                0.0
            else
                get(data["ptxy0"], (r, i), 0.0) / data["xp0"][r, i]
            end
        end
        for r in REGIONS, i in SECTORS
    )

    inv0 = Dict(
        r => sum(get(data["xdi0"], (r, i), 0.0) + get(data["xmi0"], (r, i), 0.0) for i in SECTORS)
        for r in REGIONS
    )

    invdem0 = Dict(
        (r, i) => begin
            val = if (i == :oil)
                0.0
            else
                get(data["xdi0"], (r, i), 0.0) + get(data["xmi0"], (r, i), 0.0)
            end
        end
        for r in REGIONS, i in SECTORS
    )

    mvtwr = Dict(
        (r, rr, i) => sum(get(data["vtwr"], (j, i, rr, r), 0.0) for j in SECTORS)
        for r in REGIONS, rr in REGIONS, i in SECTORS
    )

    xaroilc = Dict(
        (r, i) => get(xa0, (r, :roil, i), 0.0) * cr[:roil, i, r]
        for r in REGIONS, i in SECTORS
    )

    xaroila = Dict(
        (r, i) => get(xa0, (r, :roil, i), 0.0) * (1-cr[:roil, i, r])
        for r in REGIONS, i in SECTORS
    )

    pac0 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    for r in REGIONS, e in ENERGY
        for g in SECTORS
            g == :elec && continue
            pac0[(e, g, r)] = e == :roil ? xaroilc[r, g] : xa0[r, e, g]
        end
        for t in TECH
            pac0[e, t, r] = e == :roil ? elecin[t, :roil, r] * cr[:roil, :elec, r] : elecin[t, e, r]
        end
        pac0[e, :households, r] = e == :roil ? ence1[e, r] * cr[:roil, :final, r] : ence1[e, r]
        pac0[e, :htrn, r] = e == :roil ? tfo[r] * cr[:roil, :final, r] : 0.0
    end

    pwdem0 = Dict(
        r => cons0[r] + inv0[r] for r in REGIONS
    )

    sco20 = Dict{Tuple{Symbol,Symbol,Symbol},Float64}()
    for r in REGIONS, g in SECTORS
        g == :elec && continue
        for e in SCO2_ENERGY
            sco20[e, g, r] = sco2coef[e] * ejuse[e, g, r]
        end
    end

    for r in REGIONS, i_ in TECH, e in SCO2_ENERGY
        sco20[e, i_, r] = sco2coef[e] * ejuse[e, i_, r]
    end

    for r in REGIONS, e in SCO2_ENERGY
        sco20[e, :households, r] = sco2coef[e] * ejuse[e, :households, r]
        sco20[e, :htrn, r] = sco2coef[e] * ejuse[e, :htrn, r]
    end

    selas = Dict(
        let
            s = String(k[1])                 # "eint.noe_el"
            parts = split(s, ".")            # ["eint", "noe_el"]
            (Symbol(parts[1]), Symbol(parts[2]), k[2])
        end => v
        for (k, v) in data["selas0"]
    )

    sele0 = Dict(
        r => get(data["xp0_"], (:sele, r), 0.0)
        for r in REGIONS
    )

    wele0 = Dict(
        r => get(data["xp0_"], (:wele, r), 0.0)
        for r in REGIONS
    )

    tele0 = Dict(
        r => get(data["xp0_"], (:tele, r), 0.0)
        for r in REGIONS
    )

    wst = Dict(
        (i, r) => get(data["wstsigma"], (i, r), 0)
        for i in TECH, r in REGIONS
    )

    xat0 = Dict{Tuple{Symbol,Symbol},Float64}()
    xd0 = Dict{Tuple{Symbol,Symbol},Float64}()
    for r in REGIONS, i in SECTORS
        xat0[(r, i)] = a0[(r, i)]
        xd0[(r, i)] = d0[(r, i)]
        if (i == :food && r != :BRA) || (i == :eint && r == :BRA)
            xat0[(r, i)] -= tbo[r]
            xd0[(r, i)] -= tbo[r]
        end
    end

    # Dictionaries exist but need to avoid missing keys

    ti = Dict(
        (i, j, r) => get(data["ti"], (i, j, r), 0)
        for i in SECTORS, j in SECTORS, r in REGIONS
    )

    tf = Dict(
        (f, j, r) => get(data["tf"], (f, j, r), 0)
        for f in PRIMARY, j in SECTORS, r in REGIONS
    )

    tg = Dict(
        (i, r) => get(data["tg"], (i, r), 0)
        for i in SECTORS, r in REGIONS
    )
    
    tp = Dict(
        (i, r) => get(data["tp"], (i, r), 0)
        for i in SECTORS, r in REGIONS
    )

    tx = Dict(
        (i, rr, r) => get(data["tx"], (i, rr, r), 0)
        for i in SECTORS, rr in REGIONS, r in REGIONS
    )

    tm = Dict(
        (i, rr, r) => get(data["tm"], (i, rr, r), 0)
        for i in SECTORS, rr in REGIONS, r in REGIONS
    )

    esup = Dict(
        (i, r) => get(data["esup"], (i, r), 0)
        for i in SECTORS, r in REGIONS
    )

    xm0 = Dict(
        (r, i) => get(data["xm0"], (r, i), 0)
        for i in SECTORS, r in REGIONS
    )

    wtflow0 = Dict(
        (r, rr, i) => get(data["wtflow0"], (r, rr, i), 0)
        for r in REGIONS, rr in REGIONS, i in SECTORS
    )

    datac["kapital"]     = kapital
    datac["labor"]       = labor
    datac["ffact"]       = ffact
    datac["nhrshare"]    = nhrshare
    datac["nhrsigma"]    = nhrsigma
    datac["g0"]          = g0
    datac["rgdp0"]       = rgdp0
    datac["aeei"]        = aeei
    datac["sco2coef"]    = sco2coef
    datac["cr"]          = cr
    datac["xa0"]         = xa0
    datac["purtrn"]      = purtrn
    datac["tbo"]         = tbo
    datac["tfo"]         = tfo
    datac["toi"]         = toi
    datac["tottrn"]      = tottrn
    datac["tse"]         = tse
    datac["own"]         = own
    datac["hhwedge"]     = hhwedge
    datac["xh"]          = xh
    datac["ence1"]       = ence1
    datac["euse0"]       = euse0
    datac["fuel_in"]     = fuel_in
    datac["ejod"]        = ejod
    datac["ejuse0"]      = ejuse0
    datac["ejuse_over_euse"] = ejuse_over_euse
    datac["ejuse"]       = ejuse
    datac["a0"]          = a0
    datac["dispgen0"]    = dispgen0
    datac["efout0"]      = efout0
    datac["td_"]         = td_
    datac["ffend0"]      = ffend0
    datac["ffgprod0"]    = ffgprod0
    datac["govdem0"]     = govdem0
    datac["govoil0"]     = govoil0
    datac["homm0"]       = homm0
    datac["homx0"]       = homx0
    datac["vhomx0"]      = vhomx0
    datac["homt0"]       = homt0
    datac["tmhom"]       = tmhom
    datac["vhomm0"]      = vhomm0
    datac["homadj"]      = homadj
    datac["trnadj"]      = trnadj
    datac["pwdem0"]      = pwdem0
    datac["invoil0"]     = invoil0
    datac["trnvst0"]     = trnvst0
    datac["ytout0"]      = ytout0
    datac["d0"]          = d0
    datac["xp"]          = xp
    datac["xp_phom"]     = xp_phom
    datac["xp_pdb"]      = xp_pdb
    datac["td"]          = td
    datac["xp_"]         = xp_
    datac["inv0"]        = inv0
    datac["invdem0"]     = invdem0
    datac["mvtwr"]       = mvtwr
    datac["xaroilc"]     = xaroilc
    datac["xaroila"]     = xaroila
    datac["pac0"]        = pac0
    datac["pwdem0"]      = pwdem0
    datac["sco20"]       = sco20
    datac["selas"]       = selas
    datac["sele0"]       = sele0
    datac["wele0"]       = wele0
    datac["tele0"]       = tele0
    datac["wst"]         = wst
    datac["xat0"]        = xat0
    datac["xd0"]         = xd0
    datac["txhom"]       = txhom
    datac["elecint"]     = elecint
    datac["elecin"]      = elecin
    datac["ti"]          = ti
    datac["tf"]          = tf
    datac["tg"]          = tg
    datac["tp"]          = tp
    datac["tx"]          = tx
    datac["tm"]          = tm
    datac["esup"]        = esup
    datac["xm0"]         = xm0
    datac["wtflow0"]      = wtflow0

    return datac

end



