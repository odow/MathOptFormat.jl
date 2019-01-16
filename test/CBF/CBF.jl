const CBF = MathOptFormat.CBF

const CBF_TEST_FILE = "test.cbf"
const MODELS_DIR = joinpath(@__DIR__, "models")


function set_var_and_con_names(model::MOI.ModelLike)
    variable_names = String[]
    for j in MOI.get(model, MOI.ListOfVariableIndices())
        var_name_j = "v" * string(j.value)
        push!(variable_names, var_name_j)
        MOI.set(model, MOI.VariableName(), j, var_name_j)
    end

    constraint_names = String[]
    for (con_func, con_set) in MOI.get(model, MOI.ListOfConstraints()),
        i in MOI.get(model, MOI.ListOfConstraintIndices{con_func, con_set}())
        con_name_i = "c" * string(i.value)
        push!(constraint_names, con_name_i)
        MOI.set(model, MOI.ConstraintName(), i, con_name_i)
    end

    return (variable_names, constraint_names)
end

Base.isapprox(f::MOI.VectorOfVariables, g::MOI.VectorAffineFunction{Float64};
    kwargs...) = isapprox(MOI.VectorAffineFunction{Float64}(f), g)

function test_model_write_then_read(model_string::String)
    model1 = CBF.Model()
    MOIU.loadfromstring!(model1, model_string)
    (variable_names, constraint_names) = set_var_and_con_names(model1)

    MOI.write_to_file(model1, CBF_TEST_FILE)
    model2 = CBF.Model()
    MOI.read_from_file(model2, CBF_TEST_FILE)
    set_var_and_con_names(model2)

    MOIU.test_models_equal(model1, model2, variable_names, constraint_names)
end

function test_cbf_read(filename::String, model_string::String)
    model1 = CBF.Model()
    MOIU.loadfromstring!(model1, model_string)
    (variable_names, constraint_names) = set_var_and_con_names(model1)

    model2 = CBF.Model()
    MOI.read_from_file(model2, filename)
    set_var_and_con_names(model2)

    MOIU.test_models_equal(model1, model2, variable_names, constraint_names)
end


@test sprint(show, CBF.Model()) == "A Conic Benchmark Format (CBF) model"

@testset "Error for non-empty model" begin
    model = CBF.Model()
    MOI.add_variable(model)
    @test_throws Exception MOI.read_from_file(model,
        joinpath(MODELS_DIR, "example1.cbf"))
end

@testset "Error for incompatible version" begin
    model = CBF.Model()
    @test_throws Exception MOI.read_from_file(model,
        joinpath(MODELS_DIR, "incompatible_version.cbf"))
end

corrupted_line_models = ["corrupted_line_A.cbf", "corrupted_line_B.cbf",
    "corrupted_line_C.cbf", "corrupted_line_D.cbf"]
@testset "Error for $filename" for filename in corrupted_line_models
    model = CBF.Model()
    @test_throws Exception MOI.read_from_file(model,
        joinpath(MODELS_DIR, filename))
end

example_models = [
    ("example_A.cbf", """
        variables: U, V, W, X, Y, Z, x, y, z
        minobjective: y + 2U + 2V + 2W + 2Y + 2Z
        c1: [U, V, W, X, Y, Z] in PositiveSemidefiniteConeTriangle(3)
        c2: [y + U + W + Z + -1, x + z + U + 2V + W + 2X + 2Y + Z + -0.5] in Zeros(2)
        c3: [y, x, z] in SecondOrderCone(3)
    """),
    ("example_B.cbf", """
        variables: X, Y, Z, x, y
        minobjective: 1 + x + y + X + Z
        c1: [X, Y, Z] in PositiveSemidefiniteConeTriangle(2)
        c2: [2Y + -1x + -1y] in Nonnegatives(1)
        c3: [3y + -1, x + y, 3x + -1] in PositiveSemidefiniteConeTriangle(2)
    """),
    ("example_C.cbf", """
        variables: a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p
        maxobjective: a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p + -1
        c1: [b] in Zeros(1)
        c2: [c] in Nonnegatives(1)
        c3: [d] in Nonpositives(1)
        c4: [e, f, g] in SecondOrderCone(3)
        c5: [h, i, j] in RotatedSecondOrderCone(3)
        c6: [m, l, k] in ExponentialCone()
        c7: [p, o, n] in DualExponentialCone()
    """),
    ("example_D.cbf", """
        variables: u, v, w, x, y, z
        maxobjective: w + z
        c1: [u, v, w] in PowerCone(0.5)
        c2: [x, y, z] in DualPowerCone(0.5)
        c3: [1, u, u + v] in PowerCone(0.75)
        c4: [1, y, x + y] in DualPowerCone(0.75)
    """),
]
@testset "Read CBF $filename" for (filename, model_string) in example_models
    test_cbf_read(joinpath(MODELS_DIR, filename), model_string)
end

