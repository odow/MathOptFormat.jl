module LP

import ..MathOptFormat

import MathOptInterface
const MOI = MathOptInterface
const MOIU = MOI.Utilities

MOIU.@model(InnerLPModel,
    (MOI.ZeroOne, MOI.Integer),
    (MOI.EqualTo, MOI.GreaterThan, MOI.LessThan, MOI.Interval),
    (),
    (),
    (MOI.SingleVariable,),
    (MOI.ScalarAffineFunction,),
    (),
    ()
)

const Model = InnerLPModel{Float64}

function Base.show(io::IO, ::Model)
    print(io, "A .LP-file model")
    return
end

# ==============================================================================
#
#   MOI.write_to_file
#
# ==============================================================================


const MAX_LENGTH = 255
# 16 for lp_solve 5.0: http://lpsolve.sourceforge.net/5.0/CPLEX-format.htm
# 255 for CPLEX 12.5: https://www.ibm.com/support/knowledgecenter/SS9UKU_12.5.0/com.ibm.cplex.zos.help/FileFormats/topics/LP.html
const START_REG = r"^([\.0-9eE])"
const NAME_REG = r"([^a-zA-Z0-9\!\"\#\$\%\&\(\)\/\,\.\;\?\@\_\`\'\{\}\|\~])"

function sanitized_name(name::String)
    m = match(START_REG, name)
    if m !== nothing
        plural = length(m.match) > 1
        @warn("Name $(name) cannot start with a period, a number, e, or E. " *
              "Prepending an underscore to name.")
        return correctname("_" * name)
    end

    m = match(NAME_REG, name)
    if m !== nothing
        plural = length(m.match) > 1
        @warn("Name $(name) contains $(ifelse(plural, "", "an "))" *
              "illegal character$(ifelse(plural, "s", "")): " *
              "\"$(m.match)\". Removing the offending " *
              "character$(ifelse(plural, "s", "")) from name.")
        return correctname(replace(name, NAME_REG => s"_"))
    end

    # Truncate at the end to fit as many characters as possible.
    if length(name) > MAX_LENGTH
        @warn("Name $(name) too long (length: $(length(name))). Truncating.")
        return correctname(String(name[1:MAX_LENGTH]))
    end
    return name
end

function write_function(io::IO, model::Model, func::MOI.SingleVariable)
    name = sanitized_name(MOI.get(model, MOI.VariableName(), func.variable))
    print(io, name)
    return
end

function write_function(io::IO, model::Model, func::MOI.ScalarAffineFunction{Float64})
    is_first_item = true
    if !(func.constant ≈ 0.0)
        Base.Grisu.print_shortest(io, func.constant)
        is_first_item = false
    end
    for term in func.terms
        if !(term.coefficient ≈ 0.0)
            if is_first_item
                Base.Grisu.print_shortest(io, term.coefficient)
                is_first_item = false
            else
                print(io, term.coefficient < 0 ? " - " : " + ")
                Base.Grisu.print_shortest(io, abs(term.coefficient))
            end

            varname = sanitized_name(MOI.get(model, MOI.VariableName(), term.variable_index))
            print(io, " ", varname)
        end
    end
    return
end

function write_constraint_suffix(io::IO, set::MOI.LessThan)
    print(io, " <= ", )
    Base.Grisu.print_shortest(io, set.upper)
    println(io)
    return
end

function write_constraint_suffix(io::IO, set::MOI.GreaterThan)
    print(io, " >= ", )
    Base.Grisu.print_shortest(io, set.lower)
    println(io)
    return
end

function write_constraint_suffix(io::IO, set::MOI.EqualTo)
    print(io, " = ", )
    Base.Grisu.print_shortest(io, set.value)
    println(io)
    return
end

function write_constraint_suffix(io::IO, set::MOI.Interval)
    print(io, " <= ", )
    Base.Grisu.print_shortest(io, set.upper)
    println(io)
    return
end

function write_constraint_prefix(io::IO, set::MOI.Interval)
    Base.Grisu.print_shortest(io, set.lower)
    print(io, " <= ")
    return
end

write_constraint_prefix(io::IO, set) = nothing

function write_constraint(io::IO, model::Model, index; write_name::Bool = true)
    func = MOI.get(model, MOI.ConstraintFunction(), index)
    set = MOI.get(model, MOI.ConstraintSet(), index)
    if write_name
        print(io, MOI.get(model, MOI.ConstraintName(), index), ": ")
    end
    write_constraint_prefix(io, set)
    write_function(io, model, func)
    write_constraint_suffix(io, set)
end

const SCALAR_SETS = (
    MOI.LessThan{Float64}, MOI.GreaterThan{Float64}, MOI.EqualTo{Float64},
    MOI.Interval{Float64}
)

function write_sense(io::IO, model::Model)
    if MOI.get(model, MOI.ObjectiveSense()) == MOI.MAX_SENSE
        println(io, "maximize")
    else
        println(io, "minimize")
    end
    return
end

function write_objective(io::IO, model::Model)
    print(io, "obj: ")
    obj_func_type = MOI.get(model, MOI.ObjectiveFunctionType())
    obj_func = MOI.get(model, MOI.ObjectiveFunction{obj_func_type}())
    write_function(io, model, obj_func)
    println(io)
    return
end

function MOI.write_to_file(model::Model, io::IO)
    MathOptFormat.create_unique_names(model)
    write_sense(io, model)
    write_objective(io, model)
    println(io, "subject to")
    for S in SCALAR_SETS
        for index in MOI.get(model, MOI.ListOfConstraintIndices{MOI.ScalarAffineFunction{Float64}, S}())
            write_constraint(io, model, index; write_name = true)
        end
    end

    println(io, "Bounds")
    for S in SCALAR_SETS
        for index in MOI.get(model, MOI.ListOfConstraintIndices{MOI.SingleVariable, S}())
            write_constraint(io, model, index; write_name = false)
        end
    end

    for (S, str_S) in [(MOI.Integer, "General"), (MOI.ZeroOne, "Binary")]
        indices = MOI.get(model, MOI.ListOfConstraintIndices{MOI.SingleVariable, S}())
        if length(indices) > 0
            println(io, str_S)
            for index in indices
                write_function(io, model, MOI.get(model, MOI.ConstraintFunction(), index))
                println(io)
            end
        end
    end

    println(io, "End")

    return
end

# ==============================================================================
#
#   MOI.read_from_to_file
#
# ==============================================================================

function MOI.read_from_file(model::Model, io::IO)
    error("Read from file is not implemented for LP files.")
end

end
