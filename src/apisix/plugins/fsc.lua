local core          = require("apisix.core")
local http          = require("resty.http")
local jwt           = require("resty.jwt")
local openidc       = require("resty.openidc")
local ssl           = require("ngx.ssl")
local resty_sha256  = require("resty.sha256")
local base64        = require("ngx.base64")
local os            = os
local new_tab       = require "table.new"

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

local function format_error(error_message, error_code)
    local error = new_tab(3, 0)

    error.message = error_message
    error.domain = "ERROR_DOMAIN_INWAY"
    error.code = error_code
    core.response.add_header("Fsc-Error-Code", error_code)
    core.response.add_header("Content-Type", "application/json")
    return error
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
        local error_msg = format_error("Invalid client cert", "ERROR_CODE_ACCESS_DENIED")
        return 401, error_msg 
    end

    -- Nginx only has the sha1 fingerprint, RFC8705 needs the sha256 fingerprint
    local function sha256_fingerprint(der_cert_chain)
        local sha256_client_cert = resty_sha256:new()
        sha256_client_cert:update(der_cert_chain)
        local digest = sha256_client_cert:final()

        if digest == nil then
            ngx.core.error("Could not calculate sha256 fingerprint from certficate") 
            local error_msg = format_error("Invalid client cert", "ERROR_CODE_ACCESS_DENIED")
            return 401, error_msg 
        end

        return digest
    end

    local digest = sha256_fingerprint(der_cert_chain)

    local function encode_digest(digest)

        local encoded_digest = base64.encode_base64url(digest)
        if encoded_digest == nil then
            core.log.error("Could not base64url encode the digest")
            local error_msg = format_error("Invalid client cert", "ERROR_CODE_ACCESS_DENIED")
            return 401, error_msg 
        end

        return encoded_digest

    end

    return encode_digest(digest)

end

local function token_x5t_s256(token)
    local encoded_digest = token.cnf["x5t#S256"]

    if encoded_digest == nil then
        core.log.error("Access token does not contain x5t#S256")
        local error_msg = format_error("Invalid Access token", "ERROR_CODE_ACCESS_DENIED")
        return 401, error_msg 
    end
    return encoded_digest
end

local function set_requester_header()

    local client_dn = ngx.var.ssl_client_s_dn
    core.log.debug("client DN: " .. client_dn)
    local from, to, err = ngx.re.find(client_dn, "(serialNumber=)(.{20})", "jo", nil, 2)

    if err then
        core.log.warn("PEER_ID not found: " .. err)
    elseif from then
        local serialNumber = string.sub(client_dn, from, to)
        core.log.debug("serialNumber: " .. serialNumber)
        ngx.req.set_header("X-NLX-Requester-Organization", serialNumber)
    end

end

local function format_log_entry(token)

    core.ctx.register_var("direction", function() 
        return "DIRECTION_INCOMING" 
    end)

    core.ctx.register_var("created_at", function() 
        return os.time()
    end)

    core.ctx.register_var("transaction_id", function()
       return core.id.gen_uuid_v4() 
    end)
    
    core.ctx.register_var("source", function(ctx)
        return {outway_peer_id = token.sub}
    end)
    
    core.ctx.register_var("destination", function(ctx)
        return {service_peer_id = "unknown"} -- TODO service_peer_id is not known to inway
    end)

    core.ctx.register_var("service_name", function(ctx)
        return token.svc
    end)
    
    core.ctx.register_var("grant_hash", function(ctx)
        return token.gth
    end)
end

function _M.access(conf, ctx) 

    -- for FSC token validation
    local jwks_url = conf.jwks_url
    local validated_token, err = validate_token(jwks_url)
   
    if err == "no Authorization header found" then
        core.log.error("Fsc-Authorization header is missing: ", err)
        local error_msg = format_error("Access token is missing", "ERROR_CODE_ACCESS_TOKEN_MISSING")
        return 401, error_msg 
    end

    if err then
        core.log.error("JWT not verified: " .. err) 
        local error_msg = format_error("Invalid Access token", "ERROR_CODE_ACCESS_DENIED")
        return 401, error_msg
    end

    local inspect = require('inspect') -- TODO this should eventually be removed, kept for now for easier troubleshooting
    core.log.debug("jws verified: " .. inspect(validated_token))
    
    -- RFC 8705 Certificate bound tokens check
    local client_x5t_s256 = client_x5t_s256()
    local token_x5t_s256 = token_x5t_s256(validated_token)

    core.log.debug("client x5t#s256: " .. client_x5t_s256)
    core.log.debug("access token x5t#s256" .. token_x5t_s256)

    if client_x5t_s256 ~= token_x5t_s256 then
        core.log.error("token not bound to this client")
        local error_msg = format_error("Invalid Access token", "ERROR_CODE_ACCESS_DENIED")
        return 401, error_msg 
    end

    -- Add X-NLX-Requester-Organization header (confirmed by FSC team this is no longer needed, kept for now since we might need the client cert serial number)
    set_requester_header()
    format_log_entry(validated_token)
    
end

function _M.body_filter(conf, ctx)
    
    local res_status_code = ngx.status
    if res_status_code == 404 or res_status_code == 503 then
        local error_response = core.json.encode(ctx.error_message)
        ngx.arg[1] = error_response 
        ngx.arg[2] = true 
    end

end

function _M.header_filter(conf, ctx)
    local res_status_code = ngx.status
    if res_status_code == 503 then
        core.response.clear_header_as_body_modified()
        ctx.error_message = format_error("Service unavailable", "ERROR_CODE_SERVICE_UNREACHABLE")
    
    elseif res_status_code == 404 then
        core.response.clear_header_as_body_modified()
        ctx.error_message = format_error("Not found", "ERROR_CODE_SERVICE_NOT_FOUND")
    end
end

return _M
