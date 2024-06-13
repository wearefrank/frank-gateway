local core = require("apisix.core")

local plugin_name = "limit-size"

local schema = {
	type = "object",
	properties = {
		request_limit = {
			type = "integer"
		},
		request_limit_unit = {
			type = "string",
			enum = {"bytes", "kilobytes", "megabytes"},
			default = "bytes",
		},
		full_request = {
			type = "boolean",
			default = false,
			description = "when set to false it only checks the request body. When set to true it checks the entire HTTP request"
		},
		response_limit = {
			type = "integer",
			description = "limit of the response body returned from the Upstream. For the response only payload limit restrictions are available."
		},
		response_limit_unit = {
			type = "string",
			enum = {"bytes", "kilobytes", "megabytes"},
			default = "bytes",
		},
		full_response = {
			type = "integer",
			description = "when set to false it only checks the response body. When set to true it checks the bytes received from the entire response"
		},
		rejected_code = {
			type = "integer",
			minimum = 200,
			maximum = 599,
			default = 413
		},
		rejected_msg = {
			type = "string",
			minLength = 1,
			default = "size is too large"
		},
	}
}

local metadata_schema = {}

local _M = {
	version = 0.1,
	priority = 1,
	name = plugin_name,
	schema = schema,
	metadata_schema = metadata_schema
}

local unit_multiplication_factor = {
	["bytes"]        = 1,
	["kilobytes"]    = 1024,    -- 2 ^ 10 bytes
	["megabytes"]    = 1048576, -- 2 ^ 20 bytes
}

function _M.check_schema(conf, schema_type)
	if schema_type == core.schema.TYPE_METADATA then
		return core.schema.check(metadata_schema, conf)
	end
	return core.schema.check(schema, conf)
end

local function check_full_request(ctx, allowed_bytes_size)
	local actual_request_size = tonumber(ngx.var.request_length)
	core.log.debug("request length: ", actual_request_size)

	if actual_request_size == nil or actual_request_size > allowed_bytes_size then
		return 1
	end
end

local function check_body_request(ctx, allowed_bytes_size)
	local _, err = core.request.get_body(allowed_bytes_size, ctx)
	return err
end

local function check_full_response(ctx, allowed_bytes_size)

	local actual_response_size = tonumber(ngx.var.upstream_bytes_received)
	core.log.debug("response length: ", actual_response_size)

	if actual_response_size == nil or actual_response_size > allowed_bytes_size then
		return 1
	end
end

local function check_body_response(ctx, allowed_bytes_size)
	local actual_response_size = tonumber(ngx.var.upstream_http_content_length)
	if actual_response_size > allowed_bytes_size then
		return 1
	end
end

function _M.access(conf, ctx)
	if conf.request_limit == nil then
		return
	end

	local allowed_bytes_size = conf.request_limit * unit_multiplication_factor[conf.request_limit_unit]
	core.log.debug("request limit in bytes: ", allowed_bytes_size)

	local err

	if conf.full_request then
		err = check_full_request(ctx, allowed_bytes_size)
	else
		err = check_body_request(ctx, allowed_bytes_size)
	end

	if err ~= nil then
		core.log.error("length limit exceeded")
		return conf.rejected_code, conf.rejected_msg
	end
end

function _M.header_filter(conf, ctx)
	if conf.response_limit == nil then
		return
	end

	local allowed_bytes_size = conf.response_limit * unit_multiplication_factor[conf.response_limit_unit]
	core.log.debug("response limit in bytes: ", allowed_bytes_size)

	local err

	if conf.full_response then
		err = check_full_response(ctx, allowed_bytes_size)
	else
		err = check_body_response(ctx, allowed_bytes_size)
	end

	if err ~= nil then
		core.log.error("length limit exceeded")
		core.response.clear_header_as_body_modified()
		ngx.status = conf.rejected_code
		ctx.error = true
	end

end

function _M.body_filter(conf, ctx)
	if ctx.error then
		ngx.arg[1] = conf.rejected_msg
		ngx.arg[2] = true
	end
end

return _M
