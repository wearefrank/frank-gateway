local token_client = require("apisix.plugins.token-client-common")

local plugin_name = "generic-oauth-client"

local schema = token_client.schema {
	default_expiration = 300,
	properties = {
		client_id_field_name = {
			description = "Name for the field equivalent to client_id",
			type = "string"
		},
		client_id_value = {
			description = "value for the parameter with the name defined in 'client_id_field_name'",
			oneOf = {
				{ type = "string" },
				{ type = "integer", minimum = 0, maximum = 9007199254740991 }
			}
		},
		custom_parameters = token_client.custom_parameters_schema("Set your own parameters for OAuth request"),
	},
	required = {"client_id_field_name", "client_id_value", "token_endpoint"}
}

local function get_cache_key(conf)
	local client_id_value = conf.client_id_value
	if type(client_id_value) == "number" then
		client_id_value = string.format("%.0f", client_id_value)
	end
	return client_id_value
end

local function build_request(conf)
	return token_client.encode_form({
		{ conf.client_id_field_name, get_cache_key(conf) },
	}, conf.custom_parameters)
end

return token_client.new {
	name = plugin_name,
	schema = schema,
	get_cache_key = get_cache_key,
	build_request = build_request,
}
