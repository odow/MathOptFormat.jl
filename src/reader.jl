"""
    MOI.SolverInstance(mf::MOFInstance, solver)

Create a new MathOptInterface solver instance using `solver` from the MOFInstance `mf`
"""
function MOI.SolverInstance(mf::MOFInstance, solver)
    m = MOI.SolverInstance(solver)
    v = MOI.addvariables!(m, length(mf["variables"]))
    empty!(mf.namemap)
    for (i, dict) in enumerate(mf["variables"])
        mf.namemap[dict["name"]] = v[i]
        MOI.set!(m, MOI.VariableName(), v[i], dict["name"])
        if haskey(dict, "VariablePrimalStart")
            MOI.set!(m, MOI.VariablePrimalStart(), v[i], dict["VariablePrimalStart"])
        end
    end
    sense = MOI.get(mf, MOI.ObjectiveSense())
    MOI.set!(m, MOI.ObjectiveFunction(), parse!(mf, mf["objective"]))
    MOI.set!(m, MOI.ObjectiveSense(), sense)
    for con in mf["constraints"]
        c = MOI.addconstraint!(m, parse!(mf, con["function"]), parse!(mf, con["set"]))
        MOI.set!(m, MOI.ConstraintName(), c, con["name"])
        if haskey(con, "ConstraintPrimalStart")
            MOI.set!(m, MOI.ConstraintPrimalStart(), c, con["ConstraintPrimalStart"])
        end
        if haskey(con, "ConstraintDualStart")
            MOI.set!(m, MOI.ConstraintDualStart(), c, con["ConstraintDualStart"])
        end
    end
    m
end

"""
    MOI.SolverInstance(file::String, solver)

Create a new MathOptInterface solver instance using `solver` from the MOFInstance
located at the path `file`.
"""
MOI.SolverInstance(file::String, solver) = MOI.SolverInstance(MOFInstance(file), solver)

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
parse!(m::MOFInstance, obj::Object) = parse!(Val{Symbol(obj["head"])}(), m, obj)

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
