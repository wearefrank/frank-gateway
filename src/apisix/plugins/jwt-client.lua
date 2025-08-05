local core = require("apisix.core")
local url  = require("net.url")
local json = require("apisix.core.json")

local token_cache = ngx.shared["jwt-client-cache"]

local plugin_name = "jwt-client"

local schema = {
	type = "object",
	properties = {
		token_endpoint = {
			type = "string"
		},
		client_id_field_name = {
			description = "Name for the field equivalent to client_id",
			type = "string"
		},
		client_id_value = {
			description = "value for the parameter with the name defined in 'client_id_field_name'",
			type = "string"
		},
		ssl_verify = {
			description = "Verify SSL certificate of host",
			type = "boolean",
			default = false,
		},
		use_cache = {
			description = "Enable caching of acquired access tokens.",
			type = "boolean",
			default = true,
		},
        default_expiration = {
			type = "integer",
			minimum = 1,
			maximum = 100000,
			default = 600,
			description = "default expiration of cached tokens, when expiration is not provided by IDP in response token"
		},
		custom_parameters = {
			description = "Set your own parameters for token request",
			type = "object",
			minProperties = 1,
			patternProperties = {
				["^[^:]+$"] = {
					oneOf = {
						{ type = "string" },
						{ type = "number" }
					}
				}
			}
		}
    },
	required = {"client_id_field_name", "client_id_value", "token_endpoint"}
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

	local client_id_name = conf.client_id_field_name
	local client_id_value = conf.client_id_value
	local token_endpoint = conf.token_endpoint
	local use_cache 	  = conf.use_cache
	local custom_params = conf.custom_parameters
	local verify_ssl = conf.ssl_verify

	local cached_token = token_cache:get(client_id_value)
	if cached_token ~= nil and use_cache == true then
		core.log.info("found token in cache, using cached token")
		core.request.add_header(ctx, "Authorization", "Bearer " .. cached_token)
		return
	end

	local parsed_url = url.parse(token_endpoint)

	local httpc = assert(require('resty.http').new())
	core.log.info("JWT client before connect", parsed_url)
	local ok, err = httpc:connect {
		ssl_verify = verify_ssl,
		scheme = parsed_url.scheme,
		host = parsed_url.host,
		port = parsed_url.port,
		ssl_server_name = parsed_url.host
	}
	core.log.info("JWT client after connect ", err)

	local request_body = "{" .. "\"" .. client_id_name .. "\"" .. ":" .. "\"" .. client_id_value .. "\""
	if custom_params ~= nil then
		for param, value in pairs(custom_params) do
			request_body = request_body .. "," .. "\"" .. param .. "\"" .. ":" .. "\"" .. value .. "\""
		end
	end
    request_body = request_body .. "}"

	core.log.info("JWT client request: " ..  request_body)

	if ok and not err then
		local response, call_err = assert(httpc:request {
			method = 'POST',
			path = parsed_url.path,
			body = request_body,
			headers = {
				["Content-Type"] = "application/json"
			},
		})
		core.log.info("JWT client request")

		if call_err ~= nil or response.status ~= 200 then
			err = "getting token failed"
		end
        core.log.info("JWT client IDP response status: ", response.status)

        local body, err = response:read_body()
		if err then
			core.log.error(err)
		end
 
		local token_response = core.json.decode(body)

		token_cache:set(client_id_value, token_response.token, conf.default_expiration)
		core.log.info("JWT client token Cached: " .. token_response.token)

		core.request.add_header(ctx, "Authorization", "Bearer " .. token_response.token)
	end

	if err then
		core.log.error("JWT client connection error: ", err)
	end

	httpc:close()
end

return _M