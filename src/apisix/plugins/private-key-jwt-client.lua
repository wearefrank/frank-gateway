local core = require("apisix.core")
local http = require("resty.http")
local pkey = require("resty.openssl.pkey")
local rand = require("resty.openssl.rand")
local sha256 = require("resty.sha256")
local base64 = require("ngx.base64")

local plugin_name = "private-key-jwt-client"
local schema = {
    type = "object",
    properties = {
        token_endpoint = {type = "string", minLength = 1, pattern = "^https://"},
        client_id = {type = "string", minLength = 1},
        private_key = {type = "string", minLength = 1},
        kid = {type = "string", minLength = 1},
        audience = {type = "string", minLength = 1},
        scope = {type = "string", minLength = 1},
        use_cache = {type = "boolean", default = true},
        timeout = {type = "integer", minimum = 1, maximum = 60000, default = 5000},
    },
    encrypt_fields = {"private_key"},
    required = {"token_endpoint", "client_id", "private_key", "kid"},
    additionalProperties = false,
}

local _M = {
    version = 0.1,
    priority = 0,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function fail(message, err)
    core.log.error(plugin_name, ": ", message, err and ": " or "", err or "")
    return 502, {message = "Unable to obtain upstream access token"}
end

local function make_assertion(conf)
    local key, err = pkey.new(conf.private_key, {format = "PEM", type = "pr"})
    if not key then
        return nil, "invalid private key: " .. (err or "unknown error")
    end
    local key_type = key:get_key_type()
    if not key_type or key_type.sn ~= "rsaEncryption" then
        return nil, "private key must be RSA"
    end
    local params, params_err = key:get_parameters()
    if not params or not params.n then
        return nil, "cannot read RSA modulus: " .. (params_err or "unknown error")
    end
    local modulus, modulus_err = params.n:to_binary()
    if not modulus or #modulus < 256 or (#modulus == 256 and modulus:byte(1) < 128) then
        return nil, "RSA modulus must be at least 2048 bits: " .. (modulus_err or "invalid key")
    end

    local random, random_err = rand.bytes(32, true)
    if not random then
        return nil, "cannot generate assertion ID: " .. (random_err or "unknown error")
    end
    local now = ngx.time()
    local header = core.json.encode({alg = "RS256", typ = "JWT", kid = conf.kid})
    local payload = core.json.encode({
        iss = conf.client_id,
        sub = conf.client_id,
        aud = conf.audience or conf.token_endpoint,
        iat = now,
        exp = now + 60,
        jti = base64.encode_base64url(random),
    })
    if not header or not payload then
        return nil, "cannot encode assertion"
    end
    local input = base64.encode_base64url(header) .. "." .. base64.encode_base64url(payload)
    local signature, sign_err = key:sign(input, "sha256", pkey.PADDINGS.RSA_PKCS1_PADDING)
    if not signature then
        return nil, "cannot sign assertion: " .. (sign_err or "unknown error")
    end
    return input .. "." .. base64.encode_base64url(signature)
end

function _M.access(conf, ctx)
    local cache
    local cache_key
    if conf.use_cache ~= false then
        cache = ngx.shared["private-key-jwt-client-cache"]
        if not cache then
            return fail("shared token cache is not configured")
        end
        local identity = core.json.encode({
            conf.token_endpoint, conf.client_id, conf.private_key, conf.kid,
            conf.audience or conf.token_endpoint, conf.scope or "",
        })
        if not identity then
            return fail("cannot encode cache identity")
        end
        local hash = sha256:new()
        if not hash or not hash:update(identity) then
            return fail("cannot hash cache identity")
        end
        local digest = hash:final()
        if not digest then
            return fail("cannot hash cache identity")
        end
        cache_key = base64.encode_base64url(digest)
        local token = cache:get(cache_key)
        if token then
            core.request.set_header(ctx, "Authorization", "Bearer " .. token)
            return
        end
    end

    local assertion, assertion_err = make_assertion(conf)
    if not assertion then
        return fail("assertion creation failed", assertion_err)
    end

    local args = {
        grant_type = "client_credentials",
        client_id = conf.client_id,
        client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        client_assertion = assertion,
        scope = conf.scope,
    }
    local httpc = http.new()
    httpc:set_timeout(conf.timeout or 5000)
    local res, err = httpc:request_uri(conf.token_endpoint, {
        method = "POST",
        body = ngx.encode_args(args),
        headers = {["Content-Type"] = "application/x-www-form-urlencoded"},
        ssl_verify = true,
    })
    if not res then
        return fail("token request failed", err)
    end
    if res.status ~= 200 then
        return fail("token endpoint returned HTTP " .. res.status)
    end

    local result = core.json.decode(res.body)
    if type(result) ~= "table" or type(result.access_token) ~= "string"
        or not result.access_token:match("^[%w%-%._~%+/]+=*$")
        or type(result.token_type) ~= "string" or result.token_type:lower() ~= "bearer" then
        return fail("token endpoint returned an invalid bearer token response")
    end
    if cache then
        local ttl = tonumber(result.expires_in)
        if ttl and ttl > 30 and ttl == ttl and ttl < math.huge then
            local ok, cache_err = cache:set(cache_key, result.access_token, math.min(ttl - 30, 86400))
            if not ok then
                core.log.error(plugin_name, ": cannot cache token: ", cache_err)
            end
        end
    end
    core.request.set_header(ctx, "Authorization", "Bearer " .. result.access_token)
end

return _M
