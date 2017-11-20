using MathOptFormat, MPSWriter, MathOptInterface
const MOI = MathOptInterface

function MOFtoMPB(instance::MathOptFormat.MOFInstance)
    nvar = MOI.get(instance, MOI.NumberOfVariables())
    collb, colub, c, colcat = fill(-Inf, nvar), fill(Inf, nvar), zeros(nvar), fill(:Cont, nvar)
    rowlb, rowub, rownames = Float64[], Float64[], String[]
    vars = MOI.get(instance, MOI.ListOfVariableReferences())
    colnames = [MOI.get(instance, MOI.VariableName(), v) for v in vars]
    sense = MOI.get(instance, MOI.ObjectiveSense()) == MOI.MaxSense ? :Max : :Min
    Qrowidx = Int[]
    Qcolidx = Int[]
    Qcoeffs = Float64[]
    objf = MOI.get(instance, MOI.ObjectiveFunction())
    if objf.constant != zero(Float64)
        error("MPS File does not support constant term in objective.")
    end
    if isa(objf, MOI.ScalarAffineFunction)
        for (var, coef) in zip(objf.variables, objf.coefficients)
            idx = findfirst(vars, var)
            c[idx] += coef
        end
    else
        for (var, coef) in zip(objf.affine_variables, objf.affine_coefficients)
            idx = findfirst(vars, var)
            c[idx] += coef
        end
        for (rowvar, colvar, coef) in zip(objf.quadratic_rowvariables, objf.quadratic_colvariables, objf.quadratic_coefficients)
            push!(Qrowidx, findfirst(vars, rowvar))
            push!(Qcolidx, findfirst(vars, colvar))
            push!(Qcoeffs, coef)
        end
    end
    # Variable Bounds
    for S in [MOI.LessThan{Float64}, MOI.GreaterThan{Float64}, MOI.Interval{Float64}, MOI.EqualTo{Float64}]
        for reference in MOI.get(instance, MOI.ListOfConstraintReferences{MOI.SingleVariable,S}())
            func = MOI.get(instance, MOI.ConstraintFunction(), reference)
            set  = MOI.get(instance, MOI.ConstraintSet(), reference)
            idx = findfirst(vars, func.variable)
            updatebounds!(collb, colub, idx, set)
        end
    end
    # Variable Categories
    for S in [MOI.ZeroOne, MOI.Integer]
        for reference in MOI.get(instance, MOI.ListOfConstraintReferences{MOI.SingleVariable,S}())
            func = MOI.get(instance, MOI.ConstraintFunction(), reference)
            set  = MOI.get(instance, MOI.ConstraintSet(), reference)
            idx = findfirst(vars, func.variable)
            updatecategory!(colcat, idx, set)
        end
    end
    # Linear Constraints
    numrow = 0
    rowidx = Int[]
    colidx = Int[]
    coeffs = Float64[]
    for S in [MOI.LessThan{Float64}, MOI.GreaterThan{Float64}, MOI.Interval{Float64}, MOI.EqualTo{Float64}]
        for reference in MOI.get(instance, MOI.ListOfConstraintReferences{MOI.ScalarAffineFunction{Float64},S}())
            numrow += 1
            func = MOI.get(instance, MOI.ConstraintFunction(), reference)
            set  = MOI.get(instance, MOI.ConstraintSet(), reference)
            constant = updateconstraintmatrix!(rowidx, colidx, coeffs, numrow, vars, func)
            push!(rowlb, -Inf)
            push!(rowub, Inf)
            updatebounds!(rowlb, rowub, numrow, set, constant)
            push!(rownames, MOI.get(instance, MOI.ConstraintName(), reference))
        end
    end
    # SOS
    sos = Tuple{Int, Vector{Int}, Vector{Float64}}[]
    for (typ, S) in [(1, MOI.SOS1{Float64}), (2, MOI.SOS2{Float64})]
        for reference in MOI.get(instance, MOI.ListOfConstraintReferences{MOI.VectorOfVariables,S}())
            func = MOI.get(instance, MOI.ConstraintFunction(), reference)
            set  = MOI.get(instance, MOI.ConstraintSet(), reference)
            idxs = [findfirst(vars, var) for var in func.variables]
            weights = set.weights
            push!(sos, (typ, idxs, weights))
        end
    end

    return sparse(rowidx, colidx, coeffs, numrow, nvar), collb, colub, c, rowlb, rowub, sense, colcat, sos, sparse(Qrowidx, Qcolidx, Qcoeffs, nvar, nvar), "MOFtoMPS", colnames, rownames
end

function updateconstraintmatrix!(rowidx, colidx, coeffs, i, vars::Vector{MOI.VariableReference}, func::MOI.ScalarAffineFunction{Float64})
    for (var, coef) in zip(func.variables, func.coefficients)
        j = findfirst(vars, var)
        push!(rowidx, i)
        push!(colidx, j)
        push!(coeffs, coef)
    end
    return func.constant
end

function updatebounds!(collb, colub, idx, set::MOI.LessThan{Float64}, constant::Float64=0.0)
    colub[idx] = set.upper - constant
end
function updatebounds!(collb, colub, idx, set::MOI.GreaterThan{Float64}, constant::Float64=0.0)
    collb[idx] = set.lower - constant
end
function updatebounds!(collb, colub, idx, set::MOI.Interval{Float64}, constant::Float64=0.0)
    colub[idx] = set.upper - constant
    collb[idx] = set.lower - constant
end
function updatebounds!(collb, colub, idx, set::MOI.EqualTo{Float64}, constant::Float64=0.0)
    colub[idx] = set.value - constant
    collb[idx] = set.value - constant
end
function updatecategory!(colcat, idx, set::MOI.ZeroOne)
    colcat[idx] = :Bin
end
function updatecategory!(colcat, idx, set::MOI.Integer)
    colcat[idx] = :Int
end

function MOFtoMPS(io, instance::MathOptFormat.MOFInstance)
    MPSWriter.writemps(io, MOFtoMPB(instance)...)
end

function MOFtoLP(io, instance::MathOptFormat.MOFInstance)
    LPWriter.writelp(io, MOFtoMPB(instance)...)
end
