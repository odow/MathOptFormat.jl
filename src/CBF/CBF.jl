module CBF

using MathOptInterface

const MOI = MathOptInterface
const MOIU = MOI.Utilities

MOIU.@model(InnerCBFModel,
    (MOI.Integer,),
    (),
    (MOI.Reals, MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives,
        MOI.SecondOrderCone, MOI.RotatedSecondOrderCone,
        MOI.PositiveSemidefiniteConeTriangle,
        MOI.ExponentialCone, MOI.DualExponentialCone),
    (MOI.PowerCone, MOI.DualPowerCone),
    (MOI.SingleVariable,),
    (MOI.ScalarAffineFunction,),
    (MOI.VectorOfVariables,),
    (MOI.VectorAffineFunction,)
)

const Model = InnerCBFModel{Float64}

function Base.show(io::IO, ::Model)
    print(io, "A Conic Benchmark Format (CBF) model")
    return
end

# ==============================================================================
#
#   MOI.write_to_file
#
# ==============================================================================

function MOI.write_to_file(model::Model, filename::String)
    # Helper functions for MOI constraints.
    model_cons(con_func, con_set) = MOI.get(model,
        MOI.ListOfConstraintIndices{con_func, con_set}())
    con_function(con_idx) = MOI.get(model, MOI.ConstraintFunction(), con_idx)
    con_set(con_idx) = MOI.get(model, MOI.ConstraintSet(), con_idx)

    # Write to file.
    open(filename, "w") do io
        println(io, "# ", MOI.get(model, MOI.Name())) # Name into CBF comments.
        println(io)

        println(io, "VER") # CBF version number.
        println(io, 3)
        println(io)

        # Objective sense.
        println(io, "OBJSENSE")
        obj_sense = MOI.get(model, MOI.ObjectiveSense())
        if obj_sense == MOI.MAX_SENSE
            println(io, "MAX")
        else
            println(io, "MIN") # Includes the case of MOI.FeasibilitySense.
        end
        println(io)

        # Variables.
        num_var = MOI.get(model, MOI.NumberOfVariables())
        println(io, "VAR")
        println(io, num_var, " 1")
        println(io, "F ", num_var)
        println(io)

        # Integrality constraints.
        integer_cons = model_cons(MOI.SingleVariable, MOI.Integer)
        if length(integer_cons) > 0
            println(io, "INT")
            println(io, length(integer_cons))
            for con_idx in integer_cons
                println(io, con_function(con_idx).variable.value - 1) # CBF indices start at 0.
            end
            println(io)
        end

        # Objective function terms.
        obj_type = MOI.get(model, MOI.ObjectiveFunctionType())
        obj_function = MOI.get(model, MOI.ObjectiveFunction{obj_type}())
        if obj_type == MOI.SingleVariable # Objective is a single variable.
            println(io, "OBJACOORD")
            println(io, 1)
            println(io, obj_function.variable.value - 1, " ", 1.0) # CBF indices start at 0.
            println(io)
        elseif obj_type == MOI.ScalarAffineFunction{Float64} # Objective is affine.
            if !isempty(obj_function.terms)
                println(io, "OBJACOORD")
                println(io, length(obj_function.terms))
                for t in obj_function.terms
                    println(io, t.variable_index.value - 1, " ", t.coefficient) # CBF indices start at 0.
                end
                println(io)
            end
            if !iszero(obj_function.constant)
                println(io, "OBJBCOORD")
                println(io, obj_function.constant)
                println(io)
            end
        else
            error("Objective function type $obj_type is not recognized or supported.")
        end

        # TODO power cone (parametrized) constraints.

        # Non-PSD constraints.
        num_rows = 0 # Number of constraint rows.
        con_cones = Tuple{String, Int}[] # List of cone types/dimensions.
        acoord = Tuple{Int, Int, Float64}[] # Affine terms.
        bcoord = Tuple{Int, Float64}[] # Constant terms.

        for (set_type, cone_str) in (
            (MOI.Zeros, "L="),
            (MOI.Reals, "F"),
            (MOI.Nonnegatives, "L+"),
            (MOI.Nonpositives, "L-"),
            (MOI.SecondOrderCone, "Q"),
            (MOI.RotatedSecondOrderCone, "QR"),
            (MOI.ExponentialCone, "EXP"),
            (MOI.DualExponentialCone, "EXP*"),
            )
            for con_idx in model_cons(MOI.VectorOfVariables, set_type)
                vars = con_function(con_idx).variables
                if set_type in (MOI.ExponentialCone, MOI.DualExponentialCone) # Reverse order.
                    reverse!(vars)
                end
                for vj in vars
                    num_rows += 1
                    push!(acoord, (num_rows, vj.value, 1.0))
                end
                push!(con_cones, (cone_str, MOI.dimension(con_set(con_idx))))
            end

            for con_idx in model_cons(MOI.VectorAffineFunction{Float64}, set_type)
                con_func = con_function(con_idx)
                con_dim = MOI.dimension(con_set(con_idx))
                if set_type in (MOI.ExponentialCone, MOI.DualExponentialCone) # Reverse order.
                    @assert con_dim == 3
                    for t in con_func.terms
                        push!(acoord, (num_rows + 4 - t.output_index,
                            t.scalar_term.variable_index.value,
                            t.scalar_term.coefficient))
                    end
                    for row_constant in reverse(con_func.constants)
                        num_rows += 1
                        push!(bcoord, (num_rows, row_constant))
                    end
                else
                    for t in con_func.terms
                        push!(acoord, (num_rows + t.output_index,
                            t.scalar_term.variable_index.value,
                            t.scalar_term.coefficient))
                    end
                    for row_constant in con_func.constants
                        num_rows += 1
                        push!(bcoord, (num_rows, row_constant))
                    end
                end
                push!(con_cones, (cone_str, con_dim))
            end
        end

        if !isempty(con_cones)
            println(io, "CON")
            println(io, num_rows, " ", length(con_cones))
            for (cone_str, con_dim) in con_cones
                println(io, cone_str, " ", con_dim)
            end
            println(io)
        end

        if !isempty(acoord)
            println(io, "ACOORD")
            println(io, length(acoord))
            for (row, var, coef) in acoord
                println(io, row - 1, " ", var - 1, " ", coef) # CBF indices start at 0.
            end
            println(io)
        end

        if !isempty(bcoord)
            println(io, "BCOORD")
            println(io, length(bcoord))
            for (row, constant) in bcoord
                println(io, row - 1, " ", constant) # CBF indices start at 0.
            end
            println(io)
        end

        # PSD constraints.
        psd_side_dims = Int[] # List of side dimensions.
        hcoord = Tuple{Int, Int, Int, Int, Float64}[] # Affine terms.
        dcoord = Tuple{Int, Int, Int, Float64}[] # Constant terms.

        for con_idx in model_cons(MOI.VectorOfVariables,
            MOI.PositiveSemidefiniteConeTriangle) # MOI variable constraints.
            side_dim = con_set(con_idx).side_dimension
            push!(psd_side_dims, side_dim)
            vars = con_function(con_idx).variables
            k = 0
            for i in 1:side_dim, j in 1:i
                k += 1
                push!(hcoord, (length(psd_side_dims), vars[k].value, i, j, 1.0))
            end
            @assert k == length(vars)
        end

        for con_idx in model_cons(MOI.VectorAffineFunction{Float64},
            MOI.PositiveSemidefiniteConeTriangle) # MOI affine constraints.
            side_dim = con_set(con_idx).side_dimension
            push!(psd_side_dims, side_dim)
            con_func = con_function(con_idx)
            for t in con_func.terms
                # Get (i,j) index in symmetric matrix from lower triangle index.
                i = div(1 + isqrt(8 * t.output_index - 7), 2)
                j = t.output_index - div(i * (i - 1), 2)
                push!(hcoord, (length(psd_side_dims),
                    t.scalar_term.variable_index.value,
                    i, j, t.scalar_term.coefficient))
            end
            k = 0
            for i in 1:side_dim, j in 1:i
                k += 1
                row_constant = con_func.constants[k]
                if !iszero(row_constant)
                    push!(dcoord, (length(psd_side_dims), i, j, row_constant))
                end
            end
            @assert k == MOI.output_dimension(con_func)
        end

        if !isempty(psd_side_dims)
            println(io, "PSDCON")
            println(io, length(psd_side_dims))
            for side_dim in psd_side_dims
                println(io, side_dim)
            end
            println(io)
        end

        if !isempty(hcoord)
            println(io, "HCOORD")
            println(io, length(hcoord))
            for (psd_con_idx, var, i, j, coef) in hcoord
                println(io, psd_con_idx - 1, " ", var - 1, " ",
                    i - 1, " ", j - 1, " ", coef) # CBF indices start at 0.
            end
            println(io)
        end

        if !isempty(dcoord)
            println(io, "DCOORD")
            println(io, length(dcoord))
            for (psd_con_idx, i, j, constant) in dcoord
                println(io, psd_con_idx - 1, " ", i - 1, " ",
                    j - 1, " ", constant) # CBF indices start at 0.
            end
            println(io)
        end
    end

    return
