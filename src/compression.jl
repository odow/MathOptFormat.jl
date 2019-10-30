function error_mode(mode::String)
    throw(ArgumentError("For dealing with compressed data, mode must be \"r\" or \"w\"; $mode given"))
end

abstract type AbstractCompressionScheme end

struct NoCompression <: AbstractCompressionScheme end
function open(
    f::Function, filename::String, mode::String, ::NoCompression
)
    return open(f, filename, mode)
end

struct Gzip <: AbstractCompressionScheme end
function open(
    f::Function, filename::String, mode::String, ::Gzip
)
    return if mode == "w"
        open(f, CodecZlib.GzipCompressorStream, filename, "w")
    elseif mode == "r"
        open(f, CodecZlib.GzipDecompressorStream, filename, "w")
    end
    error_mode(mode)
end

struct Bzip2 <: AbstractCompressionScheme end
function open(
    f::Function, filename::String, mode::String, ::Bzip2
)
    return if mode == "w"
        open(f, CodecBzip2.Bzip2CompressorStream, filename, "w")
    elseif mode == "r"
        open(f, CodecBzip2.Bzip2DecompressorStream, filename, "w")
    end
    error_mode(mode)
end

struct Xz <: AbstractCompressionScheme end
function open(
    f::Function, filename::String, mode::String, ::Xz
)
    return if mode == "w"
        open(f, CodecXz.XzDecompressorStream, filename, "w")
    elseif mode == "r"
        open(f, CodecXz.XzCompressorStream, filename, "w")
    end
    error_mode(mode)
end