# TODO quadratic objective not supported test

# TODO NLP not supported test

# TODO Feasibility sense not supported test

write_read_models = [
    ("min SingleVariable", """
        variables: x
        minobjective: x
    """),
    ("min ScalarAffine", """
        variables: x, y
        minobjective: 1.2x + -1y + 1
    """),
    ("max SingleVariable", """
        variables: x
        maxobjective: x
    """),
    ("max ScalarAffine", """
        variables: x, y
        maxobjective: 1.2x + -1y + 1
    """),
    ("SingleVariable in Integer", """
        variables: x, y
        minobjective: 1.2x
        c1: y in Integer()
    """),
    ("VectorOfVariables in Nonnegatives", """
        variables: x, y
        minobjective: x
        c1: [x, y] in Nonnegatives(2)
    """),
    ("VectorOfVariables in Nonpositives", """
        variables: x, y
        minobjective: x
        c1: [y, x] in Nonpositives(2)
    """),
    ("VectorOfVariables in Reals", """
        variables: x, y
        minobjective: x
        c1: [x, y] in Reals(2)
    """),
    ("VectorAffineFunction in Nonnegatives", """
        variables: x, y
        minobjective: 1.2x
        c1: [1.1 * x, y + 1] in Nonnegatives(2)
    """),
    ("VectorAffineFunction in Nonpositives", """
        variables: x
        minobjective: 1.2x
        c1: [-1.1 * x + 1] in Nonpositives(1)
    """),
    ("VectorAffineFunction in Zeros", """
        variables: x, y
        minobjective: 1.2x
        c1: [x + 2y + -1.1, 0] in Zeros(2)
    """),
    ("VectorAffineFunction in Reals", """
        variables: x, y
        minobjective: 1.2x
        c1: [1x, 2y] in Reals(2)
    """),
    ("VectorOfVariables in SecondOrderCone", """
        variables: x, y, z
        minobjective: x
        c1: [x, y, z] in SecondOrderCone(3)
    """),
    ("VectorOfVariables in RotatedSecondOrderCone", """
        variables: x, y, z
        minobjective: x
        c1: [x, y, z] in RotatedSecondOrderCone(3)
    """),
    ("VectorOfVariables in ExponentialCone", """
        variables: x, y, z
        minobjective: x
        c1: [x, y, z] in ExponentialCone()
    """),
    ("VectorOfVariables in DualExponentialCone", """
        variables: x, y, z
        minobjective: x
        c1: [x, y, z] in DualExponentialCone()
    """),
    # ("VectorOfVariables in PowerCone", """
    #     variables: x, y, z
    #     minobjective: x
    #     c1: [x, y, z] in PowerCone(2.0)
    # """),
    # ("VectorOfVariables in DualPowerCone", """
    #     variables: x, y, z
    #     minobjective: x
    #     c1: [x, y, z] in DualPowerCone(2.0)
    # """),
    ("VectorOfVariables in PositiveSemidefiniteConeTriangle", """
        variables: x, y, z
        minobjective: x
        c1: [x, y, z] in PositiveSemidefiniteConeTriangle(2)
    """),
    ("VectorAffineFunction in SecondOrderCone", """
        variables: x, y, z
        minobjective: 1.2x
        c1: [1.1x, y + 1, 2x + z] in SecondOrderCone(3)
    """),
    ("VectorAffineFunction in RotatedSecondOrderCone", """
        variables: x, y, z
        minobjective: 1.2x
        c1: [1.1x, y + 1, 2x + z] in RotatedSecondOrderCone(3)
    """),
    ("VectorAffineFunction in ExponentialCone", """
        variables: x, y, z
        minobjective: 1.2x
        c1: [1.1x, y + 1, 2x + z] in ExponentialCone()
    """),
    ("VectorAffineFunction in DualExponentialCone", """
        variables: x, y, z
        minobjective: 1.2x
        c1: [1.1x, y + 1, 2x + z] in DualExponentialCone()
    """),
    # ("VectorAffineFunction in PowerCone", """
    #     variables: x, y, z
    #     minobjective: 1.2x
    #     c1: [1.1x, y + 1, 2x + z] in PowerCone(2.0)
    # """),
    # ("VectorAffineFunction in DualPowerCone", """
    #     variables: x, y, z
    #     minobjective: 1.2x
    #     c1: [1.1x, y + 1, 2x + z] in DualPowerCone(2.0)
    # """),
    ("VectorAffineFunction in PositiveSemidefiniteConeTriangle", """
        variables: x, y, z
        minobjective: 1.2x
        c1: [1.1x, y + 1, 2x + z] in PositiveSemidefiniteConeTriangle(2)
    """),
]
@testset "Write/read for $model_name" for (model_name, model_string) in
    write_read_models
    test_model_write_then_read(model_string)
end

# Clean up.
sleep(1.0)  # Allow time for unlink to happen.
rm(CBF_TEST_FILE, force = true)
