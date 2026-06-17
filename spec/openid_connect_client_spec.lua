describe("openid-connect-client plugin", function()
	local plugin
	local schema_check_args
	local info_logs
	local error_logs
	local httpc_connect_args
	local httpc_request_args
	local httpc_close_called
	local httpc_config
	local add_header_calls
	local cache_store
	local escape_uri_calls

	before_each(function()
		package.loaded["apisix.core"] = nil
		package.loaded["net.url"] = nil
		package.loaded["resty.http"] = nil
		package.loaded["apisix.plugins.openid-connect-client"] = nil

		schema_check_args = nil
		info_logs = {}
		error_logs = {}
		httpc_connect_args = nil
		httpc_request_args = nil
		httpc_close_called = false
		add_header_calls = {}
		cache_store = {}
		escape_uri_calls = {}

		httpc_config = {
			connect_err = nil,
			response_status = 200,
			response_reason = "OK",
			response_body = '{"access_token":"tok-abc","expires_in":600}',
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
					info  = function(...) table.insert(info_logs,  { ... }) end,
					error = function(...) table.insert(error_logs, { ... }) end,
				},
				request = {
					add_header = function(ctx, name, value)
						table.insert(add_header_calls, { ctx = ctx, name = name, value = value })
					end,
				},
				json = {
					decode = function(body)
						local token    = string.match(body, '"access_token"%s*:%s*"([^"]+)"')
						local expires  = tonumber(string.match(body, '"expires_in"%s*:%s*(%d+)'))
						if token then
							return { access_token = token, expires_in = expires }
						end
						return nil, "decode error"
					end,
				},
			}
		end

		package.preload["net.url"] = function()
			return {
				parse = function(raw)
					local scheme, host, port_str, path =
						string.match(raw, "^([%a]+)://([^:/]+):?(%d*)(/?[^?]*)")
					return {
						scheme = scheme or "http",
						host   = host   or "localhost",
						port   = tonumber(port_str) or 80,
						path   = path   or "/",
					}
				end,
			}
		end

		package.preload["resty.http"] = function()
			return {
				new = function()
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
							return {
								status = httpc_config.response_status,
								reason = httpc_config.response_reason,
								read_body = function(self)
									return httpc_config.response_body, nil
								end,
							}, nil
						end,
						close = function(self)
							httpc_close_called = true
						end,
					}
				end,
			}
		end

		_G.ngx = {
			shared = {
				["openid-connect-client-cache"] = {
					get = function(self, key)    return cache_store[key] end,
					set = function(self, key, v) cache_store[key] = v   end,
				},
			},
			escape_uri = function(value)
				table.insert(escape_uri_calls, value)
				return value
			end,
		}

		plugin = require("apisix.plugins.openid-connect-client")
	end)

	-- -------------------------------------------------------------------------
	-- check_schema
	-- -------------------------------------------------------------------------

	it("delegates regular schema checks to plugin schema", function()
		local conf = { grant_type = "client_credentials", token_endpoint = "http://idp/token", client_id = "id", client_secret = "sec" }

		local ok = plugin.check_schema(conf)

		assert.is_true(ok)
		assert.are.equal(plugin.schema, schema_check_args.schema)
		assert.are.same(conf, schema_check_args.conf)
	end)

	it("delegates metadata schema checks to metadata schema", function()
		local ok = plugin.check_schema({}, "metadata")

		assert.is_true(ok)
		assert.are.equal(plugin.metadata_schema, schema_check_args.schema)
	end)

	-- -------------------------------------------------------------------------
	-- cache hit
	-- -------------------------------------------------------------------------

	it("uses cached token and skips HTTP call when cache hit and use_cache is true", function()
		cache_store["my-client"] = "cached-token-xyz"
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp/token",
			client_id = "my-client", client_secret = "sec", use_cache = true,
		}

		plugin.access(conf, {})

		assert.is_nil(httpc_connect_args)
		assert.are.same(1, #add_header_calls)
		assert.are.same("Bearer cached-token-xyz", add_header_calls[1].value)
	end)

	-- -------------------------------------------------------------------------
	-- token fetch
	-- -------------------------------------------------------------------------

	it("fetches a new token when cache is empty", function()
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec", use_cache = true, default_expiration = 300,
		}

		plugin.access(conf, {})

		assert.is_not_nil(httpc_connect_args)
		assert.are.same(1, #add_header_calls)
		assert.are.same("Bearer tok-abc", add_header_calls[1].value)
	end)

	it("fetches a new token even when cache is populated but use_cache is false", function()
		cache_store["my-client"] = "stale-token"
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec", use_cache = false, default_expiration = 300,
		}

		plugin.access(conf, {})

		assert.is_not_nil(httpc_connect_args)
		assert.are.same("Bearer tok-abc", add_header_calls[1].value)
	end)

	-- -------------------------------------------------------------------------
	-- connect parameters
	-- -------------------------------------------------------------------------

	it("connects to IDP with parsed URL parts and ssl_verify flag", function()
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec", ssl_verify = false, default_expiration = 300,
		}

		plugin.access(conf, {})

		assert.are.same({ host = "idp", port = 9081, scheme = "http", ssl_verify = false }, httpc_connect_args)
	end)

	-- -------------------------------------------------------------------------
	-- request body composition
	-- -------------------------------------------------------------------------

	it("sends client_id, client_secret and grant_type as form-encoded body", function()
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "my-secret", default_expiration = 300,
		}

		plugin.access(conf, {})

		assert.are.same("POST", httpc_request_args.method)
		assert.are.same("application/x-www-form-urlencoded", httpc_request_args.headers["Content-Type"])
		assert.is_not_nil(string.find(httpc_request_args.body, "client_id=my%-client"))
		assert.is_not_nil(string.find(httpc_request_args.body, "client_secret=my%-secret"))
		assert.is_not_nil(string.find(httpc_request_args.body, "grant_type=client_credentials"))
	end)

	it("appends scope to request body when configured", function()
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec", scope = "api.read", default_expiration = 300,
		}

		plugin.access(conf, {})

		assert.is_not_nil(string.find(httpc_request_args.body, "scope=api%.read"))
	end)

	it("omits scope from request body when not configured", function()
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec", default_expiration = 300,
		}

		plugin.access(conf, {})

		assert.is_nil(string.find(httpc_request_args.body, "scope="))
	end)

	it("appends resourceServer to request body when configured", function()
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec",
			resource_server = "https://api.example.org", default_expiration = 300,
		}

		plugin.access(conf, {})

		assert.is_not_nil(string.find(httpc_request_args.body, "resourceServer="))
	end)

	it("omits resourceServer from request body when not configured", function()
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec", default_expiration = 300,
		}

		plugin.access(conf, {})

		assert.is_nil(string.find(httpc_request_args.body, "resourceServer="))
	end)

	-- -------------------------------------------------------------------------
	-- cache storage
	-- -------------------------------------------------------------------------

	it("stores the fetched token in cache using the expires_in TTL from the IDP", function()
		httpc_config.response_body = '{"access_token":"fresh-tok","expires_in":120}'
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec", use_cache = true, default_expiration = 300,
		}

		plugin.access(conf, {})

		assert.are.same("fresh-tok", cache_store["my-client"])
	end)

	it("falls back to default_expiration when IDP response omits expires_in", function()
		httpc_config.response_body = '{"access_token":"no-expiry-tok"}'
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec", use_cache = true, default_expiration = 999,
		}

		plugin.access(conf, {})

		assert.are.same("no-expiry-tok", cache_store["my-client"])
		assert.are.same(0, #error_logs)
	end)

	-- -------------------------------------------------------------------------
	-- error paths
	-- -------------------------------------------------------------------------

	it("returns 500 and closes connection when connect fails", function()
		httpc_config.connect_err = "connection refused"
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec", default_expiration = 300,
		}

		local status, body = plugin.access(conf, {})

		assert.are.same(500, status)
		assert.are.same({ message = "connection refused" }, body)
		assert.is_true(httpc_close_called)
		assert.is_true(#error_logs > 0)
	end)

	it("returns IDP status and body when IDP responds with non-200", function()
		httpc_config.response_status = 401
		httpc_config.response_body   = '{"error":"invalid_client"}'
		local conf = {
			grant_type = "client_credentials", token_endpoint = "http://idp:9081/token",
			client_id = "my-client", client_secret = "sec", default_expiration = 300,
		}

		local status, body = plugin.access(conf, {})

		assert.are.same(401, status)
		assert.are.same({ message = '{"error":"invalid_client"}' }, body)
		assert.is_true(httpc_close_called)
	end)
end)
