module LP

using MathOptInterface

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

function write_function(io::IO, model::Model, func::MOI.SingleVariable)
    name = MOI.get(model, MOI.VariableName(), func.variable)
    print(io, name)
    return
end

function write_function(io::IO, model::Model, func::MOI.ScalarAffineFunction{Float64})
    Base.Grisu.print_shortest(io, func.constant)
    for term in func.terms
        print(io, term.coefficient < 0 ? " - " : " + ")
        Base.Grisu.print_shortest(io, abs(term.coefficient))
        print(io, MOI.get(model, MOI.VariableName(), term.variable_index))
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
    print(io, " == ", )
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

write_constraint_suffix(io::IO, set) = nothing

function write_constraint_prefix(io::IO, set::MOI.Interval)
    Base.Grisu.print_shortest(io, set.lower)
    print(io, " <= ")
    return
end

write_constraint_prefix(io::IO, set) = nothing

const LINEAR_CONSTRAINTS = (
    MOI.LessThan{Float64}, MOI.GreaterThan{Float64}, MOI.EqualTo{Float64},
    MOI.Interval{Float64}
)

function MOI.write_to_file(model::Model, io::IO)
    if MOI.get(model, MOI.ObjectiveSense()) == MOI.MAX_SENSE
        println(io, "Maximize")
    else
        println(io, "Minimize")
    end

    print(io, "obj: ")
    obj_func_type = MOI.get(model, MOI.ObjectiveFunctionType())
    obj_func = MOI.get(model, MOI.ObjectiveFunction{obj_func_type}())
    write_function(io, model, obj_func)
    println(io)

    for S in LINEAR_CONSTRAINTS
        for index in MOI.get(model, MOI.ListOfConstraintIndices{MOI.ScalarAffineFunction{Float64}, S}())
            func = MOI.get(model, MOI.ConstraintFunction(), index)
            set = MOI.get(model, MOI.ConstraintSet(), index)
            print(io, MOI.get(model, MOI.ConstraintName(), index), " : ")
            write_constraint_prefix(io, set)
            write_function(io, model, func)
            write_constraint_suffix(io, set)
        end
    end

    println(io, "Bounds")
    for set_type in LINEAR_CONSTRAINTS
        for index in MOI.get(model, MOI.ListOfConstraintIndices{
                MOI.SingleVariable, set_type}())
            func = MOI.get(model, MOI.ConstraintFunction(), index)
            set = MOI.get(model, MOI.ConstraintSet(), index)
            write_constraint_prefix(io, set)
            write_function(io, model, func)
            write_constraint_suffix(io, set)
        end
    end

    integer_variables = MOI.get(model, MOI.ListOfConstraintIndices{MOI.SingleVariable, MOI.Integer}())
    if length(integer_variables) > 0
        println(io, "General")
        for index in integer_variables
            println(io, MOI.get(model, MOI.VariableName(), index))
        end
    end

    integer_variables = MOI.get(model, MOI.ListOfConstraintIndices{MOI.SingleVariable, MOI.ZeroOne}())
    if length(integer_variables) > 0
        println(io, "Binary")
        for index in integer_variables
            println(io, MOI.get(model, MOI.VariableName(), index))
        end
    end

    return
end

# ==============================================================================
#
#   MOI.read_from_to_file
#
# ==============================================================================

function MOI.read_from_to_file(model::Model, io::IO)
    error("Read from file is not implemented for LP files.")
end

end
