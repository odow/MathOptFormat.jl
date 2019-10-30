using MathOptFormat, Test

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
                @test !isempty(sprint(io -> MOI.write_to_file(model_dest, io)))
            end
            model_dest = MOIU.MockOptimizer(MOIU.Model{Float64}())
            MOI.copy_to(model_dest, model_src)
        end
    end

    @testset "Calling MOF.open" begin
        for cs in [MathOptFormat.Bzip2(), MathOptFormat.Gzip(), MathOptFormat.Xz()]
            @test_throws ArgumentError MathOptFormat.open((x) -> nothing,
                                                          "dummy.gz", "a", cs)
            @test_throws ArgumentError MathOptFormat.open((x) -> nothing,
                                                          "dummy.gz", "r+", cs)
            @test_throws ArgumentError MathOptFormat.open((x) -> nothing,
                                                          "dummy.gz", "w+", cs)
            @test_throws ArgumentError MathOptFormat.open((x) -> nothing,
                                                          "dummy.gz", "a+", cs)
        end
    end

    @testset "Calling gzip_open" begin
        @test_throws ArgumentError MathOptFormat.gzip_open((x) -> nothing,
                                                           "dummy.gz", "a")
        @test_throws ArgumentError MathOptFormat.gzip_open((x) -> nothing,
                                                           "dummy.gz", "r+")
        @test_throws ArgumentError MathOptFormat.gzip_open((x) -> nothing,
                                                           "dummy.gz", "w+")
        @test_throws ArgumentError MathOptFormat.gzip_open((x) -> nothing,
                                                           "dummy.gz", "a+")
    end
end
