describe("fsc plugin", function()
	local plugin
	local error_logs
	local warn_logs
	local schema_check_args
	local added_response_headers
	local clear_header_called
	local registered_vars
	local encoded_values
	local registration_store
	local bp_new_args
	local bp_new_err
	local bp_pushes
	local request_headers
	local ngx_mock
	local verify_opts
	local verify_result
	local verify_err
	local der_result
	local der_err
	local sha_digest
	local base64_result
	local http_connect_args
	local http_connect_err
	local http_request_args
	local http_response_status
	local http_close_called

	local MANAGER_KEY = "MANAGER_PUBLIC_KEY"
	local GROUP_ID = "fsc-demo-group"

	local function base_conf(overrides)
		local conf = {
			manager_public_key = MANAGER_KEY,
			fsc_group_id = GROUP_ID,
			internal_cert_chain = "CERT_CHAIN",
			internal_key = "KEY",
			registration = {
				controller_uri = "https://controller.example.com:8443",
				inway_address = "https://inway.example.com:443",
				inway_name = "inway-1",
			},
		}
		for key, value in pairs(overrides or {}) do
			conf[key] = value
		end
		return conf
	end

	local function base_token(overrides)
		local token = {
			cnf = { ["x5t#S256"] = "FINGERPRINT" },
			gid = GROUP_ID,
			sub = "outway-peer",
			iss = "service-peer",
			svc = "demo-service",
			gth = "grant-hash",
		}
		for key, value in pairs(overrides or {}) do
			token[key] = value
		end
		return token
	end

	before_each(function()
		package.loaded["apisix.core"] = nil
		package.loaded["apisix.router"] = nil
		package.loaded["apisix.utils.batch-processor"] = nil
		package.loaded["resty.openidc"] = nil
		package.loaded["resty.http"] = nil
		package.loaded["resty.sha256"] = nil
		package.loaded["ngx.ssl"] = nil
		package.loaded["ngx.base64"] = nil
		package.loaded["ngx.errlog"] = nil
		package.loaded["ngx"] = nil
		package.loaded["table.new"] = nil
		package.loaded["net.url"] = nil
		package.loaded["apisix.plugins.fsc"] = nil

		error_logs = {}
		warn_logs = {}
		schema_check_args = nil
		added_response_headers = {}
		clear_header_called = false
		registered_vars = {}
		encoded_values = {}
		registration_store = {}
		bp_new_args = nil
		bp_new_err = nil
		bp_pushes = {}
		verify_opts = nil
		verify_result = base_token()
		verify_err = nil
		der_result = "DER_CERT"
		der_err = nil
		sha_digest = "RAW_DIGEST"
		base64_result = "FINGERPRINT"
		http_connect_args = nil
		http_connect_err = nil
		http_request_args = nil
		http_response_status = 204
		http_close_called = false

		request_headers = {
			["Fsc-Authorization"] = "Bearer the-token",
			["Fsc-Transaction-Id"] = "tx-1",
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
					error = function(...) table.insert(error_logs, { ... }) end,
					warn = function(...) table.insert(warn_logs, { ... }) end,
					info = function() end,
					debug = function() end,
				},
				response = {
					add_header = function(name, value)
						added_response_headers[name] = value
					end,
					clear_header_as_body_modified = function()
						clear_header_called = true
					end,
				},
				ctx = {
					register_var = function(name, getter)
						registered_vars[name] = getter
					end,
				},
				json = {
					encode = function(value)
						table.insert(encoded_values, value)
						return "ENCODED"
					end,
				},
			}
		end

		package.preload["apisix.router"] = function()
			return { router_http = { routes = function() return {} end } }
		end

		package.preload["apisix.utils.batch-processor"] = function()
			return {
				new = function(self, handler, config)
					if bp_new_err then
						return nil, bp_new_err
					end
					bp_new_args = { handler = handler, config = config }
					return {
						push = function(self, entry)
							table.insert(bp_pushes, entry)
						end,
					}
				end,
			}
		end

		package.preload["resty.openidc"] = function()
			return {
				bearer_jwt_verify = function(opts)
					verify_opts = opts
					return verify_result, verify_err
				end,
			}
		end

		package.preload["resty.http"] = function()
			return {
				new = function()
					return {
						connect = function(self, args)
							http_connect_args = args
							if http_connect_err then
								return nil, http_connect_err
							end
							return true, nil
						end,
						request = function(self, args)
							http_request_args = args
							return { status = http_response_status, body = "" }, nil
						end,
						close = function(self)
							http_close_called = true
						end,
					}
				end,
			}
		end

		package.preload["resty.sha256"] = function()
			return {
				new = function(self)
					return {
						update = function(self, data) end,
						final = function(self) return sha_digest end,
					}
				end,
			}
		end

		package.preload["ngx.ssl"] = function()
			return {
				cert_pem_to_der = function(pem)
					return der_result, der_err
				end,
			}
		end

		package.preload["ngx.base64"] = function()
			return {
				encode_base64url = function(digest)
					return base64_result
				end,
			}
		end

		package.preload["ngx.errlog"] = function()
			return {
				get_sys_filter_level = function() return 4 end,
			}
		end

		package.preload["table.new"] = function()
			return function(narr, nrec) return {} end
		end

		package.preload["net.url"] = function()
			return {
				parse = function(raw)
					local scheme, host, port_str, path =
						string.match(raw, "^([%a]+)://([^:/]+):?(%d*)(/?[^?]*)")
					return {
						scheme = scheme,
						host = host,
						port = tonumber(port_str),
						path = (path ~= "" and path) or nil,
					}
				end,
			}
		end

		ngx_mock = {
			DEBUG = 8,
			status = 200,
			arg = {},
			var = { ssl_client_raw_cert = "PEM_CLIENT_CERT" },
			req = {
				get_headers = function()
					return request_headers
				end,
			},
			shared = {
				["fsc-registration"] = {
					get = function(self, key)
						return registration_store[key]
					end,
					set = function(self, key, value)
						registration_store[key] = value
					end,
				},
			},
		}
		package.preload["ngx"] = function()
			return ngx_mock
		end
		_G.ngx = ngx_mock

		plugin = require("apisix.plugins.fsc")
	end)

	-- -------------------------------------------------------------------------
	-- init
	-- -------------------------------------------------------------------------

	it("init creates the registration batch processor", function()
		plugin.init()

		assert.is_not_nil(bp_new_args)
		assert.are.same("fsc", bp_new_args.config.name)
		assert.is_function(bp_new_args.handler)
	end)

	it("init warns when the batch processor cannot be created", function()
		bp_new_err = "boom"

		plugin.init()

		assert.is_true(#warn_logs > 0)
	end)

	-- -------------------------------------------------------------------------
	-- check_schema
	-- -------------------------------------------------------------------------

	it("delegates metadata schema checks to metadata schema", function()
		local ok = plugin.check_schema({}, "metadata")

		assert.is_true(ok)
		assert.are.equal(plugin.metadata_schema, schema_check_args.schema)
	end)

	it("check_schema warns and aborts when no batch processor is present", function()
		local ok = plugin.check_schema(base_conf())

		assert.is_nil(ok)
		assert.is_true(#warn_logs > 0)
	end)

	it("check_schema parses the controller uri and schedules inway registration", function()
		plugin.init()
		local conf = base_conf()

		local ok = plugin.check_schema(conf)

		assert.is_true(ok)
		assert.are.same("controller.example.com", conf.registration.host)
		assert.are.same(8443, conf.registration.port)
		assert.are.same("/v1/groups/" .. GROUP_ID .. "/inways/inway-1", conf.registration.path)

		assert.are.same(1, #bp_pushes)
		local entry = bp_pushes[1]
		assert.are.same("controller.example.com", entry.host)
		assert.are.same(8443, entry.port)
		assert.are.same("CERT_CHAIN", entry.ssl_cert)
		assert.are.same("KEY", entry.ssl_key)
		assert.are.same('{"address": "https://inway.example.com:443"}', entry.body)
		assert.is_true(registration_store["registered"])

		assert.are.equal(plugin.schema, schema_check_args.schema)
	end)

	it("check_schema defaults the controller port to 443", function()
		plugin.init()
		local conf = base_conf()
		conf.registration.controller_uri = "https://controller.example.com"

		plugin.check_schema(conf)

		assert.are.same(443, conf.registration.port)
	end)

	it("check_schema does not schedule registration twice", function()
		plugin.init()
		registration_store["registered"] = true

		plugin.check_schema(base_conf())

		assert.are.same(0, #bp_pushes)
	end)

	it("check_schema parses tx_log_url into tx_log connection settings", function()
		plugin.init()
		local conf = base_conf({ tx_log_url = "https://txlog.example.com:8444/api/v1/logs" })

		plugin.check_schema(conf)

		assert.are.same("txlog.example.com", conf.tx_log.host)
		assert.are.same(8444, conf.tx_log.port)
		assert.are.same("/api/v1/logs", conf.tx_log.path)
	end)

	-- -------------------------------------------------------------------------
	-- inway registration handler
	-- -------------------------------------------------------------------------

	it("registration handler PUTs the inway address to the controller", function()
		plugin.init()
		local entry = {
			{
				host = "controller.example.com",
				port = 8443,
				path = "/v1/groups/g/inways/i",
				body = '{"address": "addr"}',
				ssl_cert = "CERT_CHAIN",
				ssl_key = "KEY",
			},
		}

		local ok = bp_new_args.handler(entry)

		assert.is_true(ok)
		assert.is_true(http_close_called)
		assert.are.same("controller.example.com", http_connect_args.host)
		assert.are.same(8443, http_connect_args.port)
		assert.are.same("PUT", http_request_args.method)
		assert.are.same("/v1/groups/g/inways/i", http_request_args.path)
		assert.are.same('{"address": "addr"}', http_request_args.body)
	end)

	it("registration handler reports failure on a non-204 response", function()
		plugin.init()
		http_response_status = 500
		local entry = {
			{
				host = "controller.example.com",
				port = 8443,
				path = "/v1/groups/g/inways/i",
				body = '{"address": "addr"}',
				ssl_cert = "CERT_CHAIN",
				ssl_key = "KEY",
			},
		}

		local ok = bp_new_args.handler(entry)

		assert.is_false(ok)
		assert.is_false(registration_store["registered"])
	end)

	-- -------------------------------------------------------------------------
	-- access – token validation
	-- -------------------------------------------------------------------------

	it("access rejects requests without an Fsc-Authorization header", function()
		request_headers["Fsc-Authorization"] = nil

		local status, err = plugin.access(base_conf(), {})

		assert.are.same(401, status)
		assert.are.same("Access token is missing", err.message)
		assert.are.same("ERROR_CODE_ACCESS_TOKEN_MISSING", err.code)
		assert.are.same("ERROR_CODE_ACCESS_TOKEN_MISSING", added_response_headers["Fsc-Error-Code"])
		assert.are.same("application/json", added_response_headers["Content-Type"])
	end)

	it("access rejects requests when openidc finds no authorization header", function()
		verify_result = nil
		verify_err = "no Authorization header found"

		local status, err = plugin.access(base_conf(), {})

		assert.are.same(401, status)
		assert.are.same("ERROR_CODE_ACCESS_TOKEN_MISSING", err.code)
	end)

	it("access rejects requests with an invalid token", function()
		verify_result = nil
		verify_err = "signature mismatch"

		local status, err = plugin.access(base_conf(), {})

		assert.are.same(401, status)
		assert.are.same("Invalid Access token", err.message)
		assert.are.same("ERROR_CODE_ACCESS_DENIED", err.code)
	end)

	it("access verifies the token against the configured manager public key", function()
		plugin.access(base_conf(), {})

		assert.are.same(MANAGER_KEY, verify_opts.public_key)
		assert.are.same("Fsc-Authorization", verify_opts.auth_accept_token_as_header_name)
	end)

	it("access rejects tokens not bound to the client certificate", function()
		verify_result = base_token()
		verify_result.cnf["x5t#S256"] = "OTHER_FINGERPRINT"

		local status, err = plugin.access(base_conf(), {})

		assert.are.same(401, status)
		assert.are.same("Invalid Access token", err.message)
		assert.are.same("ERROR_CODE_ACCESS_DENIED", err.code)
	end)

	it("access rejects requests without a client certificate", function()
		ngx_mock.var.ssl_client_raw_cert = nil

		local status, err = plugin.access(base_conf(), {})

		assert.are.same(401, status)
		assert.are.same("ERROR_CODE_ACCESS_DENIED", err.code)
	end)

	it("access rejects tokens with the wrong group id", function()
		verify_result = base_token({ gid = "other-group" })

		local status, err = plugin.access(base_conf(), {})

		assert.are.same(403, status)
		assert.are.same("WRONG_GROUP_ID_IN_TOKEN", err.code)
	end)

	-- -------------------------------------------------------------------------
	-- access – transaction log entry
	-- -------------------------------------------------------------------------

	it("access rejects requests without an Fsc-Transaction-Id header", function()
		request_headers["Fsc-Transaction-Id"] = nil

		local status, err = plugin.access(base_conf(), {})

		assert.are.same(400, status)
		assert.are.same("MISSING_LOG_RECORD_ID", err.code)
	end)

	it("access allows a valid request and registers logging variables", function()
		local status = plugin.access(base_conf(), {})

		assert.is_nil(status)
		assert.are.same(GROUP_ID, registered_vars["group_id"]())
		assert.are.same("DIRECTION_INCOMING", registered_vars["direction"]())
		assert.are.same("tx-1", registered_vars["transaction_id"]())
		assert.are.same("demo-service", registered_vars["service_name"]())
		assert.are.same("grant-hash", registered_vars["grant_hash"]())

		local source = registered_vars["source"]()
		assert.are.same("SOURCE_TYPE_SOURCE", source.type)
		assert.are.same("outway-peer", source.outway_peer_id)

		local destination = registered_vars["destination"]()
		assert.are.same("DESTINATION_TYPE_DESTINATION", destination.type)
		assert.are.same("service-peer", destination.service_peer_id)
	end)

	it("access records delegation claims in source and destination", function()
		verify_result = base_token({
			act = { sub = "delegator-peer" },
			pdi = "destination-delegator",
		})

		local status = plugin.access(base_conf(), {})

		assert.is_nil(status)

		local source = registered_vars["source"]()
		assert.are.same("SOURCE_TYPE_DELEGATED_SOURCE", source.type)
		assert.are.same("outway-peer", source.outway_peer_id)
		assert.are.same("delegator-peer", source.delegator_peer_id)

		local destination = registered_vars["destination"]()
		assert.are.same("DESTINATION_TYPE_DELEGATED_DESTINATION", destination.type)
		assert.are.same("destination-delegator", destination.delegator_peer_id)
	end)

	it("access sends a transaction log record when tx_log is configured", function()
		local conf = base_conf({
			tx_log = { host = "txlog.example.com", port = 8444, path = "/api/v1/logs" },
		})

		local status = plugin.access(conf, {})

		assert.is_nil(status)
		assert.are.same("txlog.example.com", http_connect_args.host)
		assert.are.same(8444, http_connect_args.port)
		assert.are.same("POST", http_request_args.method)
		assert.are.same("/api/v1/logs", http_request_args.path)
		assert.are.same("ENCODED", http_request_args.body)

		local record = encoded_values[#encoded_values].records[1]
		assert.are.same(GROUP_ID, record.group_id)
		assert.are.same("tx-1", record.transaction_id)
		assert.are.same("demo-service", record.service_name)
	end)

	it("access fails with 500 when the transaction log write fails", function()
		http_response_status = 500
		local conf = base_conf({
			tx_log = { host = "txlog.example.com", port = 8444, path = "/api/v1/logs" },
		})

		local status, err = plugin.access(conf, {})

		assert.are.same(500, status)
		assert.are.same("TRANSACTION_LOG_WRITE_ERROR", err.code)
	end)

	-- -------------------------------------------------------------------------
	-- header_filter / body_filter – upstream error mapping
	-- -------------------------------------------------------------------------

	it("header_filter maps 503 to 502 with a service unreachable error", function()
		ngx_mock.status = 503
		local ctx = {}

		plugin.header_filter(base_conf(), ctx)

		assert.are.same(502, ngx_mock.status)
		assert.is_true(clear_header_called)
		assert.are.same("ERROR_CODE_SERVICE_UNREACHABLE", ctx.error_message.code)
	end)

	it("header_filter sets a not found error on 404", function()
		ngx_mock.status = 404
		local ctx = {}

		plugin.header_filter(base_conf(), ctx)

		assert.are.same(404, ngx_mock.status)
		assert.is_true(clear_header_called)
		assert.are.same("ERROR_CODE_SERVICE_NOT_FOUND", ctx.error_message.code)
	end)

	it("header_filter leaves other statuses untouched", function()
		ngx_mock.status = 200
		local ctx = {}

		plugin.header_filter(base_conf(), ctx)

		assert.are.same(200, ngx_mock.status)
		assert.is_false(clear_header_called)
		assert.is_nil(ctx.error_message)
	end)

	it("body_filter replaces the body with the encoded error message", function()
		ngx_mock.status = 404
		local ctx = { error_message = { message = "Not found", code = "ERROR_CODE_SERVICE_NOT_FOUND" } }

		plugin.body_filter(base_conf(), ctx)

		assert.are.same("ENCODED", ngx_mock.arg[1])
		assert.is_true(ngx_mock.arg[2])
		assert.are.same(ctx.error_message, encoded_values[#encoded_values])
	end)

	it("body_filter leaves the body untouched for other statuses", function()
		ngx_mock.status = 200
		ngx_mock.arg = { "original", false }

		plugin.body_filter(base_conf(), { error_message = nil })

		assert.are.same("original", ngx_mock.arg[1])
		assert.is_false(ngx_mock.arg[2])
	end)
end)
