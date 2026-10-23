"""
    write_report(path, rows, eesec_ts, sco2_ts, aeei_ts)

Write the scenario workbook. Sheets are `EESEC`, `SCO2`, `AEEI`, and `solve_status`.
"""
function write_report(path, rows, eesec_ts, sco2_ts, aeei_ts)
    XLSX.openxlsx(path, mode = "w") do xf
        ej = XLSX.addsheet!(xf, "EESEC")
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
