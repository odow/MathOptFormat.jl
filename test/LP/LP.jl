const LP = MathOptFormat.LP

const LP_TEST_FILE = "test.lp"

@test sprint(show, LP.Model()) == "A .LP-file model"

@testset "write_to_file" begin
    @testset "comprehensive write" begin
        model = LP.Model()
        MOIU.loadfromstring!(model, """
        variables: a, x, y, z
        minobjective: x
        c1: x >= -1.0
        c2: x <= 2.0
        c3: y == 3.0
        c4: z in Interval(4.0, 5.0)
        c5: 1.1x + 0.0 <= 5.1
        c6: 1.3x + -1.4 >= -0.1
        c7: 1.5a + 1.6 == 0.2
        c8: 1.7a + 1.8 in Interval(0.3, 0.4)
        c9: x in ZeroOne()
        c10: y in Integer()
        """)
        MOI.write_to_file(model, LP_TEST_FILE)
        @test read(LP_TEST_FILE, String) ==
            "minimize\n" *
            "obj: x\n" *
            "subject to\n" *
            "c5: 1.1 x <= 5.1\n" *
            "c6: -1.4 + 1.3 x >= -0.1\n" *
            "c7: 1.6 + 1.5 a = 0.2\n" *
            "c8: 0.3 <= 1.8 + 1.7 a <= 0.4\n" *
            "Bounds\n" *
            "x <= 2\n" *
            "x >= -1\n" *
            "y = 3\n" *
            "4 <= z <= 5\n" *
            "General\n" *
            "y\n" *
            "Binary\n" *
            "x\n" *
            "End\n"
    end

    @testset "Name sanitisation" begin
        @testset "verifyname" begin
            @test LP.verifyname("x")
            @test LP.verifyname(repeat("x", LP.MAX_LENGTH))

            @test LP.verifyname(repeat("x", LP.MAX_LENGTH + 1)) == false
            @test LP.verifyname(".x") == false
            @test LP.verifyname("0x") == false
            @test LP.verifyname("exe") == false
            @test LP.verifyname("ExE") == false

            @test LP.verifyname("x^") == false
            @test LP.verifyname("x*ds") == false
        end

        @testset "correctname" begin
            @test LP.correctname("x") == "x"
            @test LP.correctname(repeat("x", LP.MAX_LENGTH)) == repeat("x", LP.MAX_LENGTH)

            too_long = repeat("x", LP.MAX_LENGTH + 1)
            @test (@test_logs (:warn, "Name $(too_long) too long (length: $(length(too_long))). Truncating.") LP.correctname(too_long)) == repeat("x", LP.MAX_LENGTH)

            @test (@test_logs (:warn, "Name .x cannot start with a period, a number, e, or E. Prepending an underscore to name.") LP.correctname(".x")) == "_.x"
            @test (@test_logs (:warn, "Name 0x cannot start with a period, a number, e, or E. Prepending an underscore to name.") LP.correctname("0x")) == "_0x"
            @test (@test_logs (:warn, "Name Ex cannot start with a period, a number, e, or E. Prepending an underscore to name.") LP.correctname("Ex")) == "_Ex"
            @test (@test_logs (:warn, "Name ex cannot start with a period, a number, e, or E. Prepending an underscore to name.") LP.correctname("ex")) == "_ex"

            @test (@test_logs (:warn, "Name x*ds contains an illegal character: \"*\". Removing the offending character from name.") LP.correctname("x*ds")) == "x_ds"
            @test (@test_logs (:warn, "Name x^ contains an illegal character: \"^\". Removing the offending character from name.") LP.correctname("x^")) == "x_"
            @test (@test_logs (:warn, "Name x*ds[1] contains an illegal character: \"*\". Removing the offending character from name.") LP.correctname("x*ds[1]")) == "x_ds_1_"
            @test (@test_logs (:warn, "Name Ex*ds[1] cannot start with a period, a number, e, or E. Prepending an underscore to name.") (:warn, "Name _Ex*ds[1] contains an illegal character: \"*\". Removing the offending character from name.") LP.correctname("Ex*ds[1]")) == "_Ex_ds_1_"
        end

        @testset "Whole chain" begin
            model = LP.Model()
            MOIU.loadfromstring!(model, """
            variables: a
            minobjective: a
            c1: a >= -1.0
            """)
            MOI.set(model, MOI.VariableName(), MOI.get(model, MOI.ListOfVariableIndices())[1], "a[]")

            @test_logs (:warn, "Name a[] contains an illegal character: \"[\". Removing the offending character from name.") MOI.write_to_file(model, LP_TEST_FILE)
        end
    end

    @testset "other features" begin
        model = LP.Model()
        MOIU.loadfromstring!(model, """
        variables: x
        maxobjective: 2.0 * x + -1.0
        """)
        MOI.write_to_file(model, LP_TEST_FILE)
        @test read(LP_TEST_FILE, String) ==
            "maximize\n" *
            "obj: -1 + 2 x\n" *
            "subject to\n" *
            "Bounds\n" *
            "End\n"
    end
end

@testset "read_from_file" begin
    model = LP.Model()
    exception = ErrorException("Read from file is not implemented for LP files.")
    @test_throws exception MOI.read_from_file(model, LP_TEST_FILE)
    @test_throws exception MathOptFormat.read_from_file(LP_TEST_FILE)
end

# Clean up
sleep(1.0)  # Allow time for unlink to happen.
rm(LP_TEST_FILE, force = true)
