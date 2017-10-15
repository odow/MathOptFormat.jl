function MOI.addvariable!(m::MOFFile, name::String="")
    i = length(m["variables"]) + 1
    v = MOI.VariableReference(i)
    if name == ""
        push!(m["variables"], Object("name"=>"x$(i)"))
    else
        push!(m["variables"], Object("name"=>name))
    end
    m.ext[v] = i
    v
end
MOI.addvariables!(m::MOFFile, n::Int, names::Vector{String}=fill("", n)) = [MOI.addvariable!(m, names[i]) for i in 1:n]