end

# ==============================================================================
#
#   MOI.read_from_file
#
# The CBF file format (version 3) is described at
# http://cblib.zib.de/doc/format3.pdf.
#
# ==============================================================================

# Convert a pair of row and column indices of a symmetric matrix into a vector index for the row-wise lower triangle
function matrix_to_vector_idx(i::Int, j::Int)
    if i < j
        return div((j - 1) * j, 2) + i
    else
        return div((i - 1) * i, 2) + j
    end
end

function MOI.read_from_file(model::Model, filename::String)
    if !MOI.is_empty(model)
        error("Cannot read in file because model is not empty.")
    end

    scalar_vars = MOI.VariableIndex[]
    psd_vars = Vector{MOI.VariableIndex}[]
    obj_terms = MOI.ScalarAffineTerm{Float64}[]
    obj_constant = 0.0
    con_cones = Tuple{String, Int}[]
    row_terms = Vector{MOI.ScalarAffineTerm{Float64}}[]
    row_constants = Float64[]
    psd_side_dims = Int[]
    psd_cone_dims = Int[]
    psd_row_terms = Vector{MOI.ScalarAffineTerm{Float64}}[]
    psd_row_constants = Float64[]

    open(filename, "r") do io
        while !eof(io)
            line = strip(readline(io))

            # Skip blank lines and comments (CBF comments start with #).
            if isempty(line) || startswith(line, "#")
                continue
            end

            # CBF version number.
            if startswith(line, "VER")
                ver = parse(Int, split(strip(readline(io)))[1])
                if ver < 1 || ver > 3
                    error("CBF version number $ver is not yet supported by MathOptFormat.")
                end
                continue
            end

            # Objective sense.
            if startswith(line, "OBJSENSE")
                obj_sense = strip(readline(io))
                if obj_sense == "MIN"
                    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
                elseif obj_sense == "MAX"
                    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
                else
                    error("Objective sense $obj_sense not recognized or supported.")
                end
                continue
            end

            # Non-PSD variable constraints.
            if startswith(line, "VAR")
                raw_var_info = split(strip(readline(io)))
                @assert length(raw_var_info) == 2
                num_var = parse(Int, raw_var_info[1])
                num_lines = parse(Int, raw_var_info[2])
                append!(scalar_vars, MOI.add_variables(model, num_var))
                var_idx = 0
                for k in 1:num_lines
                    raw_cone_info = split(strip(readline(io)))
                    @assert length(raw_cone_info) == 2
                    cone_str = raw_cone_info[1]
                    cone_dim = parse(Int, raw_cone_info[2])
                    if cone_str == "F" # Free cones (no constraint).
                        var_idx += cone_dim
                        continue
                    end
                    if cone_str in ("EXP", "EXP*") # Exponential cones.
                        @assert cone_dim == 3
                        con_func = MOI.VectorOfVariables(scalar_vars[
                            [var_idx + 3, var_idx + 2, var_idx + 1]])
                        con_set = (cone_str == "EXP") ? MOI.ExponentialCone() :
                            MOI.DualExponentialCone()
                    else
                        con_func = MOI.VectorOfVariables(scalar_vars[
                            (var_idx + 1):(var_idx + cone_dim)])
                        if cone_str in ("POWER", "POWER*") # Power cones.
                            error("Power cones are not yet supported.")
                        elseif cone_str == "L=" # Zero cones.
                            con_set = MOI.Zeros(cone_dim)
                        elseif cone_str == "L-" # Nonpositive cones.
                            con_set = MOI.Nonpositives(cone_dim)
                        elseif cone_str == "L+" # Nonnegative cones.
                            con_set = MOI.Nonnegatives(cone_dim)
                        elseif cone_str == "Q" # Second-order cones.
                            @assert cone_dim >= 2
                            con_set = MOI.SecondOrderCone(cone_dim)
                        elseif cone_str == "QR" # Rotated second-order cones.
                            @assert cone_dim >= 3
                            con_set = MOI.RotatedSecondOrderCone(cone_dim)
                        else
                            error("CBF cone name $cone_str is not recognized or supported.")
                        end
                    end
                    MOI.add_constraint(model, con_func, con_set)
                    var_idx += cone_dim
                end
                @assert var_idx == num_var
                continue
            end

            # Integrality constraints.
            if startswith(line, "INT")
                for k in 1:parse(Int, strip(readline(io)))
                    var_idx = parse(Int, strip(readline(io))) + 1 # CBF indices start at 0.
                    MOI.add_constraint(model,
                        MOI.SingleVariable(scalar_vars[var_idx]), MOI.Integer())
                end
                continue
            end

            # PSD variable constraints.
            if startswith(line, "PSDVAR")
                for k in 1:parse(Int, strip(readline(io)))
                    side_dim = parse(Int, strip(readline(io)))
                    cone_dim = div(side_dim * (side_dim + 1), 2)
                    psd_vars_k = MOI.add_variables(model, cone_dim)
                    push!(psd_vars, psd_vars_k)
                    MOI.add_constraint(model, MOI.VectorOfVariables(psd_vars_k),
                        MOI.PositiveSemidefiniteConeTriangle(side_dim))
                end
                continue
            end

            # Objective function terms.
            if startswith(line, "OBJFCOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    raw_coord = split(strip(readline(io)))
                    @assert length(raw_coord) == 4
                    (psd_var_idx, i, j) = (parse(Int, raw_coord[i]) + 1
                        for i in 1:3) # CBF indices start at 0.
                    coef = parse(Float64, raw_coord[end])
                    if i != j
                        coef += coef # scale off-diagonals
                    end
                    push!(obj_terms, MOI.ScalarAffineTerm(coef,
                        psd_vars[psd_var_idx][matrix_to_vector_idx(i, j)]))
                end
                continue
            end

            if startswith(line, "OBJACOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    raw_coord = split(strip(readline(io)))
                    @assert length(raw_coord) == 2
                    var_idx = parse(Int, raw_coord[1]) + 1 # CBF indices start at 0.
                    coef = parse(Float64, raw_coord[end])
                    push!(obj_terms, MOI.ScalarAffineTerm(coef,
                        scalar_vars[var_idx]))
                end
                continue
            end

            if startswith(line, "OBJBCOORD")
                obj_constant += parse(Float64, strip(readline(io)))
                continue
            end

            # Non-PSD constraints.
            if startswith(line, "CON")
                raw_con_info = split(strip(readline(io)))
                @assert length(raw_con_info) == 2
                num_rows = parse(Int, raw_con_info[1])
                num_lines = parse(Int, raw_con_info[2])
                row_idx = 0
                for k in 1:num_lines
                    raw_cone_info = split(strip(readline(io)))
                    @assert length(raw_cone_info) == 2
                    cone_str = raw_cone_info[1]
                    cone_dim = parse(Int, raw_cone_info[2])
                    push!(con_cones, (cone_str, cone_dim))
                    row_idx += cone_dim
                end
                @assert row_idx == num_rows
                append!(row_terms, Vector{MOI.ScalarAffineTerm{Float64}}()
                    for k in 1:num_rows)
                append!(row_constants, zeros(num_rows))
                continue
            end

            if startswith(line, "FCOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    raw_coord = split(strip(readline(io)))
                    @assert length(raw_coord) == 5
                    (row_idx, psd_var_idx, i, j) = (parse(Int, raw_coord[i]) + 1
                        for i in 1:4) # CBF indices start at 0.
                    coef = parse(Float64, raw_coord[end])
                    if i != j
                        coef += coef # scale off-diagonals
                    end
                    push!(row_terms[row_idx], MOI.ScalarAffineTerm(val,
                        psd_vars[psd_var_idx][matrix_to_vector_idx(i, j)]))
                end
                continue
            end

            if startswith(line, "ACOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    raw_coord = split(strip(readline(io)))
                    @assert length(raw_coord) == 3
                    (row_idx, var_idx) = (parse(Int, raw_coord[i]) + 1
                        for i in 1:2) # CBF indices start at 0.
                    coef = parse(Float64, raw_coord[end])
                    push!(row_terms[row_idx], MOI.ScalarAffineTerm(coef,
                        scalar_vars[var_idx]))
                end
                continue
            end

            if startswith(line, "BCOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    raw_coord = split(strip(readline(io)))
                    @assert length(raw_coord) == 2
                    row_idx = parse(Int, raw_coord[1]) + 1 # CBF indices start at 0.
                    row_constants[row_idx] = parse(Float64, raw_coord[end])
                end
                continue
            end

            # PSD constraints.
            if startswith(line, "PSDCON")
                idx = 0
                for k in 1:parse(Int, strip(readline(io)))
                    side_dim = parse(Int, strip(readline(io)))
                    push!(psd_side_dims, side_dim)
                    push!(psd_cone_dims, idx)
                    idx += div(side_dim * (side_dim + 1), 2)
                end
                append!(psd_row_terms, Vector{MOI.ScalarAffineTerm{Float64}}()
                    for i in 1:idx)
                append!(psd_row_constants, zeros(idx))
                continue
            end

            if startswith(line, "HCOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    raw_coord = split(strip(readline(io)))
                    @assert length(raw_coord) == 5
                    (psd_con_idx, var_idx, i, j) = (parse(Int, raw_coord[i]) + 1
                        for i in 1:4) # CBF indices start at 0.
                    coef = parse(Float64, raw_coord[end])
                    row_idx = psd_cone_dims[psd_con_idx] + matrix_to_vector_idx(i, j)
                    push!(psd_row_terms[row_idx], MOI.ScalarAffineTerm(coef,
                        scalar_vars[var_idx]))
                end
                continue
            end

            if startswith(line, "DCOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    raw_coord = split(strip(readline(io)))
                    @assert length(raw_coord) == 4
                    (psd_con_idx, i, j) = (parse(Int, raw_coord[i]) + 1
                        for i in 1:3) # CBF indices start at 0.
                    row_idx = psd_cone_dims[psd_con_idx] + matrix_to_vector_idx(i, j)
                    psd_row_constants[row_idx] += parse(Float64, raw_coord[end])
                end
                continue
            end
        end
    end

    # Objective function.
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
        MOI.ScalarAffineFunction(obj_terms, obj_constant))

    # Non-PSD constraints.
    row_idx = 0
    for (cone_str, cone_dim) in con_cones
        if cone_str == "F" # Free cones (no constraint).
            row_idx += cone_dim
            continue
        end
        if cone_str in ("EXP", "EXP*") # Exponential cones.
            @assert cone_dim == 3
            con_func = MOI.VectorAffineFunction([MOI.VectorAffineTerm(4 - l, t)
                for l in 1:cone_dim for t in row_terms[row_idx + l]],
                row_constants[[row_idx + 3, row_idx + 2, row_idx + 1]])
            con_set = (cone_str == "EXP") ? MOI.ExponentialCone() :
                MOI.DualExponentialCone()
        else
            con_func = MOI.VectorAffineFunction([MOI.VectorAffineTerm(l, t)
                for l in 1:cone_dim for t in row_terms[row_idx + l]],
                row_constants[(row_idx + 1):(row_idx + cone_dim)])
            if cone_str in ("POWER", "POWER*") # Power cones.
                error("Power cones are not yet supported.")
            elseif cone_str == "L=" # Zero cones.
                con_set = MOI.Zeros(cone_dim)
            elseif cone_str == "L-" # Nonpositive cones.
                con_set = MOI.Nonpositives(cone_dim)
            elseif cone_str == "L+" # Nonnegative cones.
                con_set = MOI.Nonnegatives(cone_dim)
            elseif cone_str == "Q" # Second-order cones.
                @assert cone_dim >= 2
                con_set = MOI.SecondOrderCone(cone_dim)
            elseif cone_str == "QR" # Rotated second-order cones.
                @assert cone_dim >= 3
                con_set = MOI.RotatedSecondOrderCone(cone_dim)
            else
                error("CBF cone name $cone_str is not recognized or supported.")
            end
        end
        MOI.add_constraint(model, con_func, con_set)
        row_idx += cone_dim
    end

    # PSD constraints.
    row_idx = 0
    for psd_con_idx in eachindex(psd_side_dims)
        cone_dim = psd_cone_dims[psd_con_idx]
        con_func = MOI.VectorAffineFunction([MOI.VectorAffineTerm(l, t)
            for l in 1:cone_dim for t in psd_row_terms[row_idx + l]],
            psd_row_constants[(row_idx + 1):(row_idx + cone_dim)])
        con_set = MOI.PositiveSemidefiniteConeTriangle(psd_side_dims[psd_con_idx])
        MOI.add_constraint(model, con_func, con_set)
        row_idx += cone_dim
    end

    return
end

end
