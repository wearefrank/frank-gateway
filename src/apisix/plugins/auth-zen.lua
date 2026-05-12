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
        endpoint = {
            type = "string",
            minLength = 1,
            default = "/access/v1/evaluation",
        },
        body = {
            type = "object",
            properties = {
                subject = {
                    type = { type = "string", minLength = 1 },
                    id = { type = "string", minLength = 1 },
                    properties = { type = "object" },
                    required = { "type", "id" },
                },
                resource = {
                    type = { type = "string", minLength = 1 },
                    id = { type = "string", minLength = 1 },
                    properties = { type = "object" },
                    required = { "type", "id" },
                },
                action = {
                    type = { type = "string", minLength = 1 },
                    name = { type = "string", minLength = 1 },
                    properties = { type = "object" },
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
            default = true,
        },
        send_headers_to_authzen = {
            type = "array",
            minItems = 1,
            items = {
                type = "string"
            },
            description = "list of headers to pass to AuthZEN in request"
        },
        send_headers_upstream = {
            type = "array",
            minItems = 1,
            items = {
                type = "string"
            },
            description = "list of headers to pass to upstream in request"
        },
        X_Request_Id = { type = "string" }, -- optional header to pass to authZen, put in the config so the generation of it can be outsourced to another plugin if needed
    },
    required = { "host", "body" }
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
    local params = {
        method = "POST",
        body = core.json.encode(conf.body),
        headers = {
            ["Content-Type"] = "application/json",
        },
        timeout = conf.timeout,
        ssl_verify = conf.ssl_verify
    }
    if conf.send_headers_to_authzen then
        for _, name in ipairs(conf.send_headers_to_authzen) do
            local value = core.request.header(ctx, name)
            if value then
                params.headers[name] = value
            end
        end
    end
    if conf.X_Request_Id then
        params.headers["X-Request-ID"] = conf.X_Request_Id
    end


    local endpoint = conf.host .. conf.endpoint --Not sure if this endpoint structure might need to be changed

    local httpc = http.new()


    local res, err = httpc:request_uri(endpoint, params)

    -- block by default when response is unavailable
    if not res then
        core.log.error("failed to process AuthZEN decision, err: ", err)
        return 403
    end

    local req_id = res.headers["x-request-id"]
    if req_id then
        core.response.set_header("X-Request-ID", req_id)
    end

    if res.status ~= 200 then
        core.log.error("unexpected status code from AuthZEN: ", res.status, " body: ", res.body)
        return res.status, res.body -- Not sure if these should be returned, might reveal too much?
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
    local result_headers = res.headers

    if not decision then
    

        if data.context and type(data.context) == "table" then
            return 403, data.context
        end

        return 403
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
