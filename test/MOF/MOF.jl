const MOF = MathOptFormat.MOF

const TEST_MOF_FILE = "test.mof.json"

@test sprint(show, MOF.Model()) == "A MathOptFormat Model"

include("nonlinear.jl")

struct UnsupportedSet <: MOI.AbstractSet end
struct UnsupportedFunction <: MOI.AbstractFunction end

function test_model_equality(model_string, variables, constraints)
    model = MOF.Model()
    MOIU.loadfromstring!(model, model_string)
    MOI.write_to_file(model, TEST_MOF_FILE)
    model_2 = MOF.Model()
    MOI.read_from_file(model_2, TEST_MOF_FILE)
    MOIU.test_models_equal(model, model_2, variables, constraints)
end

@testset "Error handling: read_from_file" begin
    failing_models_dir = joinpath(@__DIR__, "failing_models")

    @testset "Non-empty model" begin
        model = MOF.Model()
        MOI.add_variable(model)
        @test_throws Exception MOI.read_from_file(
            model, joinpath(failing_models_dir, "empty_model.mof.json"))
    end

    @testset "$(filename)" for filename in filter(
        f -> endswith(f, ".mof.json"), readdir(failing_models_dir))
        @test_throws Exception MOI.read_from_file(MOF.Model(),
            joinpath(failing_models_dir, filename))
    end
end

