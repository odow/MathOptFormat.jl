function error_mode(mode::String)
    throw(ArgumentError("Compressed mode must be \"r\" or \"w\". Got: $mode."))
end

"""
    abstract type AbstractCompressionScheme end

Base type to implement a new compression scheme for MathOptFormat.

To do so, create a concrete subtype (e.g., named after the compression scheme)
and implement:

    extension(::Val{:your_scheme_extension}) = YourScheme()
    compressed_open(f::Function, filename::String, mode::String, ::YourScheme)
"""
abstract type AbstractCompressionScheme end

struct NoCompression <: AbstractCompressionScheme end

extension(::Val) = NoCompression()

function compressed_open(
    f::Function, filename::String, mode::String, ::NoCompression
)
    return Base.open(f, filename, mode)
end

struct Gzip <: AbstractCompressionScheme end

extension(::Val{:gz}) = Gzip()

function compressed_open(
    f::Function, filename::String, mode::String, ::Gzip
)
    if mode == "w"
        return Base.open(f, CodecZlib.GzipCompressorStream, filename, mode)
    elseif mode == "r"
        return Base.open(f, CodecZlib.GzipDecompressorStream, filename, mode)
    end
    error_mode(mode)
end

struct Bzip2 <: AbstractCompressionScheme end

extension(::Val{:bz2}) = Bzip2()

function compressed_open(
    f::Function, filename::String, mode::String, ::Bzip2
)
    if mode == "w"
        return Base.open(f, CodecBzip2.Bzip2CompressorStream, filename, mode)
    elseif mode == "r"
        return Base.open(f, CodecBzip2.Bzip2DecompressorStream, filename, mode)
    end
    error_mode(mode)
end

struct AutomaticCompression <: AbstractCompressionScheme end

function compressed_open(
    f::Function, filename::String, mode::String, ::AutomaticCompression
)
    ext = Symbol(split(filename, ".")[end])
    return compressed_open(f, filename, mode, extension(Val{ext}()))
end
