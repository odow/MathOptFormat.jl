
import Base
Base.isapprox(f::MOI.VectorOfVariables, g::MOI.VectorAffineFunction{Float64};
    kwargs...) = isapprox(MOI.VectorAffineFunction{Float64}(f), g)

const CBF = MathOptFormat.CBF

const CBF_TEST_FILE = "test.cbf"
const MODELS_DIR = joinpath(@__DIR__, "models")


function set_names(model)
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

function test_model_equality(model_string)
    model1 = CBF.Model()
    MOIU.loadfromstring!(model1, model_string)
    (variable_names, constraint_names) = set_names(model1)

    MOI.write_to_file(model1, CBF_TEST_FILE)
    model2 = CBF.Model()
    MOI.read_from_file(model2, CBF_TEST_FILE)
    set_names(model2)

    MOIU.test_models_equal(model1, model2, variable_names, constraint_names)
end


@test sprint(show, CBF.Model()) == "A Conic Benchmark Format (CBF) model"

@testset "Non-empty model error" begin
    model = CBF.Model()
    MOI.add_variable(model)
    @test_throws Exception MOI.read_from_file(model,
        joinpath(MODELS_DIR, "example1.cbf"))
end

@testset "Incompatible version error" begin
    model = CBF.Model()
    @test_throws Exception MOI.read_from_file(model,
        joinpath(MODELS_DIR, "incompatible_version.cbf"))
end

@testset "Read example A" begin
    model_string = "
        variables: U, V, W, X, Y, Z, x, y, z
        minobjective: y + 2U + 2V + 2W + 2Y + 2Z
        c1: [U, V, W, X, Y, Z] in PositiveSemidefiniteConeTriangle(3)
        c2: [y + U + W + Z + -1, x + z + U + 2V + W + 2X + 2Y + Z + -0.5] in Zeros(2)
        c3: [y, x, z] in SecondOrderCone(3)
    "
    model1 = CBF.Model()
    MOIU.loadfromstring!(model1, model_string)
    (variable_names, constraint_names) = set_names(model1)

    model2 = CBF.Model()
    MOI.read_from_file(model2, joinpath(MODELS_DIR, "example_A.cbf"))
    set_names(model2)

    MOIU.test_models_equal(model1, model2, variable_names, constraint_names)
end

@testset "Read example B" begin
    model_string = "
        variables: X, Y, Z, x, y
        minobjective: 1 + x + y + X + Z
        c1: [X, Y, Z] in PositiveSemidefiniteConeTriangle(2)
        c2: [2Y + -1x + -1y] in Nonnegatives(1)
        c3: [3y + -1, x + y, 3x + -1] in PositiveSemidefiniteConeTriangle(2)
    "
    model1 = CBF.Model()
    MOIU.loadfromstring!(model1, model_string)
    (variable_names, constraint_names) = set_names(model1)

    model2 = CBF.Model()
    MOI.read_from_file(model2, joinpath(MODELS_DIR, "example_B.cbf"))
    set_names(model2)

    MOIU.test_models_equal(model1, model2, variable_names, constraint_names)
end

@testset "Read example C" begin
    model_string = "
        variables: a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p
        maxobjective: a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p + -1
        c1: [b] in Zeros(1)
        c2: [c] in Nonnegatives(1)
        c3: [d] in Nonpositives(1)
        c4: [e, f, g] in SecondOrderCone(3)
        c5: [h, i, j] in RotatedSecondOrderCone(3)
        c6: [m, l, k] in ExponentialCone()
        c7: [p, o, n] in DualExponentialCone()
    "
    model1 = CBF.Model()
    MOIU.loadfromstring!(model1, model_string)
    (variable_names, constraint_names) = set_names(model1)

    model2 = CBF.Model()
    MOI.read_from_file(model2, joinpath(MODELS_DIR, "example_C.cbf"))
    set_names(model2)

    MOIU.test_models_equal(model1, model2, variable_names, constraint_names)
end

# TODO quadratic objective not supported test

# TODO NLP not supported test

# TODO Feasibility sense not supported test

