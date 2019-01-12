const CBF = MathOptFormat.CBF

const CBF_TEST_FILE = "test.cbf"

@test sprint(show, CBF.Model()) == "A Conic Benchmark Format (CBF) model"

function test_model_equality(model_string, variables, constraints)
    model = CBF.Model()
    MOIU.loadfromstring!(model, model_string)
    MOI.write_to_file(model, CBF_TEST_FILE)
    model_2 = CBF.Model()
    MOI.read_from_file(model_2, CBF_TEST_FILE)
    MOIU.test_models_equal(model, model_2, variables, constraints)
end

@testset "Errors" begin
    @testset "Non-empty model" begin
        model = CBF.Model()
        x = MOI.add_variable(model)
        @test_throws Exception MOI.read_from_file(
            model, joinpath("CBF", "failing_models", "bad_name.cbf"))
    end

    @testset "$(filename)" for filename in filter(
        f -> endswith(f, ".cbf"), readdir("CBF/failing_models"))
        @test_throws Exception MOI.read_from_file(CBF.Model(),
            joinpath("CBF", "failing_models", filename))
    end
end

@testset "Maximization problems" begin
    model = CBF.Model()
    x = MOI.add_variable(model)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.set(model, MOI.ObjectiveFunction{MOI.SingleVariable}(),
        MOI.SingleVariable(x))
end

@testset "Round trips" begin
    @testset "min objective" begin
        test_model_equality("""
            variables: x
            minobjective: x
        """, ["x"], String[])
    end
    @testset "min scalaraffine" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x
        """, ["x"], String[])
    end
end

# Clean up
sleep(1.0)  # Allow time for unlink to happen.
rm(CBF_TEST_FILE, force = true)
