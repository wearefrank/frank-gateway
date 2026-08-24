local core = require("apisix.core")
local cjson = require("cjson.safe")
local ngx = ngx

local jsonpath = require("jsonpath")  -- external dependency

local plugin_name = "response-extractor"

local DEFAULT_MAX_BODY_SIZE = 1024 * 1024 -- 1 MB
local DEFAULT_CONTENT_TYPES = { "application/json" }

local _M = {
    version = 1,
    priority = 1000,
    name = plugin_name,
    schema = {
        type = "object",
        properties = {
            fields = {
                type = "object",
                patternProperties = {
                    ["^[a-zA-Z_][a-zA-Z0-9_]*$"] = {
                        type = "string",
                        description = "JSONPath expression"
                    }
                },
                minProperties = 1,
                additionalProperties = false
            },
            max_body_size = {
                type = "integer",
                minimum = 1,
                default = DEFAULT_MAX_BODY_SIZE,
                description = "Maximum response body size (in bytes) buffered for extraction. " ..
                    "Responses whose body exceeds this size are skipped to protect memory usage."
            },
            content_types = {
                type = "array",
                items = {
                    type = "string",
                    minLength = 1
                },
                minItems = 1,
                default = DEFAULT_CONTENT_TYPES,
                description = "Content-Type values treated as JSON, in addition to any type ending in '+json'."
            }
        },
        required = {"fields"},
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

local function init_results(fields)
    local results = {}
    for var_name, _ in pairs(fields) do
        results[var_name] = setmetatable({}, cjson.array_mt)
    end
    return results
end

local function extract_all(fields, data)
    local results = init_results(fields)

    for var_name, path in pairs(fields) do
        local res, err = jsonpath.query(data, path)
        if not res then
            core.log.warn("jsonpath error for ", var_name, ": ", err)
        else
            results[var_name] = setmetatable(res, cjson.array_mt)
        end
    end

    return results
end

local function expose_results(response_extractor_ctx, results)
    response_extractor_ctx.extracted = results
    response_extractor_ctx.var.extracted = core.json.encode(results)

    for var_name, value in pairs(results) do
        -- Keep native tables in ctx.var so downstream loggers can encode
        -- them as structured JSON instead of escaped JSON strings.
        response_extractor_ctx.var[var_name] = value

        -- Optional string form for plugins/uses that require a JSON string.
        response_extractor_ctx.var[var_name .. "_json"] = core.json.encode(value)
    end
end

local function is_json_content_type(content_type, allowed_types)
    if not content_type then
        return false
    end

    -- strip parameters such as "; charset=utf-8"
    local mime = content_type:match("^%s*([^;]+)")
    if not mime then
        return false
    end
    mime = mime:lower()

    if mime:sub(-5) == "+json" then
        return true
    end

    for _, allowed in ipairs(allowed_types) do
        if mime == allowed:lower() then
            return true
        end
    end

    return false
end

function _M.body_filter(conf, response_extractor_ctx)
    if response_extractor_ctx._skip_extraction then
        return
    end

    if not response_extractor_ctx._checked_content_type then
        response_extractor_ctx._checked_content_type = true

        local content_type = ngx.header["Content-Type"]
        local allowed_types = conf.content_types or DEFAULT_CONTENT_TYPES
        if not is_json_content_type(content_type, allowed_types) then
            response_extractor_ctx._skip_extraction = true
            return
        end
    end

    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]
    local max_body_size = conf.max_body_size or DEFAULT_MAX_BODY_SIZE

    response_extractor_ctx._resp_body_chunks = response_extractor_ctx._resp_body_chunks or {}
    response_extractor_ctx._resp_body_size = response_extractor_ctx._resp_body_size or 0

    if chunk then
        response_extractor_ctx._resp_body_size = response_extractor_ctx._resp_body_size + #chunk

        if response_extractor_ctx._resp_body_size > max_body_size then
            core.log.warn("response body exceeds max_body_size (", max_body_size,
                " bytes), skipping response-extractor")
            response_extractor_ctx._skip_extraction = true
            response_extractor_ctx._resp_body_chunks = nil
            return
        end

        table.insert(response_extractor_ctx._resp_body_chunks, chunk)
    end

    if not eof then
        return
    end

    local body = table.concat(response_extractor_ctx._resp_body_chunks)
    local data = safe_json_decode(body)
    if not data then
        expose_results(response_extractor_ctx, init_results(conf.fields))
        return
    end

    local results = extract_all(conf.fields, data)
    expose_results(response_extractor_ctx, results)
end

return _M