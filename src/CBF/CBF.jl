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
    open(filename, "w") do io
        println(io, "# ", MOI.get(model, MOI.Name())) # Name into CBF comments.
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

        # TODO power cone (parametrized) constraints.

        # Non-PSD constraints.
        ncon = 0 # Number of constraint rows.
        con = Tuple{String, Int}[] # List of cone types/dimensions.
        acoord = Tuple{Int, Int, Float64}[] # Affine terms.
        bcoord = Tuple{Int, Float64}[] # Constant terms.

        for (S, conename) in (
            (MOI.Zeros, "L="),
            (MOI.Reals, "F"),
            (MOI.Nonnegatives, "L+"),
            (MOI.Nonpositives, "L-"),
            (MOI.SecondOrderCone, "Q"),
            (MOI.RotatedSecondOrderCone, "QR"),
            (MOI.ExponentialCone, "EXP"),
            (MOI.DualExponentialCone, "EXP*"),
            )
            for ci in getmodelcons(MOI.VectorOfVariables, S)
                vars = getconfun(ci).variables
                if S in (MOI.ExponentialCone, MOI.DualExponentialCone)
                    reverse!(vars) # Reverse order.
                end
                for vj in vars
                    ncon += 1
                    push!(acoord, (ncon, vj.value, 1.0))
                end
                push!(con, (conename, MOI.dimension(getconset(ci))))
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
                push!(con, (conename, dim))
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

function mattovecidx(i, j)
    if i < j
        (i,j) = (j,i)
    end
    return div((i-1)*i, 2) + j
end

