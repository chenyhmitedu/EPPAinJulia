"""
    write_report(path, rows, eesec_ts, sco2_ts, ftotco2_ts, aeei_ts, co2p_ts; ejuse0_ts = nothing, ejuse_all0_ts = nothing, ejuse_all_ts = nothing, ejuse_ts = nothing, ejuse_over_euse_ts = nothing, cr_ts = nothing, ejadj_ts = nothing, elecint_ts = nothing, eprod__over_xp0__ts = nothing, eprod_over_xp0_ts = nothing, xp0_ts = nothing, xp0__ts = nothing, tele0_ts = nothing, td_ts = nothing)

Write the scenario workbook. Sheets are `EE`, `SCO2`, `FTOTCO2`, `AEEI`, `co2p`, and `solve_status`.
When provided, benchmark sheets `ejuse0`, `ejuse_all0`, `ejuse_all`, `ejuse`, `ejuse_over_euse`, `cr`, `ejadj`, `elecint`, `eprod__over_xp0_`, `eprod_over_xp0`, `xp0`, `xp0_`, `tele0`, and `td` are also written.
`co2p[r]` is `CP[r] / cscale[r] * 10^4`, in USD per tonne at base-year fuel prices. It is the same for every fuel and user.
"""
function write_report(path, rows, eesec_ts, sco2_ts, ftotco2_ts, aeei_ts, co2p_ts; ejuse0_ts = nothing, ejuse_all0_ts = nothing, ejuse_all_ts = nothing, ejuse_ts = nothing, ejuse_over_euse_ts = nothing, cr_ts = nothing, ejadj_ts = nothing, elecint_ts = nothing, eprod__over_xp0__ts = nothing, eprod_over_xp0_ts = nothing, xp0_ts = nothing, xp0__ts = nothing, tele0_ts = nothing, td_ts = nothing)
    XLSX.openxlsx(path, mode = "w") do xf
        ej = XLSX.addsheet!(xf, "EE")
        ej[1, 1] = "year"
        ej[1, 2] = "energy"
        ej[1, 3] = "user"
        ej[1, 4] = "region"
        ej[1, 5] = "eesec"
        for (i, (key, value)) in enumerate(sort!(collect(eesec_ts); by = x -> x.first))
            year, energy, user, region = key
            row = i + 1
            ej[row, 1] = year
            ej[row, 2] = String(energy)
            ej[row, 3] = String(user)
            ej[row, 4] = String(region)
            ej[row, 5] = value
        end

        csheet = XLSX.addsheet!(xf, "SCO2")
        csheet[1, 1] = "year"
        csheet[1, 2] = "energy"
        csheet[1, 3] = "user"
        csheet[1, 4] = "region"
        csheet[1, 5] = "sco2"
        for (i, (key, value)) in enumerate(sort!(collect(sco2_ts); by = x -> x.first))
            year, energy, user, region = key
            row = i + 1
            csheet[row, 1] = year
            csheet[row, 2] = String(energy)
            csheet[row, 3] = String(user)
            csheet[row, 4] = String(region)
            csheet[row, 5] = value
        end

        fsheet = XLSX.addsheet!(xf, "FTOTCO2")
        fsheet[1, 1] = "year"
        fsheet[1, 2] = "region"
        fsheet[1, 3] = "ftotco2"
        for (i, (key, value)) in enumerate(sort!(collect(ftotco2_ts); by = x -> x.first))
            year, region = key
            row = i + 1
            fsheet[row, 1] = year
            fsheet[row, 2] = String(region)
            fsheet[row, 3] = value
        end

        asheet = XLSX.addsheet!(xf, "AEEI")
        asheet[1, 1] = "year"
        asheet[1, 2] = "sector"
        asheet[1, 3] = "region"
        asheet[1, 4] = "aeei"
        for (i, (key, value)) in enumerate(sort!(collect(aeei_ts); by = x -> x.first))
            year, sector, region = key
            row = i + 1
            asheet[row, 1] = year
            asheet[row, 2] = String(sector)
            asheet[row, 3] = String(region)
            asheet[row, 4] = value
        end

        psheet = XLSX.addsheet!(xf, "co2p")
        psheet[1, 1] = "year"
        psheet[1, 2] = "region"
        psheet[1, 3] = "co2p"
        for (i, (key, value)) in enumerate(sort!(collect(co2p_ts); by = x -> x.first))
            year, region = key
            row = i + 1
            psheet[row, 1] = year
            psheet[row, 2] = String(region)
            psheet[row, 3] = value
        end

        if ejuse0_ts !== nothing
            bsheet = XLSX.addsheet!(xf, "ejuse0")
            bsheet[1, 1] = "energy"
            bsheet[1, 2] = "user"
            bsheet[1, 3] = "region"
            bsheet[1, 4] = "ejuse0"
            for (i, (key, value)) in enumerate(sort!(collect(ejuse0_ts); by = x -> x.first))
                energy, user, region = key
                row = i + 1
                bsheet[row, 1] = String(energy)
                bsheet[row, 2] = String(user)
                bsheet[row, 3] = String(region)
                bsheet[row, 4] = value
            end
        end

        if ejuse_all0_ts !== nothing
            allsheet = XLSX.addsheet!(xf, "ejuse_all0")
            allsheet[1, 1] = "energy"
            allsheet[1, 2] = "user"
            allsheet[1, 3] = "region"
            allsheet[1, 4] = "ejuse_all0"
            for (i, (key, value)) in enumerate(sort!(collect(ejuse_all0_ts); by = x -> x.first))
                energy, user, region = key
                row = i + 1
                allsheet[row, 1] = String(energy)
                allsheet[row, 2] = String(user)
                allsheet[row, 3] = String(region)
                allsheet[row, 4] = value
            end
        end

        if ejuse_all_ts !== nothing
            allsheet2 = XLSX.addsheet!(xf, "ejuse_all")
            allsheet2[1, 1] = "energy"
            allsheet2[1, 2] = "user"
            allsheet2[1, 3] = "region"
            allsheet2[1, 4] = "ejuse_all"
            for (i, (key, value)) in enumerate(sort!(collect(ejuse_all_ts); by = x -> x.first))
                energy, user, region = key
                row = i + 1
                allsheet2[row, 1] = String(energy)
                allsheet2[row, 2] = String(user)
                allsheet2[row, 3] = String(region)
                allsheet2[row, 4] = value
            end
        end

        if ejuse_ts !== nothing
            usheet = XLSX.addsheet!(xf, "ejuse")
            usheet[1, 1] = "energy"
            usheet[1, 2] = "user"
            usheet[1, 3] = "region"
            usheet[1, 4] = "ejuse"
            for (i, (key, value)) in enumerate(sort!(collect(ejuse_ts); by = x -> x.first))
                energy, user, region = key
                row = i + 1
                usheet[row, 1] = String(energy)
                usheet[row, 2] = String(user)
                usheet[row, 3] = String(region)
                usheet[row, 4] = value
            end
        end

        if ejuse_over_euse_ts !== nothing
            rsheet = XLSX.addsheet!(xf, "ejuse_over_euse")
            rsheet[1, 1] = "energy"
            rsheet[1, 2] = "user"
            rsheet[1, 3] = "region"
            rsheet[1, 4] = "ejuse_over_euse"
            for (i, (key, value)) in enumerate(sort!(collect(ejuse_over_euse_ts); by = x -> x.first))
                energy, user, region = key
                row = i + 1
                rsheet[row, 1] = String(energy)
                rsheet[row, 2] = String(user)
                rsheet[row, 3] = String(region)
                rsheet[row, 4] = value
            end
        end

        if elecint_ts !== nothing
            esheet = XLSX.addsheet!(xf, "elecint")
            esheet[1, 1] = "tech"
            esheet[1, 2] = "input"
            esheet[1, 3] = "region"
            esheet[1, 4] = "elecint"
            for (i, (key, value)) in enumerate(sort!(collect(elecint_ts); by = x -> x.first))
                tech, input, region = key
                row = i + 1
                esheet[row, 1] = String(tech)
                esheet[row, 2] = String(input)
                esheet[row, 3] = String(region)
                esheet[row, 4] = value
            end
        end

        if eprod__over_xp0__ts !== nothing
            psheet = XLSX.addsheet!(xf, "eprod__over_xp0_")
            psheet[1, 1] = "tech"
            psheet[1, 2] = "region"
            psheet[1, 3] = "eprod__over_xp0_"
            for (i, (key, value)) in enumerate(sort!(collect(eprod__over_xp0__ts); by = x -> x.first))
                tech, region = key
                row = i + 1
                psheet[row, 1] = String(tech)
                psheet[row, 2] = String(region)
                psheet[row, 3] = value
            end
        end

        if eprod_over_xp0_ts !== nothing
            psheet2 = XLSX.addsheet!(xf, "eprod_over_xp0")
            psheet2[1, 1] = "region"
            psheet2[1, 2] = "eprod_over_xp0"
            for (i, (key, value)) in enumerate(sort!(collect(eprod_over_xp0_ts); by = x -> x.first))
                region = key
                row = i + 1
                psheet2[row, 1] = String(region)
                psheet2[row, 2] = value
            end
        end

        if xp0_ts !== nothing
            xsheet = XLSX.addsheet!(xf, "xp0")
            xsheet[1, 1] = "region"
            xsheet[1, 2] = "sector"
            xsheet[1, 3] = "xp0"
            for (i, (key, value)) in enumerate(sort!(collect(xp0_ts); by = x -> x.first))
                region, sector = key
                row = i + 1
                xsheet[row, 1] = String(region)
                xsheet[row, 2] = String(sector)
                xsheet[row, 3] = value
            end
        end

        if xp0__ts !== nothing
            xsheet2 = XLSX.addsheet!(xf, "xp0_")
            xsheet2[1, 1] = "tech"
            xsheet2[1, 2] = "region"
            xsheet2[1, 3] = "xp0_"
            for (i, (key, value)) in enumerate(sort!(collect(xp0__ts); by = x -> x.first))
                tech, region = key
                row = i + 1
                xsheet2[row, 1] = String(tech)
                xsheet2[row, 2] = String(region)
                xsheet2[row, 3] = value
            end
        end

        if tele0_ts !== nothing
            tsheet = XLSX.addsheet!(xf, "tele0")
            tsheet[1, 1] = "region"
            tsheet[1, 2] = "tele0"
            for (i, (key, value)) in enumerate(sort!(collect(tele0_ts); by = x -> x.first))
                region = key
                row = i + 1
                tsheet[row, 1] = String(region)
                tsheet[row, 2] = value
            end
        end

        if td_ts !== nothing
            tdsheet = XLSX.addsheet!(xf, "td")
            tdsheet[1, 1] = "region"
            tdsheet[1, 2] = "sector"
            tdsheet[1, 3] = "td"
            for (i, (key, value)) in enumerate(sort!(collect(td_ts); by = x -> x.first))
                region, sector = key
                row = i + 1
                tdsheet[row, 1] = String(region)
                tdsheet[row, 2] = String(sector)
                tdsheet[row, 3] = value
            end
        end

        if cr_ts !== nothing
            crsheet = XLSX.addsheet!(xf, "cr")
            crsheet[1, 1] = "context"
            crsheet[1, 2] = "region"
            crsheet[1, 3] = "cr"
            for (i, (key, value)) in enumerate(sort!(collect(cr_ts); by = x -> x.first))
                context, region = key
                row = i + 1
                crsheet[row, 1] = String(context)
                crsheet[row, 2] = String(region)
                crsheet[row, 3] = value
            end
        end

        if ejadj_ts !== nothing
            jsheet = XLSX.addsheet!(xf, "ejadj")
            jsheet[1, 1] = "energy"
            jsheet[1, 2] = "region"
            jsheet[1, 3] = "ejadj"
            for (i, (key, value)) in enumerate(sort!(collect(ejadj_ts); by = x -> x.first))
                energy, region = key
                row = i + 1
                jsheet[row, 1] = String(energy)
                jsheet[row, 2] = String(region)
                jsheet[row, 3] = value
            end
        end

        stsheet = XLSX.addsheet!(xf, "solve_status")
        stsheet[1, 1] = "year"
        stsheet[1, 2] = "region"
        stsheet[1, 3] = "gprod"
        stsheet[1, 4] = "rgdp"
        stsheet[1, 5] = "target"
        stsheet[1, 6] = "status"
        for (i, row) in enumerate(rows)
            r = i + 1
            stsheet[r, 1] = row.year
            stsheet[r, 2] = String(row.region)
            stsheet[r, 3] = row.gprod
            stsheet[r, 4] = row.rgdp
            stsheet[r, 5] = row.target
            stsheet[r, 6] = row.status
        end
    end
    return path
end
