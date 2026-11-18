local token_client = require("apisix.plugins.token-client-common")

local plugin_name = "openid-connect-client"

local schema = token_client.schema {
	default_expiration = 300,
	properties = {
		client_id = {
			type = "string"
		},
		client_secret = {
			type = "string"
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
		},
	},
	required = {"grant_type", "token_endpoint", "client_id", "client_secret"}
}

local function get_cache_key(conf)
	return conf.client_id
end

local function build_request(conf)
	local fields = {
		{ "client_id", conf.client_id },
		{ "client_secret", conf.client_secret },
		{ "grant_type", conf.grant_type },
	}
	if conf.scope ~= nil then
		table.insert(fields, { "scope", conf.scope })
	end
	if conf.resource_server ~= nil then
		table.insert(fields, { "resourceServer", conf.resource_server })
	end

	return token_client.encode_form(fields)
end

return token_client.new {
	name = plugin_name,
	schema = schema,
	get_cache_key = get_cache_key,
	build_request = build_request,
}
