function MOI.read(filename::String)
    model = MOFModel{Float64}()
    file = open(filename, "r") do io
        JSON.parse(io; dicttype=Object)
    end
    name_map = read_variables(file, model)
    read_objectives(file, model, name_map)
    read_constraints(file, model, name_map)
    return model
end

function read_variables(file, model)
    indices = MOI.addvariables!(model, length(file["variables"]))
    name_map = Dict{String, MOI.VariableIndex}()
    for (index, variable) in zip(indices, file["variables"])
        name = variable["name"]
        MOI.set!(model, MOI.VariableName(), index, name)
        name_map[name] = index
    end
    return name_map
end

function read_objectives(file, model, name_map)
    if length(file["objectives"]) > 1
        error("Multi-objective models not supported.")
    end
    objective = first(file["objectives"])
    MOI.set!(model, MOI.ObjectiveSense(),
             read_objective_sense(objective["sense"]))
    objective_type = MOI.get(model, MOI.ObjectiveFunctionType())
    MOI.set!(model, MOI.ObjectiveFunction{objective_type}(),
             read(objective["function"], model, name_map))
end

function read_constraints(file, model, name_map)
    for constraint in file["constraints"]
        foo = read(constraint["function"], model, name_map)
        set = read(constraint["set"], model, name_map)
        index = MOI.addconstraint!(model, foo, set)
        MOI.set!(model, MOI.ConstraintName(), index, constraint["name"])
    end
end

"""
    read(x::OrderedDict, model::MOFModel)

Convert `x` from an OrderedDict representation into a MOI representation.
"""
read(x::Object, args...) = read(Val{Symbol(x["head"])}(), x, args...)

function read_objective_sense(sense::String)
    if sense == "min"
        return MOI.MinSense
    elseif sense == "max"
        return MOI.MaxSense
    elseif sense == "feasibility"
        return MOI.FeasibilitySense
    end
    error("Unknown objective sense: $(sense)")
end

# ========== Non-typed scalar functions ==========

function read(::Val{:SingleVariable}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.SingleVariable(name_map[object["variable"]])
end

# ========== Typed scalar functions ==========

function read(::Val{:ScalarAffineTerm}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.ScalarAffineTerm(
                object["coefficient"],
                name_map[object["variable_index"]])
end

function read(::Val{:ScalarAffineFunction}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.ScalarAffineFunction(
                read.(object["terms"], Ref(model), Ref(name_map)),
                object["constant"])
end

function read(::Val{:ScalarQuadraticTerm}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.ScalarQuadraticTerm(
                object["coefficient"],
                name_map[object["variable_index_1"]],
                name_map[object["variable_index_2"]])
end

function read(::Val{:ScalarQuadraticFunction}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.ScalarQuadraticFunction(
                read.(object["affine_terms"], Ref(model), Ref(name_map)),
                read.(object["quadratic_terms"], Ref(model), Ref(name_map)),
                object["constant"])
end

# ========== Non-typed vector functions ==========

function read(::Val{:VectorOfVariables}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.VectorOfVariables(
                [name_map[variable] for variable in object["variables"]])
end

# ========== Typed vector functions ==========

function read(::Val{:VectorAffineTerm}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.VectorAffineTerm(
                object["output_index"],
                read(object["scalar_term"], model, name_map))
end

function read(::Val{:VectorAffineFunction}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.VectorAffineFunction(
                read.(object["terms"], Ref(model), Ref(name_map)),
                Float64.(object["constants"]))
end

function read(::Val{:VectorQuadraticTerm}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.VectorQuadraticTerm(
                object["output_index"],
                read(object["scalar_term"], model, name_map))
end

function read(::Val{:VectorQuadraticFunction}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.VectorQuadraticFunction(
                read.(object["affine_terms"], Ref(model), Ref(name_map)),
                read.(object["quadratic_terms"], Ref(model), Ref(name_map)),
                Float64.(object["constants"]))
end

# ========== Default fallback ==========
set_type(S) = error("MathOptFormat does not support the set $(S).")

# ========== Non-typed scalar sets ==========
set_type(::Type{Val{:ZeroOne}}) = (MOI.ZeroOne,)
set_type(::Type{Val{:Integer}}) = (MOI.Integer,)

# ========== Typed scalar sets ==========
set_type(::Type{Val{:LessThan}}) = (MOI.LessThan, "upper")
set_type(::Type{Val{:GreaterThan}}) = (MOI.GreaterThan, "lower")
set_type(::Type{Val{:EqualTo}}) = (MOI.EqualTo, "value")
set_type(::Type{Val{:Interval}}) = (MOI.Interval, "lower", "upper")
set_type(::Type{Val{:Semiinteger}}) = (MOI.Semiinteger, "lower", "upper")
set_type(::Type{Val{:Semicontinuous}}) = (MOI.Semicontinuous, "lower", "upper")

# ========== Non-typed vector sets ==========
set_type(::Type{Val{:Zeros}}) = (MOI.Zeros, "dimension")
set_type(::Type{Val{:Reals}}) = (MOI.Reals, "dimension")
set_type(::Type{Val{:Nonnegatives}}) = (MOI.Nonnegatives, "dimension")
set_type(::Type{Val{:Nonpositives}}) = (MOI.Nonpositives, "dimension")
set_type(::Type{Val{:SecondOrderCone}}) = (MOI.SecondOrderCone, "dimension")
function set_type(::Type{Val{:RotatedSecondOrderCone}})
    return MOI.RotatedSecondOrderCone, "dimension"
end
set_type(::Type{Val{:GeometricMeanCone}}) = (MOI.GeometricMeanCone, "dimension")
function set_type(::Type{Val{:RootDetConeTriangle}})
    return MOI.RootDetConeTriangle, "side_dimension"
end
function set_type(::Type{Val{:RootDetConeSquare}})
    return MOI.RootDetConeSquare, "side_dimension"
end
function set_type(::Type{Val{:LogDetConeTriangle}})
    return MOI.LogDetConeTriangle, "side_dimension"
end
function set_type(::Type{Val{:LogDetConeSquare}})
    return MOI.LogDetConeSquare, "side_dimension"
end
function set_type(::Type{Val{:PositiveSemidefiniteConeTriangle}})
    return MOI.PositiveSemidefiniteConeTriangle, "side_dimension"
end
function set_type(::Type{Val{:PositiveSemidefiniteConeSquare}})
    return MOI.PositiveSemidefiniteConeSquare, "side_dimension"
end
set_type(::Type{Val{:ExponentialCone}}) = (MOI.ExponentialCone, )
set_type(::Type{Val{:DualExponentialCone}}) = (MOI.DualExponentialCone, )

# ========== Typed vector sets ==========
set_type(::Type{Val{:PowerCone}}) = (MOI.PowerCone, "exponent")
set_type(::Type{Val{:DualPowerCone}}) = (MOI.DualPowerCone, "exponent")

function read(::Val{:SOS1}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.SOS1(Float64.(object["weights"]))
end
function read(::Val{:SOS2}, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex})
    return MOI.SOS2(Float64.(object["weights"]))
end

function read(::S, object::Object, model::MOFModel,
              name_map::Dict{String, MOI.VariableIndex}) where S
    args = set_type(S)
    SetType = args[1]
    if length(args) > 1
        return SetType([object[key] for key in args[2:end]]...)
    else
        return SetType()
    end
end
