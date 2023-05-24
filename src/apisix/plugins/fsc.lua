local core = require("apisix.core")
local http     = require("resty.http")
local jwt = require("resty.jwt")
local openidc = require("resty.openidc")
local ssl = require("ngx.ssl")
local resty_sha256 = require("resty.sha256")
local base64 = require("ngx.base64")

local plugin_name = "fsc"

local schema = {
    type = "object",
    properties = {
        jwks_url = {
            type = "string"
        },
    },
    required = {"jwks_url"}
}

local metadata_schema = {}

local _M = {
    version = 0.1,
    priority = 1,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema
}

function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    return core.schema.check(schema, conf)
end

local function validate_token(jwks_url)

    local opts = {
        discovery = {
            jwks_uri = jwks_url,
        },
        auth_accept_token_as_header_name = "Fsc-Authorization"
    }
    core.log.debug("discovery jwks endpoint is: " .. opts.discovery.jwks_uri)

    local res, err = openidc.bearer_jwt_verify(opts)
    return res, err

end

local function client_x5t_s256()
    
    local raw_client_cert = ngx.var.ssl_client_raw_cert
    local der_cert_chain, err = ssl.cert_pem_to_der(raw_client_cert)

    if err then
        core.log.error("Could not convert PEM certificate to DER")
        ngx.say("Could not convert PEM certificate to DER") -- TODO return FSC error
    end

    -- Nginx only has the sha1 fingerprint, RFC8705 needs the sha256 fingerprint
    local function sha256_fingerprint(der_cert_chain)
        local sha256_client_cert = resty_sha256:new()
        sha256_client_cert:update(der_cert_chain)
        local digest = sha256_client_cert:final()

        if digest == nil then
            ngx.core.error("Could not calculate sha256 fingerprint from certficate") 
            ngx.say("Could not calculate sha256 fingerprint from certficate") -- TODO return FSC error
        end

        return digest
    end

    local digest = sha256_fingerprint(der_cert_chain)

    local function encode_digest(digest)

        local encoded_digest = base64.encode_base64url(digest)
        if encoded_digest == nil then
            core.log.error("Could not base64url encode the digest")
            ngx.say("Could not base64url encode the digest") -- TODO return FSC error
        end

        return encoded_digest

    end

    return encode_digest(digest)

end

local function token_x5t_s256(token)
    local encoded_digest = token.cnf["x5t#S256"]

    if encoded_digest == nil then
        core.log.error("Access token does not contain x5t#S256")
        ngx.say("Access Token does not contain x5t#S256") -- TODO return FSC error
    end
    return encoded_digest
end

function _M.access(conf, ctx) 

    -- for FSC token validation
    local jwks_url = conf.jwks_url
    local validated_token, err = validate_token(jwks_url)
    
    if err then
        core.log.error("JWT not verified: " .. err)
        ngx.say("JWT not verified: " .. err) -- TODO return FSC error
        return
    end

    local inspect = require('inspect') -- TODO this should eventually be removed, kept for now for easier troubleshooting
    core.log.debug("jws verified: " .. inspect(validated_token))
    
    -- RFC 8705 Certificate bound tokens check
    local client_x5t_s256 = client_x5t_s256()
    local token_x5t_s256 = token_x5t_s256(validated_token)

    core.log.debug("client x5t#s256: " .. client_x5t_s256)
    core.log.debug("access token x5t#s256" .. token_x5t_s256)

    if not client_x5t_s256 == token_x5t_s256 then
        core.log.error("token not bound to this client")
        ngx.say("Token not bound to this client") -- TODO return FSC error
        return
    end

end

return _M