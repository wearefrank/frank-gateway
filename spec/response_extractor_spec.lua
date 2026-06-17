describe("response-extractor plugin", function()
	local plugin
	local array_mt
	local schema_check_args
	local decode_calls
	local encode_calls
	local warn_logs
	local query_calls

	before_each(function()
		package.loaded["apisix.core"] = nil
		package.loaded["jsonpath"] = nil
		package.loaded["cjson.safe"] = nil
		package.loaded["apisix.plugins.response-extractor"] = nil

		array_mt = {}
		schema_check_args = nil
		decode_calls = {}
		encode_calls = {}
		warn_logs = {}
		query_calls = {}

		package.preload["cjson.safe"] = function()
			return {
				array_mt = array_mt
			}
		end

		package.preload["apisix.core"] = function()
			return {
				schema = {
					check = function(schema, conf)
						schema_check_args = { schema = schema, conf = conf }
						return true
					end
				},
				json = {
					decode = function(body)
						table.insert(decode_calls, body)
						if body == '{"headers":{"X-Real-Ip":"127.0.0.1","X-Request-Id":"req-1"}}' then
							return {
								headers = {
									["X-Real-Ip"] = "127.0.0.1",
									["X-Request-Id"] = "req-1"
								}
							}
						end
						return nil, "invalid json"
					end,
					encode = function(value)
						table.insert(encode_calls, value)
						if type(value) == "table" and getmetatable(value) == array_mt then
							if value[1] then
								return string.format('["%s"]', value[1])
							end
							return "[]"
						end
						return "encoded_object"
					end
				},
				log = {
					warn = function(...)
						table.insert(warn_logs, { ... })
					end
				}
			}
		end

		package.preload["jsonpath"] = function()
			return {
				query = function(data, path)
					table.insert(query_calls, { data = data, path = path })
					if path == "$.headers['X-Real-Ip']" then
						return { data.headers["X-Real-Ip"] }
					end
					if path == "$.headers['X-Request-Id']" then
						return { data.headers["X-Request-Id"] }
					end
					return nil, "unsupported path"
				end
			}
		end

		_G.ngx = { arg = { nil, false } }

		plugin = require("apisix.plugins.response-extractor")
	end)

	it("delegates schema checks to apisix core", function()
		local conf = { ip = "$.headers['X-Real-Ip']" }

		local ok = plugin.check_schema(conf)

		assert.is_true(ok)
		assert.is_not_nil(schema_check_args)
		assert.are.equal(plugin.schema, schema_check_args.schema)
		assert.are.same(conf, schema_check_args.conf)
	end)

	it("buffers chunks when response is not finished", function()
		local conf = { ip = "$.headers['X-Real-Ip']" }
		local ctx = { var = {} }

		ngx.arg = { '{"headers":', false }
		plugin.body_filter(conf, ctx)

		assert.are.same(1, #ctx._resp_body_chunks)
		assert.are.same('{"headers":', ctx._resp_body_chunks[1])
		assert.is_nil(ctx.extracted)
		assert.are.same(0, #decode_calls)
		assert.are.same(0, #query_calls)
	end)

	it("extracts configured values on response end", function()
		local conf = {
			ip = "$.headers['X-Real-Ip']",
			requestId = "$.headers['X-Request-Id']"
		}
		local ctx = { var = {} }

		ngx.arg = { '{"headers":{"X-Real-Ip":"127.0.0.1",', false }
		plugin.body_filter(conf, ctx)

		ngx.arg = { '"X-Request-Id":"req-1"}}', true }
		plugin.body_filter(conf, ctx)

		assert.are.same(1, #decode_calls)
		assert.are.same('{"headers":{"X-Real-Ip":"127.0.0.1","X-Request-Id":"req-1"}}', decode_calls[1])

		assert.is_table(ctx.extracted)
		assert.are.same("127.0.0.1", ctx.extracted.ip[1])
		assert.are.same("req-1", ctx.extracted.requestId[1])
		assert.are.same("127.0.0.1", ctx.var.ip[1])
		assert.are.same("req-1", ctx.var.requestId[1]) 
		assert.are.same('["127.0.0.1"]', ctx.var.ip_json)
		assert.are.same('["req-1"]', ctx.var.requestId_json)
		assert.are.same("encoded_object", ctx.var.extracted)
		assert.are.same(2, #query_calls)
	end)

	it("returns empty extracted arrays when JSON decode fails", function()
		local conf = {
			ip = "$.headers['X-Real-Ip']",
			requestId = "$.headers['X-Request-Id']"
		}
		local ctx = { var = {} }

		ngx.arg = { 'not-json', true }
		plugin.body_filter(conf, ctx)

		assert.are.same(1, #warn_logs)
		assert.are.same("failed to decode response body: ", warn_logs[1][1])
		assert.are.same("invalid json", warn_logs[1][2])
		assert.are.same(0, #query_calls)

		assert.is_table(ctx.extracted.ip)
		assert.is_table(ctx.extracted.requestId)
		assert.are.same(0, #ctx.extracted.ip)
		assert.are.same(0, #ctx.extracted.requestId)
		assert.are.equal(array_mt, getmetatable(ctx.extracted.ip))
		assert.are.equal(array_mt, getmetatable(ctx.extracted.requestId))
		assert.are.same("[]", ctx.var.ip_json)
		assert.are.same("[]", ctx.var.requestId_json)
	end)

	it("logs jsonpath failures and keeps empty arrays for failed paths", function()
		local conf = {
			ip = "$.headers['X-Real-Ip']",
			missing = "$.headers['Missing']"
		}
		local ctx = { var = {} }

		ngx.arg = { '{"headers":{"X-Real-Ip":"127.0.0.1","X-Request-Id":"req-1"}}', true }
		plugin.body_filter(conf, ctx)

		assert.are.same("127.0.0.1", ctx.extracted.ip[1])
		assert.are.same(0, #ctx.extracted.missing)
		assert.are.equal(array_mt, getmetatable(ctx.extracted.missing))
		assert.are.same("[]", ctx.var.missing_json)

		assert.are.same(1, #warn_logs)
		assert.are.same("jsonpath error for ", warn_logs[1][1])
		assert.are.same("missing", warn_logs[1][2])
		assert.are.same(": ", warn_logs[1][3])
		assert.are.same("unsupported path", warn_logs[1][4])
	end)
end)
