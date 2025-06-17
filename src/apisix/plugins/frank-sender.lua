local core = require("apisix.core")
local url  = require("net.url")
local ngx = ngx
local req_set_body_data = ngx.req.set_body_data
local req_get_body_data = ngx.req.get_body_data

local plugin_name = "frank-sender"

local schema = {
	type = "object",
	properties = {
		frank_endpoint = {
			type = "string"
		}
	},
	required = {"frank_endpoint"}
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

	local frank_endpoint = conf.frank_endpoint
	local parsed_url = url.parse(frank_endpoint)

	local httpc = assert(require('resty.http').new())
	local ok, err = httpc:connect {
		ssl_verify = false,
		scheme = parsed_url.scheme,
		host = parsed_url.host,
		port = parsed_url.port,
	}

	ngx.req.read_body()
	local request_body = req_get_body_data()

	core.log.info("Initial body: " .. request_body .. "; sending to Frank:" .. frank_endpoint)

	if ok and not err then
		local res, call_err = assert(httpc:request {
			method = 'POST',
			path = parsed_url.path,
			body = request_body,
			headers = {
				["Content-Type"] = "text/plain",
			},
		})
		
		core.log.info("Frank responde code: ", res.status)
		if call_err ~= nil or res.status ~= 200 then
			err = "error:" .. call_err "; http code: ".. res.status
		end
		local body, err = res:read_body()
		if err then
			core.log.error(err)
		end

	    core.log.info("Transformed body: " .. body)
		req_set_body_data(body)
	end

	if err then
		core.log.error(err)
	end

	httpc:close()
end

return _M