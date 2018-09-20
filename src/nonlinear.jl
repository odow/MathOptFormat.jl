# Overload for writing.
function moi_to_object(foo::Nonlinear, model::Model,
                       name_map::Dict{MOI.VariableIndex, String})
    node_list = Object[]
    foo_object = convert_expr_to_mof(foo.expr, node_list)
    return Object("head" => "Nonlinear", "root" => foo_object,
                  "node_list" => node_list)
end

# Overload for reading.
function function_to_moi(::Val{:Nonlinear}, object::Object, model::Model,
                       name_map::Dict{String, MOI.VariableIndex})
    node_list = Object.(object["node_list"])
    expr = convert_mof_to_expr(object["root"], node_list)
    return Nonlinear(expr)
end

#=
Expr:
    2 * x + sin(x)^2 + y

Tree form:
                    +-- (2)
          +-- (*) --+
          |         +-- (x)
    (+) --+
          |         +-- (sin) --+-- (x)
          +-- (^) --+
          |         +-- (2)
          +-- (y)

MOF format:

    {
        "head": "nonlinear",
        "root": {"head": "node", "index": 4},
        "node_list": [
            {
                "head": "*", "args": [
                    {"head": "real", "value": 2},
                    {"head": "variable", "name": "x"}
                ]
            },
            {
                "head": "sin",
                "args": [
                    {"head": "variable", "name", "x"}
                ]
            }
            {
                "head": "^",
                "args": [
                    {"head": "node", "index": 2},
                    {"head": "real", "value": 2}
                ]
            },
            {
                "head": "+",
                "args": [
                    {"head": "node", "index": 1},
                    {"head": "node", "index": 3},
                    {"head": "variable", "name": "y"}
                ]
            }
        ]
    }
=#

"""
    ARITY

The arity of a nonlinear function. One of:
 - `Nary` if the function accepts one or more arguments
 - `Unary` if the function accepts exactly one argument
 - `Binary` if the function accepts exactly two arguments.
"""
@enum ARITY Nary Unary Binary

# A nice error message telling the user they supplied the wrong number of
# arguments to a nonlinear function.
function throw_invalid_arguments(function_name, function_type, num_arguments)
    error("The function $(function_name) is an ($function_type) function, but" *
          " you have passed $(num_arguments) arguments.")
end

function validate_arguments(function_name, actual::Int, required::ARITY)
    if required == Nary && actual < 1
        throw_invalid_arguments(function_name, "n-ary", actual)
    elseif required == Unary && actual != 1
        throw_invalid_arguments(function_name, "unary", actual)
    elseif required == Binary && actual != 2
        throw_invalid_arguments(function_name, "biary", actual)
    end
end

"""
    SUPPORTED_FUNCTIONS

A vector of string-symbol pairs that map the MathOptFormat string representation
(i.e, the value of the `"head"` field) to the name of a Julia function (in
Symbol form).
"""
const SUPPORTED_FUNCTIONS = Pair{String, Tuple{Symbol, ARITY}}[
    # ==========================================================================
    # The standard arithmetic functions.
    # The addition operator: +(a, b, c, ...) = a + b + c + ...
    # In the unary case, +(a) = a.
    "+"     => (:+, Nary),
    # The subtraction operator: -(a, b, c, ...) = a - b - c - ...
    # In the unary case, -(a) = -a.
    "-"     => (:-, Nary),
    # The multiplication operator: *(a, b, c, ...) = a * b * c * ...
    # In the unary case, *(a) = a.
    "*"     => (:*, Nary),
    # The division operator. This must have exactly two arguments. The first
    # argument is the numerator, the second argument is the denominator:
    # /(a, b) = a / b.
    "/"     => (:/, Binary),
    # ==========================================================================
    # N-ary minimum and maximum functions.
    "min"   => (:min, Nary),
    "max"   => (:max, Nary),
    # ==========================================================================
    # The absolute value function: abs(x) = (x >= 0 ? x : -x).
    "abs"   => (:abs, Unary),
    # ==========================================================================
    # Log- and power-related functions.
    # A binary function for exponentiation: ^(a, b) = a ^ b.
    "^"     => (:^, Binary),
    # The natural exponential function: exp(x) = e^x.
    "exp"   => (:exp, Unary),
    # The base-e log function: y = log(x) => e^y = x.
    "log"   => (:log, Unary),
    # The base-10 log function: y = log10(x) => 10^y = x.
    "log10" => (:log10, Unary),
    # The square root function: sqrt(x) = √x = x^(0.5).
    "sqrt"  => (:sqrt, Unary),
    # ==========================================================================
    # The unary trigonometric functions. These must have exactly one argument.
    "cos"   => (:cos, Unary),
    "cosh"  => (:cosh, Unary),
    "acos"  => (:acos, Unary),
    "acosh" => (:acosh, Unary),
    "sin"   => (:sin, Unary),
    "sinh"  => (:sinh, Unary),
    "asin"  => (:asin, Unary),
    "asinh" => (:asinh, Unary),
    "tan"   => (:tan, Unary),
    "tanh"  => (:tanh, Unary),
    "atan"  => (:atan, Unary),
    "atanh" => (:atanh, Unary)
]

