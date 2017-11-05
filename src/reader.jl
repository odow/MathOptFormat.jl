"""
    MOFInstance(file::String)

Read a MOF file located at `file`

### Example

    MOFInstance("path/to/model.mof.json")
"""
function MOFInstance(file::String)
    m = MOFInstance()
    MOI.read!(m, file)
    m
end

function MOI.read!(m::MOFInstance, file::String)
    d = open(file, "r") do io
        JSON.parse(io, dicttype=OrderedDict{String, Any})
    end
    if length(m["variables"]) > 0
        error("Unable to load the model from $(file). Instance is not empty!")
    end
    src = MOFInstance(d, Dict{String, MOI.VariableReference}(), Dict{MOI.VariableReference, Int}(), Dict{UInt64, Int}(), CurrentReference(UInt64(0), UInt64(0)))
    # delete everything in the current instance
    empty!(m.d)
    m.d["version"]     = "0.0"
    m.d["sense"]       = "min"
    m.d["variables"]   = Object[]
    m.d["objective"]   = Object("head"=>"ScalarAffineFunction", "variables"=>String[], "coefficients"=>Float64[], "constant"=>0.0)
    m.d["constraints"] = Object[]
    MOI.copy!(m, src)
end

function tryset!(dest, dict, ref, attr, str)
    if haskey(dict, str) && MOI.canset(dest, attr, ref)
        MOI.set!(dest, attr, ref, dict[str])
    end
end

function MOI.copy!(dest::MOI.AbstractInstance, src::MOFInstance)
    v = MOI.addvariables!(dest, length(src["variables"]))
    empty!(src.namemap)
    for (i, dict) in enumerate(src["variables"])
        src.namemap[dict["name"]] = v[i]
        tryset!(dest, dict, v[i], MOI.VariableName(), "name")
        tryset!(dest, dict, v[i], MOI.VariablePrimalStart(), "VariablePrimalStart")
    end
    sense = MOI.get(src, MOI.ObjectiveSense())
    MOI.set!(dest, MOI.ObjectiveFunction(), parse!(src, src["objective"]))
    MOI.set!(dest, MOI.ObjectiveSense(), sense)
    for con in src["constraints"]
        func = parse!(src, con["function"])
        set  = parse!(src, con["set"])
        if MOI.canaddconstraint(dest, func, set)
            c = MOI.addconstraint!(dest, func, set)
            tryset!(dest, con, c, MOI.ConstraintName(), "name")
            tryset!(dest, con, c, MOI.ConstraintPrimalStart(), "ConstraintPrimalStart")
            tryset!(dest, con, c, MOI.ConstraintDualStart(), "ConstraintDualStart")
        else
            error("Unable to add the constraint of type ($(func["head"]), $(set["head"]))")
        end
    end
    dest
end

#=
    Parse Function objects to MathOptInterface representation
=#

vvec(m::MOFInstance, names::Vector) = MOI.VariableReference[m.namemap[n] for n in names]

# we need to do this because float.(Any[]) returns Any[] rather than Float64[]
floatify(x::Vector{Float64}) = x
floatify(x::Float64) = x
function floatify(x::Vector)
    if length(x) == 0
        Float64[]
    else
        floatify.(x)
    end
end
floatify(x) = Float64(x)

# dispatch on "head" Val types to avoid a big if .. elseif ... elseif ... end
function parse!(m::MOFInstance, obj::Object)
    parse!(Val{Symbol(obj["head"])}(), m, obj)
end

function parse!(::Val{:SingleVariable}, m::MOFInstance, f::Object)
    MOI.SingleVariable(
        m.namemap[f["variable"]]
    )
end

function parse!(::Val{:VectorOfVariables}, m::MOFInstance, f::Object)
    MOI.VectorOfVariables(
        vvec(m, f["variables"])
    )
end

