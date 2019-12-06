module MathOptFormat

import MathOptInterface
const MOI = MathOptInterface

import CodecBzip2
import CodecZlib

include("compression.jl")
include("CBF/CBF.jl")
include("LP/LP.jl")
include("MOF/MOF.jl")
include("MPS/MPS.jl")

"""
    create_unique_names(
        model::MOI.ModelLike;
        warn::Bool = false,
        replacements::Vector{Function} = Function[]
    )

Rename variables in `model` to ensure that all variables and constraints have
a unique name. In addition, loop through `replacements` and replace names with
`f(name)`.

If `warn`, print a warning if a variable or constraint is renamed.
"""
function create_unique_names(
    model::MOI.ModelLike;
    warn::Bool = false,
    replacements::Vector{Function} = Function[]
)
    create_unique_variable_names(model, warn, replacements)
    create_unique_constraint_names(model, warn, replacements)
    return
end

function _replace(s::String, replacements::Vector{Function})
    for f in replacements
        s = f(s)
    end
    return s
end

function create_unique_constraint_names(
    model::MOI.ModelLike, warn::Bool, replacements::Vector{Function}
)
    original_names = Set{String}()
    for (F, S) in MOI.get(model, MOI.ListOfConstraints())
        for index in MOI.get(model, MOI.ListOfConstraintIndices{F, S}())
            name = MOI.get(model, MOI.ConstraintName(), index)
            push!(original_names, _replace(name, replacements))
        end
    end
    added_names = Set{String}()
    for (F, S) in MOI.get(model, MOI.ListOfConstraints())
        for index in MOI.get(model, MOI.ListOfConstraintIndices{F, S}())
            original_name = MOI.get(model, MOI.ConstraintName(), index)
            new_name = _replace(
                original_name != "" ? original_name : "c$(index.value)",
                replacements
            )
            if new_name in added_names
                # We found a duplicate name! We could just append a string like
                # "_", but we're going to be clever and loop through the
                # integers to name them appropriately. Thus, if we have three
                # constraints named c, we'll end up with variables named c, c_1,
                # and c_2.
                i = 1
                tmp_name = string(new_name, "_", i)
                while tmp_name in added_names || tmp_name in original_names
                    i += 1
                    tmp_name = string(new_name, "_", i)
                end
                new_name = tmp_name
            end
            push!(added_names, new_name)
            if new_name != original_name
                if warn
                    if original_name == ""
                        @warn("Blank name detected for constraint $(index). " *
                              "Renamed to $(new_name).")
                    else
                        @warn("Duplicate name $(original_name) detected for " *
                              "constraint $(index). Renamed to $(new_name).")
                    end
                end
                MOI.set(model, MOI.ConstraintName(), index, new_name)
            end
        end
    end
end

function create_unique_variable_names(
    model::MOI.ModelLike, warn::Bool, replacements::Vector{Function}
)
    variables = MOI.get(model, MOI.ListOfVariableIndices())
    # This is a list of all of the names currently in the model. We're going to
    # use this to make sure we don't rename a variable to a name that already
    # exists.
    original_names = Set{String}([
        _replace(MOI.get(model, MOI.VariableName(), index), replacements)
        for index in variables
    ])
    # This set of going to store all of the names in the model so that we don't
    # add duplicates.
    added_names = Set{String}()
    for index in variables
        original_name = MOI.get(model, MOI.VariableName(), index)
        new_name = _replace(
            original_name != "" ? original_name : "x$(index.value)",
            replacements
        )
        if new_name in added_names
            # We found a duplicate name! We could just append a string like "_",
            # but we're going to be clever and loop through the integers to name
            # them appropriately. Thus, if we have three variables named x,
            # we'll end up with variables named x, x_1, and x_2.
            i = 1
            tmp_name = string(new_name, "_", i)
            while tmp_name in added_names || tmp_name in original_names
                i += 1
                tmp_name = string(new_name, "_", i)
            end
            new_name = tmp_name
        end
        push!(added_names, new_name)
        if new_name != original_name
            if warn
                if original_name == ""
                    @warn("Blank name detected for variable $(index). Renamed to " *
                          "$(new_name).")
                else
                    @warn("Duplicate name $(original_name) detected for variable " *
                          "$(index). Renamed to $(new_name).")
                end
            end
            MOI.set(model, MOI.VariableName(), index, new_name)
        end
    end
end

const MATH_OPT_FORMATS = Union{
    CBF.InnerModel,
    LP.InnerModel,
    MOF.Model,
    MPS.InnerModel
}

"""
    FileFormat

List of accepted export formats.

- `FORMAT_CBF`: the Conic Benchmark format
- `FORMAT_LP`: the LP file format
- `FORMAT_MOF`: the MathOptFormat file format
- `FORMAT_MPS`: the MPS file format
- `AUTOMATIC_FILE_FORMAT`: try to detect the file format based on the file name.
"""
@enum(
    FileFormat,
    AUTOMATIC_FILE_FORMAT,
    FORMAT_CBF,
    FORMAT_LP,
    FORMAT_MOF,
    FORMAT_MPS,
)

"""
    new_model(
        format::FileFormat, filename::Union{Nothing, String} = nothing
    )

Return model corresponding to the `FileFormat` `format`.

If `format == AUTOMATIC_FILE_FORMAT`, attempt to guess the format from the
`filename`.
"""
function new_model(
    format::FileFormat, filename::Union{Nothing, String} = nothing
)
    if format == FORMAT_CBF
        return CBF.Model()
    elseif format == FORMAT_LP
        return LP.Model()
    elseif format == FORMAT_MOF
        return MOF.Model()
    elseif format == FORMAT_MPS
        return MPS.Model()
    else
        @assert format == AUTOMATIC_FILE_FORMAT
        if filename === nothing
            error("Unable to automatically detect file format. No filename provided.")
        end
        for (ext, model) in [
            (".cbf", CBF.Model),
            (".lp", LP.Model),
            (".mof.json", MOF.Model),
            (".mps", MPS.Model)
        ]
            if endswith(filename, ext) || occursin(ext, filename)
                return model()
            end
        end
        error("Unable to detect automatically format of $(filename).")
    end
end

function MOI.write_to_file(
    model::MATH_OPT_FORMATS,
    filename::String;
    compression::AbstractCompressionScheme = AutomaticCompression()
)
    _compressed_open(filename, "w", compression) do io
        write(io, model)
    end
end

function MOI.read_from_file(
    model::MATH_OPT_FORMATS,
    filename::String;
    compression::AbstractCompressionScheme = AutomaticCompression()
)
    _compressed_open(filename, "r", compression) do io
        read!(io, model)
    end
end

"""
    read_from_file(
        filename::String;
        compression::AbstractCompressionScheme = AutomaticCompression(),
        file_format::FileFormat = AUTOMATIC_FILE_FORMAT,
    )

Return a new MOI model by reading `filename`.

Default arguments for `file_format` and `compression` will attempt to detect
model type from `filename`.
"""
function read_from_file(
    filename::String;
    compression::AbstractCompressionScheme = AutomaticCompression(),
    file_format::FileFormat = AUTOMATIC_FILE_FORMAT,
)
    model = new_model(file_format, filename)
    MOI.read_from_file(model, filename; compression = compression)
    return model
end

end
