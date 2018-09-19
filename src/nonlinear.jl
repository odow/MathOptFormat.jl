#=
    Expr:
        2 * x + sin(x)^2 + y

    Tree form:
                    +-- (2)
          +-- (*) --+
          |         +-- (x)
    (+) --+
          |         +-- (sin) -+- (x)
          +-- (^) --+
          |         +-- (2)
          |
          +-- (y)

    MOF format:

        {
            "objectives": [
                {"sense": "max", "function": {"head": "node", "index": 4}}
            ]
            "node_list": [
                {
                    "head": "*", "args": [
                        {"head": "constant", "value": 2},
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
                        {"head": "constant", "value": 2}
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
    FUNCTION_TO_STRING

A dictionary that maps function names in Symbol form to their MathOptFormat
string representation.

If the list of functions that MathOptFormat supports is extended, a reverse
entry should also be added to `STRING_TO_FUNCTION`.
"""
const FUNCTION_TO_STRING = Dict{Symbol, String}(
    :+ => "+",
    :- => "-",
    :* => "*",
    :/ => "/",
    :^ => "^",
    :sin => "sin"
)

"""
    STRING_TO_FUNCTION

A dictionary that maps function names in their MathOptFormat string
representation to the symbol representing the Julia function.

If the list of functions that MathOptFormat supports is extended, a reverse
entry should also be added to `FUNCTION_TO_STRING`.
"""
const STRING_TO_FUNCTION = Dict{String, Symbol}(
    "+" => :+,
    "-" => :-,
    "*" => :*,
    "/" => :/,
    "^" => :^,
    "sin" => :sin
)

"""
    convert_mof_to_expr(node::Object, node_list::Vector{Object})

Convert a MathOptFormat node `node` into a Julia expression given a list of
MathOptFormat nodes in `node_list`.
"""
function convert_mof_to_expr(node::Object, node_list::Vector{Object})
    head = node["head"]
    if head == "constant"
        return node["value"]
    elseif head == "variable"
        return Symbol(node["name"])
    elseif head == "node"
        return convert_mof_to_expr(node_list[node["index"]], node_list)
    else
        if !haskey(STRING_TO_FUNCTION, head)
            error("Cannot convert MOF to Expr. Unknown function: $(head).")
        end
        expr = Expr(:call)
        push!(expr.args, STRING_TO_FUNCTION[head])
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
        error("Expected an expression that was a function.")
    end
    function_name = expr.args[1]
    if !haskey(FUNCTION_TO_STRING, function_name)
        error("Cannot convert Expr to MOF. Unknown function: $(function_name).")
    end
    node = Object(
        "head" => FUNCTION_TO_STRING[function_name],
        "args" => Object[]
    )
    for arg in expr.args[2:end]
        push!(node["args"], convert_expr_to_mof(arg, node_list))
    end
    push!(node_list, node)
    return Object("head" => "node", "index" => length(node_list))
end

# Recursion end for variables.
function convert_expr_to_mof(expr::Symbol, node_list::Vector{Object})
    return Object("head" => "variable", "name" => String(expr))
end

# Recursion end for numeric constants.
function convert_expr_to_mof(expr::Real, node_list::Vector{Object})
    return Object("head" => "constant", "value" => expr)
end
