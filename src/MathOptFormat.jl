module MathOptFormat

import MathOptInterface
const MOI = MathOptInterface

import CodecBzip2
import CodecZlib

include("utils.jl")

include("CBF/CBF.jl")
include("LP/LP.jl")
include("MOF/MOF.jl")
include("MPS/MPS.jl")

"""
    FileFormat

List of accepted export formats.

- `FORMAT_AUTOMATIC`: try to detect the file format based on the file name
- `FORMAT_CBF`: the Conic Benchmark format
- `FORMAT_LP`: the LP file format
- `FORMAT_MOF`: the MathOptFormat file format
- `FORMAT_MPS`: the MPS file format
"""
@enum(
    FileFormat,
    FORMAT_AUTOMATIC,
    FORMAT_CBF,
    FORMAT_LP,
    FORMAT_MOF,
    FORMAT_MPS,
)

"""
    Model(
        ;
        format::FileFormat = FORMAT_AUTOMATIC,
        filename::Union{Nothing, String} = nothing
    )

Return model corresponding to the `FileFormat` `format`, or, if
`format == FORMAT_AUTOMATIC`, guess the format from `filename`.

You must pass _one_ of `format` or `filename`. You cannot use both arguments.
"""
function Model(
    ;
    format::FileFormat = FORMAT_AUTOMATIC,
    filename::Union{Nothing, String} = nothing
)
    if format == FORMAT_AUTOMATIC && filename === nothing
        error("When `format == FORMAT_AUTOMATIC`, you must pass a `filename`.")
    elseif format != FORMAT_AUTOMATIC && filename !== nothing
        error("You cannot pass `format` and `filename` at the same time.")
    elseif format == FORMAT_CBF
        return CBF.Model()
    elseif format == FORMAT_LP
        return LP.Model()
    elseif format == FORMAT_MOF
        return MOF.Model()
    elseif format == FORMAT_MPS
        return MPS.Model()
    else
        @assert format == FORMAT_AUTOMATIC && filename !== nothing
        for (ext, model) in [
            (".cbf", CBF.Model),
            (".lp", LP.Model),
            (".mof.json", MOF.Model),
            (".mps", MPS.Model)
        ]
            if endswith(filename, ext) || occursin("$(ext).", filename)
                return model()
            end
        end
        error("Unable to automatically detect format of $(filename).")
    end
end

const MATH_OPT_FORMATS = Union{
    CBF.InnerModel,
    LP.InnerModel,
    MOF.Model,
    MPS.InnerModel
}

function MOI.write_to_file(model::MATH_OPT_FORMATS, filename::String)
    compressed_open(filename, "w", AutomaticCompression()) do io
        write(io, model)
    end
end

function MOI.read_from_file(model::MATH_OPT_FORMATS, filename::String)
    compressed_open(filename, "r", AutomaticCompression()) do io
        read!(io, model)
    end
end

end
