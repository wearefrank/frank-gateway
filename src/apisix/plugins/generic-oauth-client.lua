local core = require("apisix.core")
local url  = require("net.url")

local token_cache = ngx.shared["generic-oauth-client-cache"]

local plugin_name = "generic-oauth-client"

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
		default_expiration = {
			type = "integer",
			minimum = 1,
			maximum = 100000,
			default = 300,
			description = "default expiration of cached tokens, when expiration is not provided by IDP in response token"
		},
		custom_parameters = {
			description = "Set your own parameters for OAuth request",
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
	local custom_params = conf.custom_parameters

	local cached_token = token_cache:get(client_id_value)
	if cached_token ~= nil then
		core.log.info("found token in cache, using cached token")
		core.request.add_header(ctx, "Authorization", "Bearer " .. cached_token)
		return
	end

	local parsed_url = url.parse(token_endpoint)

	core.log.info("Parsed token url (scheme, host, path, port): ", parsed_url)
	local httpc = assert(require('resty.http').new())
	local ok, err = httpc:connect {
		ssl_verify = false,
		scheme = parsed_url.scheme,
		host = parsed_url.host,
		port = parsed_url.port,
	}

	local request_body = client_id_name .. "=" .. ngx.escape_uri(client_id_value)
	if custom_params ~= nil then
		for param, value in pairs(custom_params) do
			request_body = request_body .. "&" .. param .. "=" .. ngx.escape_uri(value)
		end
	end

	core.log.info("Built request body: " ..  request_body)

	if ok and not err then
		local res, call_err = assert(httpc:request {
			method = 'POST',
			path = parsed_url.path,
			body = request_body,
			headers = {
				["Content-Type"] = "application/x-www-form-urlencoded",
			},
		})

		core.log.info("IDP response status: ", res.status)
		if call_err ~= nil or res.status ~= 200 then
			err = "getting token failed"
		end
		local body, err = res:read_body()
		if err then
			core.log.error(err)
		end

		local token_response = core.json.decode(body)
		local expiration = token_response.expires_in or conf.default_expiration

		token_cache:set(client_id_value, token_response.access_token, expiration)
		core.log.info("Token Cached: " .. token_response.access_token)
		core.request.add_header(ctx, "Authorization", "Bearer " .. token_response.access_token)
	end

	if err then
		core.log.error(err)
	end

	httpc:close()
end

return _M
