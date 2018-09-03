function MOI.read_from_file(model::Model, filename::String)
    if !MOI.is_empty(model)
        error("Cannot read model from file as destination model is not empty.")
    end
    object = open(filename, "r") do io
        JSON.parse(io; dicttype=Object)
    end
    name_map = read_variables(model, object)
    read_objectives(model, object, name_map)
    read_constraints(model, object, name_map)
    return
end

function read_variables(model::Model, object::Object)
    indices = MOI.add_variables(model, length(object["variables"]))
    name_map = Dict{String, MOI.VariableIndex}()
    for (index, variable) in zip(indices, object["variables"])
        name = variable["name"]
        MOI.set(model, MOI.VariableName(), index, name)
        name_map[name] = index
    end
    return name_map
end

function read_objectives(model::Model, object::Object,
                         name_map::Dict{String, MOI.VariableIndex})
    if length(object["objectives"]) > 1
        error("Multi-objective models not supported.")
    end
    objective = first(object["objectives"])
    MOI.set(model, MOI.ObjectiveSense(),
            read_objective_sense(objective["sense"]))
    objective_type = MOI.get(model, MOI.ObjectiveFunctionType())
    MOI.set(model, MOI.ObjectiveFunction{objective_type}(),
            object_to_moi(objective["function"], model, name_map))
end

function read_constraints(model::Model, object::Object,
                          name_map::Dict{String, MOI.VariableIndex})
    for constraint in object["constraints"]
        foo = object_to_moi(constraint["function"], model, name_map)
        set = object_to_moi(constraint["set"], model, name_map)
        index = MOI.add_constraint(model, foo, set)
        MOI.set(model, MOI.ConstraintName(), index, constraint["name"])
    end
end

"""
    object_to_moi(x::OrderedDict, model::Model)

Convert `x` from an OrderedDict representation into a MOI representation.
"""
function object_to_moi(x::Object, args...)
    val_type = Val{Symbol(x["head"])}()
    return object_to_moi(val_type, x, args...)
end

"""
    parse_vector_or_default(terms, default_type, model::Model, name_map)

Try converting each term in `terms` to a MOI representation, otherwise return an
empty vector with eltype `default_type`.
"""
function parse_vector_or_default(terms, default_type, model::Model, name_map)
    if length(terms) == 0
        return default_type[]
    else
        return object_to_moi.(terms, Ref(model), Ref(name_map))
    end
end

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

