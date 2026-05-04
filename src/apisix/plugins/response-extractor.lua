local core = require("apisix.core")
local cjson = require("cjson.safe")
local ngx = ngx

local jsonpath = require("jsonpath")  -- external dependency

local plugin_name = "response-extractor"

local _M = {
    version = 1,
    priority = 1000,
    name = plugin_name,
    schema = {
        type = "object",
        patternProperties = {
            ["^[a-zA-Z_][a-zA-Z0-9_]*$"] = {
                type = "string",
                description = "JSONPath expression"
            }
        },
        additionalProperties = false
    }
}

_M.log_schema = _M.schema

function _M.check_schema(conf)
    return core.schema.check(_M.schema, conf)
end

local function safe_json_decode(body)
    local data, err = core.json.decode(body)
    if not data then
        core.log.warn("failed to decode response body: ", err)
        return nil
    end
    return data
end

local function init_results(conf)
    local results = {}
    for var_name, _ in pairs(conf) do
        results[var_name] = setmetatable({}, cjson.array_mt)
    end
    return results
end

local function extract_all(conf, data)
    local results = init_results(conf)

    for var_name, path in pairs(conf) do
        local res, err = jsonpath.query(data, path)
        if not res then
            core.log.warn("jsonpath error for ", var_name, ": ", err)
        else
            results[var_name] = setmetatable(res, cjson.array_mt)
        end
    end

    return results
end

local function expose_results(ctx, results)
    ctx.extracted = results
    ctx.var.extracted = core.json.encode(results)

    for var_name, value in pairs(results) do
        -- Keep native tables in ctx.var so downstream loggers can encode
        -- them as structured JSON instead of escaped JSON strings.
        ctx.var[var_name] = value

        -- Optional string form for plugins/uses that require a JSON string.
        ctx.var[var_name .. "_json"] = core.json.encode(value)
    end
end

function _M.body_filter(conf, ctx)
    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]

    ctx._resp_body_chunks = ctx._resp_body_chunks or {}

    if chunk then
        table.insert(ctx._resp_body_chunks, chunk)
    end

    if not eof then
        return
    end

    local body = table.concat(ctx._resp_body_chunks)
    local data = safe_json_decode(body)
    if not data then
        expose_results(ctx, init_results(conf))
        return
    end

    local results = extract_all(conf, data)
    expose_results(ctx, results)
end

return _M