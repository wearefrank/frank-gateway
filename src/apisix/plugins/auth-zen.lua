local core = require("apisix.core")
local plugin_name = "auth-zen"
local http = require("resty.http")
local ngx_ssl

do
    local ok, ssl_mod = pcall(require, "ngx.ssl")
    if ok then
        ngx_ssl = ssl_mod
    end
end


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
                        type = { type = "string", minLength = 1 },
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
            default = true,
        },
        pdp_auth = {
            type = "object",
            properties = {
                mode = {
                    type = "string",
                    enum = { "none", "bearer" },
                    default = "none",
                },
                bearer_header = {
                    type = "string",
                    minLength = 1,
                    default = "Authorization",
                },
                bearer_prefix = {
                    type = "string",
                    default = "Bearer ",
                },
                bearer_token = {
                    type = "string",
                    minLength = 1,
                },
                mtls = {
                    type = "object",
                    properties = {
                        enabled = {
                            type = "boolean",
                            default = false,
                        },
                        client_cert = {
                            type = "string",
                            minLength = 1,
                        },
                        client_key = {
                            type = "string",
                            minLength = 1,
                        },
                    },
                },
            },
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
        x_request_id = { type = "string" }, -- optional header to pass to authZen, put in the config so the generation of it can be outsourced to another plugin if needed
    },
    required = { "host", "body" }
}


local consumer_schema = {}




local _M = {
    version = 0.1,
    priority = 1999, 
    name = plugin_name,
    type = "auth",   
    schema = schema,
    consumer_schema = consumer_schema
}

function _M.check_schema(conf)
    local check = { "host" }
    core.utils.check_https(check, conf, _M.name)
    core.utils.check_tls_bool({ "ssl_verify" }, conf, _M.name)

    local pdp_auth = conf.pdp_auth
    if pdp_auth then
        if pdp_auth.mode == "bearer" and not pdp_auth.bearer_token then
            return false, "pdp_auth.bearer_token is required when pdp_auth.mode is bearer"
        end

        if pdp_auth.mtls and pdp_auth.mtls.enabled then
            if not pdp_auth.mtls.client_cert or not pdp_auth.mtls.client_key then
                return false, "pdp_auth.mtls.client_cert and pdp_auth.mtls.client_key are required when pdp_auth.mtls.enabled is true"
            end
        end
    end

    return core.schema.check(schema, conf)
end

local function resolve_placeholders(value, ctx)
    local value_type = type(value)

    if value_type == "string" then
        local var_name = value:match("^%$([%w_]+)$")
        if var_name then
            return ctx.var[var_name]
        end

        return (value:gsub("%$([%w_]+)", function(name)
            local resolved = ctx.var[name]
            if resolved == nil then
                return "$" .. name
            end
            return tostring(resolved)
        end))
    end

    if value_type ~= "table" then
        return value
    end

    local out = {}
    for k, v in pairs(value) do
        local resolved = resolve_placeholders(v, ctx)
        if resolved ~= nil then
            out[k] = resolved
        end
    end

    return out
end

local function parse_pem_objects(client_cert_pem, client_key_pem)
    if not ngx_ssl then
        return nil, nil, "ngx.ssl is unavailable; cannot parse mTLS client certificate"
    end

    local cert, cert_err = ngx_ssl.parse_pem_cert(client_cert_pem)
    if not cert then
        return nil, nil, "failed to parse pdp_auth.mtls.client_cert: " .. (cert_err or "unknown error")
    end

    local pkey, pkey_err = ngx_ssl.parse_pem_priv_key(client_key_pem)
    if not pkey then
        return nil, nil, "failed to parse pdp_auth.mtls.client_key: " .. (pkey_err or "unknown error")
    end

    return cert, pkey
end

function _M.access(conf, ctx)
    local request_body = resolve_placeholders(conf.body, ctx)
    local body_ok, body_err = core.schema.check(schema.properties.body, request_body) -- validate the resolved body against the schema
    if not body_ok then
        core.log.error("resolved AuthZEN request body is invalid (missing or unset placeholder?): ", body_err)
        return 500
    end
    local params = {
        method = "POST",
        body = core.json.encode(request_body),
        headers = {
            ["Content-Type"] = "application/json",
        },
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
    if conf.x_request_id then
        local request_id = resolve_placeholders(conf.x_request_id, ctx)
        if request_id ~= nil then
            params.headers["X-Request-ID"] = tostring(request_id)
        end
    end

    if conf.pdp_auth then
        local auth_conf = conf.pdp_auth

        if auth_conf.mode == "bearer" then
            local token = resolve_placeholders(auth_conf.bearer_token, ctx)
            if token == nil or token == "" then
                core.log.error("pdp_auth.mode is bearer but pdp_auth.bearer_token resolved to empty")
                return 500
            end

            local header_name = auth_conf.bearer_header or "Authorization"
            local header_prefix = auth_conf.bearer_prefix or "Bearer "
            params.headers[header_name] = header_prefix .. tostring(token)
        end

        if auth_conf.mtls and auth_conf.mtls.enabled then
            local client_cert_pem = resolve_placeholders(auth_conf.mtls.client_cert, ctx)
            local client_key_pem = resolve_placeholders(auth_conf.mtls.client_key, ctx)

            if not client_cert_pem or not client_key_pem then
                core.log.error("pdp_auth.mtls is enabled but client certificate or key is missing")
                return 500
            end

            local cert, pkey, parse_err = parse_pem_objects(client_cert_pem, client_key_pem)
            if not cert then
                core.log.error(parse_err)
                return 500
            end

            params.ssl_client_cert = cert
            params.ssl_client_priv_key = pkey
        end
    end

    local host = conf.host:gsub("/+$", "")          -- remove trailing slashes from host if any
    local path = conf.endpoint:gsub("^/*", "/")     -- Also ensure endpoint starts with a single slash
    local endpoint = host .. path

    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

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
        return res.status
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
            return 403, data.context --TODO Add return context
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
