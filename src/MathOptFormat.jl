module MathOptFormat

using MathOptInterface
const MOI = MathOptInterface
const MOIU = MOI.Utilities

include("MOF/MOF.jl")
include("MPS/MPS.jl")
include("CBF/CBF.jl")

# TODO delete after https://github.com/JuliaOpt/MathOptInterface.jl/issues/633
function MOI.read_from_file(model::MOI.ModelLike, filename::String)
    open(filename, "r") do io
        MOI.read_from_file(model, io)
    end
end
function MOI.write_to_file(model::MOI.ModelLike, filename::String)
    open(filename, "w") do io
        MOI.write_to_file(model, io)
    end
end

end
