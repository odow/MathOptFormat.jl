function MOI.write(model::MOFModel, filename::String)
    file = Object(
        "name"        => "MathOptFormat Model",
        "version"     => VERSION,
        "variables"   => Object[],
        "objectives"  => Object[],
        "constraints" => Object[]
    )
    name_map = write_variables(file, model)
    write_objectives(file, model, name_map)
    write_constraints(file, model, name_map)
    open(filename, "w") do io
        Base.write(io, JSON.json(file, 2))
    end
end

function write_variables(file, model)
    name_map = Dict{MOI.VariableIndex, String}()
    for index in MOI.get(model, MOI.ListOfVariableIndices())
        variable = write(index, model)
        name_map[index] = variable["name"]
        push!(file["variables"], variable)
    end
    return name_map
end

function write_objectives(file, model, name_map)
    sense = MOI.get(model, MOI.ObjectiveSense())
    objective_type = MOI.get(model, MOI.ObjectiveFunctionType())
    objective_function = MOI.get(model, MOI.ObjectiveFunction{objective_type}())
    push!(file["objectives"], Object(
        "sense"    => write(sense),
        "function" => write(objective_function, model, name_map)
    ))
end

function write_constraints(file, model, name_map)
    for (F, S) in MOI.get(model, MOI.ListOfConstraints())
        for index in MOI.get(model, MOI.ListOfConstraintIndices{F,S}())
            push!(file["constraints"], write(index, model, name_map))
        end
    end
end

"""
    write(x, model::MOFModel)

Convert `x` into an OrderedDict representation.
"""
function write end

function write(index::MOI.VariableIndex, model::MOFModel)
    name = MOI.get(model, MOI.VariableName(), index)
    if name == ""
        name = "x$(index.value)"
    end
    return Object("name" => name)
end

function write(index::MOI.ConstraintIndex{F,S}, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String}) where {F, S}
    func = MOI.get(model, MOI.ConstraintFunction(), index)
    set = MOI.get(model, MOI.ConstraintSet(), index)
    name = MOI.get(model, MOI.ConstraintName(), index)
    return Object("function" => write(func, model, name_map),
                  "set"      => write(set, model, name_map),
                  "name"     => name)
end

function write(sense::MOI.OptimizationSense)
    if sense == MOI.MinSense
        return "min"
    elseif sense == MOI.MaxSense
        return "max"
    elseif sense == MOI.FeasibilitySense
        return "feasibility"
    end
    error("Unknown objective sense: $(sense)")
end

# ========== Non-typed scalar functions ==========

function write(foo::MOI.SingleVariable, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "SingleVariable",
        "variable" => name_map[foo.variable]
    )
end

# ========== Typed scalar functions ==========

function write(foo::MOI.ScalarAffineTerm{Float64}, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "ScalarAffineTerm",
        "coefficient" => foo.coefficient,
        "variable_index" => name_map[foo.variable_index]
    )
end

function write(foo::MOI.ScalarAffineFunction{Float64}, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "ScalarAffineFunction",
        "terms" => write.(foo.terms, Ref(model), Ref(name_map)),
        "constant" => foo.constant
    )
end

function write(foo::MOI.ScalarQuadraticTerm{Float64}, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "ScalarQuadraticTerm",
        "coefficient" => foo.coefficient,
        "variable_index_1" => name_map[foo.variable_index_1],
        "variable_index_2" => name_map[foo.variable_index_2]
    )
end

function write(foo::MOI.ScalarQuadraticFunction{Float64}, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "ScalarQuadraticFunction",
        "affine_terms" => write.(foo.affine_terms, Ref(model), Ref(name_map)),
        "quadratic_terms" => write.(foo.quadratic_terms, Ref(model), Ref(name_map)),
        "constant" => foo.constant
    )
end

# ========== Non-typed vector functions ==========

function write(foo::MOI.VectorOfVariables, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "VectorOfVariables",
        "variables" => [name_map[variable] for variable in foo.variables]
    )
end

# ========== Typed vector functions ==========

function write(foo::MOI.VectorAffineTerm, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "VectorAffineTerm",
        "output_index" => foo.output_index,
        "scalar_term" => write(foo.scalar_term, model, name_map)
    )
end

function write(foo::MOI.VectorAffineFunction, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "VectorAffineFunction",
        "terms" => write.(foo.terms, Ref(model), Ref(name_map)),
        "constants" => foo.constants
    )
end

function write(foo::MOI.VectorQuadraticTerm, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "VectorQuadraticTerm",
        "output_index" => foo.output_index,
        "scalar_term" => write(foo.scalar_term, model, name_map)
    )
end

function write(foo::MOI.VectorQuadraticFunction, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "VectorQuadraticFunction",
        "affine_terms" => write.(foo.affine_terms, Ref(model), Ref(name_map)),
        "quadratic_terms" => write.(foo.quadratic_terms, Ref(model), Ref(name_map)),
        "constants" => foo.constants
    )
end

# ========== Default fallback ==========
head_name(S) = error("MathOptFormat does not support the set $(S).")

# ========== Non-typed scalar sets ==========
head_name(::Type{MOI.ZeroOne}) = "ZeroOne"
head_name(::Type{MOI.Integer}) = "Integer"

# ========== Typed scalar sets ==========
head_name(::Type{<:MOI.LessThan}) = "LessThan"
head_name(::Type{<:MOI.GreaterThan}) = "GreaterThan"
head_name(::Type{<:MOI.EqualTo}) = "EqualTo"
head_name(::Type{<:MOI.Interval}) = "Interval"
head_name(::Type{<:MOI.Semiinteger}) = "Semiinteger"
head_name(::Type{<:MOI.Semicontinuous}) = "Semicontinuous"

# ========== Non-typed vector sets ==========
head_name(::Type{MOI.Zeros}) = "Zeros"
head_name(::Type{MOI.Reals}) = "Reals"
head_name(::Type{MOI.Nonnegatives}) = "Nonnegatives"
head_name(::Type{MOI.Nonpositives}) = "Nonpositives"
head_name(::Type{MOI.SecondOrderCone}) = "SecondOrderCone"
head_name(::Type{MOI.RotatedSecondOrderCone}) = "RotatedSecondOrderCone"
head_name(::Type{MOI.GeometricMeanCone}) = "GeometricMeanCone"
head_name(::Type{MOI.ExponentialCone}) = "ExponentialCone"
head_name(::Type{MOI.DualExponentialCone}) = "DualExponentialCone"
head_name(::Type{MOI.RootDetConeTriangle}) = "RootDetConeTriangle"
head_name(::Type{MOI.RootDetConeSquare}) = "RootDetConeSquare"
head_name(::Type{MOI.LogDetConeTriangle}) = "LogDetConeTriangle"
head_name(::Type{MOI.LogDetConeSquare}) = "LogDetConeSquare"
head_name(::Type{MOI.PositiveSemidefiniteConeTriangle}) = "PositiveSemidefiniteConeTriangle"
head_name(::Type{MOI.PositiveSemidefiniteConeSquare}) = "PositiveSemidefiniteConeSquare"

# ========== Typed vector sets ==========
head_name(::Type{<:MOI.PowerCone}) = "PowerCone"
head_name(::Type{<:MOI.DualPowerCone}) = "DualPowerCone"
head_name(::Type{<:MOI.SOS1}) = "SOS1"
head_name(::Type{<:MOI.SOS2}) = "SOS2"

function write(set::S, model::MOFModel,
               name_map::Dict{MOI.VariableIndex, String}) where S
    object = Object("head" => head_name(S))
    for key in fieldnames(S)
        object[string(key)] = getfield(set, key)
    end
    return object
end
