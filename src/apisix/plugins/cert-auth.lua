local core = require("apisix.core")
local url  = require("net.url")
local plugin_name = "cert-auth"
local consumer_mod = require("apisix.consumer")

local schema = {
}

local consumer_schema = {
	type = "object",
	properties = {
		cn = {type = "string"},
	},
	required = {"cn"},
}

local _M = {
	version = 0.1,
	priority = 2401,
	name = plugin_name,
	type = "auth", -- This means authentication plugin
	schema = schema,
	consumer_schema = consumer_schema
}

-- If its an authentication plugin then it needs to choose a consumer after execution
-- To interact with the consumer resource, this type of plugin needs to provide a consumer_schema to check the plugins configuration in the consumer.
-- The consumer schema is used to create the consumer object.

function _M.check_schema(conf, schema_type)
	if schema_type == core.schema.TYPE_CONSUMER then
		return core.schema.check(consumer_schema, conf)
	end
	return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    local full_dn = ngx.var.ssl_client_s_dn

	if not ngx.var.ssl_client_cert then
		return 401, {message = "Client certificate required"}
	end

	if not full_dn then
        core.log.warn("Client CN is nil. No client certificate presented or not verified.")
		return 403, { message = "No client DN found" }
    else
        core.log.info("Client CN: ", full_dn)
    end

	local cn = string.match(full_dn, "CN=([^,/]+)")
	if not cn then
		return 403, { message = "Failed to extract CN" }
	end
	core.log.info("Extracted CN: ", cn)


	local consumer, consumer_conf, err = consumer_mod.find_consumer(plugin_name, "cn", cn)
    core.log.info("consumer: ", core.json.delay_encode(consumer))
    if not consumer then
		core.log.warn("No consumer found for CN: ", err or "invalid common name")
    	return 403, {message = "No matching consumer for CN"}
    end

    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
	
	if consumer and consumer.username then
    	ctx.consumer_name = consumer.username
	elseif consumer and consumer.consumer_name then
		ctx.consumer_name = consumer.consumer_name
	end

	return
end

return _M