function parse!(::Val{:ScalarAffineFunction}, m::MOFInstance, f::Object)
    MOI.ScalarAffineFunction(
        vvec(m, f["variables"]),
        floatify(f["coefficients"]),
        floatify(f["constant"])
    )
end

function parse!(::Val{:VectorAffineFunction}, m::MOFInstance, f::Object)
    MOI.VectorAffineFunction(
        Int.(f["outputindex"]),
        vvec(m, f["variables"]),
        floatify(f["coefficients"]),
        floatify(f["constant"])
    )
end

function parse!(::Val{:ScalarQuadraticFunction}, m::MOFInstance, f::Object)
    MOI.ScalarQuadraticFunction(
        vvec(m, f["affine_variables"]),
        floatify(f["affine_coefficients"]),
        vvec(m, f["quadratic_rowvariables"]),
        vvec(m, f["quadratic_colvariables"]),
        floatify(f["quadratic_coefficients"]),
        floatify(f["constant"])
    )
end

function parse!(::Val{:VectorQuadraticFunction}, m::MOFInstance, f::Object)
    MOI.VectorQuadraticFunction(
        Int.(f["affine_outputindex"]),
        vvec(m, f["affine_variables"]),
        floatify(f["affine_coefficients"]),
        Int.(f["quadratic_outputindex"]),
        vvec(m, f["quadratic_rowvariables"]),
        vvec(m, f["quadratic_colvariables"]),
        floatify(f["quadratic_coefficients"]),
        floatify(f["constant"])
    )
end

#=
    Parse Set objects to MathOptInterface representation
=#

parse!(::Val{:EqualTo}, m, set)        = MOI.EqualTo(set["value"])
parse!(::Val{:LessThan}, m, set)       = MOI.LessThan(set["upper"])
parse!(::Val{:GreaterThan}, m, set)    = MOI.GreaterThan(set["lower"])
parse!(::Val{:Interval}, m, set)       = MOI.Interval(set["lower"], set["upper"])
parse!(::Val{:Integer}, m, set)        = MOI.Integer()
parse!(::Val{:ZeroOne}, m, set)        = MOI.ZeroOne()
parse!(::Val{:Reals}, m, set)          = MOI.Reals(set["dimension"])
parse!(::Val{:Zeros}, m, set)          = MOI.Zeros(set["dimension"])
parse!(::Val{:Nonnegatives}, m, set)   = MOI.Nonnegatives(set["dimension"])
parse!(::Val{:Nonpositives}, m, set)   = MOI.Nonpositives(set["dimension"])
parse!(::Val{:Semicontinuous}, m, set) = MOI.Semicontinuous(set["lower"], set["upper"])
parse!(::Val{:Semiinteger}, m, set)    = MOI.Semiinteger(set["lower"], set["upper"])
parse!(::Val{:SOS1}, m, set)           = MOI.SOS1(floatify(set["weights"]))
parse!(::Val{:SOS2}, m, set)           = MOI.SOS2(floatify(set["weights"]))
parse!(::Val{:SecondOrderCone}, m, set)                  = MOI.SecondOrderCone(set["dimension"])
parse!(::Val{:RotatedSecondOrderCone}, m, set)           = MOI.RotatedSecondOrderCone(set["dimension"])
parse!(::Val{:ExponentialCone}, m, set)                  = MOI.ExponentialCone()
parse!(::Val{:DualExponentialCone}, m, set)              = MOI.DualExponentialCone()
parse!(::Val{:PowerCone}, m, set)                        = MOI.PowerCone(floatify(set["exponent"]))
parse!(::Val{:DualPowerCone}, m, set)                    = MOI.DualPowerCone(floatify(set["exponent"]))
parse!(::Val{:PositiveSemidefiniteConeTriangle}, m, set) = MOI.PositiveSemidefiniteConeTriangle(set["dimension"])
parse!(::Val{:PositiveSemidefiniteConeScaled}, m, set)   = MOI.PositiveSemidefiniteConeScaled(set["dimension"])
