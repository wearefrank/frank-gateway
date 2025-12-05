local core          = require("apisix.core")
local openidc       = require("resty.openidc")
local ssl           = require("ngx.ssl")
local resty_sha256  = require("resty.sha256")
local base64        = require("ngx.base64")
local os            = os
local new_tab       = require "table.new"
local errlog        = require "ngx.errlog"
local ngx           = require("ngx")
local string        = string
local router        = require("apisix.router")
local bp_manager    = require("apisix.utils.batch-processor")
local url           = require("net.url")

local registration_cache = ngx.shared["fsc-registration"]

local plugin_name = "fsc"

local registration_schema = {
    type = "object",
    properties = {
        controller_uri = {
            type = "string"
        },
        inway_address = {
            type = "string"
        },
        inway_name = {
            type = "string"
        }
    },
    required = {"controller_uri", "inway_address", "inway_name"}
}

local schema = {
    type = "object",
    properties = {
        manager_public_key = {
            type = "string"
        },
        fsc_group_id = {
            type = "string"
        },
        internal_cert_chain = {
            type = "string"
        },
        internal_key = {
            type = "string"
        },
        tx_log_url = {
            type = "string"
        },
        registration = registration_schema,
    },
    required = {"manager_public_key", "fsc_group_id", "internal_cert_chain", "internal_key", "registration"}
}

local metadata_schema = {}

local _M = {
    version = 0.1,
    priority = 1,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}

local register_inway = function(entry)
    local httpc = assert(require('resty.http').new())
    local ok, err = httpc:connect {
        scheme = 'https',
        host = entry[1].host,
        port = entry[1].port,
        ssl_verify = false,
        ssl_cert = entry[1].ssl_cert,
        ssl_key = entry[1].ssl_key,
    }

    if ok and not err then
        local res, err = assert(httpc:request {
            method = 'PUT',
            path = entry[1].path,
            body = entry[1].body,
            headers = {
                ['Host'] = entry[1].host,
                ["Content-Type"] = "application/json",
            },
        })

        core.log.debug("FSC Controller register Inway response status: ", res.status)
        if err ~= nil or res.status ~= 204 then
            core.log.error(err)

            registration_cache:set("registered", false)
            return false, err, 1
        end

    end

    httpc:close()

    return true

end

local config_bat = {
    name = plugin_name,
}

local batch_processor
function _M.init()
    local err
    batch_processor, err = bp_manager:new(register_inway, config_bat)
    if not batch_processor then
        core.log.warn("error when creating the batch processor: ", err)
        return
    end
end

function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    if conf.registration then
        local registration_url = url.parse(conf.registration.controller_uri)
        conf.registration.host = registration_url.host
        conf.registration.port = registration_url.port or 443
        conf.registration.path = "/v1/groups/" .. conf.fsc_group_id .. "/inways/" .. conf.registration.inway_name
        core.log.debug("host: " .. conf.registration.host)
        core.log.debug("port: " .. conf.registration.port)
        core.log.debug("path: " .. conf.registration.path)
    end

    if not batch_processor then
        core.log.warn("no batch processor present, cannot automatically register inway")
        return
    end

    local is_registered = registration_cache:get("registered")

    if is_registered == nil then
        registration_cache:set("registered", true)
        core.log.debug("Inway not registered, scheduling registration call")
        local entry = {
            ssl_cert = conf.internal_cert_chain,
            ssl_key = conf.internal_key,
            host = conf.registration.host,
            port = conf.registration.port,
            path = conf.registration.path,
            body = '{"address": "' .. conf.registration.inway_address .. '"}',
        }
        batch_processor:push(entry)
        core.log.debug("registration call successfully scheduled")
    end

    if conf.tx_log_url then
        local tx_log_url = url.parse(conf.tx_log_url)
        conf.tx_log = {
            host = tx_log_url.host,
            port = tx_log_url.port or 443,
            path = tx_log_url.path,
        }
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

local function validate_token(manager_public_key)

    local opts = {
        public_key = manager_public_key,
        auth_accept_token_as_header_name = "Fsc-Authorization",
    }

    local res, err = openidc.bearer_jwt_verify(opts)
    return res, err

end

local function client_x5t_s256()

    local raw_client_cert = ngx.var.ssl_client_raw_cert
    local der_cert_chain, err = ssl.cert_pem_to_der(raw_client_cert)

    if err then
        core.log.error("Could not convert PEM certificate to DER")
        local error_msg = format_error("Invalid client cert", "ERROR_CODE_ACCESS_DENIED")
        return 540, error_msg
    end

    -- Nginx only has the sha1 fingerprint, RFC8705 needs the sha256 fingerprint
    local function sha256_fingerprint(der_cert_chain)
        local sha256_client_cert = resty_sha256:new()
        sha256_client_cert:update(der_cert_chain)
        local digest = sha256_client_cert:final()

        if digest == nil then
            ngx.core.error("Could not calculate sha256 fingerprint from certficate")
            local error_msg = format_error("Invalid client cert", "ERROR_CODE_ACCESS_DENIED")
            return 540, error_msg
        end

        return digest
    end

    local digest = sha256_fingerprint(der_cert_chain)

    local function encode_digest(digest)

        local encoded_digest = base64.encode_base64url(digest)
        if encoded_digest == nil then
            core.log.error("Could not base64url encode the digest")
            local error_msg = format_error("Invalid client cert", "ERROR_CODE_ACCESS_DENIED")
            return 540, error_msg
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

local function is_valid_group_id(validated_token, group_id)
    local jwt_gid = validated_token.gid
    return jwt_gid == group_id
end