@testset "Round trips" begin
    @testset "min SingleVariable" begin
        test_model_equality("""
            variables: x
            minobjective: x
        """)
    end
    @testset "min ScalarAffine" begin
        test_model_equality("""
            variables: x, y
            minobjective: 1.2x + -1y + 1
        """)
    end
    @testset "max SingleVariable" begin
        test_model_equality("""
            variables: x
            maxobjective: x
        """)
    end
    @testset "max ScalarAffine" begin
        test_model_equality("""
            variables: x, y
            maxobjective: 1.2x + -1y + 1
        """)
    end

    @testset "SingleVariable in Integer" begin
        test_model_equality("""
            variables: x, y
            minobjective: 1.2x
            c1: y in Integer()
        """)
    end

    @testset "VectorOfVariables in Nonnegatives" begin
        test_model_equality("""
            variables: x, y
            minobjective: x
            c1: [x, y] in Nonnegatives(2)
        """)
    end
    @testset "VectorOfVariables in Nonpositives" begin
        test_model_equality("""
            variables: x, y
            minobjective: x
            c1: [y, x] in Nonpositives(2)
        """)
    end
    @testset "VectorOfVariables in Zeros" begin
        test_model_equality("""
            variables: x, y
            minobjective: x
            c1: [x, x] in Zeros(2)
        """)
    end
    @testset "VectorOfVariables in Reals" begin
        test_model_equality("""
            variables: x, y
            minobjective: x
            c1: [x, y] in Reals(2)
        """)
    end

    @testset "VectorAffineFunction in Nonnegatives" begin
        test_model_equality("""
            variables: x, y
            minobjective: 1.2x
            c1: [1.1 * x, y + 1] in Nonnegatives(2)
        """)
    end
    @testset "VectorAffineFunction in Nonpositives" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x
            c1: [-1.1 * x + 1] in Nonpositives(1)
        """)
    end
    @testset "VectorAffineFunction in Zeros" begin
        test_model_equality("""
            variables: x, y
            minobjective: 1.2x
            c1: [x + 2y + -1.1, 0] in Zeros(2)
        """)
    end
    @testset "VectorAffineFunction in Reals" begin
        test_model_equality("""
            variables: x, y
            minobjective: 1.2x
            c1: [1x, 2y] in Reals(2)
        """)
    end

    @testset "VectorOfVariables in SecondOrderCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in SecondOrderCone(3)
        """)
    end
    @testset "VectorOfVariables in RotatedSecondOrderCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in RotatedSecondOrderCone(3)
        """)
    end
    @testset "VectorOfVariables in ExponentialCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in ExponentialCone()
        """)
    end
    @testset "VectorOfVariables in DualExponentialCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in DualExponentialCone()
        """)
    end
    # @testset "VectorOfVariables in PowerCone" begin
    #     test_model_equality("""
    #         variables: x, y, z
    #         minobjective: x
    #         c1: [x, y, z] in PowerCone(2.0)
    #     """)
    # end
    # @testset "VectorOfVariables in DualPowerCone" begin
    #     test_model_equality("""
    #         variables: x, y, z
    #         minobjective: x
    #         c1: [x, y, z] in DualPowerCone(2.0)
    #     """)
    # end
    @testset "VectorOfVariables in PositiveSemidefiniteConeTriangle" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in PositiveSemidefiniteConeTriangle(2)
        """)
    end

    @testset "VectorAffineFunction in SecondOrderCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: 1.2x
            c1: [1.1x, y + 1, 2x + z] in SecondOrderCone(3)
        """)
    end
    @testset "VectorAffineFunction in RotatedSecondOrderCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: 1.2x
            c1: [1.1x, y + 1, 2x + z] in RotatedSecondOrderCone(3)
        """)
    end
    @testset "VectorAffineFunction in ExponentialCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: 1.2x
            c1: [1.1x, y + 1, 2x + z] in ExponentialCone()
        """)
    end
    @testset "VectorAffineFunction in DualExponentialCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: 1.2x
            c1: [1.1x, y + 1, 2x + z] in DualExponentialCone()
        """)
    end
    # @testset "VectorAffineFunction in PowerCone" begin
    #     test_model_equality("""
    #         variables: x, y, z
    #         minobjective: 1.2x
    #         c1: [1.1x, y + 1, 2x + z] in PowerCone(2.0)
    #     """)
    # end
    # @testset "VectorAffineFunction in DualPowerCone" begin
    #     test_model_equality("""
    #         variables: x, y, z
    #         minobjective: 1.2x
    #         c1: [1.1x, y + 1, 2x + z] in DualPowerCone(2.0)
    #     """)
    # end
    @testset "VectorAffineFunction in PositiveSemidefiniteConeTriangle" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: 1.2x
            c1: [1.1x, y + 1, 2x + z] in PositiveSemidefiniteConeTriangle(2)
        """)
    end
end

# Clean up.
sleep(1.0)  # Allow time for unlink to happen.
rm(CBF_TEST_FILE, force = true)
