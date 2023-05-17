local core = require("apisix.core")
local http     = require("resty.http")
local jwt = require("resty.jwt")
local openidc = require("resty.openidc")

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

function _M.access(conf, ctx) 

    -- for RFC 8705 certificate bound tokens
    local raw_client_cert = ngx.var.ssl_client_raw_cert

    local ssl = require "ngx.ssl"
    local der_cert_chain, err = ssl.cert_pem_to_der(raw_client_cert)
    if err then
        ngx.say("Could not convert PEM certificate to DER")
    end

    local resty_sha256 = require("resty.sha256")
    local sha256_client_cert = resty_sha256:new()
    sha256_client_cert:update(der_cert_chain)
    local digest = sha256_client_cert:final()

    core.log.debug("sha256 digest of client cert: " .. digest)

    local base64 = require("ngx.base64")
    local encoded_digest = base64.encode_base64url(digest)
    core.log.debug("encoded digest: " .. encoded_digest)

    -- fOr FSC token validation
    local opts = {
        discovery = {
            jwks_uri = conf.jwks_url,
        },
        auth_accept_token_as_header_name = "Fsc-Authorization"
    }
    core.log.debug("discovery jwks endpoint is: " .. opts.discovery.jwks_uri)

    local res, err = openidc.bearer_jwt_verify(opts)

    if err then
        ngx.say("JWT not verified: " .. err)
    end

    local inspect = require('inspect')
    core.log.debug("jws verified: " .. inspect(res))
end

return _M