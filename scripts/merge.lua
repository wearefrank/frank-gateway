local yaml = require("lyaml")
local lfs = require("lfs")

local input_dir = "/usr/local/apisix/conf/mergeconfigs"
local output_file = "/usr/local/apisix/conf/apisix.yaml"

local ROOT_ORDER = {
    "ssls",
    "consumers",
    "consumer_groups",
    "services",
    "routes",
    "stream_routes",
    "upstreams",
    "global_rules",
    "plugin_configs",
    "plugin_metadata",
    "secrets"
}

--------------------------------------------------
-- SAFE LOAD → IMMEDIATELY SERIALIZE TO LUA TABLES VIA YAML ROUNDTRIP
--------------------------------------------------
local function load_yaml(path)
    local f = io.open(path, "r")
    if not f then
        print("[merge] FILE NOT FOUND:", path)
        return nil
    end

    local content = f:read("*a")
    f:close()

    local ok, doc = pcall(yaml.load, content)

    if not ok then
        print("[merge] YAML PARSE ERROR:", path)
        print(doc)
        return nil
    end

    if not doc then
        print("[merge] EMPTY DOC:", path)
        return nil
    end

    while type(doc) == "table" and doc[1] do
        doc = doc[1]
    end

    print("[merge] loaded OK:", path)

    return doc
end

--------------------------------------------------
-- MERGE
--------------------------------------------------
local function merge(dst, src)
    if type(src) ~= "table" then return end

    for _, root in ipairs(ROOT_ORDER) do
        local section = src[root]

        if type(section) == "table" then
            dst[root] = dst[root] or {}

            for _, item in pairs(section) do
                if type(item) == "table" then
                    table.insert(dst[root], item)
                end
            end
        end
    end
end

--------------------------------------------------
-- FILES
--------------------------------------------------
local function list_files()
    local files = {}

    for f in lfs.dir(input_dir) do
        if f:match("%.ya?ml$") then
            table.insert(files, f)
        end
    end

    table.sort(files)
    return files
end

--------------------------------------------------
-- BUILD YAML MANUALLY (NO PER-ITEM lyaml DUMP)
--------------------------------------------------
local function dump_section(name, list, out)
    if not list or #list == 0 then return end

    -- lyaml.dump expects an array of documents
    local block = yaml.dump({ { [name] = list } })
    -- strip YAML document-start marker (---) produced by lyaml
    block = block:gsub("^%-%-%-%s*\n", "")
    -- strip trailing document-end marker (...) if present
    block = block:gsub("\n?%.%.%.%s*$", "")

    out:write("\n" .. block .. "\n")
end

--------------------------------------------------
-- BUILD
--------------------------------------------------
local function build()
    print("[merge] rebuilding config")

    local merged = {}
    for _, r in ipairs(ROOT_ORDER) do
        merged[r] = {}
    end

    local files = list_files()
    if #files == 0 then error("no files") end

    local total = 0

    for _, f in ipairs(files) do
        local fpath = input_dir .. "/" .. f
        local doc = load_yaml(fpath)
        if doc then merge(merged, doc) end
    end

    for _, r in ipairs(ROOT_ORDER) do
        total = total + #(merged[r] or {})
    end

    if total == 0 then
        error("NO CONFIG GENERATED")
    end

    local out = assert(io.open(output_file, "w"))

    out:write("# AUTO-GENERATED APISIX CONFIG\n")

    for _, r in ipairs(ROOT_ORDER) do
        dump_section(r, merged[r], out)
    end

    out:write("#END\n")
    out:close()

    print("[merge] written:", output_file)
end

build()