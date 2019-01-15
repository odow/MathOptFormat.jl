const CBF = MathOptFormat.CBF

const CBF_TEST_FILE = "test.cbf"

@test sprint(show, CBF.Model()) == "A Conic Benchmark Format (CBF) model"

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
    model = CBF.Model()
    MOIU.loadfromstring!(model, model_string)
    (variable_names, constraint_names) = set_names(model)

    MOI.write_to_file(model, CBF_TEST_FILE)
    model_2 = CBF.Model()
    MOI.read_from_file(model_2, CBF_TEST_FILE)
    set_names(model_2)

    MOIU.test_models_equal(model, model_2, variable_names, constraint_names)
end

@testset "Errors" begin
    failing_models_dir = joinpath(@__DIR__, "failing_models")

    @testset "Non-empty model" begin
        model = CBF.Model()
        MOI.add_variable(model)
        @test_throws Exception MOI.read_from_file(model,
            joinpath(failing_models_dir, "bad_name.cbf"))
    end

    @testset "$(filename)" for filename in filter(f -> endswith(f, ".cbf"),
        readdir(failing_models_dir))
        @test_throws Exception MOI.read_from_file(CBF.Model(),
            joinpath(failing_models_dir, filename))
    end
end

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

    @testset "VectorAffine-in-Nonnegatives" begin
        test_model_equality("""
            variables: x, y
            minobjective: 1.2x
            c1: [1.1 * x, y + 1] in Nonnegatives(2)
        """)
    end
    @testset "VectorAffine-in-Nonpositives" begin
        test_model_equality("""
            variables: x
            minobjective: 1.2x
            c1: [-1.1 * x + 1] in Nonpositives(1)
        """)
    end
    @testset "VectorAffine-in-Zeros" begin
        test_model_equality("""
            variables: x, y
            minobjective: 1.2x
            c1: [x + 2y + -1.1, 0] in Zeros(2)
        """)
    end
end

# Clean up.
sleep(1.0)  # Allow time for unlink to happen.
rm(CBF_TEST_FILE, force = true)
