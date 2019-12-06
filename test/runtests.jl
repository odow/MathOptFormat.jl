using MathOptFormat
using Test

const MOI = MathOptFormat.MOI
const MOIU = MOI.Utilities

@testset "MathOptFormat tests" begin
    @testset "$(file)" for file in ["CBF", "LP", "MOF", "MPS"]
        include("$(file)/$(file).jl")
    end

    @testset "Copying options" begin
        models = [
            MathOptFormat.CBF.Model,
            MathOptFormat.LP.Model,
            MathOptFormat.MOF.Model,
            MathOptFormat.MPS.Model
        ]
        for src in models
            model_src = src()
            for dest in models
                model_dest = dest()
                MOI.copy_to(model_dest, model_src)
                @test !isempty(sprint(write, model_dest))
            end
            model_dest = MOIU.MockOptimizer(MOIU.Model{Float64}())
            MOI.copy_to(model_dest, model_src)
        end
    end

    @testset "Calling MOF.compressed_open" begin
        for cs in [MathOptFormat.Bzip2(), MathOptFormat.Gzip()]
            for open_type in ["a", "r+", "w+", "a+"]
                @test_throws ArgumentError MathOptFormat.compressed_open(
                    (x) -> nothing, "dummy.gz", open_type, cs
                )
            end
        end
    end

    @testset "Provided compression schemes" begin
        model = MathOptFormat.read_from_file(
            joinpath(@__DIR__, "MPS", "free_integer.mps")
        )
        filename = joinpath(@__DIR__, "free_integer.mps")
        MOI.write_to_file(model, filename * ".garbage")
        for ext in ["", ".bz2", ".gz"]
            MOI.write_to_file(model, filename * ext)
            MathOptFormat.read_from_file(filename * ext)
        end

        sleep(1.0)  # Allow time for unlink to happen.
        for ext in ["", ".garbage", ".bz2", ".gz"]
            rm(filename * ext, force = true)
        end
    end

    @testset "new_model" begin
        for (format, model) in [
            (MathOptFormat.FORMAT_CBF, MathOptFormat.CBF.Model()),
            (MathOptFormat.FORMAT_LP, MathOptFormat.LP.Model()),
            (MathOptFormat.FORMAT_MOF, MathOptFormat.MOF.Model()),
            (MathOptFormat.FORMAT_MPS, MathOptFormat.MPS.Model()),
        ]
            @test typeof(MathOptFormat.new_model(format)) == typeof(model)
        end
        @test_throws(
            ErrorException("Unable to automatically detect file format. No filename provided."),
            MathOptFormat.new_model(MathOptFormat.FORMAT_AUTOMATIC)
        )
        for (ext, model) in [
            (".cbf", MathOptFormat.CBF.Model()),
            (".lp", MathOptFormat.LP.Model()),
            (".mof.json", MathOptFormat.MOF.Model()),
            (".mps", MathOptFormat.MPS.Model()),
        ]
            @test typeof(MathOptFormat.new_model(
                MathOptFormat.FORMAT_AUTOMATIC, "a$(ext)"
            )) == typeof(model)
            @test typeof(MathOptFormat.new_model(
                MathOptFormat.FORMAT_AUTOMATIC, "a$(ext).gz"
            )) == typeof(model)
        end
        @test_throws(
            ErrorException("Unable to automatically detect format of a.b."),
            MathOptFormat.new_model(MathOptFormat.FORMAT_AUTOMATIC, "a.b")
        )
    end
end
