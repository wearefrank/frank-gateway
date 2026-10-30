describe("auth-zen plugin", function()
	local plugin
	local error_logs
	local schema_check_calls
	local body_schema_check_err
	local check_https_calls
	local check_tls_calls
	local request_headers
	local upstream_headers_set
	local response_headers_set
	local encoded_bodies
	local json_decode_map
	local http_request_args
	local http_timeout
	local http_response
	local http_error
	local ssl_cert_err
	local ssl_key_err

	local function base_conf(overrides)
		local conf = {
			host = "https://pdp.example.com",
			endpoint = "/access/v1/evaluation",
			timeout = 3000,
			ssl_verify = true,
			body = {
				subject = { type = "user", id = "$remote_user" },
				resource = { type = "route", id = "$uri" },
				action = { name = "GET" },
			},
		}
		for key, value in pairs(overrides or {}) do
			conf[key] = value
		end
		return conf
	end

	local function base_ctx()
		return {
			var = {
				remote_user = "alice",
				uri = "/api/thing",
				request_id = "rid-123",
				secret_token = "tok-xyz",
			},
		}
	end

	before_each(function()
		package.loaded["apisix.core"] = nil
		package.loaded["resty.http"] = nil
		package.loaded["ngx.ssl"] = nil
		package.loaded["apisix.plugins.auth-zen"] = nil

		error_logs = {}
		schema_check_calls = {}
		body_schema_check_err = nil
		check_https_calls = {}
		check_tls_calls = {}
		request_headers = {}
		upstream_headers_set = {}
		response_headers_set = {}
		encoded_bodies = {}
		http_request_args = nil
		http_timeout = nil
		http_error = nil
		ssl_cert_err = nil
		ssl_key_err = nil

		http_response = { status = 200, headers = {}, body = "ALLOW" }
		json_decode_map = {
			ALLOW = { decision = true },
			DENY = { decision = false },
		}

		package.preload["apisix.core"] = function()
			local core
			core = {
				schema = {
					check = function(schema, conf)
						table.insert(schema_check_calls, { schema = schema, conf = conf })
						if body_schema_check_err and plugin and schema == plugin.schema.properties.body then
							return false, body_schema_check_err
						end
						return true
					end,
				},
				log = {
					error = function(...) table.insert(error_logs, { ... }) end,
					warn = function() end,
					info = function() end,
					debug = function() end,
				},
				utils = {
					check_https = function(fields, conf, name)
						table.insert(check_https_calls, { fields = fields, conf = conf, name = name })
					end,
					check_tls_bool = function(fields, conf, name)
						table.insert(check_tls_calls, { fields = fields, conf = conf, name = name })
					end,
				},
				request = {
					header = function(ctx, name)
						return request_headers[name]
					end,
					set_header = function(ctx, name, value)
						upstream_headers_set[name] = value
					end,
				},
				response = {
					set_header = function(name, value)
						response_headers_set[name] = value
					end,
				},
				json = {
					encode = function(value)
						table.insert(encoded_bodies, value)
						return "ENCODED_BODY"
					end,
					decode = function(body)
						local decoded = json_decode_map[body]
						if decoded ~= nil then
							return decoded
						end
						return nil, "decode error"
					end,
				},
			}
			return core
		end

		package.preload["ngx.ssl"] = function()
			return {
				parse_pem_cert = function(pem)
					if ssl_cert_err then
						return nil, ssl_cert_err
					end
					return { pem = pem }
				end,
				parse_pem_priv_key = function(pem)
					if ssl_key_err then
						return nil, ssl_key_err
					end
					return { pem = pem }
				end,
			}
		end

		package.preload["resty.http"] = function()
			return {
				new = function()
					return {
						set_timeout = function(self, timeout)
							http_timeout = timeout
						end,
						request_uri = function(self, uri, params)
							http_request_args = { uri = uri, params = params }
							if http_error then
								return nil, http_error
							end
							return http_response
						end,
					}
				end,
			}
		end

		plugin = require("apisix.plugins.auth-zen")
	end)

	-- -------------------------------------------------------------------------
	-- check_schema
	-- -------------------------------------------------------------------------

	it("delegates regular schema checks to plugin schema", function()
		local conf = base_conf()

		local ok = plugin.check_schema(conf)

		assert.is_true(ok)
		assert.are.equal(plugin.schema, schema_check_calls[#schema_check_calls].schema)
		assert.are.same({ "host" }, check_https_calls[1].fields)
		assert.are.same({ "ssl_verify" }, check_tls_calls[1].fields)
	end)

	it("check_schema rejects bearer mode without bearer_token", function()
		local conf = base_conf({ pdp_auth = { mode = "bearer" } })

		local ok, err = plugin.check_schema(conf)

		assert.is_false(ok)
		assert.are.same("pdp_auth.bearer_token is required when pdp_auth.mode is bearer", err)
	end)

	it("check_schema rejects enabled mtls without client cert and key", function()
		local conf = base_conf({ pdp_auth = { mode = "none", mtls = { enabled = true } } })

		local ok, err = plugin.check_schema(conf)

		assert.is_false(ok)
		assert.are.same(
			"pdp_auth.mtls.client_cert and pdp_auth.mtls.client_key are required when pdp_auth.mtls.enabled is true",
			err)
	end)

	-- -------------------------------------------------------------------------
	-- access – request building
	-- -------------------------------------------------------------------------

	it("access resolves placeholders and allows the request on positive decision", function()
		local status = plugin.access(base_conf(), base_ctx())

		assert.is_nil(status)
		assert.are.same("https://pdp.example.com/access/v1/evaluation", http_request_args.uri)
		assert.are.same("POST", http_request_args.params.method)
		assert.are.same("ENCODED_BODY", http_request_args.params.body)
		assert.are.same("application/json", http_request_args.params.headers["Content-Type"])
		assert.is_true(http_request_args.params.ssl_verify)
		assert.are.same(3000, http_timeout)

		local sent_body = encoded_bodies[1]
		assert.are.same("alice", sent_body.subject.id)
		assert.are.same("/api/thing", sent_body.resource.id)
		assert.are.same("GET", sent_body.action.name)
	end)

	it("access normalizes host trailing slashes and missing endpoint slash", function()
		local conf = base_conf({ host = "https://pdp.example.com//", endpoint = "evaluate" })

		plugin.access(conf, base_ctx())

		assert.are.same("https://pdp.example.com/evaluate", http_request_args.uri)
	end)

	it("access resolves embedded placeholders inside longer strings", function()
		local conf = base_conf()
		conf.body.subject.id = "user-$remote_user-$unknown"

		plugin.access(conf, base_ctx())

		assert.are.same("user-alice-$unknown", encoded_bodies[1].subject.id)
	end)

	it("access returns 500 when the resolved body fails schema validation", function()
		body_schema_check_err = "property subject is required"

		local status = plugin.access(base_conf(), base_ctx())

		assert.are.same(500, status)
		assert.is_true(#error_logs > 0)
		assert.is_nil(http_request_args)
	end)

	-- -------------------------------------------------------------------------
	-- access – headers towards the PDP
	-- -------------------------------------------------------------------------

	it("access forwards configured request headers to AuthZEN", function()
		request_headers["X-Tenant"] = "tenant-1"
		local conf = base_conf({ send_headers_to_authzen = { "X-Tenant", "X-Absent" } })

		plugin.access(conf, base_ctx())

		assert.are.same("tenant-1", http_request_args.params.headers["X-Tenant"])
		assert.is_nil(http_request_args.params.headers["X-Absent"])
	end)

	it("access resolves and sends the configured x_request_id", function()
		local conf = base_conf({ x_request_id = "$request_id" })

		plugin.access(conf, base_ctx())

		assert.are.same("rid-123", http_request_args.params.headers["X-Request-ID"])
	end)

	it("access adds a bearer header when pdp_auth mode is bearer", function()
		local conf = base_conf({
			pdp_auth = { mode = "bearer", bearer_token = "$secret_token" },
		})

		plugin.access(conf, base_ctx())

		assert.are.same("Bearer tok-xyz", http_request_args.params.headers["Authorization"])
	end)

	it("access honors custom bearer header name and prefix", function()
		local conf = base_conf({
			pdp_auth = {
				mode = "bearer",
				bearer_token = "static-token",
				bearer_header = "X-PDP-Auth",
				bearer_prefix = "Token ",
			},
		})

		plugin.access(conf, base_ctx())

		assert.are.same("Token static-token", http_request_args.params.headers["X-PDP-Auth"])
	end)

	it("access returns 500 when the bearer token resolves to nothing", function()
		local conf = base_conf({
			pdp_auth = { mode = "bearer", bearer_token = "$missing_variable" },
		})

		local status = plugin.access(conf, base_ctx())

		assert.are.same(500, status)
		assert.is_nil(http_request_args)
	end)

	-- -------------------------------------------------------------------------
	-- access – mTLS towards the PDP
	-- -------------------------------------------------------------------------

	it("access attaches parsed client cert and key when mtls is enabled", function()
		local conf = base_conf({
			pdp_auth = {
				mode = "none",
				mtls = { enabled = true, client_cert = "CERT_PEM", client_key = "KEY_PEM" },
			},
		})

		local status = plugin.access(conf, base_ctx())

		assert.is_nil(status)
		assert.are.same({ pem = "CERT_PEM" }, http_request_args.params.ssl_client_cert)
		assert.are.same({ pem = "KEY_PEM" }, http_request_args.params.ssl_client_priv_key)
	end)

	it("access returns 500 when the mtls client cert cannot be parsed", function()
		ssl_cert_err = "bad pem"
		local conf = base_conf({
			pdp_auth = {
				mode = "none",
				mtls = { enabled = true, client_cert = "CERT_PEM", client_key = "KEY_PEM" },
			},
		})

		local status = plugin.access(conf, base_ctx())

		assert.are.same(500, status)
		assert.is_nil(http_request_args)
	end)

	-- -------------------------------------------------------------------------
	-- access – decision handling
	-- -------------------------------------------------------------------------

	it("access blocks with 403 when the PDP cannot be reached", function()
		http_error = "connection refused"

		local status = plugin.access(base_conf(), base_ctx())

		assert.are.same(403, status)
		assert.is_true(#error_logs > 0)
	end)

	it("access propagates non-200 status codes from the PDP", function()
		http_response = { status = 401, headers = {}, body = "nope" }

		local status = plugin.access(base_conf(), base_ctx())

		assert.are.same(401, status)
	end)

	it("access returns 503 when the response body cannot be decoded", function()
		http_response = { status = 200, headers = {}, body = "NOT_JSON" }

		local status = plugin.access(base_conf(), base_ctx())

		assert.are.same(503, status)
	end)

	it("access returns 503 when the decision field is missing", function()
		http_response = { status = 200, headers = {}, body = "NO_DECISION" }
		json_decode_map["NO_DECISION"] = { something = "else" }

		local status = plugin.access(base_conf(), base_ctx())

		assert.are.same(503, status)
	end)

	it("access returns 503 when the decision field is not a boolean", function()
		http_response = { status = 200, headers = {}, body = "STRING_DECISION" }
		json_decode_map["STRING_DECISION"] = { decision = "yes" }

		local status = plugin.access(base_conf(), base_ctx())

		assert.are.same(503, status)
	end)

	it("access denies with 403 on a negative decision", function()
		http_response = { status = 200, headers = {}, body = "DENY" }

		local status = plugin.access(base_conf(), base_ctx())

		assert.are.same(403, status)
	end)

	it("access returns the AuthZEN context on a negative decision", function()
		http_response = { status = 200, headers = {}, body = "DENY_CTX" }
		json_decode_map["DENY_CTX"] = { decision = false, context = { reason = "no access" } }

		local status, body = plugin.access(base_conf(), base_ctx())

		assert.are.same(403, status)
		assert.are.same({ reason = "no access" }, body)
	end)

	it("access copies the x-request-id response header to the client response", function()
		http_response = { status = 200, headers = { ["x-request-id"] = "rid-9" }, body = "ALLOW" }

		plugin.access(base_conf(), base_ctx())

		assert.are.same("rid-9", response_headers_set["X-Request-ID"])
	end)

	it("access forwards configured PDP response headers upstream on allow", function()
		http_response = {
			status = 200,
			headers = { ["X-Role"] = "admin", ["X-Other"] = "ignored" },
			body = "ALLOW",
		}
		local conf = base_conf({ send_headers_upstream = { "X-Role" } })

		local status = plugin.access(conf, base_ctx())

		assert.is_nil(status)
		assert.are.same("admin", upstream_headers_set["X-Role"])
		assert.is_nil(upstream_headers_set["X-Other"])
	end)

	it("access does not forward headers upstream on deny", function()
		http_response = { status = 200, headers = { ["X-Role"] = "admin" }, body = "DENY" }
		local conf = base_conf({ send_headers_upstream = { "X-Role" } })

		local status = plugin.access(conf, base_ctx())

		assert.are.same(403, status)
		assert.is_nil(upstream_headers_set["X-Role"])
	end)
end)
