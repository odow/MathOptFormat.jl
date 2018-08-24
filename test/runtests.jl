using MathOptFormat, Test

const MOI = MathOptFormat.MOI
const MOIU = MathOptFormat.MOIU

function test_model_equality(model_string, variables, constraints)
    model = MathOptFormat.MOFModel{Float64}()
    MOIU.loadfromstring!(model, model_string)
    MOI.write(model, "test.mof.json")
    model_2 = MOI.read("test.mof.json")
    MOIU.test_models_equal(model, model_2, variables, constraints)
end

@testset "round trips" begin
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
    # Clean up
    sleep(1.0)  # allow time for unlink to happen
    rm("test.mof.json", force=true)
end
