module MathOptFormat

using MathOptInterface
const MOI = MathOptInterface
const MOIU = MOI.Utilities
import GZip

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

# Create a MathOptInterface model by reading in a CBF, MOF, or MPS file.
# The file may be GZipped (with extension `.gz`).
function read_into_model(filename::String)
    if endswith(filename, ".gz")
        io = GZip.open(filename, "r")
    else
        io = open(filename, "r")
    end
    if endswith(filename, ".mof.json.gz") || endswith(filename, ".mof.json")
        model = MathOptFormat.MOF.Model()
    elseif endswith(filename, ".cbf.gz") || endswith(filename, ".cbf")
        model = MathOptFormat.CBF.Model()
    elseif endswith(filename, ".mps.gz") || endswith(filename, ".mps")
        model = MathOptFormat.MPS.Model()
    else
        error("read_from_file is not implemented for this filetype: $filename")
    end
    MOI.read_from_file(model, io)
    return model
end

end
