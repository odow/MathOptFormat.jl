module MathOptFormat

using JSON, DataStructures
using TOML
using MathOptInterface
const MOI = MathOptInterface

# we use an ordered dict to make the JSON printing nicer
const Object = OrderedDict{String, Any}

struct MOFFile <: MOI.AbstractStandaloneInstance
    d::Object
    # an extension dictionary to help MOI reading/writing
    # should be improved later
    ext::Dict
    # constrmap
    constrmap::Dict{UInt64, Int}
end
MOFFile() = MOFFile(
    OrderedDict(
        "version" => "0.0",
        "sense"   => "min",
        "variables" => String[],
        "objective" => Object(),
        "constraints" => Object[]
    ),
    Dict(),
    Dict{UInt64, Int}()
)

struct MOFWriter <: MOI.AbstractSolver end
MOI.SolverInstance(::MOFWriter) = MOFFile()

"""
    MOFFile(file::String)

Read a MOF file located at `file`

### Example

    MOFFile("path/to/model.mof.json")
"""
function MOFFile(file::String)
    d = open(file, "r") do io
        TOM.parse(io)
        # JSON.parse(io, dicttype=OrderedDict{String, Any})
    end
    MOFFile(d, Dict{Any, Any}(), Dict{UInt64, Int}())
end

# overload getset for m.d
Base.getindex(m::MOFFile, key) = getindex(m.d, key)
Base.setindex!(m::MOFFile, key, value) = setindex!(m.d, key, value)

function MOI.writeproblem(m::MOFFile, io::IO, indent::Int=0)
    TOML.print(io, m.d)
    # if indent > 0
    #     write(io, JSON.json(m.d, indent))
    # else
    #     write(io, JSON.json(m.d))
    # end
end
function MOI.writeproblem(m::MOFFile, f::String, indent::Int=0)
    open(f, "w") do io
        MOI.writeproblem(m, io, indent)
    end
end

include("sets.jl")
include("functions.jl")
include("variables.jl")
include("constraints.jl")
include("objectives.jl")
include("reader.jl")

end # module
