local core = require("apisix.core")
local plugin_name = "auth-zen"



local schema = {}
local consumer_schema = {}



local _M = {
	version = 0.2,
	priority = 2402,
	name = plugin_name,
	type = "auth", -- marks this as an authentication plugin, so APISIX knows it must pick a consumer
	schema = schema,
	consumer_schema = consumer_schema
}
