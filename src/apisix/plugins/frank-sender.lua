local core = require("apisix.core")
local url  = require("net.url")
local ngx = ngx
local ngx_req = ngx.req
local req_set_body_data = ngx_req.set_body_data
local req_get_body_data = ngx_req.get_body_data

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
	metadata_schema = metadata_schema,
}

function _M.check_schema(conf, schema_type)
	if schema_type == core.schema.TYPE_METADATA then
		return core.schema.check(metadata_schema, conf)
	else
		return core.schema.check(schema, conf)
	end
end

function _M.access(conf, ctx) -- think about if this needs to be access phase or another phase.
	
	local frank_endpoint = conf.frank_endpoint
	
	ngx_req.read_body()
	local request_body = req_get_body_data()
	
	local frank_url = url.parse(frank_endpoint)
	local request_method = core.request.get_method()
	local request_params = {
		path = frank_url.path,
		method = request_method,
		headers = ngx_req.get_headers()
	}
	
	local httpc = assert(require('resty.http').new())
	local ok, err = httpc:connect {
		ssl_verify = false,
		scheme = frank_url.scheme,
		host = frank_url.host,
		port = frank_url.port,
	}

	core.log.info("Headers for Frank: ", core.json.encode(request_params.headers))
	if request_body ~= nil then
		request_params.body = request_body
		core.log.info("Request body set for Frank: ", request_body)
	end

	if frank_url.query ~= nil and frank_url.query ~= "" then
		request_params.query = frank_url.query
		core.log.info("Query set for Frank: ", frank_url.query)
	end
	
	if ok and not err then
		local res, call_err = assert(httpc:request(request_params))
		
		core.log.info("Frank response code: ", res.status)
		if call_err ~= nil and res.status ~= 200 then
			err = "error:" .. call_err .. "; http code: " .. res.status .. ": " .. res.reason
		elseif res.status ~= 200 then
			err = "unexpected response code: " .. res.status .. ": " .. res.reason
		end

		local transformed_body, err = res:read_body()
		if err then
			core.log.error(err)
		end

		--maybe set headers from frank too?

		core.log.info("Transformed body: " .. transformed_body)
		req_set_body_data(transformed_body)
	end

	if err then
		core.log.error(err)
	end

	httpc:close()
end

return _M