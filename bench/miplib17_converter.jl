using MathOptFormat, Dates, Statistics

const MPS_DIRECTORY = joinpath(@__DIR__, "benchmark")
const MOF_DIRECTORY = joinpath(@__DIR__, "benchmark_mof")

# Exclude files that are too large to convert on @odow's laptop.
const EXCLUDED_MODELS = [
    "neos-2075418-temuka.mps.gz",
    "neos-3402454-bohle.mps.gz",
    "square41.mps.gz",
    "square47.mps.gz",
    "supportcase19.mps.gz"
]

if !isfile(joinpath(MPS_DIRECTORY, "30n20b8.mps.gz"))
    error("Please download `https://miplib.zib.de/downloads/benchmark.zip` " *
          "and save it to this directory. Then extract the files to the " *
          "directory `MathOptFormat/bench/benchmark`.")
elseif !isdir(MOF_DIRECTORY)
    mkdir(MOF_DIRECTORY)
end

"Append `message` to the file `log_filename` and write `message` to `stdout`."
function log(log_filename, message)
    open(log_filename, "a") do io
        println(io, message)
    end
    println(message)
end

function convert_files(backend_str::String = "JSON")
    log_filename = joinpath(
        @__DIR__, Dates.format(Dates.now(), "yyyy-mm-dd-HH-MM-SS.log"))
    for filename in readdir(MPS_DIRECTORY)
        mps_filename = joinpath(MPS_DIRECTORY, filename)
        mof_filename = joinpath(
            MOF_DIRECTORY,
            replace(filename, ".mps.gz" => ".mof.gz"))
        if isfile(mof_filename) || filename in EXCLUDED_MODELS
            log(log_filename, "[SKIPPED] $(filename)")
            continue
        end
        mps_model = MathOptFormat.MPS.Model()
        backend = if backend_str == "JSON"
            MathOptFormat.MOF.JSONBackend(nothing)
        elseif backend_str == "MsgPack"
            MathOptFormat.MOF.MsgPackBackend()
        end
        mof_model = MathOptFormat.MOF.Model(backend = backend)
        try
            MathOptFormat.MOI.read_from_file(mps_model, mps_filename)
            MathOptFormat.MOI.copy_to(mof_model, mps_model)
            MathOptFormat.MOI.write_to_file(mof_model, mof_filename)
            log(log_filename, "[SUCCESS] $(filename)")
        catch ex
            log(log_filename, "[FAIL   ] $(filename) $(ex)")
        end
    end
    return
end

function summarize_filesize()
    mof = Dict{String, Int}(
        file => Base.stat(joinpath(MOF_DIRECTORY, file)).size
        for file in readdir(MOF_DIRECTORY))
    mps = Dict{String, Int}(
        file => Base.stat(joinpath(MPS_DIRECTORY, file)).size
        for file in readdir(MPS_DIRECTORY))
    open(joinpath(@__DIR__, "filesizes.csv"), "w") do io
        println(io, "file, mof, mps")
        for (key, mps_size) in mps
            filename = replace(key, ".mps.gz" => "")
            mof_size = get(mof, filename * ".mof.gz", "")
            println(io, "$(filename), $(mof_size), $(mps_size)")
        end
    end
    mps_sizes = Int[]
    mof_sizes = Int[]
    strip_key(key) = replace(replace(key, ".mps.gz" => ""), ".mof.bson.gz" => "")
    for key in intersect(strip_key.(keys(mof)), strip_key.(keys(mps)))
        push!(mps_sizes, mps[key * ".mps.gz"])
        push!(mof_sizes, mof[key * ".mof.bson.gz"])
    end
    dif_sizes = mof_sizes ./ mps_sizes
    quantiles = hcat(
        Statistics.quantile(mof_sizes, [0.0, 0.25, 0.5, 0.75, 1.0]),
        Statistics.quantile(mps_sizes, [0.0, 0.25, 0.5, 0.75, 1.0]),
        Statistics.quantile(dif_sizes, [0.0, 0.25, 0.5, 0.75, 1.0]))
    for i in 1:size(quantiles, 1)
        println(join(quantiles[i, :], "    "))
    end
    return
end

if length(ARGS) > 0
    if ARGS[1] == "convert"
        backend_str = length(ARGS) == 2 ? ARGS[2] : "JSON"
        convert_files(backend_str)
    elseif ARGS[1] == "summarize"
        summarize_filesize()
    end
end
