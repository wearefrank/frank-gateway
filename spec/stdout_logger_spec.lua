describe("stdout-logger plugin", function()
	local plugin
	local schema_check_args
	local error_logs
	local warn_logs
	local json_encode_result
	local json_encode_err
	local json_encode_args
	local written_chunks
	local flush_called
	local original_stdout
	local get_body_calls
	local get_body_err
	local expr_new_args
	local expr_new_err
	local expr_eval_args
	local expr_eval_result

	before_each(function()
		package.loaded["apisix.core"] = nil
		package.loaded["resty.expr.v1"] = nil
		package.loaded["apisix.plugins.stdout-logger"] = nil

		schema_check_args = nil
		error_logs = {}
		warn_logs = {}
		json_encode_result = "{}"
		json_encode_err = nil
		json_encode_args = nil
		written_chunks = {}
		flush_called = false
		get_body_calls = {}
		get_body_err = nil
		expr_new_args = nil
		expr_new_err = nil
		expr_eval_args = nil
		expr_eval_result = false

		package.preload["apisix.core"] = function()
			return {
				schema = {
					check = function(schema, conf)
						schema_check_args = { schema = schema, conf = conf }
						return true
					end,
				},
				log = {
					error = function(...) table.insert(error_logs, { ... }) end,
					warn = function(...) table.insert(warn_logs, { ... }) end,
				},
				json = {
					encode = function(entry)
						json_encode_args = entry
						return json_encode_result, json_encode_err
					end,
				},
				request = {
					get_body = function()
						table.insert(get_body_calls, true)
						return nil, get_body_err
					end,
				},
			}
		end

		package.preload["resty.expr.v1"] = function()
			return {
				new = function(rule)
					expr_new_args = rule
					if expr_new_err then
						return nil, expr_new_err
					end
					return {
						eval = function(self, vars)
							expr_eval_args = vars
							return expr_eval_result
						end,
					}
				end,
			}
		end

		original_stdout = io.stdout
		io.stdout = {
			write = function(self, ...)
				table.insert(written_chunks, { ... })
			end,
			flush = function(self)
				flush_called = true
			end,
		}

		_G.ngx = {
			arg = { nil, false },
			req = { get_headers = function() return { ["X-Req"] = "req-value" } end },
			resp = { get_headers = function() return { ["X-Resp"] = "resp-value" } end },
		}

		plugin = require("apisix.plugins.stdout-logger")
	end)

	after_each(function()
		io.stdout = original_stdout
		_G.ngx = nil
	end)

	-- -------------------------------------------------------------------------
	-- check_schema
	-- -------------------------------------------------------------------------

	it("delegates schema checks to plugin schema", function()
		local conf = { log_format = { message = "$request_id" } }

		local ok = plugin.check_schema(conf)

		assert.is_true(ok)
		assert.are.equal(plugin.schema, schema_check_args.schema)
		assert.are.equal(conf, schema_check_args.conf)
	end)

	-- -------------------------------------------------------------------------
	-- log
	-- -------------------------------------------------------------------------

	it("resolves top-level $ values from ctx.var", function()
		local conf = { log_format = { request_id = "$request_id" } }
		local ctx = { var = { request_id = "abc-123" } }

		plugin.log(conf, ctx)

		assert.are.same({ request_id = "abc-123" }, json_encode_args)
	end)

	it("copies non-$ string and other scalar values as-is", function()
		local conf = { log_format = { level = "info", count = 42, enabled = true } }
		local ctx = { var = {} }

		plugin.log(conf, ctx)

		assert.are.same({ level = "info", count = 42, enabled = true }, json_encode_args)
	end)

	it("resolves nested tables recursively", function()
		local conf = {
			log_format = {
				request = {
					id = "$request_id",
					method = "$request_method",
				},
			},
		}
		local ctx = { var = { request_id = "abc-123", request_method = "GET" } }

		plugin.log(conf, ctx)

		assert.are.same({
			request = { id = "abc-123", method = "GET" },
		}, json_encode_args)
	end)

	it("resolves labels map when conf.labels is defined", function()
		local conf = {
			log_format = { message = "hello" },
			labels = {
				log_type = "$log_type",
				env = "prod",
			},
		}
		local ctx = { var = { status = "200" } }

		plugin.log(conf, ctx)

		assert.are.same({
			message = "hello",
			labels = {
				log_type = "Info",
				env = "prod",
			},
		}, json_encode_args)
	end)

	it("writes the encoded line followed by a newline and flushes stdout", function()
		json_encode_result = '{"a":1}'
		local conf = { log_format = { a = 1 } }
		local ctx = { var = {} }

		plugin.log(conf, ctx)

		assert.are.same({ { '{"a":1}', "\n" } }, written_chunks)
		assert.is_true(flush_called)
	end)

	it("logs an error and does not write to stdout when encoding fails", function()
		json_encode_result = nil
		json_encode_err = "boom"
		local conf = { log_format = { a = 1 } }
		local ctx = { var = {} }

		plugin.log(conf, ctx)

		assert.are.equal(1, #error_logs)
		assert.are.same({ "failed to encode stdout-logger entry: ", "boom" }, error_logs[1])
		assert.are.same({}, written_chunks)
		assert.is_false(flush_called)
	end)

	-- -------------------------------------------------------------------------
	-- log / log_type
	-- -------------------------------------------------------------------------

	it("classifies status >= 500 as Error", function()
		local conf = { log_format = { log_type = "$log_type" } }
		local ctx = { var = { status = "500" } }

		plugin.log(conf, ctx)

		assert.are.same({ log_type = "Error" }, json_encode_args)
	end)

	it("classifies status >= 400 and < 500 as Warn", function()
		local conf = { log_format = { log_type = "$log_type" } }
		local ctx = { var = { status = "404" } }

		plugin.log(conf, ctx)

		assert.are.same({ log_type = "Warn" }, json_encode_args)
	end)

	it("classifies status < 400 as Info", function()
		local conf = { log_format = { log_type = "$log_type" } }
		local ctx = { var = { status = "200" } }

		plugin.log(conf, ctx)

		assert.are.same({ log_type = "Info" }, json_encode_args)
	end)

	it("classifies a missing status as Info", function()
		local conf = { log_format = { log_type = "$log_type" } }
		local ctx = { var = {} }

		plugin.log(conf, ctx)

		assert.are.same({ log_type = "Info" }, json_encode_args)
	end)

	-- -------------------------------------------------------------------------
	-- access / include_req_body
	-- -------------------------------------------------------------------------

	it("does not read the request body when include_req_body is not set", function()
		local conf = { log_format = { a = 1 } }
		local ctx = { var = {} }

		plugin.access(conf, ctx)

		assert.are.same({}, get_body_calls)
		assert.is_nil(expr_new_args)
	end)

	it("reads the request body when include_req_body is true", function()
		local conf = { log_format = { a = 1 }, include_req_body = true }
		local ctx = { var = {} }

		plugin.access(conf, ctx)

		assert.are.equal(1, #get_body_calls)
	end)

	it("logs a warning when reading the request body fails", function()
		get_body_err = "body too large"
		local conf = { log_format = { a = 1 }, include_req_body = true }
		local ctx = { var = {} }

		plugin.access(conf, ctx)

		assert.are.equal(1, #warn_logs)
		assert.are.same({ "stdout-logger failed to read request body: ", "body too large" }, warn_logs[1])
	end)

	it("does not read the request body when include_req_body_expr does not match", function()
		expr_eval_result = false
		local conf = { log_format = { a = 1 }, include_req_body_expr = { { "arg_debug", "==", "1" } } }
		local ctx = { var = { arg_debug = "0" } }

		plugin.access(conf, ctx)

		assert.are.same({ { "arg_debug", "==", "1" } }, expr_new_args)
		assert.are.equal(ctx.var, expr_eval_args)
		assert.are.same({}, get_body_calls)
	end)

	it("reads the request body when include_req_body_expr matches", function()
		expr_eval_result = true
		local conf = { log_format = { a = 1 }, include_req_body_expr = { { "arg_debug", "==", "1" } } }
		local ctx = { var = { arg_debug = "1" } }

		plugin.access(conf, ctx)

		assert.are.equal(1, #get_body_calls)
	end)

	it("logs an error and skips the body when include_req_body_expr fails to compile", function()
		expr_new_err = "invalid rule"
		local conf = { log_format = { a = 1 }, include_req_body_expr = { { "bad" } } }
		local ctx = { var = {} }

		plugin.access(conf, ctx)

		assert.are.equal(1, #error_logs)
		assert.are.same({ "stdout-logger failed to compile expr: ", "invalid rule" }, error_logs[1])
		assert.are.same({}, get_body_calls)
	end)

	-- -------------------------------------------------------------------------
	-- access / include_req_headers
	-- -------------------------------------------------------------------------

	it("does not expose request headers when include_req_headers is not set", function()
		local conf = { log_format = { a = 1 } }
		local ctx = { var = {} }

		plugin.access(conf, ctx)

		assert.is_nil(ctx.var.request_headers)
	end)

	it("exposes request headers when include_req_headers is true", function()
		local conf = { log_format = { a = 1 }, include_req_headers = true }
		local ctx = { var = {} }

		plugin.access(conf, ctx)

		assert.are.same({ ["X-Req"] = "req-value" }, ctx.var.request_headers)
	end)

	-- -------------------------------------------------------------------------
	-- header_filter / include_resp_headers
	-- -------------------------------------------------------------------------

	it("does not expose response headers when include_resp_headers is not set", function()
		local conf = { log_format = { a = 1 } }
		local ctx = { var = {} }

		plugin.header_filter(conf, ctx)

		assert.is_nil(ctx.var.response_headers)
	end)

	it("exposes response headers when include_resp_headers is true", function()
		local conf = { log_format = { a = 1 }, include_resp_headers = true }
		local ctx = { var = {} }

		plugin.header_filter(conf, ctx)

		assert.are.same({ ["X-Resp"] = "resp-value" }, ctx.var.response_headers)
	end)

	-- -------------------------------------------------------------------------
	-- body_filter / include_resp_body
	-- -------------------------------------------------------------------------

	it("does not touch ctx.var.response_body when include_resp_body is not set", function()
		local conf = { log_format = { a = 1 } }
		local ctx = { var = {} }
		ngx.arg = { "chunk", true }

		plugin.body_filter(conf, ctx)

		assert.is_nil(ctx.var.response_body)
	end)

	it("accumulates chunks and exposes the full body once eof is reached", function()
		local conf = { log_format = { a = 1 }, include_resp_body = true }
		local ctx = { var = {} }

		ngx.arg = { "hello ", false }
		plugin.body_filter(conf, ctx)
		assert.is_nil(ctx.var.response_body)

		ngx.arg = { "world", true }
		plugin.body_filter(conf, ctx)
		assert.are.equal("hello world", ctx.var.response_body)
	end)

	it("handles a final chunk that is nil when eof is reached", function()
		local conf = { log_format = { a = 1 }, include_resp_body = true }
		local ctx = { var = {} }

		ngx.arg = { "hello", false }
		plugin.body_filter(conf, ctx)

		ngx.arg = { nil, true }
		plugin.body_filter(conf, ctx)

		assert.are.equal("hello", ctx.var.response_body)
	end)

	it("exposes the response body when include_resp_body_expr matches", function()
		expr_eval_result = true
		local conf = { log_format = { a = 1 }, include_resp_body_expr = { { "status", "==", "200" } } }
		local ctx = { var = { status = "200" } }

		ngx.arg = { "body", true }
		plugin.body_filter(conf, ctx)

		assert.are.same({ { "status", "==", "200" } }, expr_new_args)
		assert.are.equal("body", ctx.var.response_body)
	end)

	it("does not expose the response body when include_resp_body_expr does not match", function()
		expr_eval_result = false
		local conf = { log_format = { a = 1 }, include_resp_body_expr = { { "status", "==", "200" } } }
		local ctx = { var = { status = "500" } }

		ngx.arg = { "body", true }
		plugin.body_filter(conf, ctx)

		assert.is_nil(ctx.var.response_body)
	end)
end)
