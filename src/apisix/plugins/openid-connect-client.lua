local url  = require("net.url")
local core = require("apisix.core")

local plugin_name = "openid-connect-client"

local token_cache = ngx.shared["openid-connect-client-cache"]

local schema = {
	type = "object",
	properties = {
		token_endpoint = {
			type = "string"
		},
		client_id = {
			type = "string"
		},
		client_secret = {
			type = "string"
		},
		ssl_verify = {
			description = "Verify SSL certificate of IDP (Must be set to false if the IDP is using a self-signed certificate)",
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
			default = 300,
			description = "Default expiration time of cached tokens in seconds. Used when expiration is not provided by IDP in response"
		},
		scope = {
			type = "string"
		},
		resource_server = {
			type = "string"
		},
		grant_type = {
			type = "string",
			default = "client_credentials"
		}
	},
	required = {"grant_type", "token_endpoint", "client_id", "client_secret"}
}

local metadata_schema = {}

local _M = {
	name 			= plugin_name,
	schema 			= schema,
	version 		= 0.1,
	priority 		= 1,
	metadata_schema = metadata_schema
}

function _M.check_schema(conf, schema_type)
	if schema_type == core.schema.TYPE_METADATA then
		return core.schema.check(metadata_schema, conf)
	end
	return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)

	local scope 		  = conf.scope
	local client_id 	  = conf.client_id
	local use_cache 	  = conf.use_cache
	local grant_type	  = conf.grant_type
	local verify_ssl 	  = conf.ssl_verify
	local client_secret   = conf.client_secret
	local token_endpoint  = conf.token_endpoint
	local resource_server = conf.resource_server

	local cached_token = token_cache:get(client_id)
	if cached_token ~= nil and use_cache == true then
		core.log.info("found token in cache, using cached token")
		core.request.add_header(ctx, "Authorization", "Bearer " .. cached_token)
		return
	end

	local parsed_url = url.parse(token_endpoint)

	local httpc = assert(require('resty.http').new())
	local _, err = httpc:connect {
		host 	   = parsed_url.host,
		port 	   = parsed_url.port,
		scheme 	   = parsed_url.scheme,
		ssl_verify = verify_ssl
	}

	if err then
		core.log.error(err)
		httpc:close()
		return 500, { message = err }
	end

	local request_body = "client_id=" .. ngx.escape_uri(client_id) .. "&client_secret=" .. ngx.escape_uri(client_secret) .. "&grant_type=" .. ngx.escape_uri(grant_type)
	if scope ~= nil then
		request_body = request_body .. "&scope=" .. ngx.escape_uri(scope)
	end

	if resource_server ~= nil then
		request_body = request_body .. "&resourceServer=" .. ngx.escape_uri(resource_server)
	end

	core.log.info("Built request body: " .. request_body)

	local res, call_err = assert(httpc:request {
		path    = parsed_url.path,
		body    = request_body,
		method  = 'POST',
		headers = {
			["Content-Type"] = "application/x-www-form-urlencoded",
		},
	})

	local body, _ = res:read_body()
	core.log.info("IDP response status: ", res.status)
	if call_err ~= nil or res.status ~= 200 then
		core.log.error("Http error: ", body)
		core.log.error("Call error: ", call_err)
		httpc:close()
		if body == nil then
			return res.status, { message = "Failed to make request to IDP. No error message was given. Error code: " .. res.status }
		else
			return res.status, { message = body }
		end
	else
		local token_response = core.json.decode(body)
		local expiration = token_response.expires_in or conf.default_expiration

		token_cache:set(client_id, token_response.access_token, expiration)
		core.request.add_header(ctx, "Authorization", "Bearer " .. token_response.access_token)
		httpc:close()
	end
end

return _M