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


function _M.access(conf, ctx)
	
	local frank_endpoint = conf.frank_endpoint
	local parsed_url = url.parse(frank_endpoint)
	
	local consumer = core.request.header(ctx, "Consumer")
    if not consumer then
        core.log.info("No Consumer header found in request. Continuing without.")
    end
	core.log.info("Found consumer header: ", consumer)


	local httpc = assert(require('resty.http').new())
	local ok, err = httpc:connect {
		ssl_verify = false,
		scheme = parsed_url.scheme,
		host = parsed_url.host,
		port = parsed_url.port,
	}

	ngx_req.read_body()
	local request_body = req_get_body_data()

	core.log.info("Initial body: " .. request_body .. " ; sending to : " .. frank_endpoint)

	local headers_for_frank = {
		["Consumer"] = consumer,
		["Content-Type"] = "application/json"
	}

	core.log.info("Headers for Frank BEFORE CONTENTTYPE: ", core.json.encode(headers_for_frank))

	local content_type = core.request.header(ctx, "Content-Type")
	if content_type then
		headers_for_frank["Content-Type"] = content_type
		core.log.info("Using content type from header: ", content_type)
	else
		core.log.info("No Content-Type header found in request. Using default of application/json.")
	end

	core.log.info("Headers for Frank AFTER CONTENTTYPE: ", core.json.encode(headers_for_frank))

	if ok and not err then
		local res, call_err = assert(httpc:request {
			method = 'POST',
			path = parsed_url.path,
			body = request_body,
			headers = headers_for_frank
		})
		
		core.log.info("Frank responde code: ", res.status)
		if call_err ~= nil or res.status ~= 200 then
			err = "error:" .. call_err "; http code: ".. res.status
		end

		local transformed_body, err = res:read_body()
		if err then
			core.log.error(err)
		end

		core.log.info("Transformed body: " .. transformed_body)
		req_set_body_data(transformed_body)
	end

	if err then
		core.log.error(err)
	end

	httpc:close()
end

return _M