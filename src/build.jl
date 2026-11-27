function Build(data::NamedTuple, setting::Int64)

    apply_smooth!()
    MGE  = MPSGEModel()

    EPPACore(MGE, data, setting)

    # -1 is for benchmark calibration check
    if setting != -1    
        #Backstop(MGE, data)
    end

    return MGE

end
