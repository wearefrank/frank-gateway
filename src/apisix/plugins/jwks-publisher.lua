local core = require("apisix.core")
local pkey = require("resty.openssl.pkey")
local base64 = require("ngx.base64")

local plugin_name = "jwks-publisher"
local schema = {
    type = "object",
    properties = {
        keys = {
            type = "array",
            minItems = 1,
            items = {
                type = "object",
                properties = {
                    kid = {type = "string", minLength = 1},
                    public_key = {type = "string", minLength = 1},
                },
                required = {"kid", "public_key"},
                additionalProperties = false,
            },
        },
    },
    required = {"keys"},
    additionalProperties = false,
}

local _M = {
    version = 0.1,
    priority = 1,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return ok, err
    end
    local seen = {}
    for _, key in ipairs(conf.keys) do
        if seen[key.kid] then
            return false, "JWKS key IDs must be unique"
        end
        seen[key.kid] = true
    end
    return true
end

function _M.access(conf)
    if ngx.req.get_method() ~= "GET" then
        ngx.header["Allow"] = "GET"
        return 405, {message = "Method not allowed"}
    end

    local keys = {}
    for _, configured in ipairs(conf.keys) do
        local key, err = pkey.new(configured.public_key, {format = "PEM", type = "pu"})
        if not key then
            core.log.error(plugin_name, ": invalid public key: ", err)
            return 500, {message = "Unable to publish JWKS"}
        end
        local key_type = key:get_key_type()
        local params, params_err = key:get_parameters()
        if not key_type or key_type.sn ~= "rsaEncryption" or not params
            or not params.n or not params.e then
            core.log.error(plugin_name, ": invalid RSA public key: ", params_err or "invalid key")
            return 500, {message = "Unable to publish JWKS"}
        end
        local n = params.n:to_binary()
        local e = params.e:to_binary()
        if not n or #n < 256 or (#n == 256 and n:byte(1) < 128) or not e or #e == 0 then
            core.log.error(plugin_name, ": invalid RSA public key parameters")
            return 500, {message = "Unable to publish JWKS"}
        end
        keys[#keys + 1] = {
            kty = "RSA",
            use = "sig",
            alg = "RS256",
            kid = configured.kid,
            n = base64.encode_base64url(n),
            e = base64.encode_base64url(e),
        }
    end
    ngx.header["Cache-Control"] = "no-cache"
    ngx.header["Content-Type"] = "application/json"
    return 200, {keys = keys}
end

return _M
