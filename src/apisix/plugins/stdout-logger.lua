local core = require("apisix.core")
local expr = require("resty.expr.v1")
local ngx = ngx

local plugin_name = "stdout-logger"

local _M = {
    version = 1,
    priority = 1,
    name = plugin_name,
    schema = {
        type = "object",
        properties = {
            log_output = {
                type = "string",
                enum = {"json"},
                default = "json",
                description = "Serialization format used for each log line."
            },
            log_format = {
                type = "object",
                minProperties = 1,
                description = "Template for each log line. String leaf values starting " ..
                    "with '$' are resolved as APISIX/nginx variables, other leaf values " ..
                    "(and nested objects) are copied as-is."
            },
            labels = {
                type = "object",
                description = "Key-value map of log labels. String leaf values starting " ..
                    "with '$' are resolved as APISIX/nginx variables, other leaf values " ..
                    "(and nested objects) are copied as-is."
            },
            include_req_body = {type = "boolean", default = false},
            include_req_body_expr = {
                type = "array",
                minItems = 1,
                items = {
                    type = "array"
                }
            },
            include_resp_body = {type = "boolean", default = false},
            include_resp_body_expr = {
                type = "array",
                minItems = 1,
                items = {
                    type = "array"
                }
            },
            include_req_headers = {type = "boolean", default = false},
            include_resp_headers = {type = "boolean", default = false},
        },
        required = {"log_format"},
        additionalProperties = false,
    }
}

function _M.check_schema(conf)
    return core.schema.check(_M.schema, conf)
end

-- evaluates an APISIX "expr" rule (e.g. {{"arg_debug", "==", "1"}}) against ctx.var
local function match_expr(rule, ctx)
    if not rule then
        return false
    end

    local ex, err = expr.new(rule)
    if not ex then
        core.log.error("stdout-logger failed to compile expr: ", err)
        return false
    end

    return ex:eval(ctx.var)
end

function _M.access(conf, ctx)
    if conf.include_req_headers then
        -- request_headers is not a real nginx var, expose it via ctx.var so log_format can use "$request_headers"
        ctx.var.request_headers = ngx.req.get_headers()
    end

    local include_body = conf.include_req_body or match_expr(conf.include_req_body_expr, ctx)
    if not include_body then
        return
    end

    -- reading the body here primes nginx's $request_body var for use in log_format
    local _, err = core.request.get_body()
    if err then
        core.log.warn("stdout-logger failed to read request body: ", err)
    end
end

function _M.header_filter(conf, ctx)
    if not conf.include_resp_headers then
        return
    end

    -- response_headers is not a real nginx var, expose it via ctx.var so log_format can use "$response_headers"
    ctx.var.response_headers = ngx.resp.get_headers()
end

function _M.body_filter(conf, ctx)
    local include_body = conf.include_resp_body or match_expr(conf.include_resp_body_expr, ctx)
    if not include_body then
        return
    end

    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]

    ctx._stdout_logger_resp_body_chunks = ctx._stdout_logger_resp_body_chunks or {}

    if chunk then
        table.insert(ctx._stdout_logger_resp_body_chunks, chunk)
    end

    if not eof then
        return
    end

    -- response_body is not a real nginx var, expose it via ctx.var so log_format can use "$response_body"
    ctx.var.response_body = table.concat(ctx._stdout_logger_resp_body_chunks)
end

local function resolve_value(value, ctx)
    if type(value) == "string" and value:byte(1) == string.byte("$") then
        return ctx.var[value:sub(2)]
    end

    if type(value) == "table" then
        local resolved = {}
        for key, nested in pairs(value) do
            resolved[key] = resolve_value(nested, ctx)
        end
        return resolved
    end

    return value
end

-- classifies the response status into a log severity: >=500 Error, >=400 Warn, otherwise Info
local function resolve_log_type(ctx)
    local status = tonumber(ctx.var.status)
    if status and status >= 500 then
        return "Error"
    elseif status and status >= 400 then
        return "Warn"
    end

    return "Info"
end

function _M.log(conf, ctx)
    -- log_type is not a real nginx var, expose it via ctx.var so log_format can use "$log_type"
    ctx.var.log_type = resolve_log_type(ctx)

    local entry = resolve_value(conf.log_format, ctx)
    if conf.labels then
        entry.labels = resolve_value(conf.labels, ctx)
    end

    local line, err = core.json.encode(entry)
    if not line then
        core.log.error("failed to encode stdout-logger entry: ", err)
        return
    end

    -- one write call per line to keep concurrent writes from different workers from interleaving
    io.stdout:write(line, "\n")
    io.stdout:flush()
end

return _M
