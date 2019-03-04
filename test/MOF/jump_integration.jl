function MOI.copy_to(dest, src::Model; kwargs...)
    if src.nlp_data !== nothing
        MOI.set(src, MOI.NLPBlock(), JuMP._create_nlp_block_data(src))
    end
    MOI.copy_to(dest, backend(src); kwargs...)
end

function MOI.copy_to(dest::Model, src; kwargs...)
    MOI.copy_to(backend(dest), src; kwargs...)
    nlp_block = MOI.get(src, MOI.NLPBlock())
    if nlp_block !== nothing
        MOI.set(dest, MOI.NLPBlock(), nlp_block)
    end
    return
end

using JuMP, MathOptFormat, Ipopt

jump_1 = Model()
@variable(jump_1, x, start = 1)
@variable(jump_1, y, start = 2.12)
@variable(jump_1, z >= 1)
@NLobjective(jump_1, Min, x * exp(x) + cos(y) + z^3 - z^2)

mof_1 = MathOptFormat.MOF.Model()
MOI.copy_to(mof_1, jump_1)
MOI.write_to_file(mof_1, "mof.json")

mof_2 = MathOptFormat.MOF.Model()
MOI.read_from_file(mof_2, "mof.json")

jump_2 = Model(with_optimizer(Ipopt.Optimizer))
MOI.copy_to(jump_2, mof_2)

x_2 = JuMP.variable_by_name(jump_2, "x")
y_2 = JuMP.variable_by_name(jump_2, "y")
z_2 = JuMP.variable_by_name(jump_2, "z")
JuMP.set_start_value(y_2, 2.12)

optimize!(jump_2)

@test termination_status(jump_2) == MOI.LOCALLY_SOLVED
@test objective_value(jump_2) ≈ -1.3678794486503105 atol=1e-6
@test isapprox(JuMP.value.([x_2, y_2, z_2]), [-1, pi, 1], atol=1e-6)

rm("mof.json")
