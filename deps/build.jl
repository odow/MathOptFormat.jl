using HTTP

escape(s::String) = replace(s, "\\" => "\\\\")

function download_schema(schema_git_hash)
    schema_path = joinpath(@__DIR__, "$(schema_git_hash).json")
    r = HTTP.request("GET", "https://raw.githubusercontent.com/odow/MathOptFormat/$(schema_git_hash)/mof.schema.json")
    if r.status == 200
        open(schema_path, "w") do io
            write(io, String(r.body))
        end
        open(joinpath(@__DIR__, "deps.jl"), "w") do io
            write(io, "const SCHEMA_PATH = \"$(escape(schema_path))\"\n")
        end
    else
        error("Unable to download the latest MathOptFormat schema.\n" *
              "HTTP status: $(r.status)\n" *
              "HTTP body: $(String(r.body))")
    end
end

# Update this hash whenever github.com/odow/MathOptFormat changes the schema.
# Once a proper version is released, we can change the URL to point to a Github
# release.
SCHEMA_GIT_HASH = "650add188c8479c4dd9f327d2baa8306f3ee1f59"

download_schema(SCHEMA_GIT_HASH)