local function format_log_entry(token, group_id)

    local group_id = group_id
    local direction = "DIRECTION_INCOMING"
    local created_at = os.time()
    local transaction_id = ngx.req.get_headers()["Fsc-Transaction-Id"]

    if transaction_id == nil then
        return nil, format_error("The the Fsc-Transaction-Id header is missing", "MISSING_LOG_RECORD_ID")
    end

    -- check if token contains delegation claims
    local source = {}
    if token.act ~= nil  and token.act.sub ~= "" then
        source.type = "SOURCE_TYPE_DELEGATED_SOURCE"
        source.outway_peer_id = token.sub
        source.delegator_peer_id = token.act.sub
    else
        source.type = "SOURCE_TYPE_SOURCE"
        source.outway_peer_id = token.sub
    end

    local destination = {}
    if token.pdi ~= nil then
        destination.type = "DESTINATION_TYPE_DELEGATED_DESTINATION"
        destination.service_peer_id = token.iss
        destination.delegator_peer_id = token.pdi
    else
        destination.type = "DESTINATION_TYPE_DESTINATION"
        destination.service_peer_id = token.iss
    end

    local service_name = token.svc
    local grant_hash = token.gth

    -- register variables so they can be used in APISIX logging plugins
    core.ctx.register_var("group_id", function()
        return group_id
    end)

    core.ctx.register_var("direction", function()
        return direction
    end)

    core.ctx.register_var("created_at", function()
        return created_at
    end)

    core.ctx.register_var("transaction_id", function()
        return transaction_id
    end)

    core.ctx.register_var("source", function(ctx)
        return source
    end)

    core.ctx.register_var("destination", function(ctx)
        return destination
    end)

    core.ctx.register_var("service_name", function(ctx)
        return service_name
    end)

    core.ctx.register_var("grant_hash", function(ctx)
        return grant_hash
    end)

    local records = {
        records = {}
    }
    records.records[1] = {
        group_id = group_id,
        direction = direction,
        transaction_id = transaction_id,
        grant_hash = grant_hash,
        service_name = service_name,
        source = source,
        destination = destination,
        created_at = created_at,
    }

    return records, nil
end

local function send_tx_log_record(log_record, txLogConf)
    local httpc = assert(require('resty.http').new())
    local ok, err = httpc:connect {
        scheme = 'https',
        host = txLogConf.host,
        port = txLogConf.port,
        ssl_verify = false,
        ssl_cert = txLogConf.internal_cert_chain,
        ssl_key = txLogConf.internal_key,
    }

    core.log.debug("txLog record: ", core.json.encode(log_record))

    if ok and not err then
        local res, call_err = assert(httpc:request {
            method = 'POST',
            path = txLogConf.path,
            body = core.json.encode(log_record),
            headers = {
                ['Host'] = txLogConf.host,
                ["Content-Type"] = "application/json",
            },
        })

        core.log.debug("FSC TxLog API response status: ", res.status)
        core.log.debug("FSC TxLog API response body: ", res.body)
        if call_err ~= nil or res.status ~= 204 then
            err = "tx logging failed"
        end
    end

    httpc:close()

    if err then
        return false, err
    end
    return true, nil
end

function _M.access(conf, ctx)

    local headers = ngx.req.get_headers()["Fsc-Authorization"]
    if headers == nil then
        core.log.error("Fsc-Authorization header is missing.")
        local error_msg = format_error("Access token is missing", "ERROR_CODE_ACCESS_TOKEN_MISSING")
        return 401, error_msg
    end

    -- for FSC token validation
    local manager_public_key = conf.manager_public_key
    local validated_token, err = validate_token(manager_public_key)

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

    local log_level = errlog.get_sys_filter_level()
    if log_level == ngx.DEBUG then
        local inspect = require('inspect')
        local routes = router.router_http.routes()
        core.log.debug("jws verified: " .. inspect(validated_token))
        core.log.debug("found routes in config: " .. inspect(routes))
    end

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

    -- FSC Group ID check
    local valid_group_id = is_valid_group_id(validated_token, conf.fsc_group_id)
    if not valid_group_id then
        local error = string.format("wrong group ID in token: %s: want group ID %s", conf.fsc_group_id, validated_token.gid)
        core.log.error(error)
        local error_msg = format_error(error, "WRONG_GROUP_ID_IN_TOKEN")
        return 403, error_msg
    end

    local log_record, err = format_log_entry(validated_token, conf.fsc_group_id)
    if err then
        return 400, err
    end

    if conf.tx_log then
        local ok, err = send_tx_log_record(log_record, {
            internal_cert_chain = conf.internal_cert_chain,
            internal_key = conf.internal_key,
            host = conf.tx_log.host,
            port = conf.tx_log.port,
            path = conf.tx_log.path,
        })

        if err then
            core.log.error("could not send log record to Tx log")
            local error_msg = format_error("The TransactionLog record could not be created", "TRANSACTION_LOG_WRITE_ERROR")
            return 500, error_msg
        end
    end
end

function _M.body_filter(conf, ctx)

    local res_status_code = ngx.status
    if res_status_code == 404 or res_status_code == 503 or res_status_code == 502 then
        local error_response = core.json.encode(ctx.error_message)
        ngx.arg[1] = error_response
        ngx.arg[2] = true
    end

end

function _M.header_filter(conf, ctx)
    local res_status_code = ngx.status
    if res_status_code == 503 then
        ngx.status = 502
        core.response.clear_header_as_body_modified()
        ctx.error_message = format_error("Service unavailable", "ERROR_CODE_SERVICE_UNREACHABLE")

    elseif res_status_code == 404 then
        core.response.clear_header_as_body_modified()
        ctx.error_message = format_error("Not found", "ERROR_CODE_SERVICE_NOT_FOUND")
    end
end

return _M
