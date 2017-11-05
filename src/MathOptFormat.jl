module MathOptFormat

using JSON, DataStructures

using MathOptInterface
const MOI = MathOptInterface

# we use an ordered dict to make the JSON printing nicer
const Object = OrderedDict{String, Any}

mutable struct CurrentReference
    variable::UInt64
    constraint::UInt64
end
struct MOFInstance <: MOI.AbstractStandaloneInstance
    d::Object
    # an extension dictionary to help MOI reading/writing
    # should be improved later
    namemap::Dict{String, MOI.VariableReference}
    # varmap
    varmap::Dict{MOI.VariableReference, Int}
    # constrmap
    constrmap::Dict{UInt64, Int}
    current_reference::CurrentReference
end

MOFInstance() = MOFInstance(
    OrderedDict(
        "version" => "0.0",
        "sense"   => "min",
        "variables" => Object[],
        "objective" => Object(),
        "constraints" => Object[]
    ),
    Dict{String, MOI.VariableReference}(),
    Dict{MOI.VariableReference, Int}(),
    Dict{UInt64, Int}(),
    CurrentReference(UInt64(0), UInt64(0))
)


struct MOFWriter <: MOI.AbstractSolver end
MOI.SolverInstance(::MOFWriter) = MOFInstance()

"""
    MOFInstance(file::String)

Read a MOF file located at `file`

### Example

    MOFInstance("path/to/model.mof.json")
"""
function MOFInstance(file::String)
    d = open(file, "r") do io
        JSON.parse(io, dicttype=OrderedDict{String, Any})
    end
    MOFInstance(d, Dict{String, MOI.VariableReference}(), Dict{MOI.VariableReference, Int}(), Dict{UInt64, Int}(), CurrentReference(UInt64(0), UInt64(0)))
end

function MOI.read!(m::MOFInstance, file::String)
    d = open(file, "r") do io
        JSON.parse(io, dicttype=OrderedDict{String, Any})
    end
    if length(m["variables"]) > 0
        error("Unable to load the model from $(file). Instance is not empty!")
    end
    # delete everything in the current instance
    empty!(m.d)
    copy!(m.d, d)
end

# overload getset for m.d
Base.getindex(m::MOFInstance, key) = getindex(m.d, key)
Base.setindex!(m::MOFInstance, key, value) = setindex!(m.d, key, value)

function MOI.write(m::MOFInstance, io::IO, indent::Int=0)
    if indent > 0
        write(io, JSON.json(m.d, indent))
    else
        write(io, JSON.json(m.d))
    end
end
function MOI.write(m::MOFInstance, f::String, indent::Int=0)
    open(f, "w") do io
        MOI.write(m, io, indent)
    end
end

include("variables.jl")
include("sets.jl")
include("functions.jl")
include("constraints.jl")
include("attributes.jl")
include("reader.jl")

function MOI.supportsproblem(m::MOFWriter, obj, constraints::Vector)
    if !Base.method_exists(object!, (MOFInstance, obj))
        return false
    end
    for (f, s) in constraints
        if !(Base.method_exists(object!, (MOFInstance, f)) && Base.method_exists(object, (s,)))
            return false
        end
    end
    return true
end

end # module
