local core = require("apisix.core")

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
            }
        },
        required = {"log_format"},
        additionalProperties = false
    }
}

function _M.check_schema(conf)
    return core.schema.check(_M.schema, conf)
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

function _M.log(conf, ctx)
    local entry = resolve_value(conf.log_format, ctx)

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
