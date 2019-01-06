module CBF

using MathOptInterface

const MOI = MathOptInterface
const MOIU = MOI.Utilities

MOIU.@model(InnerCBFModel,
    (MOI.Integer,),
    (,),
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

moitocbfcones = Tuple{MOI.AbstractVectorSet, String}[
    (MOI.Zeros, "L="),
    (MOI.Reals, "F"),
    (MOI.Nonnegatives, "L+"),
    (MOI.Nonpositives, "L-"),
    (MOI.SecondOrderCone, "Q"),
    (MOI.RotatedSecondOrderCone, "QR"),
    (MOI.ExponentialCone, "EXP"),
    (MOI.DualExponentialCone, "EXP*"),
]

function MOI.write_to_file(model::Model, filename::String)
    open(filename, "w") do io
        println(io, "# ", MOI.get(model, MOI.Name()) # Name into CBF comments.
        println(io)

        println(io, "VER") # CBF version number.
        println(io, 3)
        println(io)

        # Objective sense.
        println(io, "OBJSENSE")
        objsense = MOI.get(model, MOI.ObjectiveSense())
        if objsense == MOI.MaxSense
            println(io, "MAX")
        else
            println(io, "MIN") # Includes the case of MOI.FeasibilitySense.
        end
        println(io)

        # Variables.
        nvar = MOI.get(model, MOI.NumberOfVariables())
        println(io, "VAR")
        println(io, nvar, " 1")
        println(io, "F ", nvar)
        println(io)

        # Helper functions for MOI.
        getmodelcons(F, S) = MOI.get(model, MOI.ListOfConstraintIndices{F, S}())
        getconfun(conidx) = MOI.get(model, MOI.ConstraintFunction(), conidx)
        getconset(conidx) = MOI.get(model, MOI.ConstraintSet(), conidx)

        # Integrality constraints.
        intlist = getmodelcons(MOI.SingleVariable, MOI.Integer)
        if length(intlist) > 0
            println(io, "INT")
            println(io, length(intlist))
            for k in intlist
                println(io, getconfun(ci).variable.value - 1)
            end
            println(io)
        end

        # Objective function terms.
        F = MOI.get(model, MOI.ObjectiveFunctionType())
        obj = MOI.get(model, MOI.ObjectiveFunction{F}())
        if F == MOI.SingleVariable # Objective is a single variable.
            println(io, "OBJACOORD")
            println(io, 1)
            println(io, F.variable.value - 1, " ", 1.0)
            println(io)
        elseif F == MOI.ScalarAffineFunction{Float64} # Objective is affine.
            if !isempty(obj.terms)
                println(io, "OBJACOORD")
                println(io, length(obj.terms))
                for t in obj.terms
                    println(io, t.variable_index.value - 1, " ", t.coefficient)
                end
                println(io)
            end
            if !iszero(obj.constant)
                println(io, "OBJBCOORD")
                println(io, obj.constant)
                println(io)
            end
        else
            error("Objective function type $F is unsupported.")
        end

        # PSD constraints.
        psdcon = Int[] # List of side dimensions.
        hcoord = Tuple{Int, Int, Int, Int, Float64}[] # Affine terms.
        dcoord = Tuple{Int, Int, Int, Float64}[] # Constant terms.

        for ci in getmodelcons(MOI.VectorOfVariables,
            MOI.PositiveSemidefiniteConeTriangle) # MOI variable constraints.
            side = getconset(ci).side_dimension
            push!(psdcon, side)
            vars = getconfun(ci).variables
            k = 0
            for i in 1:side, j in 1:i
                k += 1
                push!(hcoord, (length(psdcon), vars[k].value, i, j, 1.0))
            end
            @assert k == length(vars)
        end

        for ci in getmodelcons(MOI.VectorAffineFunction{Float64},
            MOI.PositiveSemidefiniteConeTriangle) # MOI affine constraints.
            side = getconset(ci).side_dimension
            push!(psdcon, side)
            fi = getconfun(ci)
            for vt in fi.terms
                st = vt.scalar_term
                # Get (i,j) index in symmetric matrix from lower triangle index.
                i = div(1 + isqrt(8*vt.output_index - 7), 2)
                j = vt.output_index - div(i*(i-1), 2)
                push!(hcoord, (length(psdcon), st.variable_index.value, i, j,
                    st.coefficient))
            end
            k = 0
            for i in 1:side, j in 1:i
                k += 1
                if !iszero(fi.constants[k])
                    push!(dcoord, (length(psdcon), i, j, fi.constants[k]))
                end
            end
            @assert k == MOI.output_dimension(fi)
        end

        if !isempty(psdcon)
            println(io, "PSDCON")
            println(io, length(psdcon))
            for v in psdcon
                println(io, v)
            end
            println(io)
        end

        if !isempty(hcoord)
            println(io, "HCOORD")
            println(io, length(hcoord))
            for (a, b, c, d, v) in hcoord
                println(io, a-1, " ", b-1, " ", c-1, " ", d-1, " ", v)
            end
            println(io)
        end

        if !isempty(dcoord)
            println(io, "DCOORD")
            println(io, length(dcoord))
            for (a, b, c, v) in dcoord
                println(io, a-1, " ", b-1, " ", c-1, " ", v)
            end
            println(io)
        end

        # TODO power cone (parametrized) constraints.

        # Non-PSD constraints.
        ncon = 0 # Number of constraint rows.
        con = Tuple{String, Int}[] # List of cone types/dimensions.
        acoord = Tuple{Int, Int, Float64}[] # Affine terms.
        bcoord = Tuple{Int, Float64}[] # Constant terms.


        for (S, cbfcone) in moitocbfcones
            for ci in getmodelcons(MOI.VectorOfVariables, S)
                vars = getconfun(ci).variables
                if S in (MOI.ExponentialCone, MOI.DualExponentialCone)
                    reverse!(vars) # Reverse order.
                end
                for vj in vars
                    ncon += 1
                    push!(acoord, (ncon, vj.value, 1.0))
                end
                push!(con, (cbfcone, MOI.dimension(getconset(ci))))
            end

            for ci in getmodelcons(MOI.VectorAffineFunction{Float64}, S)
                fi = getconfun(ci)
                dim = MOI.dimension(getconset(ci))
                if S in (MOI.ExponentialCone, MOI.DualExponentialCone)
                    @assert dim == 3
                    # Reverse order.
                    for vt in fi.terms
                        idx = ncon + 4 - vt.output_index
                        st = vt.scalar_term
                        push!(acoord, (idx, st.variable_index.value,
                            st.coefficient))
                    end
                    for row in [3,2,1]
                        ncon += 1
                        push!(bcoord, (ncon, fi.constants[row]))
                    end
                else
                    for vt in fi.terms
                        idx = ncon + vt.output_index
                        st = vt.scalar_term
                        push!(acoord, (idx, st.variable_index.value,
                            st.coefficient))
                    end
                    for row in 1:dim
                        ncon += 1
                        push!(bcoord, (ncon, fi.constants[row]))
                    end
                end
                push!(con, (cbfcone, dim))
            end
        end

        if !isempty(con)
            println(io, "CON")
            println(io, ncon, " ", length(con))
            for (cone, conesize) in con
                println(io, cone, " ", conesize)
            end
            println(io)
        end

        if !isempty(acoord)
            println(io, "ACOORD")
            println(io, length(acoord))
            for (a, b, v) in acoord
                println(io, a-1, " ", b-1, " ", v)
            end
            println(io)
        end

        if !isempty(bcoord)
            println(io, "BCOORD")
            println(io, length(bcoord))
            for (a, v) in bcoord
                println(io, a-1, " ", v)
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

# TODO

# function MOI.read_from_file(model::Model, filename::String)
#     if !MOI.is_empty(model)
#         error("Cannot read in file because model is not empty.")
#     end
#
#     data = TempMPSModel()
#     open(filename, "r") do io
#         header = "NAME"
#         while !eof(io) && header != "ENDATA"
#             line = strip(readline(io))
#             if line == "" || startswith(line, "*")
#                 # Skip blank lines and comments.
#                 continue
#             end
#             if uppercase(string(line)) in HEADERS
#                 header = uppercase(string(line))
#                 continue
#             end
#             # TODO: split into hard fields based on column indices.
#             items = if VERSION >= v"0.7"
#                 String.(split(line, " ", keepempty = false))
#             else
#                 String.(split(line, " ", keep = false))
#             end
#             if header == "NAME"
#                 # A special case. This only happens at the start.
#                 parse_name_line(data, items)
#             elseif header == "ROWS"
#                 parse_rows_line(data, items)
#             elseif header == "COLUMNS"
#                 parse_columns_line(data, items)
#             elseif header == "RHS"
#                 parse_rhs_line(data, items)
#             elseif header == "RANGES"
#                 parse_ranges_line(data, items)
#             elseif header == "BOUNDS"
#                 parse_bounds_line(data, items)
#             end
#         end
#     end
#
#     copy_to(model, data)
#     return
# end
#
# function copy_to(model::Model, temp::TempMPSModel)
#     MOI.set(model, MOI.Name(), temp.name)
#     variable_map = Dict{String, MOI.VariableIndex}()
#
#     # Add variables.
#     for (name, column) in temp.columns
#         x = MOI.add_variable(model)
#         variable_map[name] = x
#         MOI.set(model, MOI.VariableName(), x, name)
#         set = bounds_to_set(column.lower, column.upper)
#         if set === nothing && column.is_int
#             # TODO: some solvers may interpret this as binary.
#             MOI.add_constraint(model, MOI.SingleVariable(x), MOI.Integer())
#         elseif set !== nothing && column.is_int
#             if set == MOI.Interval(0.0, 1.0)
#                 MOI.add_constraint(model, MOI.SingleVariable(x), MOI.ZeroOne())
#             else
#                 MOI.add_constraint(model, MOI.SingleVariable(x), MOI.Integer())
#                 MOI.add_constraint(model, MOI.SingleVariable(x), set)
#             end
#         elseif set !== nothing
#             MOI.add_constraint(model, MOI.SingleVariable(x), set)
#         end
#     end
#
#     # Add linear constraints.
#     for (c_name, row) in temp.rows
#         if c_name == temp.obj_name
#             # Set objective.
#             MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
#             obj_func = if length(row.terms) == 1 &&
#                     first(row.terms).second == 1.0
#                 MOI.SingleVariable(variable_map[first(row.terms).first])
#             else
#                 MOI.ScalarAffineFunction([
#                     MOI.ScalarAffineTerm(coef, variable_map[v_name])
#                         for (v_name, coef) in row.terms],
#                 0.0)
#             end
#             MOI.set(model, MOI.ObjectiveFunction{typeof(obj_func)}(), obj_func)
#         else
#             constraint_function = MOI.ScalarAffineFunction([
#                 MOI.ScalarAffineTerm(coef, variable_map[v_name])
#                     for (v_name, coef) in row.terms],
#                 0.0)
#             set = bounds_to_set(row.lower, row.upper)
#             if set !== nothing
#                 c = MOI.add_constraint(model, constraint_function, set)
#                 MOI.set(model, MOI.ConstraintName(), c, c_name)
#             end
#         end
#     end
#     return
# end
#
# # ==============================================================================
# #   NAME
# # ==============================================================================
#
# function parse_name_line(data::TempMPSModel, items::Vector{String})
#     if !(1 <= length(items) <= 2) || uppercase(items[1]) != "NAME"
#         error("Malformed NAME line: $(join(items, " "))")
#     end
#     if length(items) == 2
#         data.name = items[2]
#     elseif length(items) == 1
#         data.name = ""
#     end
#     return
# end
#
# # ==============================================================================
# #   ROWS
# # ==============================================================================
#
# function parse_rows_line(data::TempMPSModel, items::Vector{String})
#     if length(items) != 2
#         error("Malformed ROWS line: $(join(items, " "))")
#     end
#     sense, name = items
#     if haskey(data.rows, name)
#         error("Duplicate row encountered: $(line).")
#     elseif sense != "N" && sense != "L" && sense != "G" && sense != "E"
#         error("Invalid row sense: $(join(items, " "))")
#     end
#     row = TempRow()
#     row.sense = sense
#     data.rows[name] = row
#     if sense == "N"
#         if data.obj_name != ""
#             error("Multiple obectives encountered: $(join(items, " "))")
#         end
#         data.obj_name = name
#     end
#     return
# end
#
# # ==============================================================================
# #   COLUMNS
# # ==============================================================================
#
# function parse_single_coefficient(data, row_name, column_name, value)
#     terms = data.rows[row_name].terms
#     value = parse(Float64, value)
#     if haskey(terms, column_name)
#         terms[column_name] += value
#     else
#         terms[column_name] = value
#     end
#     return
# end
#
# function parse_columns_line(data::TempMPSModel, items::Vector{String})
#     if length(items) == 3
#         # [column name] [row name] [value]
#         column_name, row_name, value = items
#         if uppercase(row_name) == "'MARKER'" && uppercase(value) == "'INTORG'"
#             data.intorg_flag = true
#             return
#         elseif uppercase(row_name) == "'MARKER'" &&
#                 uppercase(value) == "'INTEND'"
#             data.intorg_flag = false
#             return
#         end
#         if !haskey(data.columns, column_name)
#             data.columns[column_name] = TempColumn()
#         end
#         parse_single_coefficient(data, row_name, column_name, value)
#         if data.columns[column_name].is_int && !data.intorg_flag
#             error("Variable $(column_name) appeared in COLUMNS outside an" *
#                   " `INT` marker after already being declared as integer.")
#         end
#         data.columns[column_name].is_int = data.intorg_flag
#     elseif length(items) == 5
#         # [column name] [row name] [value] [row name 2] [value 2]
#         column_name, row_name_1, value_1, row_name_2, value_2 = items
#         if !haskey(data.columns, column_name)
#             data.columns[column_name] = TempColumn()
#         end
#         parse_single_coefficient(data, row_name_1, column_name, value_1)
#         parse_single_coefficient(data, row_name_2, column_name, value_2)
#         if data.columns[column_name].is_int && !data.intorg_flag
#             error("Variable $(column_name) appeared in COLUMNS outside an" *
#                   " `INT` marker after already being declared as integer.")
#         end
#         data.columns[column_name].is_int = data.intorg_flag
#     else
#         error("Malformed COLUMNS line: $(join(items, " "))")
#     end
#     return
# end
#
# # ==============================================================================
# #   RHS
# # ==============================================================================
#
# function parse_single_rhs(data, row_name, value)
#     if !haskey(data.rows, row_name)
#         error("ROW name $(row_name) not recognised. Is it in the ROWS field?")
#     end
#     value = parse(Float64, value)
#     sense = data.rows[row_name].sense
#     if sense == "E"
#         data.rows[row_name].upper = value
#         data.rows[row_name].lower = value
#     elseif sense == "G"
#         data.rows[row_name].lower = value
#     elseif sense == "L"
#         data.rows[row_name].upper = value
#     elseif sense == "N"
#         error("Cannot have RHS for objective: $(join(items, " "))")
#     end
#     return
# end
#
# # TODO: handle multiple RHS vectors.
# function parse_rhs_line(data::TempMPSModel, items::Vector{String})
#     if length(items) == 3
#         # [rhs name] [row name] [value]
#         rhs_name, row_name, value = items
#         parse_single_rhs(data, row_name, value)
#     elseif length(items) == 5
#         # [rhs name] [row name 1] [value 1] [row name 2] [value 2]
#         rhs_name, row_name_1, value_1, row_name_2, value_2 = items
#         parse_single_rhs(data, row_name_1, value_1)
#         parse_single_rhs(data, row_name_2, value_2)
#     else
#         error("Malformed RHS line: $(join(items, " "))")
#     end
#     return
# end
#
# # ==============================================================================
# #  RANGES
# #
# # Here is how RANGE information is encoded. (We repeat this comment because it
# # is so non-trivial.)
# #
# #     Row type | Range value |  lower bound  |  upper bound
# #     ------------------------------------------------------
# #         G    |     +/-     |     rhs       | rhs + |range|
# #         L    |     +/-     | rhs - |range| |     rhs
# #         E    |      +      |     rhs       | rhs + range
# #         E    |      -      | rhs + range   |     rhs
# # ==============================================================================
#
# function parse_single_range(data, row_name, value)
#     if !haskey(data.rows, row_name)
#         error("ROW name $(row_name) not recognised. Is it in the ROWS field?")
#     end
#     value = parse(Float64, value)
#     row = data.rows[row_name]
#     if row.sense == "G"
#         row.upper = row.lower + abs(value)
#     elseif row.sense == "L"
#         row.lower = row.upper - abs(value)
#     elseif row.sense == "E"
#         if value > 0.0
#             row.upper = row.upper + value
#         else
#             row.lower = row.lower + value
#         end
#     end
#     return
# end
#
# # TODO: handle multiple RANGES vectors.
# function parse_ranges_line(data::TempMPSModel, items::Vector{String})
#     if length(items) == 3
#         # [rhs name] [row name] [value]
#         rhs_name, row_name, value = items
#         parse_single_range(data, row_name, value)
#     elseif length(items) == 5
#         # [rhs name] [row name] [value] [row name 2] [value 2]
#         rhs_name, row_name, value, row_name_2, value_2 = items
#         parse_single_range(data, row_name, value)
#         parse_single_range(data, row_name_2, value_2)
#     else
#         error("Malformed RANGES line: $(join(items, " "))")
#     end
#     return
# end
#
# # ==============================================================================
# #   BOUNDS
# # ==============================================================================
#
# function parse_bounds_line(data::TempMPSModel, items::Vector{String})
#     if length(items) == 3
#         bound_type, bound_name, column_name = items
#         if !haskey(data.columns, column_name)
#             error("Column name $(column_name) not found.")
#         end
#         column = data.columns[column_name]
#         if bound_type == "PL"
#             column.upper = Inf
#         elseif bound_type == "MI"
#             column.lower = -Inf
#         elseif bound_type == "FR"
#             column.lower = -Inf
#             column.upper = Inf
#         elseif bound_type == "BV"
#             column.lower = 0.0
#             column.upper = 1.0
#             column.is_int = true
#         else
#             error("Invalid bound type $(bound_type): $(join(items, " "))")
#         end
#     elseif length(items) == 4
#         bound_type, bound_name, column_name, value = items
#         if !haskey(data.columns, column_name)
#             error("Column name $(column_name) not found.")
#         end
#         column = data.columns[column_name]
#         value = parse(Float64, value)
#         if bound_type == "FX"
#             column.lower = column.upper = value
#         elseif bound_type == "UP"
#             column.upper = value
#         elseif bound_type == "LO"
#             column.lower = value
#         elseif bound_type == "LI"
#             column.lower = value
#             column.is_int = true
#         elseif bound_type == "UI"
#             column.upper = value
#             column.is_int = true
#         else
#             error("Invalid bound type $(bound_type): $(join(items, " "))")
#         end
#     else
#         error("Malformed BOUNDS line: $(join(items, " "))")
#     end
#     return
# end
#
# end
