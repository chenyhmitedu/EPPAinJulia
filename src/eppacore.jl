# Active EPPA8 blocks: production by nest class, electricity technologies,
# Armington and bilateral trade, homogeneous oil, household transport,
# welfare, and the gprod/rgdp closure. No vintage, backstops, land use,
# Stone-Geary, or emissions commodities.

function build_model(B)
    # New methods are invisible to this call frame. Rebuild in the latest world.
    apply_smooth!()
    return Base.invokelatest(_build_model, B)
end

# iter = -1 is the base year, before any endowment update.
# solve!(MGE, cumulative_iteration_limit = 0) then reports the benchmark residual.
function EPPA_model(data, iter::Integer = -1)
    iter == -1 || throw(ArgumentError(
        "EPPA_model(data, -1) is the base-year model. Later years are solved by calibrate.",
    ))
    MGE, _ = build_model(data)
    return MGE
end

function _build_model(B)
    PATHSolver.c_api_License_SetString(PATH_LICENSE)
    MGE = MPSGEModel()
    R = REGIONS
    I = SECTORS
    g = B.g
    ge = B.ge

    y_na = [(i, r) for i in NOT_AENOE for r in R if g("xp0", (r, i)) > 0]
    y_ei = [(i, r) for i in [:eint] for r in R if g("xp0", (r, i)) > 0]
    y_ag = [(i, r) for i in AGRI for r in R if g("xp0", (r, i)) > 0]
    y_en = [(i, r) for i in ENOE for r in R if g("xp0", (r, i)) > 0]
    y_el = [r for r in R if g("xp0", (r, :elec)) > 0]
    y_f = [(t, r) for t in TECH_F for r in R if ge("xp0_", (t, r)) > 0]
    y_nhr = [(t, r) for t in TECH_NHR for r in R if ge("xp0_", (t, r)) > 0 && get(B.ffact_e, (t, r), 0.0) > 0]
    y_n = [(t, r) for t in TECH_N for r in R if ge("xp0_", (t, r)) > 0]
    y_t = [(t, r) for t in [:tele] for r in R if ge("xp0_", (t, r)) > 0]
    y_arm = [(i, r) for i in I if i != :oil for r in R if B.a0[(r, i)] != 0]
    y_m = [(i, r) for i in I if i != :oil for r in R if g("xm0", (r, i)) > 0]
    flows = [(r, rr, i) for r in R for rr in R for i in I if i != :oil && g("wtflow0", (r, rr, i)) > 0]
    y_hm = [r for r in R if B.homm0[r] > 0]
    y_hx = [r for r in R if B.homx0[r] > 0]

    @parameter(MGE, K0[r=R], B.kapital[r])
    @parameter(MGE, L0[r=R], B.labor[r])
    @parameter(MGE, FF0[i=I, r=R], B.ffact[(r, i)])
    @parameter(MGE, FFe[t=TECH_NHR, r=R], get(B.ffact_e, (t, r), 0.0))
    @parameter(MGE, SAV[r=R], g("savf0", (r,)))
    @parameter(MGE, GRG[r=R], B.g0[r])
    @parameter(MGE, GDP0[r=R], B.rgdp0[r])

    @commodity(MGE, PD[i=I, r=R])
    @commodity(MGE, PA[i=I, r=R])
    @commodity(MGE, PHOM[r=R])
    @commodity(MGE, PM[i=I, r=R])
    @commodity(MGE, PDs[i=I, r=R])
    @commodity(MGE, PDB[i=[:food, :eint], r=R])
    @commodity(MGE, PK[r=R])
    @commodity(MGE, PL[r=R])
    @commodity(MGE, PF[i=I, r=R])
    @commodity(MGE, PFr[t=TECH, r=R])
    @commodity(MGE, PDd[r=R])
    @commodity(MGE, PDf[t=TECH_F, r=R])
    @commodity(MGE, PDn[t=TECH_N, r=R])
    @commodity(MGE, PDt[r=R])
    @commodity(MGE, PG[r=R])
    @commodity(MGE, PINV[r=R])
    @commodity(MGE, PT)
    @commodity(MGE, PU[r=R])
    @commodity(MGE, PW[r=R])
    @commodity(MGE, PTRN[r=R])
    @commodity(MGE, PTNn[r=R])
    @commodity(MGE, PTNv[r=R])
    @commodity(MGE, PTN[r=R])
    @commodity(MGE, PTNs[r=R])
    @commodity(MGE, PWH)
    @commodity(MGE, PWHs[r=R])

    @consumer(MGE, RA[r=R])
    @auxiliary(MGE, gprod[r=R], lower_bound = 0, start = 1)
    @auxiliary(MGE, rgdp[r=R], lower_bound = 0, start = B.rgdp0[r])

    @sector(MGE, Yna[k=y_na])
    @sector(MGE, Yei[k=y_ei])
    @sector(MGE, Yag[k=y_ag])
    @sector(MGE, Yen[k=y_en])
    @sector(MGE, Yel[r=y_el])
    @sector(MGE, Yef[r=R])
    @sector(MGE, Yf[k=y_f])
    @sector(MGE, Ynhr[k=y_nhr])
    @sector(MGE, Yn[k=y_n])
    @sector(MGE, Yt[k=y_t])
    @sector(MGE, GOVT[r=R])
    @sector(MGE, INV[r=R])
    @sector(MGE, YT)
    @sector(MGE, HTRN[r=R])
    @sector(MGE, HNEW[r=R])
    @sector(MGE, HOLD[r=R])
    @sector(MGE, HAGG[r=R])
    @sector(MGE, Z[r=R])
    @sector(MGE, W[r=R])
    @sector(MGE, A[k=y_arm])
    @sector(MGE, IMP[k=y_m])
    @sector(MGE, TFL[k=flows])
    @sector(MGE, HOMM[r=y_hm])
    @sector(MGE, HOMX[r=y_hx])
    @sector(MGE, MQ[r=y_hm])

    # --- non-energy (not aenoe): food, othr, serv, tran, dwe ---
    for (i, r) in y_na
        xp = g("xp0", (r, i))
        td = B.td[(r, i)]
        qpd = (i == :food && r != :bra) ? xp - B.tbo[r] : xp
        qpdb = (i == :food && r != :bra) ? B.tbo[r] : 0.0
        sigu = get(B.sigu, (i, r), 0.0)
        es = get(B.esup, (i, r), 0.0)
        pn = i in AGRI ? 0.7 : 0.0
        ekl = B.elas(i, :e_kl, r)
        lk = B.elas(i, :l_k, r)
        noe = B.elas(i, :noe_el, r)
        esb = get(B.esube, (i, r), 0.0)
        @production(MGE, Yna[(i, r)], [t=2, s=sigu, b=>s=es, a=>b=pn, ee=>a=ekl, va=>ee=lk, en=>ee=noe, en1=>en=esb,
                oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PD[i, r], qpd, t, taxes=[Tax(RA[r], td)])
            @output(PDB[:food, r], qpdb, t, taxes=[Tax(RA[r], td)])
            [@input(PA[j, r], g("xdp0", (r, j, i)) + g("xmp0", (r, j, i)), a,
                taxes=[Tax(RA[r], g("ti", (j, i, r)))], reference_price=1 + g("ti", (j, i, r))) for j in NE]...
            [@input(PA[:roil, r], (g("xdp0", (r, :roil, i)) + g("xmp0", (r, :roil, i))) * (1 - B.cr(:roil, i, r)), a,
                taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            @input(PL[r], g("labd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:lab, i, r)))], reference_price=1 + g("tf", (:lab, i, r)))
            @input(PK[r], g("kapd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:cap, i, r)))], reference_price=1 + g("tf", (:cap, i, r)))
            @input(PF[i, r], B.ffact[(r, i)], b)
            [@input(PHOM[r], g("xdp0", (r, :oil, i)) + g("xmp0", (r, :oil, i)), oil,
                taxes=[Tax(RA[r], g("ti", (:oil, i, r)))], reference_price=1 + g("ti", (:oil, i, r)))]...
            [@input(PA[:gas, r], g("xdp0", (r, :gas, i)) + g("xmp0", (r, :gas, i)), gas,
                taxes=[Tax(RA[r], g("ti", (:gas, i, r)))], reference_price=1 + g("ti", (:gas, i, r)))]...
            [@input(PA[:coal, r], g("xdp0", (r, :coal, i)) + g("xmp0", (r, :coal, i)), coal,
                taxes=[Tax(RA[r], g("ti", (:coal, i, r)))], reference_price=1 + g("ti", (:coal, i, r)))]...
            [@input(PA[:roil, r], (g("xdp0", (r, :roil, i)) + g("xmp0", (r, :roil, i))) * B.cr(:roil, i, r), roil,
                taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            [@input(PA[:elec, r], g("xdp0", (r, :elec, i)) + g("xmp0", (r, :elec, i)), en,
                taxes=[Tax(RA[r], g("ti", (:elec, i, r)))], reference_price=1 + g("ti", (:elec, i, r)))]...
        end)
    end

    # --- energy intensive (sa = 1; bra biofuel split) ---
    for (i, r) in y_ei
        xp = g("xp0", (r, i))
        td = B.td[(r, i)]
        qpd = r == :bra ? xp - B.tbo[r] : xp
        qpdb = r == :bra ? B.tbo[r] : 0.0
        sigu = get(B.sigu, (i, r), 0.0)
        es = get(B.esup, (i, r), 0.0)
        ekl = B.elas(i, :e_kl, r)
        lk = B.elas(i, :l_k, r)
        noe = B.elas(i, :noe_el, r)
        esb = get(B.esube, (i, r), 0.0)
        @production(MGE, Yei[(i, r)], [t=2, s=sigu, b=>s=es, a=>b=0, ee=>a=ekl, va=>ee=lk, en=>ee=noe, en1=>en=esb,
                oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PD[i, r], qpd, t, taxes=[Tax(RA[r], td)])
            @output(PDB[:eint, r], qpdb, t, taxes=[Tax(RA[r], td)])
            [@input(PA[j, r], g("xdp0", (r, j, i)) + g("xmp0", (r, j, i)), a,
                taxes=[Tax(RA[r], g("ti", (j, i, r)))], reference_price=1 + g("ti", (j, i, r))) for j in NE]...
            [@input(PA[:roil, r], (g("xdp0", (r, :roil, i)) + g("xmp0", (r, :roil, i))) * (1 - B.cr(:roil, i, r)), a,
                taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            @input(PL[r], g("labd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:lab, i, r)))], reference_price=1 + g("tf", (:lab, i, r)))
            @input(PK[r], g("kapd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:cap, i, r)))], reference_price=1 + g("tf", (:cap, i, r)))
            @input(PF[i, r], B.ffact[(r, i)], b)
            [@input(PHOM[r], g("xdp0", (r, :oil, i)) + g("xmp0", (r, :oil, i)), oil,
                taxes=[Tax(RA[r], g("ti", (:oil, i, r)))], reference_price=1 + g("ti", (:oil, i, r)))]...
            [@input(PA[:gas, r], g("xdp0", (r, :gas, i)) + g("xmp0", (r, :gas, i)), gas,
                taxes=[Tax(RA[r], g("ti", (:gas, i, r)))], reference_price=1 + g("ti", (:gas, i, r)))]...
            [@input(PA[:coal, r], g("xdp0", (r, :coal, i)) + g("xmp0", (r, :coal, i)), coal,
                taxes=[Tax(RA[r], g("ti", (:coal, i, r)))], reference_price=1 + g("ti", (:coal, i, r)))]...
            [@input(PA[:roil, r], (g("xdp0", (r, :roil, i)) + g("xmp0", (r, :roil, i))) * B.cr(:roil, i, r), roil,
                taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            [@input(PA[:elec, r], g("xdp0", (r, :elec, i)) + g("xmp0", (r, :elec, i)), en,
                taxes=[Tax(RA[r], g("ti", (:elec, i, r)))], reference_price=1 + g("ti", (:elec, i, r)))]...
        end)
    end

    # --- agriculture: materials under the energy/value nest, fixed factor on fx ---
    for (i, r) in y_ag
        xp = g("xp0", (r, i))
        td = B.td[(r, i)]
        sigu = get(B.sigu, (i, r), 0.0)
        es = get(B.esup, (i, r), 0.0)
        ekl = B.elas(i, :e_kl, r)
        lk = B.elas(i, :l_k, r)
        noe = B.elas(i, :noe_el, r)
        esb = get(B.esube, (i, r), 0.0)
        @production(MGE, Yag[(i, r)], [t=0, s=sigu, a=>s=0.7, va=>a=lk, fx=>a=es, e=>fx=ekl, ne=>e=0, en=>e=noe, en1=>en=esb,
                oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PD[i, r], xp, t, taxes=[Tax(RA[r], td)])
            [@input(PA[j, r], g("xdp0", (r, j, i)) + g("xmp0", (r, j, i)), ne,
                taxes=[Tax(RA[r], g("ti", (j, i, r)))], reference_price=1 + g("ti", (j, i, r))) for j in NE]...
            [@input(PA[:roil, r], (g("xdp0", (r, :roil, i)) + g("xmp0", (r, :roil, i))) * (1 - B.cr(:roil, i, r)), ne,
                taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            @input(PL[r], g("labd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:lab, i, r)))], reference_price=1 + g("tf", (:lab, i, r)))
            @input(PK[r], g("kapd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:cap, i, r)))], reference_price=1 + g("tf", (:cap, i, r)))
            @input(PF[i, r], B.ffact[(r, i)], fx)
            [@input(PHOM[r], g("xdp0", (r, :oil, i)) + g("xmp0", (r, :oil, i)), oil,
                taxes=[Tax(RA[r], g("ti", (:oil, i, r)))], reference_price=1 + g("ti", (:oil, i, r)))]...
            [@input(PA[:gas, r], g("xdp0", (r, :gas, i)) + g("xmp0", (r, :gas, i)), gas,
                taxes=[Tax(RA[r], g("ti", (:gas, i, r)))], reference_price=1 + g("ti", (:gas, i, r)))]...
            [@input(PA[:coal, r], g("xdp0", (r, :coal, i)) + g("xmp0", (r, :coal, i)), coal,
                taxes=[Tax(RA[r], g("ti", (:coal, i, r)))], reference_price=1 + g("ti", (:coal, i, r)))]...
            [@input(PA[:roil, r], (g("xdp0", (r, :roil, i)) + g("xmp0", (r, :roil, i))) * B.cr(:roil, i, r), roil,
                taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            [@input(PA[:elec, r], g("xdp0", (r, :elec, i)) + g("xmp0", (r, :elec, i)), en,
                taxes=[Tax(RA[r], g("ti", (:elec, i, r)))], reference_price=1 + g("ti", (:elec, i, r)))]...
        end)
    end

    # --- coal, oil, gas, refined oil. Crude oil output is the homogeneous good. ---
    for (i, r) in y_en
        xp = g("xp0", (r, i))
        td = B.td[(r, i)]
        es = get(B.esup, (i, r), 0.0)
        pn = 0.0
        lk = B.elas(i, :l_k, r)
        noe = B.elas(i, :noe_el, r)
        esb = get(B.esube, (i, r), 0.0)
        @production(MGE, Yen[(i, r)], [t=0, s=0, b=>s=es, a=>b=pn, va=>a=lk, en=>a=noe, en1=>en=esb,
                oil=>en1=0, gas=>en1=0, coal=>en1=0, roil=>en1=0], begin
            @output(PHOM[r], i == :oil ? xp : 0.0, t, taxes=[Tax(RA[r], td)])
            @output(PD[i, r], i == :oil ? 0.0 : xp, t, taxes=[Tax(RA[r], td)])
            [@input(PA[j, r], g("xdp0", (r, j, i)) + g("xmp0", (r, j, i)), a,
                taxes=[Tax(RA[r], g("ti", (j, i, r)))], reference_price=1 + g("ti", (j, i, r))) for j in NE]...
            [@input(PA[:roil, r], (g("xdp0", (r, :roil, i)) + g("xmp0", (r, :roil, i))) * (1 - B.cr(:roil, i, r)), a,
                taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            @input(PL[r], g("labd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:lab, i, r)))], reference_price=1 + g("tf", (:lab, i, r)))
            @input(PK[r], g("kapd0", (r, i)), va, taxes=[Tax(RA[r], g("tf", (:cap, i, r)))], reference_price=1 + g("tf", (:cap, i, r)))
            @input(PF[i, r], B.ffact[(r, i)], b)
            [@input(PHOM[r], g("xdp0", (r, :oil, i)) + g("xmp0", (r, :oil, i)), oil,
                taxes=[Tax(RA[r], g("ti", (:oil, i, r)))], reference_price=1 + g("ti", (:oil, i, r)))]...
            [@input(PA[:gas, r], g("xdp0", (r, :gas, i)) + g("xmp0", (r, :gas, i)), gas,
                taxes=[Tax(RA[r], g("ti", (:gas, i, r)))], reference_price=1 + g("ti", (:gas, i, r)))]...
            [@input(PA[:coal, r], g("xdp0", (r, :coal, i)) + g("xmp0", (r, :coal, i)), coal,
                taxes=[Tax(RA[r], g("ti", (:coal, i, r)))], reference_price=1 + g("ti", (:coal, i, r)))]...
            [@input(PA[:roil, r], (g("xdp0", (r, :roil, i)) + g("xmp0", (r, :roil, i))) * B.cr(:roil, i, r), roil,
                taxes=[Tax(RA[r], g("ti", (:roil, i, r)))], reference_price=1 + g("ti", (:roil, i, r)))]...
            [@input(PA[:elec, r], g("xdp0", (r, :elec, i)) + g("xmp0", (r, :elec, i)), en,
                taxes=[Tax(RA[r], g("ti", (:elec, i, r)))], reference_price=1 + g("ti", (:elec, i, r)))]...
        end)
    end

    # --- electricity aggregation and technologies ---
    for r in y_el
        @production(MGE, Yel[r], [t=0, s=0, s001=>s=1, s011=>s001=1], begin
            @output(PD[:elec, r], g("xp0", (r, :elec)), t)
            [@input(PDn[:sele, r], ge("xp0_", (:sele, r)), s001)]...
            [@input(PDd[r], sum(ge("xp0_", (t, r)) for t in TECH_D), s011)]...
            [@input(PDn[:wele, r], ge("xp0_", (:wele, r)), s011)]...
            [@input(PDt[r], ge("xp0_", (:tele, r)), s)]...
        end)
        ekl = B.elas(:elec, :e_kl, r)
        lk = B.elas(:elec, :l_k, r)
        @production(MGE, Yef[r], [t=0, s=1.5], begin
            @output(PDd[r], sum(ge("xp0_", (t, r)) for t in TECH_F), t)
            [@input(PDf[t, r], ge("xp0_", (t, r)), s) for t in TECH_F]...
        end)
    end

    function elec_inputs(t, r)
        mats = [(j, get(B.elecin, (t, j, r), 0.0), get(B.elecint, (t, j, r), 0.0)) for j in NE]
        fuels = []
        for j in ENERGY
            q = get(B.elecin, (t, j, r), 0.0)
            rate = get(B.elecint, (t, j, r), 0.0)
            if j == :roil
                push!(fuels, (:ac, j, q * (1 - B.cr(:roil, :elec, r)), rate))
                push!(fuels, (:curb, j, q * B.cr(:roil, :elec, r), rate))
            else
                push!(fuels, (:curb, j, q, rate))
            end
        end
        return mats, fuels
    end

    for (t, r) in y_f
        td = ge("td_", (r, t))
        ekl = B.elas(:elec, :e_kl, r)
        lk = B.elas(:elec, :l_k, r)
        mats, fuels = elec_inputs(t, r)
        @production(MGE, Yf[(t, r)], [t=0, s=0, bc=>s=0.6, ac=>bc=0, eec=>ac=ekl, curb=>eec=0, vac=>eec=lk], begin
            @output(PDf[t, r], ge("xp0_", (t, r)), t, taxes=[Tax(RA[r], td)])
            [@input(PA[j, r], q, ac, taxes=[Tax(RA[r], rate)], reference_price=1 + rate) for (j, q, rate) in mats]...
            @input(PHOM[r], get(B.elecin, (t, :oil, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :oil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :oil, r), 0.0))
            @input(PA[:gas, r], get(B.elecin, (t, :gas, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :gas, r), 0.0))], reference_price=1 + get(B.elecint, (t, :gas, r), 0.0))
            @input(PA[:coal, r], get(B.elecin, (t, :coal, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :coal, r), 0.0))], reference_price=1 + get(B.elecint, (t, :coal, r), 0.0))
            @input(PA[:elec, r], get(B.elecin, (t, :elec, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :elec, r), 0.0))], reference_price=1 + get(B.elecint, (t, :elec, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (t, :roil, r), 0.0) * (1 - B.cr(:roil, :elec, r)), ac, taxes=[Tax(RA[r], get(B.elecint, (t, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :roil, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (t, :roil, r), 0.0) * B.cr(:roil, :elec, r), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :roil, r), 0.0))
            @input(PL[r], get(B.elecin, (t, :lab, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (t, :lab, r), 0.0))], reference_price=1 + get(B.elecint, (t, :lab, r), 0.0))
            @input(PK[r], get(B.elecin, (t, :cap, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (t, :cap, r), 0.0))], reference_price=1 + get(B.elecint, (t, :cap, r), 0.0))
            @input(PFr[t, r], get(B.elecin, (t, :res, r), 0.0), bc, taxes=[Tax(RA[r], get(B.elecint, (t, :res, r), 0.0))], reference_price=1 + get(B.elecint, (t, :res, r), 0.0))
        end)
    end

    for (t, r) in y_nhr
        td = ge("td_", (r, t))
        ekl = B.elas(:elec, :e_kl, r)
        lk = B.elas(:elec, :l_k, r)
        sig = B.nhrsigma[(t, r)]
        mats, fuels = elec_inputs(t, r)
        @production(MGE, Ynhr[(t, r)], [t=0, s=0, bc=>s=sig, ac=>bc=0, eec=>ac=ekl, curb=>eec=0, vac=>eec=lk], begin
            @output(PDd[r], ge("xp0_", (t, r)), t, taxes=[Tax(RA[r], td)])
            [@input(PA[j, r], q, ac, taxes=[Tax(RA[r], rate)], reference_price=1 + rate) for (j, q, rate) in mats]...
            @input(PHOM[r], get(B.elecin, (t, :oil, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :oil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :oil, r), 0.0))
            @input(PA[:gas, r], get(B.elecin, (t, :gas, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :gas, r), 0.0))], reference_price=1 + get(B.elecint, (t, :gas, r), 0.0))
            @input(PA[:coal, r], get(B.elecin, (t, :coal, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :coal, r), 0.0))], reference_price=1 + get(B.elecint, (t, :coal, r), 0.0))
            @input(PA[:elec, r], get(B.elecin, (t, :elec, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :elec, r), 0.0))], reference_price=1 + get(B.elecint, (t, :elec, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (t, :roil, r), 0.0) * (1 - B.cr(:roil, :elec, r)), ac, taxes=[Tax(RA[r], get(B.elecint, (t, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :roil, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (t, :roil, r), 0.0) * B.cr(:roil, :elec, r), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :roil, r), 0.0))
            @input(PL[r], get(B.elecin, (t, :lab, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (t, :lab, r), 0.0))], reference_price=1 + get(B.elecint, (t, :lab, r), 0.0))
            @input(PK[r], get(B.elecin, (t, :cap, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (t, :cap, r), 0.0))], reference_price=1 + get(B.elecint, (t, :cap, r), 0.0))
            @input(PFr[t, r], get(B.elecin, (t, :res, r), 0.0), bc, taxes=[Tax(RA[r], get(B.elecint, (t, :res, r), 0.0))], reference_price=1 + get(B.elecint, (t, :res, r), 0.0))
        end)
    end

    for (t, r) in y_n
        td = ge("td_", (r, t))
        ekl = B.elas(:elec, :e_kl, r)
        lk = B.elas(:elec, :l_k, r)
        sig = get(B.wst, (t, r), 0.0)
        mats, fuels = elec_inputs(t, r)
        @production(MGE, Yn[(t, r)], [t=0, s=0, s001=>s=sig, ac=>s001=0, eec=>ac=ekl, curb=>eec=0, vac=>eec=lk], begin
            @output(PDn[t, r], ge("xp0_", (t, r)), t, taxes=[Tax(RA[r], td)])
            [@input(PA[j, r], q, ac, taxes=[Tax(RA[r], rate)], reference_price=1 + rate) for (j, q, rate) in mats]...
            @input(PHOM[r], get(B.elecin, (t, :oil, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :oil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :oil, r), 0.0))
            @input(PA[:gas, r], get(B.elecin, (t, :gas, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :gas, r), 0.0))], reference_price=1 + get(B.elecint, (t, :gas, r), 0.0))
            @input(PA[:coal, r], get(B.elecin, (t, :coal, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :coal, r), 0.0))], reference_price=1 + get(B.elecint, (t, :coal, r), 0.0))
            @input(PA[:elec, r], get(B.elecin, (t, :elec, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :elec, r), 0.0))], reference_price=1 + get(B.elecint, (t, :elec, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (t, :roil, r), 0.0) * (1 - B.cr(:roil, :elec, r)), ac, taxes=[Tax(RA[r], get(B.elecint, (t, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :roil, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (t, :roil, r), 0.0) * B.cr(:roil, :elec, r), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :roil, r), 0.0))
            @input(PL[r], get(B.elecin, (t, :lab, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (t, :lab, r), 0.0))], reference_price=1 + get(B.elecint, (t, :lab, r), 0.0))
            @input(PK[r], get(B.elecin, (t, :cap, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (t, :cap, r), 0.0))], reference_price=1 + get(B.elecint, (t, :cap, r), 0.0))
        end)
    end

    for (t, r) in y_t
        td = ge("td_", (r, t))
        ekl = B.elas(:elec, :e_kl, r)
        lk = B.elas(:elec, :l_k, r)
        mats, fuels = elec_inputs(t, r)
        @production(MGE, Yt[(t, r)], [t=0, s=0, s001=>s=0.6, ac=>s001=0, eec=>ac=ekl, curb=>eec=0, vac=>eec=lk], begin
            @output(PDt[r], ge("xp0_", (t, r)), t, taxes=[Tax(RA[r], td)])
            [@input(PA[j, r], q, ac, taxes=[Tax(RA[r], rate)], reference_price=1 + rate) for (j, q, rate) in mats]...
            @input(PHOM[r], get(B.elecin, (t, :oil, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :oil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :oil, r), 0.0))
            @input(PA[:gas, r], get(B.elecin, (t, :gas, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :gas, r), 0.0))], reference_price=1 + get(B.elecint, (t, :gas, r), 0.0))
            @input(PA[:coal, r], get(B.elecin, (t, :coal, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :coal, r), 0.0))], reference_price=1 + get(B.elecint, (t, :coal, r), 0.0))
            @input(PA[:elec, r], get(B.elecin, (t, :elec, r), 0.0), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :elec, r), 0.0))], reference_price=1 + get(B.elecint, (t, :elec, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (t, :roil, r), 0.0) * (1 - B.cr(:roil, :elec, r)), ac, taxes=[Tax(RA[r], get(B.elecint, (t, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :roil, r), 0.0))
            @input(PA[:roil, r], get(B.elecin, (t, :roil, r), 0.0) * B.cr(:roil, :elec, r), curb, taxes=[Tax(RA[r], get(B.elecint, (t, :roil, r), 0.0))], reference_price=1 + get(B.elecint, (t, :roil, r), 0.0))
            @input(PL[r], get(B.elecin, (t, :lab, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (t, :lab, r), 0.0))], reference_price=1 + get(B.elecint, (t, :lab, r), 0.0))
            @input(PK[r], get(B.elecin, (t, :cap, r), 0.0), vac, taxes=[Tax(RA[r], get(B.elecint, (t, :cap, r), 0.0))], reference_price=1 + get(B.elecint, (t, :cap, r), 0.0))
        end)
    end

    for r in R
        @production(MGE, GOVT[r], [t=0, s=0.5], begin
            @output(PG[r], B.g0[r], t)
            [@input(PA[i, r], i == :oil ? 0.0 : g("xdg0", (r, i)) + g("xmg0", (r, i)), s,
                taxes=[Tax(RA[r], g("tg", (i, r)))], reference_price=g("pg0", (i, r))) for i in I]...
            @input(PHOM[r], g("xdg0", (r, :oil)) + g("xmg0", (r, :oil)), s,
                taxes=[Tax(RA[r], g("tg", (:oil, r)))], reference_price=g("pg0", (:oil, r)))
        end)
        @production(MGE, INV[r], [t=0, s=5], begin
            @output(PINV[r], B.inv0[r], t)
            [@input(PA[i, r], i == :oil ? 0.0 : g("xdi0", (r, i)) + g("xmi0", (r, i)), s) for i in I]...
            @input(PHOM[r], g("xdi0", (r, :oil)) + g("xmi0", (r, :oil)), s)
        end)
    end

    @production(MGE, YT, [t=0, s=1], begin
        @output(PT, sum(g("vst", (:tran, r)) for r in R), t)
        [@input(PD[:tran, r], g("vst", (:tran, r)), s) for r in R]...
    end)

    # Household transport. Identity layers with a single input are omitted;
    # htrn buys the two conventional streams directly.
    for r in R
        own = B.own[r]
        pcR = g("pc0", (:roil, r))
        tpR = g("tp", (:roil, r))
        foodp = r == :bra ? :eint : :food
        tn1 = (r == :usa || r == :eur) ? 0.75 : 1.0
        @production(MGE, HNEW[r], [t=0, s=0.1, a=>s=tn1, c=>a=0, b=>s=1], begin
            @output(PTNn[r], HTRNS * own, t)
            @input(PA[:roil, r], HTRNS * B.tfo[r], c, taxes=[Tax(RA[r], tpR)], reference_price=pcR)
            @input(PDB[foodp, r], HTRNS * B.tbo[r], c, taxes=[Tax(RA[r], tpR)], reference_price=pcR)
            @input(PA[:othr, r], HTRNS * B.toi[r] * PROPFRAC, a, taxes=[Tax(RA[r], g("tp", (:othr, r)))], reference_price=g("pc0", (:othr, r)))
            @input(PA[:othr, r], HTRNS * B.toi[r] * (1 - PROPFRAC), b, taxes=[Tax(RA[r], g("tp", (:othr, r)))], reference_price=g("pc0", (:othr, r)))
            @input(PA[:serv, r], HTRNS * B.tse[r], b, taxes=[Tax(RA[r], g("tp", (:serv, r)))], reference_price=g("pc0", (:serv, r)))
        end)
        @production(MGE, HOLD[r], [t=0, s=0], begin
            @output(PTNv[r], (1 - HTRNS) * own, t)
            @input(PA[:roil, r], (1 - HTRNS) * B.tfo[r], s, taxes=[Tax(RA[r], tpR)], reference_price=pcR)
            @input(PDB[foodp, r], (1 - HTRNS) * B.tbo[r], s, taxes=[Tax(RA[r], tpR)], reference_price=pcR)
            @input(PA[:othr, r], (1 - HTRNS) * B.toi[r], s, taxes=[Tax(RA[r], g("tp", (:othr, r)))], reference_price=g("pc0", (:othr, r)))
            @input(PA[:serv, r], (1 - HTRNS) * B.tse[r], s, taxes=[Tax(RA[r], g("tp", (:serv, r)))], reference_price=g("pc0", (:serv, r)))
        end)
        @production(MGE, HAGG[r], [t=4, s=0], begin
            @output(PTN[r], 0.2 * own, t)
            @output(PTNs[r], 0.8 * own, t)
            @input(PTNn[r], HTRNS * own, s)
            @input(PTNv[r], (1 - HTRNS) * own, s)
        end)
        @production(MGE, HTRN[r], [t=0, s=0.2, s1=>s=4], begin
            @output(PTRN[r], B.tottrn[r], t)
            @input(PA[:tran, r], B.purtrn[r], s, taxes=[Tax(RA[r], g("tp", (:tran, r)))], reference_price=g("pc0", (:tran, r)))
            @input(PTN[r], 0.2 * own, s1)
            @input(PTNs[r], 0.8 * own, s1)
        end)

        wedge = (pcR - g("pc0", (foodp, r))) * B.tbo[r]
        delas = get(B.delas, (r,), 0.0)
        noe = B.elas(:hh, :noe_el, r)
        @production(MGE, Z[r], [t=0, s=0.5, u=>s=0.25, a=>u=delas, dw=>u=0.3, en=>dw=noe,
                oil=>en=0, gas=>en=0, coal=>en=0, roil=>en=0, elec=>en=0], begin
            @output(PU[r], g("cons0", (r,)) + wedge, t)
            @input(PTRN[r], B.tottrn[r], s)
            [@input(PA[i, r], max(get(B.xdc, (r, i), 0.0) + g("xmc0", (r, i)), 0.0), a,
                taxes=[Tax(RA[r], g("tp", (i, r)))], reference_price=g("pc0", (i, r))) for i in NENDT]...
            [@input(PA[:dwe, r], max(get(B.xdc, (r, :dwe), 0.0) + g("xmc0", (r, :dwe)), 0.0), dw,
                taxes=[Tax(RA[r], g("tp", (:dwe, r)))], reference_price=g("pc0", (:dwe, r)))]...
            @input(PHOM[r], max(B.ence[(:oil, r)], 0.0), oil, taxes=[Tax(RA[r], g("tp", (:oil, r)))], reference_price=g("pc0", (:oil, r)))
            @input(PA[:gas, r], max(B.ence[(:gas, r)], 0.0), gas, taxes=[Tax(RA[r], g("tp", (:gas, r)))], reference_price=g("pc0", (:gas, r)))
            @input(PA[:coal, r], max(B.ence[(:coal, r)], 0.0), coal, taxes=[Tax(RA[r], g("tp", (:coal, r)))], reference_price=g("pc0", (:coal, r)))
            @input(PA[:roil, r], max(B.ence[(:roil, r)], 0.0), roil, taxes=[Tax(RA[r], g("tp", (:roil, r)))], reference_price=g("pc0", (:roil, r)))
            @input(PA[:elec, r], max(B.ence[(:elec, r)], 0.0), elec, taxes=[Tax(RA[r], g("tp", (:elec, r)))], reference_price=g("pc0", (:elec, r)))
        end)
        @production(MGE, W[r], [t=0, s=0], begin
            @output(PW[r], g("cons0", (r,)) + B.inv0[r] + wedge, t)
            @input(PU[r], g("cons0", (r,)) + wedge, s)
            @input(PINV[r], B.inv0[r], s)
        end)
    end

    for (i, r) in y_arm
        qout = B.a0[(r, i)]
        qdom = B.d0[(r, i)]
        if (i == :food && r != :bra) || (i == :eint && r == :bra)
            qout -= B.tbo[r]
            qdom -= B.tbo[r]
        end
        sdm = B.elas(i, :sdm, r)
        @production(MGE, A[(i, r)], [t=0, s=sdm], begin
            @output(PA[i, r], qout, t)
            @input(PD[i, r], qdom, s)
            @input(PM[i, r], g("xm0", (r, i)), s)
        end)
    end

    for (i, r) in y_m
        smm = B.elas(i, :smm, r)
        @production(MGE, IMP[(i, r)], [t=0, s=smm, src[rr=R]=>s=0], begin
            @output(PM[i, r], g("xm0", (r, i)), t)
            [@input(PDs[i, rr], g("wtflow0", (r, rr, i)), src[rr],
                taxes=[Tax(RA[rr], g("tx", (i, rr, r))), Tax(RA[r], g("tm", (i, rr, r)) * (1 + g("tx", (i, rr, r))))],
                reference_price=(1 + g("tx", (i, rr, r))) * (1 + g("tm", (i, rr, r)))) for rr in R]...
            [@input(PT, sum(g("vtwr", (j, i, rr, r)) for j in I), src[rr],
                taxes=[Tax(RA[r], g("tm", (i, rr, r)))], reference_price=1 + g("tm", (i, rr, r))) for rr in R]...
        end)
    end

    for (r, rr, i) in flows
        @production(MGE, TFL[(r, rr, i)], [t=0, s=0], begin
            @output(PDs[i, rr], g("wtflow0", (r, rr, i)), t)
            @input(PD[i, rr], g("wtflow0", (r, rr, i)), s)
        end)
    end

    for r in y_hm
        @production(MGE, HOMM[r], [t=0, s=0], begin
            @output(PHOM[r], B.vhomm0[r], t)
            @input(PWHs[r], B.homm0[r], s, taxes=[Tax(RA[r], B.tmhom[r])])
            @input(PT, B.homt0[r], s, taxes=[Tax(RA[r], B.tmhom[r])])
        end)
        @production(MGE, MQ[r], [t=0, s=0], begin
            @output(PWHs[r], B.homm0[r], t)
            @input(PWH, B.homm0[r], s)
        end)
    end
    for r in y_hx
        @production(MGE, HOMX[r], [t=0, s=0], begin
            @output(PWH, B.homx0[r], t)
            @input(PHOM[r], B.vhomx0[r], s, taxes=[Tax(RA[r], B.txhom[r])])
        end)
    end

    for r in R
        @demand(MGE, RA[r], begin
            @final_demand(PW[r], g("cons0", (r,)) + B.inv0[r])
            @endowment(PK[r], K0[r] * gprod[r])
            @endowment(PL[r], L0[r] * gprod[r])
            [@endowment(PF[i, r], (i in FF ? 1.0 : gprod[r]) * FF0[i, r]) for i in I]...
            [@endowment(PFr[t, r], 1.0 * FFe[t, r]) for t in TECH_NHR]...
            @endowment(PU[:usa], 1.0 * SAV[r])
            @endowment(PG[r], -GRG[r])
            @endowment(PHOM[r], B.homadj[r])
            @endowment(PT, B.trnadj[r])
        end)
    end

    for r in R
        ex = sum((1 + g("tx", (i, r, rr))) * PD[i, r] * TFL[(rr, r, i)] * g("wtflow0", (rr, r, i))
                 for rr in R for i in I if i != :oil && g("wtflow0", (rr, r, i)) > 0; init=0)
        im = sum((1 + g("tx", (i, rr, r))) * PD[i, rr] * TFL[(r, rr, i)] * g("wtflow0", (r, rr, i))
                 for rr in R for i in I if i != :oil && g("wtflow0", (r, rr, i)) > 0; init=0)
        hx = B.homx0[r] > 0 ? PWH * B.homx0[r] * HOMX[r] : 0
        hm = B.homm0[r] > 0 ? PWH * B.homm0[r] * MQ[r] : 0
        @aux_constraint(MGE, rgdp[r],
            PU[r] * rgdp[r] - (PU[r] * g("cons0", (r,)) * Z[r] + B.inv0[r] * PINV[r] * INV[r] + B.g0[r] * PG[r] * GOVT[r] + ex - im + hx - hm))
        @aux_constraint(MGE, gprod[r], rgdp[r] - GDP0[r])
    end

    fix(PU[:usa], 1.0)
    state = (; MGE, R, K0, L0, SAV, GRG, GDP0, gprod, rgdp,
        kapital0 = copy(B.kapital), labor0 = copy(B.labor),
        labor_pre = Dict(r => sum(g("labd0", (r, i)) for i in I) + g("labdg0", (r,)) for r in R),
        inv0 = copy(B.inv0), scale = Dict{Symbol,Float64}())
    srve0 = (1 - DPE)^5
    for r in R
        state.scale[r] = (state.kapital0[r] - state.kapital0[r] * srve0) / (0.95 * ROR * state.inv0[r])
    end
    return MGE, state
end
