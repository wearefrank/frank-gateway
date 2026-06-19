describe("limit-size plugin", function()
	local plugin
	local schema_check_args
	local debug_logs
	local error_logs
	local get_body_calls
	local clear_header_called
	local get_body_err

	before_each(function()
		package.loaded["apisix.core"] = nil
		package.loaded["apisix.plugins.limit-size"] = nil

		schema_check_args = nil
		debug_logs = {}
		error_logs = {}
		get_body_calls = {}
		clear_header_called = false
		get_body_err = nil

		package.preload["apisix.core"] = function()
			return {
				schema = {
					TYPE_METADATA = "metadata",
					check = function(schema, conf)
						schema_check_args = { schema = schema, conf = conf }
						return true
					end,
				},
				log = {
					debug = function(...) table.insert(debug_logs, { ... }) end,
					error = function(...) table.insert(error_logs, { ... }) end,
				},
				request = {
					get_body = function(limit, ctx)
						table.insert(get_body_calls, { limit = limit, ctx = ctx })
						return nil, get_body_err
					end,
				},
				response = {
					clear_header_as_body_modified = function()
						clear_header_called = true
					end,
				},
			}
		end

		_G.ngx = {
			var = {
				request_length = nil,
				upstream_bytes_received = nil,
				upstream_http_content_length = nil,
			},
			status = nil,
			arg = { nil, nil },
		}

		plugin = require("apisix.plugins.limit-size")
	end)

	-- -------------------------------------------------------------------------
	-- check_schema
	-- -------------------------------------------------------------------------

	it("delegates regular schema checks to plugin schema", function()
		local conf = { request_limit = 1024 }

		local ok = plugin.check_schema(conf)

		assert.is_true(ok)
		assert.are.equal(plugin.schema, schema_check_args.schema)
	end)

	it("delegates metadata schema checks to metadata schema", function()
		local ok = plugin.check_schema({}, "metadata")

		assert.is_true(ok)
		assert.are.equal(plugin.metadata_schema, schema_check_args.schema)
	end)

	-- -------------------------------------------------------------------------
	-- access – no request_limit configured
	-- -------------------------------------------------------------------------

	it("access returns nil when request_limit is not configured", function()
		local status, body = plugin.access({}, {})

		assert.is_nil(status)
		assert.is_nil(body)
		assert.are.same(0, #get_body_calls)
	end)

	-- -------------------------------------------------------------------------
	-- access – body-only check (full_request = false / nil)
	-- -------------------------------------------------------------------------

	it("access allows request when body check passes", function()
		get_body_err = nil
		local conf = { request_limit = 1024, request_limit_unit = "bytes", full_request = false, rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		local status, body = plugin.access(conf, ctx)

		assert.is_nil(status)
		assert.are.same(1, #get_body_calls)
		assert.are.same(1024, get_body_calls[1].limit)
	end)

	it("access rejects request when body check exceeds limit", function()
		get_body_err = "request body exceeded limit"
		local conf = { request_limit = 512, request_limit_unit = "bytes", full_request = false, rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		local status, body = plugin.access(conf, ctx)

		assert.are.same(413, status)
		assert.are.same("too large", body)
		assert.is_true(#error_logs > 0)
	end)

	-- -------------------------------------------------------------------------
	-- access – full request check (full_request = true)
	-- -------------------------------------------------------------------------

	it("access allows request when full_request size is within limit", function()
		ngx.var.request_length = "500"
		local conf = { request_limit = 1024, request_limit_unit = "bytes", full_request = true, rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		local status = plugin.access(conf, ctx)

		assert.is_nil(status)
		assert.are.same(0, #get_body_calls)
	end)

	it("access rejects request when full_request size exceeds limit", function()
		ngx.var.request_length = "2000"
		local conf = { request_limit = 1024, request_limit_unit = "bytes", full_request = true, rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		local status, body = plugin.access(conf, ctx)

		assert.are.same(413, status)
		assert.are.same("too large", body)
	end)

	it("access rejects when request_length is nil (cannot determine size)", function()
		ngx.var.request_length = nil
		local conf = { request_limit = 1024, request_limit_unit = "bytes", full_request = true, rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		local status, body = plugin.access(conf, ctx)

		assert.are.same(413, status)
		assert.are.same("too large", body)
	end)

	-- -------------------------------------------------------------------------
	-- access – unit conversion
	-- -------------------------------------------------------------------------

	it("access converts kilobytes to bytes before comparing", function()
		ngx.var.request_length = "1025"
		local conf = { request_limit = 1, request_limit_unit = "kilobytes", full_request = true, rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		local status, body = plugin.access(conf, ctx)

		-- 1025 bytes > 1 * 1024 bytes → reject
		assert.are.same(413, status)
	end)

	it("access converts megabytes to bytes before comparing", function()
		ngx.var.request_length = "1048575"
		local conf = { request_limit = 1, request_limit_unit = "megabytes", full_request = true, rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		local status = plugin.access(conf, ctx)

		-- 1048575 bytes < 1 * 1048576 bytes → allow
		assert.is_nil(status)
	end)

	-- -------------------------------------------------------------------------
	-- header_filter – no response_limit configured
	-- -------------------------------------------------------------------------

	it("header_filter does nothing when response_limit is not configured", function()
		local ctx = {}

		plugin.header_filter({}, ctx)

		assert.is_nil(ctx.error)
		assert.is_false(clear_header_called)
	end)

	-- -------------------------------------------------------------------------
	-- header_filter – body-only check (full_response falsy)
	-- -------------------------------------------------------------------------

	it("header_filter allows response when content-length is within limit", function()
		ngx.var.upstream_http_content_length = "500"
		local conf = { response_limit = 1024, response_limit_unit = "bytes", rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		plugin.header_filter(conf, ctx)

		assert.is_nil(ctx.error)
		assert.is_false(clear_header_called)
	end)

	it("header_filter rejects response when content-length exceeds limit", function()
		ngx.var.upstream_http_content_length = "2000"
		local conf = { response_limit = 1024, response_limit_unit = "bytes", rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		plugin.header_filter(conf, ctx)

		assert.is_true(ctx.error)
		assert.is_true(clear_header_called)
		assert.are.same(413, ngx.status)
	end)

	-- -------------------------------------------------------------------------
	-- header_filter – full response check (full_response truthy)
	-- -------------------------------------------------------------------------

	it("header_filter allows response when upstream_bytes_received is within limit", function()
		ngx.var.upstream_bytes_received = "500"
		local conf = { response_limit = 1024, response_limit_unit = "bytes", full_response = true, rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		plugin.header_filter(conf, ctx)

		assert.is_nil(ctx.error)
	end)

	it("header_filter rejects response when upstream_bytes_received exceeds limit", function()
		ngx.var.upstream_bytes_received = "2000"
		local conf = { response_limit = 1024, response_limit_unit = "bytes", full_response = true, rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		plugin.header_filter(conf, ctx)

		assert.is_true(ctx.error)
		assert.are.same(413, ngx.status)
	end)

	it("header_filter rejects when upstream_bytes_received is nil", function()
		ngx.var.upstream_bytes_received = nil
		local conf = { response_limit = 1024, response_limit_unit = "bytes", full_response = true, rejected_code = 413, rejected_msg = "too large" }
		local ctx = {}

		plugin.header_filter(conf, ctx)

		assert.is_true(ctx.error)
	end)

	-- -------------------------------------------------------------------------
	-- body_filter
	-- -------------------------------------------------------------------------

	it("body_filter replaces body and sets eof when ctx.error is set", function()
		local conf = { rejected_msg = "size is too large", rejected_code = 413 }
		local ctx = { error = true }

		plugin.body_filter(conf, ctx)

		assert.are.same("size is too large", ngx.arg[1])
		assert.is_true(ngx.arg[2])
	end)

	it("body_filter leaves body untouched when ctx.error is not set", function()
		ngx.arg = { "original body", false }
		local conf = { rejected_msg = "size is too large", rejected_code = 413 }
		local ctx = {}

		plugin.body_filter(conf, ctx)

		assert.are.same("original body", ngx.arg[1])
		assert.is_false(ngx.arg[2])
	end)
end)
