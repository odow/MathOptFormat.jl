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

# ================================== Functions =================================

function read(::Val{:SingleVariable}, object::Object, model::MOFModel,
                   name_map::Dict{String, MOI.VariableIndex})
    return MOI.SingleVariable(name_map[object["variable"]])
end

function read(::Val{:ScalarAffineTerm}, object::Object, model::MOFModel,
                   name_map::Dict{String, MOI.VariableIndex})
    return MOI.ScalarAffineTerm(object["coefficient"],
                                name_map[object["variable_index"]])
end


function read(::Val{:ScalarAffineFunction}, object::Object, model::MOFModel,
                   name_map::Dict{String, MOI.VariableIndex})
    return MOI.ScalarAffineFunction(
                read.(object["terms"], Ref(model), Ref(name_map)),
                object["constant"])
end

# ===================================== Sets ===================================

function read(::Val{:LessThan}, object::Object, model::MOFModel,
                   name_map::Dict{String, MOI.VariableIndex})
    return MOI.LessThan(object["upper"])
end

function read(::Val{:GreaterThan}, object::Object, model::MOFModel,
                   name_map::Dict{String, MOI.VariableIndex})
    return MOI.GreaterThan(object["lower"])
end

function read(::Val{:EqualTo}, object::Object, model::MOFModel,
                   name_map::Dict{String, MOI.VariableIndex})
    return MOI.EqualTo(object["value"])
end

function read(::Val{:Interval}, object::Object, model::MOFModel,
                   name_map::Dict{String, MOI.VariableIndex})
    return MOI.Interval(object["lower"], object["upper"])
end

function read(::Val{:ZeroOne}, object::Object, model::MOFModel,
                   name_map::Dict{String, MOI.VariableIndex})
    return MOI.ZeroOne()
end

function read(::Val{:Integer}, object::Object, model::MOFModel,
                   name_map::Dict{String, MOI.VariableIndex})
    return MOI.Integer()
end