@testset "round trips" begin
    @testset "Empty model" begin
        model = MOF.Model()
        MOI.write_to_file(model, TEST_MOF_FILE)
        model_2 = MOF.Model()
        MOI.read_from_file(model_2, TEST_MOF_FILE)
        MOIU.test_models_equal(model, model_2, String[], String[])
    end
    @testset "Blank variable name" begin
        model = MOF.Model()
        variable_index = MOI.add_variable(model)
        @test MOF.moi_to_object(variable_index, model) ==
            MOF.Object("name" => "x1")
    end
    @testset "FEASIBILITY_SENSE" begin
        model = MOF.Model()
        x = MOI.add_variable(model)
        MOI.set(model, MOI.VariableName(), x, "x")
        MOI.set(model, MOI.ObjectiveSense(), MOI.FEASIBILITY_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{MOI.SingleVariable}(),
            MOI.SingleVariable(x))
        MOI.write_to_file(model, TEST_MOF_FILE)
        model_2 = MOF.Model()
        MOI.read_from_file(model_2, TEST_MOF_FILE)
        MOIU.test_models_equal(model, model_2, ["x"], String[])
    end
    @testset "Empty function term" begin
        model = MOF.Model()
        x = MOI.add_variable(model)
        MOI.set(model, MOI.VariableName(), x, "x")
        c = MOI.add_constraint(model,
            MOI.ScalarAffineFunction(MOI.ScalarAffineTerm{Float64}[], 0.0),
            MOI.GreaterThan(1.0)
        )
        MOI.set(model, MOI.ConstraintName(), c, "c")
        MOI.write_to_file(model, TEST_MOF_FILE)
        model_2 = MOF.Model()
        MOI.read_from_file(model_2, TEST_MOF_FILE)
        MOIU.test_models_equal(model, model_2, ["x"], ["c"])
    end
    @testset "min objective" begin
        test_model_equality("""
            variables: x
            minobjective: x
        """, ["x"], String[])
    end
    @testset "max objective" begin
        test_model_equality("""
            variables: x
            maxobjective: x
        """, ["x"], String[])
    end
    @testset "min scalaraffine" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x + 0.5
        """, ["x"], String[])
    end
    @testset "max scalaraffine" begin
        test_model_equality("""
            variables: x
            maxobjective: 1.2x + 0.5
        """, ["x"], String[])
    end
    @testset "singlevariable-in-lower" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x + 0.5
            c1: x >= 1.0
        """, ["x"], ["c1"])
    end
    @testset "singlevariable-in-upper" begin
        test_model_equality("""
            variables: x
            maxobjective: 1.2x + 0.5
            c1: x <= 1.0
        """, ["x"], ["c1"])
    end
    @testset "singlevariable-in-interval" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x + 0.5
            c1: x in Interval(1.0, 2.0)
        """, ["x"], ["c1"])
    end
    @testset "singlevariable-in-equalto" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x + 0.5
            c1: x == 1.0
        """, ["x"], ["c1"])
    end
    @testset "singlevariable-in-zeroone" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x + 0.5
            c1: x in ZeroOne()
        """, ["x"], ["c1"])
    end
    @testset "singlevariable-in-integer" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x + 0.5
            c1: x in Integer()
        """, ["x"], ["c1"])
    end
    @testset "singlevariable-in-Semicontinuous" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x + 0.5
            c1: x in Semicontinuous(1.0, 2.0)
        """, ["x"], ["c1"])
    end
    @testset "singlevariable-in-Semiinteger" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x + 0.5
            c1: x in Semiinteger(1.0, 2.0)
        """, ["x"], ["c1"])
    end
    @testset "scalarquadratic-objective" begin
        test_model_equality("""
            variables: x
            minobjective: 1.0*x*x + -2.0x + 1.0
        """, ["x"], String[])
    end
    @testset "SOS1" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in SOS1([1.0, 2.0, 3.0])
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "SOS2" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in SOS2([1.0, 2.0, 3.0])
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "Reals" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in Reals(3)
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "Zeros" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in Zeros(3)
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "Nonnegatives" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in Nonnegatives(3)
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "Nonpositives" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in Nonpositives(3)
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "PowerCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in PowerCone(2.0)
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "DualPowerCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in DualPowerCone(0.5)
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "GeometricMeanCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in GeometricMeanCone(3)
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "vectoraffine-in-zeros" begin
        test_model_equality("""
            variables: x, y
            minobjective: x
            c1: [1.0x + -3.0, 2.0y + -4.0] in Zeros(2)
        """, ["x", "y"], ["c1"])
    end
    @testset "vectorquadratic-in-nonnegatives" begin
        test_model_equality("""
            variables: x, y
            minobjective: x
            c1: [1.0*x*x + -2.0x + 1.0, 2.0y + -4.0] in Nonnegatives(2)
        """, ["x", "y"], ["c1"])
    end
    @testset "ExponentialCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in ExponentialCone()
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "DualExponentialCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in DualExponentialCone()
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "SecondOrderCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in SecondOrderCone(3)
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "RotatedSecondOrderCone" begin
        test_model_equality("""
            variables: x, y, z
            minobjective: x
            c1: [x, y, z] in RotatedSecondOrderCone(3)
        """, ["x", "y", "z"], ["c1"])
    end
    @testset "PositiveSemidefiniteConeTriangle" begin
        test_model_equality("""
            variables: x1, x2, x3
            minobjective: x1
            c1: [x1, x2, x3] in PositiveSemidefiniteConeTriangle(2)
        """, ["x1", "x2", "x3"], ["c1"])
    end
    @testset "PositiveSemidefiniteConeSquare" begin
        test_model_equality("""
            variables: x1, x2, x3, x4
            minobjective: x1
            c1: [x1, x2, x3, x4] in PositiveSemidefiniteConeSquare(2)
        """, ["x1", "x2", "x3", "x4"], ["c1"])
    end
    @testset "LogDetConeTriangle" begin
        test_model_equality("""
            variables: t, u, x1, x2, x3
            minobjective: x1
            c1: [t, u, x1, x2, x3] in LogDetConeTriangle(2)
        """, ["t", "u", "x1", "x2", "x3"], ["c1"])
    end
    @testset "LogDetConeSquare" begin
        test_model_equality("""
            variables: t, u, x1, x2, x3, x4
            minobjective: x1
            c1: [t, u, x1, x2, x3, x4] in LogDetConeSquare(2)
        """, ["t", "u", "x1", "x2", "x3", "x4"], ["c1"])
    end
    @testset "RootDetConeTriangle" begin
        test_model_equality("""
            variables: t, x1, x2, x3
            minobjective: x1
            c1: [t, x1, x2, x3] in RootDetConeTriangle(2)
        """, ["t", "x1", "x2", "x3"], ["c1"])
    end
    @testset "RootDetConeSquare" begin
        test_model_equality("""
            variables: t, x1, x2, x3, x4
            minobjective: x1
            c1: [t, x1, x2, x3, x4] in RootDetConeSquare(2)
        """, ["t", "x1", "x2", "x3", "x4"], ["c1"])
    end

    # Clean up
    sleep(1.0)  # allow time for unlink to happen
    rm(TEST_MOF_FILE, force=true)
end
