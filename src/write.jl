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

# ================================== Functions =================================

function write(foo::MOI.SingleVariable, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "SingleVariable",
        "variable" => name_map[foo.variable]
    )
end

function write(foo::MOI.ScalarAffineTerm{Float64}, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object(
        "head" => "ScalarAffineTerm",
        "variable_index" => name_map[foo.variable_index],
        "coefficient" => foo.coefficient
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

# ===================================== Sets ===================================

function write(set::MOI.LessThan{Float64}, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object("head" => "LessThan", "upper" => set.upper)
end

function write(set::MOI.GreaterThan{Float64}, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object("head" => "GreaterThan", "lower" => set.lower)
end

function write(set::MOI.EqualTo{Float64}, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object("head" => "EqualTo", "value" => set.value)
end

function write(set::MOI.Interval{Float64}, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object("head" => "Interval", "lower" => set.lower,
                  "upper" => set.upper)
end

function write(set::MOI.ZeroOne, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object("head" => "ZeroOne")
end

function write(set::MOI.Integer, model::MOFModel,
                   name_map::Dict{MOI.VariableIndex, String})
    return Object("head" => "Integer")
end
