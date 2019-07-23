using MathOptFormat, MathOptInterface, BenchmarkTools
# using ProfileView,
using Profile

const MOI = MathOptInterface

function bench_read(filename, new_model)
    model = new_model()
    MOI.read_from_file(model, filename)
    return model
end

function bench_write(model, filename)
    MOI.write_to_file(model, filename)
    return
end

function bench_copy(src, new_model)
    dest = new_model()
    MOI.copy_to(dest, src)
    return dest
end

function _setup_read(filename, new_model)
    model = new_model()
    MOI.read_from_file(model, filename)
    return model
end

function add_bench_file(group, filename, new_model)
    group[filename * "_read"] = @benchmarkable(
        bench_read($(filename), $(new_model))
    )
    group[filename * "_copy"] = @benchmarkable(
        bench_copy(src, $(new_model)),
        setup = (
            src = $(_setup_read(filename, new_model))
        )
    )
    group[filename * "_write"] = @benchmarkable(
        bench_write(model, "tmp.out.gz"),
        setup = (
            model = $(_setup_read(filename, new_model))
        ),
        teardown = (rm("tmp.out.gz"))
    )
    return
end

function create_baseline(
    suite::BenchmarkTools.BenchmarkGroup, name::String; directory::String = "",
    kwargs...
)
    tune!(suite)
    BenchmarkTools.save(joinpath(directory, name * "_params.json"), params(suite))
    results = run(suite; kwargs...)
    BenchmarkTools.save(joinpath(directory, name * "_baseline.json"), results)
    return
end

function compare_against_baseline(
    suite::BenchmarkTools.BenchmarkGroup, name::String;
    directory::String = "", report_filename::String = "report.txt", kwargs...
)
    params_filename = joinpath(directory, name * "_params.json")
    baseline_filename = joinpath(directory, name * "_baseline.json")
    if !isfile(params_filename) || !isfile(baseline_filename)
        error("You create a baseline with `create_baseline` first.")
    end
    loadparams!(
        suite, BenchmarkTools.load(params_filename)[1], :evals, :samples
    )
    new_results = run(suite; kwargs...)
    old_results = BenchmarkTools.load(baseline_filename)[1]
    open(joinpath(directory, report_filename), "w") do io
        println(stdout, "\n========== Results ==========")
        println(io,     "\n========== Results ==========")
        for key in keys(new_results)
            judgement = judge(
                BenchmarkTools.median(new_results[key]),
                BenchmarkTools.median(old_results[key])
            )
            println(stdout, "\n", key)
            println(io,     "\n", key)
            show(stdout, MIME"text/plain"(), judgement)
            show(io, MIME"text/plain"(), judgement)
        end
    end
    return
end

function benchmark_group()
    group = BenchmarkTools.BenchmarkGroup()
    for filename in readdir(joinpath(@__DIR__, "MPS"))
        add_bench_file(
            group, joinpath(@__DIR__, "MPS", filename),
            () -> MathOptFormat.MPS.Model()
        )
    end
    for filename in readdir(joinpath(@__DIR__, "MOF"))
        add_bench_file(
            group, joinpath(@__DIR__, "MOF", filename),
            () -> MathOptFormat.MOF.Model()
        )
    end
    return group
end

if length(ARGS) == 2
    name = ARGS[2]
    group = benchmark_group()
    if ARGS[1] == "create"
        create_baseline(group, name)
    elseif ARGS[1] == "compare"
        compare_against_baseline(group, name)
    end
elseif length(ARGS) == 1 && ARGS[1] == "profile"
    bench_read(
        joinpath(@__DIR__, "MOF", "mas74.mof.json.gz"),
        () -> MathOptFormat.MOF.Model()
    )
    Profile.clear()
    @profile bench_read(
        joinpath(@__DIR__, "MOF", "mas74.mof.json.gz"),
        () -> MathOptFormat.MOF.Model(validate=false)
    )
    Profile.print()
else
    filename = joinpath(@__DIR__, "MOF", "mas74.mof.json.gz")
    src = MathOptFormat.MOF.Model()
    MOI.read_from_file(src, filename)
    dest = MathOptFormat.LP.Model()
    MOI.copy_to(dest, src)
    @profile MOI.write_to_file(dest, "test.lp")
    Profile.clear()
    @profile (for _=1:100; MOI.write_to_file(dest, "test.lp"); end)
    Profile.print()
end


