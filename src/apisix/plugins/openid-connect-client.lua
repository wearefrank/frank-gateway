local core = require("apisix.core")
local url  = require("net.url")

local token_cache = ngx.shared["openid-connect-client-cache"]

local plugin_name = "openid-connect-client"

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
		default_expiration = {
			type = "integer",
			minimum = 1,
			maximum = 100000,
			default = 300,
			description = "default expiration of cached tokens, when expiration is not provided by IDP in response token"
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

	local grant_type = conf.grant_type
	local client_id = conf.client_id
	local client_secret = conf.client_secret
	local token_endpoint = conf.token_endpoint
	local scope = conf.scope
	local resource_server = conf.resource_server

	local cached_token = token_cache:get(client_id)
	if cached_token ~= nil then
		core.log.info("found token in cache, using cached token")
		core.request.add_header(ctx, "Authorization", "Bearer " .. cached_token)
		return
	end

	local parsed_url = url.parse(token_endpoint)

	local httpc = assert(require('resty.http').new())
	local ok, err = httpc:connect {
		ssl_verify = false,
		scheme = parsed_url.scheme,
		host = parsed_url.host,
		port = parsed_url.port,
	}

	local request_body = "client_id=" .. ngx.escape_uri(client_id) .. "&client_secret=" .. ngx.escape_uri(client_secret)
	if scope ~= nil then
		request_body = request_body .. "&scope=" .. ngx.escape_uri(scope)
	end

	if grant_type ~= nil then
		request_body = request_body .. "&grant_type=" .. ngx.escape_uri(grant_type)
	end

	if resource_server ~= nil then
		request_body = request_body .. "&resourceServer=" .. ngx.escape_uri(resource_server)
	end

	core.log.info("Built request body: " .. request_body)

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
			err = "getting access token failed"
		end
		local body, err = res:read_body()
		if err then
			core.log.error(err)
		end

		local token_response = core.json.decode(body)
		local expiration = token_response.expires_in or conf.default_expiration

		token_cache:set(client_id, token_response.access_token, expiration)
		core.request.add_header(ctx, "Authorization", "Bearer " .. token_response.access_token)
	end

	if err then
		core.log.error(err)
	end

	httpc:close()
end

return _M