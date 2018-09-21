function roundtrip_nonlinear_expression(expr, variable_to_string,
                                        string_to_variable)
    node_list = MathOptFormat.Object[]
    object = MathOptFormat.convert_expr_to_mof(expr, node_list,
                                               variable_to_string)
    @test MathOptFormat.convert_mof_to_expr(object, node_list,
                                            string_to_variable) == expr
end

@testset "Nonlinear functions" begin
    @testset "Error handling" begin
        node_list = MathOptFormat.Object[]
        string_to_variable = Dict{String, MOI.VariableIndex}()
        variable_to_string = Dict{MOI.VariableIndex, String}()
        # Test unsupported function for Expr -> MOF.
        @test_throws Exception MathOptFormat.convert_expr_to_mof(
            :(not_supported_function(x)), node_list, variable_to_string)
        # Test unsupported function for MOF -> Expr.
        @test_throws Exception MathOptFormat.convert_mof_to_expr(
            MathOptFormat.Object("head"=>"not_supported_function", "value"=>1),
            node_list, string_to_variable)
        # Test n-ary function with no arguments.
        @test_throws Exception MathOptFormat.convert_expr_to_mof(
            :(min()), node_list, variable_to_string)
        # Test unary function with two arguments.
        @test_throws Exception MathOptFormat.convert_expr_to_mof(
            :(sin(x, y)), node_list, variable_to_string)
        # Test binary function with one arguments.
        @test_throws Exception MathOptFormat.convert_expr_to_mof(
            :(^(x)), node_list, variable_to_string)
        # An expression with something other than :call as the head.
        @test_throws Exception MathOptFormat.convert_expr_to_mof(
            :(a <= b <= c), node_list, variable_to_string)
        # Hit the default fallback with an un-interpolated complex number.
        @test_throws Exception MathOptFormat.convert_expr_to_mof(
            :(1 + 2im), node_list, variable_to_string)

    end
    @testset "Roundtrip nonlinear expressions" begin
        x = MOI.VariableIndex(123)
        y = MOI.VariableIndex(456)
        z = MOI.VariableIndex(789)
        string_to_var = Dict{String, MOI.VariableIndex}("x"=>x, "y"=>y, "z"=>z)
        var_to_string = Dict{MOI.VariableIndex, String}(x=>"x", y=>"y", z=>"z")
        for expr in [2, 2.34, 2 + 3im, x, :(1 + $x), :($x - 1),
                     :($x + $y), :($x + $y - $z), :(2 * $x), :($x * $y),
                     :($x / 2), :(2 / $x), :($x / $y), :($x / $y / $z), :(2^$x),
                     :($x^2), :($x^$y), :($x^(2 * $y + 1)), :(sin($x)),
                     :(sin($x + $y)), :(2 * $x + sin($x)^2 + $y),
                     :(sin($(3im))^2 + cos($(3im))^2), :($(1 + 2im) * $x)]
            roundtrip_nonlinear_expression(expr, var_to_string, string_to_var)
        end
    end
    @testset "Reading and Writing" begin
        # Write to file.
        model = MathOptFormat.Model()
        (x, y) = MOI.add_variables(model, 2)
        MOI.set(model, MOI.VariableName(), x, "var_x")
        MOI.set(model, MOI.VariableName(), y, "y")
        con = MOI.add_constraint(model,
                 MathOptFormat.Nonlinear(:(2 * $x + sin($x)^2 - $y)),
                 MOI.EqualTo(1.0))
        MOI.set(model, MOI.ConstraintName(), con, "con")
        MOI.write_to_file(model, "test.mof.json")
        # Read the model back in.
        model2 = MathOptFormat.Model()
        MOI.read_from_file(model2, "test.mof.json")
        con2 = MOI.get(model2, MOI.ConstraintIndex, "con")
        foo2 = MOI.get(model2, MOI.ConstraintFunction(), con2)
        # Test that we recover the constraint.
        @test foo2.expr == :(2 * $x + sin($x)^2 - $y)
        @test MOI.get(model, MOI.ConstraintSet(), con) ==
                MOI.get(model2, MOI.ConstraintSet(), con2)
    end
end
