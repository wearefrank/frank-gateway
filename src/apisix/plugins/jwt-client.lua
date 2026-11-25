local token_client = require("apisix.plugins.token-client-common")

local plugin_name = "jwt-client"

local schema = token_client.schema {
	default_expiration = 600,
	properties = {
		client_id_field_name = {
			description = "Name for the field equivalent to client_id",
			type = "string"
		},
		client_id_value = {
			description = "value for the parameter with the name defined in 'client_id_field_name'",
			type = "string"
		},
		custom_parameters = token_client.custom_parameters_schema("Set your own parameters for token request"),
	},
	required = {"client_id_field_name", "client_id_value", "token_endpoint"}
}

local function get_cache_key(conf)
	return conf.client_id_value
end

local function build_request(conf)
	return token_client.encode_json({
		{ conf.client_id_field_name, conf.client_id_value },
	}, conf.custom_parameters)
end

return token_client.new {
	name = plugin_name,
	schema = schema,
	get_cache_key = get_cache_key,
	build_request = build_request,
	set_ssl_server_name = true,
}