function MOI.read_from_file(model::Model, filename::String)
    if !MOI.is_empty(model)
        error("Cannot read in file because model is not empty.")
    end

    x = MOI.VariableIndex[]
    X = Vector{MOI.VariableIndex}[]
    objterms = MOI.ScalarAffineTerm{Float64}[]
    objconst = 0.0
    conecons = Tuple{String, Int}[]
    conterms = Vector{MOI.ScalarAffineTerm{Float64}}[]
    conconst = Float64[]
    psdcons = Tuple{Int, Int}[]
    psdterms = Vector{MOI.ScalarAffineTerm{Float64}}[]
    psdconst = Float64[]

    open(filename, "r") do io
        while !eof(io)
            line = strip(readline(io))

            # Comments.
            if startswith(line, "#") || length(line) == 1
                continue
            end

            # CBF version number.
            if startswith(line, "VER")
                ver = parse(Int, split(strip(readline(io)))[1])
                if !(ver in (1, 2, 3))
                    warn("CBF Version number $ver is not yet supported.")
                end
                continue
            end

            # Objective sense.
            if startswith(line, "OBJSENSE")
                objsense = strip(readline(io))
                if objsense == "MIN"
                    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
                elseif objsense == "MAX"
                    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
                else
                    error("Objective sense $objsense not recognized")
                end
                continue
            end

            # Non-PSD variable constraints.
            if startswith(line, "VAR")
                (nvar, nlines) = (parse(Int, strip(i)) for i in
                    split(strip(readline(io))))
                append!(x, MOI.add_variables(model, nvar))
                idx = 0
                for k in 1:nlines
                    coneinfo = split(strip(readline(io)))
                    conename = coneinfo[1]
                    conelen = parse(Int, coneinfo[2])
                    if conename == "F" # Free cones (no constraint).
                        idx += conelen
                        continue
                    end
                    if conename in ("EXP", "EXP*") # Exponential cones.
                        @assert conelen == 3
                        F = MOI.VectorOfVariables(x[idx+3, idx+2, idx+1])
                        if conename == "EXP"
                            S = MOI.ExponentialCone()
                        else
                            S = MOI.DualExponentialCone()
                        end
                    else
                        F = MOI.VectorOfVariables(x[idx .+ (1:conelen)])
                        if conename in ("POWER", "POWER*") # Power cones.
                            error("Power cones are not yet supported.")
                        elseif conename == "L=" # Zero cones.
                            S = MOI.Zeros(conelen)
                        elseif conename == "L-" # Nonpositive cones.
                            S = MOI.Nonpositives(conelen)
                        elseif conename == "L+" # Nonnegative cones.
                            S = MOI.Nonnegatives(conelen)
                        elseif conename == "Q" # Second-order cones.
                            @assert conelen >= 3
                            S = MOI.SecondOrderCone(conelen)
                        elseif conename == "QR" # Rotated second-order cones.
                            @assert conelen >= 3
                            S = MOI.RotatedSecondOrderCone(conelen)
                        else
                            error("cone type $conename is not recognized")
                        end
                    end
                    @assert MOI.output_dimension(F) == MOI.dimension(S)
                    MOI.add_constraint(model, F, S)
                    idx += conelen
                end
                @assert idx == nvar
                continue
            end

            # Integrality constraints.
            if startswith(line, "INT")
                for k in 1:parse(Int, strip(readline(io)))
                    idx = parse(Int, strip(readline(io)))
                    MOI.add_constraint(model, MOI.SingleVariable(x[idx+1]),
                        MOI.Integer())
                end
                continue
            end

            # PSD variable constraints.
            if startswith(line, "PSDVAR")
                for k in 1:parse(Int, strip(readline(io)))
                    side = parse(Int, strip(readline(io)))
                    conelen = div(side*(side+1), 2)
                    Xk = MOI.add_variables(model, conelen)
                    push!(X, Xk)
                    F = MOI.VectorOfVariables(Xk)
                    S = MOI.PositiveSemidefiniteConeTriangle(side)
                    @assert MOI.output_dimension(F) == MOI.dimension(S)
                    MOI.add_constraint(model, F, S)
                end
                continue
            end

            # Objective function terms.
            if startswith(line, "OBJFCOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    linesplit = split(strip(readline(io)))
                    @assert length(linesplit) == 4
                    (a, b, c) = (parse(Int, linesplit[i]) + 1 for i in 1:3)
                    val = parse(Float64, linesplit[end])
                    if b != c
                        val += val # scale off-diagonals
                    end
                    vidx = mattovecidx(b, c)
                    push!(objterms, MOI.ScalarAffineTerm(val, X[a][vidx]))
                end
                continue
            end

            if startswith(line, "OBJACOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    linesplit = split(strip(readline(io)))
                    @assert length(linesplit) == 2
                    a = parse(Int, linesplit[i]) + 1
                    val = parse(Float64, linesplit[end])
                    push!(objterms, MOI.ScalarAffineTerm(val, x[a]))
                end
                continue
            end

            if startswith(line, "OBJBCOORD")
                objconst += parse(Float64, strip(readline(io)))
                continue
            end

            # Non-PSD constraints.
            if startswith(line, "CON")
                (ncon, nlines) = (parse(Int,
                    strip(i)) for i in split(strip(readline(io))))
                idx = 0
                for k in 1:nlines
                    coneinfo = split(strip(readline(io)))
                    conelen = parse(Int, coneinfo[2])
                    push!(conecons, (coneinfo[1], conelen))
                    idx += conelen
                end
                @assert idx == ncon
                append!(conterms,
                    Vector{MOI.ScalarAffineTerm{Float64}}() for i in 1:ncon)
                append!(conconst, zeros(ncon))
                continue
            end

            if startswith(line, "FCOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    linesplit = split(strip(readline(io)))
                    @assert length(linesplit) == 5
                    (a, b, c, d) = (parse(Int, linesplit[i]) + 1 for i in 1:4)
                    val = parse(Float64, linesplit[end])
                    if c != d
                        val += val # scale off-diagonals
                    end
                    vidx = mattovecidx(c, d)
                    push!(conterms[a], MOI.ScalarAffineTerm(val, X[b][vidx]))
                end
                continue
            end

            if startswith(line, "ACOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    linesplit = split(strip(readline(io)))
                    @assert length(linesplit) == 3
                    (a, b) = (parse(Int, linesplit[i]) + 1 for i in 1:2)
                    val = parse(Float64, linesplit[end])
                    push!(conterms[a], MOI.ScalarAffineTerm(val, x[b]))
                end
                continue
            end

            if startswith(line, "BCOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    linesplit = split(strip(readline(io)))
                    @assert length(linesplit) == 2
                    a = parse(Int, linesplit[1]) + 1
                    conconst[a] = parse(Float64, linesplit[end])
                end
                continue
            end

            # PSD constraints.
            if startswith(line, "PSDCON")
                idx = 0
                for k in 1:parse(Int, strip(readline(io)))
                    side = parse(Int, strip(readline(io)))
                    push!(psdcons, (side, idx))
                    idx += div(side*(side+1), 2)
                end
                append!(psdterms,
                    Vector{MOI.ScalarAffineTerm{Float64}}() for i in 1:idx)
                append!(psdconst, zeros(idx))
                continue
            end

            if startswith(line, "HCOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    linesplit = split(strip(readline(io)))
                    @assert length(linesplit) == 5
                    (a, b, c, d) = (parse(Int, linesplit[i]) + 1 for i in 1:4)
                    val = parse(Float64, linesplit[end])
                    cidx = psdcons[a][2] + mattovecidx(c, d)
                    push!(psdterms[cidx], MOI.ScalarAffineTerm(val, x[b]))
                end
                continue
            end

            if startswith(line, "DCOORD")
                for k in 1:parse(Int, strip(readline(io)))
                    linesplit = split(strip(readline(io)))
                    @assert length(linesplit) == 4
                    (a, b, c) = (parse(Int, linesplit[i]) + 1 for i in 1:3)
                    cidx = psdcons[a][2] + mattovecidx(b, c)
                    psdconst[cidx] += parse(Float64, linesplit[end])
                end
                continue
            end
        end
    end

    # Objective function.
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
        MOI.ScalarAffineFunction(objterms, objconst))

    # Non-PSD constraints.
    idx = 0
    for (conename, conelen) in conecons
        if conename == "F" # Free cones (no constraint).
            idx += conelen
            continue
        end
        if conename in ("EXP", "EXP*") # Exponential cones.
            @assert conelen == 3
            vats = [MOI.VectorAffineTerm(4-l, t) for l in 1:conelen
                for t in conterms[idx+l]]
            F = MOI.VectorAffineFunction(vats, conconst[[idx+3, idx+2, idx+1]])
            if conename == "EXP"
                S = MOI.ExponentialCone()
            else
                S = MOI.DualExponentialCone()
            end
        else
            vats = [MOI.VectorAffineTerm(l, t) for l in 1:conelen
                for t in conterms[idx+l]]
            F = MOI.VectorAffineFunction(vats, conconst[idx .+ (1:conelen)])
            if conename in ("POWER", "POWER*") # Power cones.
                error("Power cones are not yet supported.")
            elseif conename == "L=" # Zero cones.
                S = MOI.Zeros(conelen)
            elseif conename == "L-" # Nonpositive cones.
                S = MOI.Nonpositives(conelen)
            elseif conename == "L+" # Nonnegative cones.
                S = MOI.Nonnegatives(conelen)
            elseif conename == "Q" # Second-order cones.
                @assert conelen >= 3
                S = MOI.SecondOrderCone(conelen)
            elseif conename == "QR" # Rotated second-order cones.
                @assert conelen >= 3
                S = MOI.RotatedSecondOrderCone(conelen)
            else
                error("cone type $conename is not recognized")
            end
        end
        MOI.add_constraint(model, F, S)
        idx += conelen
    end

    # PSD constraints.
    idx = 0
    for (side, conelen) in psdcons
        vats = [MOI.VectorAffineTerm(l, t) for l in 1:conelen
            for t in psdterms[idx+l]]
        F = MOI.VectorAffineFunction(vats, psdconst[idx .+ (1:conelen)])
        S = MOI.PositiveSemidefiniteConeTriangle(side)
        MOI.add_constraint(model, F, S)
        idx += conelen
    end

    return
end

end