function object_to_moi(::Val{:SingleVariable}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
    return MOI.SingleVariable(name_map[object["variable"]])
end

# ========== Typed scalar functions ==========

function object_to_moi(::Val{:ScalarAffineTerm}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
    return MOI.ScalarAffineTerm(
                object["coefficient"],
                name_map[object["variable_index"]])
end

function object_to_moi(::Val{:ScalarAffineFunction}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
    terms = parse_vector_or_default(object["terms"],
                                    MOI.ScalarAffineTerm{Float64},
                                    model, name_map)
    return MOI.ScalarAffineFunction(terms, object["constant"])
end

function object_to_moi(::Val{:ScalarQuadraticTerm}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
    return MOI.ScalarQuadraticTerm(
                object["coefficient"],
                name_map[object["variable_index_1"]],
                name_map[object["variable_index_2"]])
end

function object_to_moi(::Val{:ScalarQuadraticFunction}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
   affine_terms = parse_vector_or_default(object["affine_terms"],
                       MOI.ScalarAffineTerm{Float64}, model, name_map)
   quadratic_terms = parse_vector_or_default(object["quadratic_terms"],
                       MOI.ScalarQuadraticTerm{Float64}, model, name_map)
    return MOI.ScalarQuadraticFunction(affine_terms, quadratic_terms,
                                       object["constant"])
end

# ========== Non-typed vector functions ==========

function object_to_moi(::Val{:VectorOfVariables}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
    return MOI.VectorOfVariables(
                [name_map[variable] for variable in object["variables"]])
end

# ========== Typed vector functions ==========

function object_to_moi(::Val{:VectorAffineTerm}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
    return MOI.VectorAffineTerm(
                object["output_index"],
                object_to_moi(object["scalar_term"], model, name_map))
end

function object_to_moi(::Val{:VectorAffineFunction}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
   terms = parse_vector_or_default(object["terms"],
               MOI.VectorAffineTerm{Float64}, model, name_map)
    return MOI.VectorAffineFunction(terms, Float64.(object["constants"]))
end

function object_to_moi(::Val{:VectorQuadraticTerm}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
    return MOI.VectorQuadraticTerm(
                object["output_index"],
                object_to_moi(object["scalar_term"], model, name_map))
end

function object_to_moi(::Val{:VectorQuadraticFunction}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
   affine_terms = parse_vector_or_default(object["affine_terms"],
                       MOI.VectorAffineTerm{Float64}, model, name_map)
   quadratic_terms = parse_vector_or_default(object["quadratic_terms"],
                         MOI.VectorQuadraticTerm{Float64}, model, name_map)
    return MOI.VectorQuadraticFunction(affine_terms, quadratic_terms,
                                       Float64.(object["constants"]))
end

# ========== Default fallback ==========
"""
    set_info(::Type{Val{HeadName}}) where HeadName

Return a tuple of the corresponding MOI set and an ordered list of fieldnames.

`HeadName` is a symbol of the string returned by `head_name(set)`.

    HeadName = Symbol(head_name(set))
    typeof(set_info(Val{HeadName})[1]) == typeof(set)
"""
function set_info(::Type{Val{SetSymbol}}) where SetSymbol
    error("Version $(VERSION) of MathOptFormat does not support the set " *
          "$(SetType).")
end

function object_to_moi(::Val{SetSymbol}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex}) where SetSymbol
    args = set_info(Val{SetSymbol})
    SetType = args[1]
    if length(args) > 1
        return SetType([object[key] for key in args[2:end]]...)
    else
        return SetType()
    end
end

function object_to_moi(::Val{:SOS1}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
    return MOI.SOS1(Float64.(object["weights"]))
end
function object_to_moi(::Val{:SOS2}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
    return MOI.SOS2(Float64.(object["weights"]))
end


# ========== Non-typed scalar sets ==========
set_info(::Type{Val{:ZeroOne}}) = (MOI.ZeroOne,)
set_info(::Type{Val{:Integer}}) = (MOI.Integer,)

# ========== Typed scalar sets ==========
set_info(::Type{Val{:LessThan}}) = (MOI.LessThan, "upper")
set_info(::Type{Val{:GreaterThan}}) = (MOI.GreaterThan, "lower")
set_info(::Type{Val{:EqualTo}}) = (MOI.EqualTo, "value")
set_info(::Type{Val{:Interval}}) = (MOI.Interval, "lower", "upper")
set_info(::Type{Val{:Semiinteger}}) = (MOI.Semiinteger, "lower", "upper")
set_info(::Type{Val{:Semicontinuous}}) = (MOI.Semicontinuous, "lower", "upper")

# ========== Non-typed vector sets ==========
set_info(::Type{Val{:Zeros}}) = (MOI.Zeros, "dimension")
set_info(::Type{Val{:Reals}}) = (MOI.Reals, "dimension")
set_info(::Type{Val{:Nonnegatives}}) = (MOI.Nonnegatives, "dimension")
set_info(::Type{Val{:Nonpositives}}) = (MOI.Nonpositives, "dimension")
set_info(::Type{Val{:SecondOrderCone}}) = (MOI.SecondOrderCone, "dimension")
function set_info(::Type{Val{:RotatedSecondOrderCone}})
    return MOI.RotatedSecondOrderCone, "dimension"
end
set_info(::Type{Val{:GeometricMeanCone}}) = (MOI.GeometricMeanCone, "dimension")
function set_info(::Type{Val{:RootDetConeTriangle}})
    return MOI.RootDetConeTriangle, "side_dimension"
end
function set_info(::Type{Val{:RootDetConeSquare}})
    return MOI.RootDetConeSquare, "side_dimension"
end
function set_info(::Type{Val{:LogDetConeTriangle}})
    return MOI.LogDetConeTriangle, "side_dimension"
end
function set_info(::Type{Val{:LogDetConeSquare}})
    return MOI.LogDetConeSquare, "side_dimension"
end
function set_info(::Type{Val{:PositiveSemidefiniteConeTriangle}})
    return MOI.PositiveSemidefiniteConeTriangle, "side_dimension"
end
function set_info(::Type{Val{:PositiveSemidefiniteConeSquare}})
    return MOI.PositiveSemidefiniteConeSquare, "side_dimension"
end
set_info(::Type{Val{:ExponentialCone}}) = (MOI.ExponentialCone, )
set_info(::Type{Val{:DualExponentialCone}}) = (MOI.DualExponentialCone, )

# ========== Typed vector sets ==========
set_info(::Type{Val{:PowerCone}}) = (MOI.PowerCone, "exponent")
set_info(::Type{Val{:DualPowerCone}}) = (MOI.DualPowerCone, "exponent")
