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
const SCO2_SECTORS  = [filter(!=(:elec), SECTORS)..., TECH..., :households, :htrn]
const PDE_DIM   = [:dispgen, TECH_F..., TECH_N..., :tnd]
const NOT_AENOE = [:food, :othr, :serv, :tran, :dwe]
const LKR       = [:lab, :cap, :res]
const LK        = [:lab, :cap]

const HTRNS     = 0.3753
const PROPFRAC  = 0.2
const DPE       = 0.05
const ROR       = 0.1

function uno_data(data::Dict)

    labor   = Dict(r => sum(get(data["labd0"], (r, i), 0.0) for i in SECTORS) + get(data["labdg0"], (r,), 0.0) for r in REGIONS)
    kapital = Dict(r => sum(get(data["kapd0"], (r, i), 0.0) for i in SECTORS) for r in REGIONS)
    ffact   = Dict((i, r) => get(data["ffactd0"], (r, i), 0.0) * (1 + get(data["tf"], (:lnd, i, r), 0.0)) for r in REGIONS, i in SECTORS)
    rshr    = Dict((i, r) => get(data["rshr"], (i, r), 0.0) for i in TECH, r in REGIONS)
    xp0_    = Dict((i, r) => get(data["xp0_"], (i, r), 0.0) for i in TECH, r in REGIONS)
    td_     = Dict((i, r) => get(data["td_"], (r, i), 0.0) for r in REGIONS, i in TECH)
    elecint = Dict((i, f, r) => get(data["elecint"], (i, f, r), 0.0) for i in TECH, f in LKR, r in REGIONS)
    r0      = Dict((i, r) => rshr[i, r] * xp0_[i, r] * (1-td_[i, r]) / (1+elecint[i, :cap, r]) for i in TECH_NHR, r in REGIONS)
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
                (1 / denom) * xp0_[i, r] * (1 - td_[i, r]) / opelecint[i, r] * rshr[i, r]
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

    ffact0 = Dict((i, r) => ffact[i, r] for i in TECH_NHR, r in REGIONS)

    nhrshare = Dict(
        (i, r) => begin
            val = if xp0_[i, r] != 0
                denom = (1-td_[i, r]) * xp0_[i, r]
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

#=

nhrshare(i_nhr,r)$xp0_(i_nhr,r)			= elecin(i_nhr,"res",r)/((1-td_(r,i_nhr))*xp0_(i_nhr,r));
nhrsigma(i_nhr,r)$(1-nhrshare(i_nhr,r))		= nhreta(i_nhr,r)*nhrshare(i_nhr,r)/(1-nhrshare(i_nhr,r)); 

=#


    return kapital, ffact0, nhrshare, nhrsigma
end
