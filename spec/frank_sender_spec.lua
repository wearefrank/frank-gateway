describe("frank-sender plugin", function()
	local plugin
	local schema_check_args
	local info_logs
	local error_logs
	local httpc_connect_args
	local httpc_request_args
	local httpc_close_called
	local httpc_config
	local read_body_called
	local get_body_data_return
	local get_headers_return
	local get_method_return
	local set_body_data_calls

	before_each(function()
		package.loaded["apisix.core"] = nil
		package.loaded["net.url"] = nil
		package.loaded["resty.http"] = nil
		package.loaded["apisix.plugins.frank-sender"] = nil

		schema_check_args = nil
		info_logs = {}
		error_logs = {}
		httpc_connect_args = nil
		httpc_request_args = nil
		httpc_close_called = false
		read_body_called = false
		get_body_data_return = nil
		get_headers_return = { ["Content-Type"] = "text/xml" }
		get_method_return = "POST"
		set_body_data_calls = {}

		httpc_config = {
			connect_err = nil,
			response_status = 200,
			response_reason = "OK",
			response_body = "<result>ok</result>",
			response_body_err = nil,
			request_err = nil,
		}

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
					info = function(...)
						table.insert(info_logs, { ... })
					end,
					error = function(...)
						table.insert(error_logs, { ... })
					end,
				},
				request = {
					get_method = function()
						return get_method_return
					end,
				},
				json = {
					encode = function(value)
						return "encoded"
					end,
				},
			}
		end

		package.preload["net.url"] = function()
			return {
				parse = function(raw)
					-- Minimal URL parser stub matching what the plugin uses
					local scheme, host, port_str, path, query =
						string.match(raw, "^([%a]+)://([^:/]+):?(%d*)(/?[^?]*)%??(.*)")
					return {
						scheme = scheme or "http",
						host = host or "localhost",
						port = tonumber(port_str) or 80,
						path = path or "/",
						query = query ~= "" and query or nil,
					}
				end,
			}
		end

		local function make_httpc()
			return {
				connect = function(self, args)
					httpc_connect_args = args
					if httpc_config.connect_err then
						return nil, httpc_config.connect_err
					end
					return true, nil
				end,
				request = function(self, args)
					httpc_request_args = args
					if httpc_config.request_err then
						error(httpc_config.request_err)
					end
					local res = {
						status = httpc_config.response_status,
						reason = httpc_config.response_reason,
						read_body = function(self)
							return httpc_config.response_body, httpc_config.response_body_err
						end,
					}
					return res, nil
				end,
				close = function(self)
					httpc_close_called = true
				end,
			}
		end

		package.preload["resty.http"] = function()
			return {
				new = function()
					return make_httpc()
				end,
			}
		end

		_G.ngx = {
			req = {
				read_body = function()
					read_body_called = true
				end,
				get_body_data = function()
					return get_body_data_return
				end,
				get_headers = function()
					return get_headers_return
				end,
				set_body_data = function(data)
					table.insert(set_body_data_calls, data)
				end,
			},
		}

		plugin = require("apisix.plugins.frank-sender")
	end)

	it("delegates regular schema checks to plugin schema", function()
		local conf = { frank_endpoint = "http://frank:8080/api" }

		local ok = plugin.check_schema(conf)

		assert.is_true(ok)
		assert.are.equal(plugin.schema, schema_check_args.schema)
		assert.are.same(conf, schema_check_args.conf)
	end)

	it("delegates metadata schema checks to metadata schema", function()
		local conf = {}

		local ok = plugin.check_schema(conf, "metadata")

		assert.is_true(ok)
		assert.are.equal(plugin.metadata_schema, schema_check_args.schema)
	end)

	it("connects to Frank with parsed URL parts", function()
		local conf = { frank_endpoint = "http://frank:8080/api/transform" }
		local ctx = {}

		plugin.access(conf, ctx)

		assert.is_true(read_body_called)
		assert.are.same({
			ssl_verify = false,
			scheme = "http",
			host = "frank",
			port = 8080,
		}, httpc_connect_args)
	end)

	it("sends request with method, path, and headers from the incoming request", function()
		get_method_return = "POST"
		get_headers_return = { ["Content-Type"] = "text/xml" }
		local conf = { frank_endpoint = "http://frank:8080/api/transform" }
		local ctx = {}

		plugin.access(conf, ctx)

		assert.are.same("POST", httpc_request_args.method)
		assert.are.same("/api/transform", httpc_request_args.path)
		assert.are.same({ ["Content-Type"] = "text/xml" }, httpc_request_args.headers)
	end)

	it("includes request body when present", function()
		get_body_data_return = "<input>hello</input>"
		local conf = { frank_endpoint = "http://frank:8080/api/transform" }
		local ctx = {}

		plugin.access(conf, ctx)

		assert.are.same("<input>hello</input>", httpc_request_args.body)
	end)

	it("omits body field when request has no body", function()
		get_body_data_return = nil
		local conf = { frank_endpoint = "http://frank:8080/api/transform" }
		local ctx = {}

		plugin.access(conf, ctx)

		assert.is_nil(httpc_request_args.body)
	end)

	it("passes query string from Frank endpoint URL when present", function()
		local conf = { frank_endpoint = "http://frank:8080/api/transform?action=run" }
		local ctx = {}

		plugin.access(conf, ctx)

		assert.are.same("action=run", httpc_request_args.query)
	end)

	it("omits query field when Frank endpoint URL has no query string", function()
		local conf = { frank_endpoint = "http://frank:8080/api/transform" }
		local ctx = {}

		plugin.access(conf, ctx)

		assert.is_nil(httpc_request_args.query)
	end)

	it("replaces the request body with Frank's response body on success", function()
		httpc_config.response_body = "<transformed>yes</transformed>"
		local conf = { frank_endpoint = "http://frank:8080/api/transform" }
		local ctx = {}

		plugin.access(conf, ctx)

		assert.are.same(1, #set_body_data_calls)
		assert.are.same("<transformed>yes</transformed>", set_body_data_calls[1])
	end)

	it("logs an error when Frank returns a non-200 status", function()
		httpc_config.response_status = 500
		httpc_config.response_reason = "Internal Server Error"
		local conf = { frank_endpoint = "http://frank:8080/api/transform" }
		local ctx = {}

		plugin.access(conf, ctx)

		assert.is_true(#error_logs > 0)
	end)

	it("closes the HTTP connection regardless of outcome", function()
		local conf = { frank_endpoint = "http://frank:8080/api/transform" }
		local ctx = {}

		plugin.access(conf, ctx)

		assert.is_true(httpc_close_called)
	end)
end)
