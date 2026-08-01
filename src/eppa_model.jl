function EPPA_model(data::Dict, setting::Int64)

    MGE  = MPSGEModel()

    EPPACore(MGE, data, setting)

    # -1 is for benchmark calibration check
    if setting != -1    
        #Backstop(MGE, data)
    end

    return MGE

end