# An internal helper dictionary that maps function names in Symbol form to their
# MathOptFormat string representation.
const FUNCTION_TO_STRING = Dict{Symbol, Tuple{String, ARITY}}()

# An internal helper dictionary that maps function names in their MathOptFormat
# string representation to the symbol representing the Julia function.
const STRING_TO_FUNCTION = Dict{String, Tuple{Symbol, ARITY}}()

# Programatically add the list of supported functions to the helper dictionaries
# for easy of look-up later.
for (mathoptformat_string, (julia_symbol, num_arguments)) in SUPPORTED_FUNCTIONS
    FUNCTION_TO_STRING[julia_symbol] = (mathoptformat_string, num_arguments)
    STRING_TO_FUNCTION[mathoptformat_string] = (julia_symbol, num_arguments)
end

"""
    convert_mof_to_expr(node::Object, node_list::Vector{Object})

Convert a MathOptFormat node `node` into a Julia expression given a list of
MathOptFormat nodes in `node_list`.
"""
function convert_mof_to_expr(node::Object, node_list::Vector{Object})
    head = node["head"]
    if head == "real"
        return node["value"]
    elseif head == "complex"
        return Complex(node["real"], node["imag"])
    elseif head == "variable"
        return Symbol(node["name"])
    elseif head == "node"
        return convert_mof_to_expr(node_list[node["index"]], node_list)
    else
        if !haskey(STRING_TO_FUNCTION, head)
            error("Cannot convert MOF to Expr. Unknown function: $(head).")
        end
        (julia_symbol, num_arguments) = STRING_TO_FUNCTION[head]
        validate_arguments(head, length(node["args"]), num_arguments)
        expr = Expr(:call, julia_symbol)
        for arg in node["args"]
            push!(expr.args, convert_mof_to_expr(arg, node_list))
        end
        return expr
    end
end

"""
    convert_mof_to_expr(node::Object, node_list::Vector{Object})

Convert a Julia expression into a MathOptFormat representation. Any intermediate
nodes that are required are appended to `node_list`.
"""
function convert_expr_to_mof(expr::Expr, node_list::Vector{Object})
    if expr.head != :call
        error("Expected an expression that was a function. Got $(expr).")
    end
    function_name = expr.args[1]
    if !haskey(FUNCTION_TO_STRING, function_name)
        error("Cannot convert Expr to MOF. Unknown function: $(function_name).")
    end
    (mathoptformat_string, num_arguments) = FUNCTION_TO_STRING[function_name]
    validate_arguments(function_name, length(expr.args) - 1, num_arguments)
    node = Object(
        "head" => mathoptformat_string,
        "args" => Object[]
    )
    for arg in @view(expr.args[2:end])
        push!(node["args"], convert_expr_to_mof(arg, node_list))
    end
    push!(node_list, node)
    return Object("head" => "node", "index" => length(node_list))
end

# Recursion end for variables.
function convert_expr_to_mof(sym::Symbol, node_list::Vector{Object})
    return Object("head" => "variable", "name" => String(sym))
end

# Recursion end for real constants.
function convert_expr_to_mof(value::Real, node_list::Vector{Object})
    return Object("head" => "real", "value" => value)
end

# Recursion end for complex numbers.
function convert_expr_to_mof(value::Complex, node_list::Vector{Object})
    return Object("head" => "complex", "real" => real(value),
                  "imag" => imag(value))
end
