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
    new_model(
        format::FileFormat, filename::Union{Nothing, String} = nothing
    )

Return model corresponding to the `FileFormat` `format`.

If `format == FORMAT_AUTOMATIC`, guess the format from the `filename`.
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
        @assert format == FORMAT_AUTOMATIC
        if filename === nothing
            error(
                "Unable to automatically detect file format. " *
                "No filename provided."
            )
        end
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

"""
    read_from_file(filename::String; format::FileFormat = FORMAT_AUTOMATIC)

Return a new MOI model by the file `filename` in the format `format`.
"""
function read_from_file(filename::String; format::FileFormat = FORMAT_AUTOMATIC)
    model = new_model(format, filename)
    MOI.read_from_file(model, filename)
    return model
end

end
