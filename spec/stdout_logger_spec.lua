describe("stdout-logger plugin", function()
	local plugin
	local schema_check_args
	local error_logs
	local json_encode_result
	local json_encode_err
	local json_encode_args
	local written_chunks
	local flush_called
	local original_stdout

	before_each(function()
		package.loaded["apisix.core"] = nil
		package.loaded["apisix.plugins.stdout-logger"] = nil

		schema_check_args = nil
		error_logs = {}
		json_encode_result = "{}"
		json_encode_err = nil
		json_encode_args = nil
		written_chunks = {}
		flush_called = false

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
				},
				json = {
					encode = function(entry)
						json_encode_args = entry
						return json_encode_result, json_encode_err
					end,
				},
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

		plugin = require("apisix.plugins.stdout-logger")
	end)

	after_each(function()
		io.stdout = original_stdout
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
end)
