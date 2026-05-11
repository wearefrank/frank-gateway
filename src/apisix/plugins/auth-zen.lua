local core = require("apisix.core")
local plugin_name = "auth-zen"
local http = require("resty.http")


local schema = {
    type = "object",
    properties = {
        host = {
            type = "string",
            minLength = 1,
        },
        policy = {
            type = "string",
            minLength = 1,
        },
        body = {
            type = "object",
            properties = {
                subject = {
                    type = "object",
                    properties = {
                        type = { type = "string", minLength = 1 },
                        id = { type = "string", minLength = 1 },
                        properties = { type = "object" },
                    },
                    required = { "type", "id" },
                },
                resource = {
                    type = "object",
                    properties = {
                        type = { type = "string", minLength = 1 },
                        id = { type = "string", minLength = 1 },
                        properties = { type = "object" },
                    },
                    required = { "type", "id" },
                },
                action = {
                    type = "object",
                    properties = {
                        name = { type = "string", minLength = 1 },
                        properties = { type = "object" },
                    },
                    required = { "name" },
                },
                context = {
                    type = "object",
                },
            },
            required = { "subject", "resource", "action" },
        },
        timeout = {
            type = "integer",
            minimum = 1,
            default = 3000,
        },
        ssl_verify = {
            type = "boolean",
            default = false,
        },
        send_headers_upstream = {
            type = "array",
            items = {
                type = "string",
                minLength = 1,
            },
        },
    },
    required = { "host", "policy", "body" }
}


local consumer_schema = {}




local _M = {
    version = 0.1,
    priority = 1999, -- needs to occur before opa plugin
    name = plugin_name,
    type = "auth",   -- marks this as an authentication plugin, so APISIX knows it must pick a consumer
    schema = schema,
    consumer_schema = consumer_schema
}

function _M.check_schema(conf)
    local check = { "host" }
    core.utils.check_https(check, conf, _M.name)
    core.utils.check_tls_bool({ "ssl_verify" }, conf, _M.name)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    -- local body = helper.build_opa_input(conf, ctx, "http") --TO BE UPDATED

    local params = {
        method = "POST",
        body = core.json.encode(conf.body),
        headers = {
            ["Content-Type"] = "application/json",
        },
        -- keepalive = conf.keepalive,
        -- ssl_verify = conf.ssl_verify
    }

    -- if conf.keepalive then
    --     params.keepalive_timeout = conf.keepalive_timeout
    --     params.keepalive_pool = conf.keepalive_pool
    -- end

    local endpoint = conf.host .. "/v1/data/" .. conf.policy

    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local res, err = httpc:request_uri(endpoint, params)

    -- block by default when decision is unavailable
    if not res then
        core.log.error("failed to process AuthZEN decision, err: ", err)
        return 403
    end

    -- parse the results of the decision
    local data, decode_err = core.json.decode(res.body)
    if not data then
        core.log.error("invalid response body: ", res.body, " err: ", decode_err)
        return 503
    end

    if data.decision == nil then
        core.log.error("invalid AuthZEN decision format: ", res.body,
            " err: `decision` field does not exist")
        return 503
    end

    if type(data.decision) ~= "boolean" then
        core.log.error("invalid AuthZEN decision format: ", res.body,
            " err: `decision` must be boolean")
        return 503
    end

    local decision = data.decision
    local result_headers = data.headers

    if not decision then
        if type(result_headers) == "table" then
            core.response.set_header(result_headers)
        end

        local status_code = 403
        if type(data.status_code) == "number" then
            status_code = data.status_code
        end

        local reason = nil
        if data.reason then
            reason = type(data.reason) == "table"
                and core.json.encode(data.reason)
                or data.reason
        elseif type(data.context) == "table" then
            local user_reason = data.context.reason_user
            if type(user_reason) == "table" and user_reason["403"] then
                reason = user_reason["403"]
            end

            if not reason then
                local admin_reason = data.context.reason_admin
                if type(admin_reason) == "table" and admin_reason["403"] then
                    reason = admin_reason["403"]
                end
            end
        end

        return status_code, reason
    end

    if type(result_headers) == "table" and conf.send_headers_upstream then
        for _, name in ipairs(conf.send_headers_upstream) do
            local value = result_headers[name]
            if value then
                core.request.set_header(ctx, name, value)
            end
        end
    end
end

return _M
