local core = require("apisix.core")
local jsonpath = require("jsonpath")

local ngx = ngx
local plugin_name = "response-extractor"
local max_response_body_bytes = 1024 * 1024

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

local function extract_all(conf, data)
    local results = {}

    for var_name, path in pairs(conf) do
        local res, err = jsonpath.query(data, path)
        if not res then
            core.log.warn("jsonpath error for ", var_name, ": ", err)
        else
            results[var_name] = res[1]
        end
    end

    return results
end

local function to_var_string(value)
    local value_type = type(value)

    if value_type == "string" then
        return value
    end

    if value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end

    if value == nil then
        return nil
    end

    return core.json.encode(value)
end

local function is_json_response()
    local headers = ngx.resp.get_headers()
    if not headers then
        return false
    end

    local content_type = headers["Content-Type"] or headers["content-type"]
    if not content_type then
        return false
    end

    content_type = string.lower(content_type)
    return string.find(content_type, "application/json", 1, true)
        or string.find(content_type, "+json", 1, true)
end

function _M.body_filter(conf, ctx)
    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]

    if ctx._skip_response_extractor then
        return
    end

    if ctx._response_extractor_checked_content_type == nil then
        ctx._response_extractor_checked_content_type = true
        if not is_json_response() then
            core.log.warn("skipping response extraction: not a JSON response")
            ctx._skip_response_extractor = true
            return
        end
    end

    ctx._resp_body_chunks = ctx._resp_body_chunks or {}
    ctx._resp_body_size = ctx._resp_body_size or 0

    if chunk and #chunk > 0 then
        ctx._resp_body_size = ctx._resp_body_size + #chunk
        if ctx._resp_body_size > max_response_body_bytes then
            core.log.warn("skipping response extraction: response body too large")
            ctx._skip_response_extractor = true
            ctx._resp_body_chunks = nil
            ctx._resp_body_size = nil
            return
        end

        table.insert(ctx._resp_body_chunks, chunk)
    end

    if not eof then
        return
    end

    local body = table.concat(ctx._resp_body_chunks)
    ctx._resp_body_chunks = nil
    ctx._resp_body_size = nil

    if body == "" then
        return
    end

    local data = safe_json_decode(body)
    if not data then
        return
    end

    local results = extract_all(conf, data)

    -- store per-request (usable by other plugins)
    ctx.extracted = results

    -- expose individually to log_format
    ctx.var.extracted = core.json.encode(results)

    -- Expose flattened variables for direct use.
    for k, v in pairs(results) do
        local var_value = to_var_string(v)
        if var_value ~= nil then
            ctx.var[k] = var_value
        end
    end
end

return _M