function MOI.addvariable!(m::MOFFile, name::String="")
    i = length(m["variables"]) + 1
    v = MOI.VariableReference(i)
    if name == ""
        push!(m["variables"], Object("name"=>"x$(i)", "VariablePrimalStart"=>NaN))
    else
        push!(m["variables"], Object("name"=>name, "VariablePrimalStart"=>NaN))
    end
    m.ext[v] = i
    v
end
MOI.addvariables!(m::MOFFile, n::Int, names::Vector{String}=fill("", n)) = [MOI.addvariable!(m, names[i]) for i in 1:n]

struct VariableName <: MOI.AbstractVariableAttribute end
"""
    MOI.setattribute!(m::MOFFile, ::MOF.VariableName, v::MOI.VariableReference, name::String)

Rename the variable `v` in the MOFFile `m` to `name`. This should be done
immediately after introducing a variable and before it is used in any constraints.

If the variable has already been used, this function will _not_ update the
previous references.
"""
function MOI.setattribute!(m::MOFFile, ::VariableName, v::MOI.VariableReference, name::String)
    i = m.ext[v]
    m["variables"][i]["name"] = name
end

function MOI.setattribute!(m::MOFFile, ::MOI.VariablePrimalStart, v::MOI.VariableReference, value)
    i = m.ext[v]
    m["variables"][i]["VariablePrimalStart"] = value
end

function MOI.getattribute(m::MOFFile, ::VariableName, v::MOI.VariableReference)
    i = m.ext[v]
    m["variables"][i]["name"]
end
function MOI.cangetattribute(m::MOFFile, ::VariableName, v::MOI.VariableReference)
    haskey(m.ext, v)
end
