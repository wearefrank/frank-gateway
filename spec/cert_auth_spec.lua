describe("cert-auth plugin", function()
	local plugin
	local schema_check_args
	local debug_logs
	local consumer_nodes
	local attached_consumer_call
	local x509_new_calls
	local x509_config

	before_each(function()
		package.loaded["apisix.core"] = nil
		package.loaded["apisix.consumer"] = nil
		package.loaded["resty.openssl.x509"] = nil
		package.loaded["apisix.plugins.cert-auth"] = nil

		schema_check_args = nil
		debug_logs = {}
		consumer_nodes = {}
		attached_consumer_call = nil
		x509_new_calls = {}
		x509_config = {
			new_err = nil,
			san = nil,
			san_err = nil,
			ext = nil,
		}

		package.preload["apisix.core"] = function()
			return {
				schema = {
					TYPE_CONSUMER = "consumer",
					check = function(schema, conf)
						schema_check_args = { schema = schema, conf = conf }
						return true
					end,
				},
				log = {
					debug = function(...)
						table.insert(debug_logs, { ... })
					end,
				},
			}
		end

		package.preload["apisix.consumer"] = function()
			return {
				plugin = function(name)
					if name ~= "cert-auth" then
						return nil
					end
					return { nodes = consumer_nodes }
				end,
				attach_consumer = function(ctx, consumer, conf)
					attached_consumer_call = {
						ctx = ctx,
						consumer = consumer,
						conf = conf,
					}
				end,
			}
		end

		package.preload["resty.openssl.x509"] = function()
			return {
				new = function(pem, format)
					table.insert(x509_new_calls, { pem = pem, format = format })
					if x509_config.new_err then
						return nil, x509_config.new_err
					end
					return {
						get_subject_alt_name = function()
							return x509_config.san, x509_config.san_err
						end,
						get_extension = function(name)
							if name == "subjectAltName" then
								return x509_config.ext
							end
							return nil
						end,
					}
				end,
			}
		end

		_G.ngx = {
			var = {
				ssl_client_s_dn = nil,
				ssl_client_raw_cert = nil,
				ssl_client_cert = nil,
			},
		}

		plugin = require("apisix.plugins.cert-auth")
	end)

	it("delegates regular schema checks to plugin schema", function()
		local conf = { any = "value" }

		local ok = plugin.check_schema(conf)

		assert.is_true(ok)
		assert.is_not_nil(schema_check_args)
		assert.are.equal(plugin.schema, schema_check_args.schema)
		assert.are.same(conf, schema_check_args.conf)
	end)

	it("delegates consumer schema checks to consumer schema", function()
		local conf = { identifier = "example.org" }

		local ok = plugin.check_schema(conf, "consumer")

		assert.is_true(ok)
		assert.is_not_nil(schema_check_args)
		assert.are.equal(plugin.consumer_schema, schema_check_args.schema)
		assert.are.same(conf, schema_check_args.conf)
	end)

	it("returns 401 when no client certificate is present", function()
		local ctx = {}

		local status, body = plugin.access({}, ctx)

		assert.are.same(401, status)
		assert.are.same({ message = "Client certificate required" }, body)
		assert.is_nil(attached_consumer_call)
	end)

	it("matches consumer by SAN identifier variants", function()
		x509_config.san = {
			{ type = "dns", value = "api.example.org" },
		}
		consumer_nodes = {
			{
				username = "identifier-user",
				auth_conf = { identifier = "DNS:api.example.org" },
			},
		}
		ngx.var.ssl_client_raw_cert = "-----BEGIN CERTIFICATE-----\\nabc\\n-----END CERTIFICATE-----"
		ngx.var.ssl_client_s_dn = "CN=ignored, O=example"
		local ctx = {}

		local status, body = plugin.access({}, ctx)

		assert.is_nil(status)
		assert.is_nil(body)
		assert.are.same(1, #x509_new_calls)
		assert.are.same("PEM", x509_new_calls[1].format)
		assert.is_true(string.sub(x509_new_calls[1].pem, -1) == "\n")
		assert.are.same({ "api.example.org" }, ctx.cert_auth_dns_sans)
		assert.are.same("identifier-user", ctx.consumer_name)
		assert.is_not_nil(attached_consumer_call)
		assert.are.same(consumer_nodes[1], attached_consumer_call.consumer)
	end)

	it("falls back to CN when identifier lookup does not match", function()
		x509_config.san = {}
		consumer_nodes = {
			{
				consumer_name = "cn-user",
				auth_conf = { cn = "legacy-cn" },
			},
		}
		ngx.var.ssl_client_raw_cert = "-----BEGIN CERTIFICATE-----\\nabc\\n-----END CERTIFICATE-----"
		ngx.var.ssl_client_s_dn = "CN=legacy-cn, O=example"
		local ctx = {}

		local status, body = plugin.access({}, ctx)

		assert.is_nil(status)
		assert.is_nil(body)
		assert.are.same("cn-user", ctx.consumer_name)
		assert.is_not_nil(attached_consumer_call)
		assert.are.same(consumer_nodes[1], attached_consumer_call.consumer)
	end)

	it("returns 403 when neither identifier nor CN can be extracted", function()
		x509_config.san = {}
		ngx.var.ssl_client_raw_cert = "-----BEGIN CERTIFICATE-----\\nabc\\n-----END CERTIFICATE-----"
		ngx.var.ssl_client_s_dn = nil
		local ctx = {}

		local status, body = plugin.access({}, ctx)

		assert.are.same(403, status)
		assert.are.same({ message = "Failed to extract identifier or CN" }, body)
		assert.is_nil(attached_consumer_call)
	end)

	it("returns 403 when no consumer matches identifier or CN", function()
		x509_config.san = {
			{ type = "dns", value = "api.example.org" },
		}
		consumer_nodes = {
			{
				username = "other-user",
				auth_conf = { identifier = "different.example.org" },
			},
		}
		ngx.var.ssl_client_raw_cert = "-----BEGIN CERTIFICATE-----\\nabc\\n-----END CERTIFICATE-----"
		ngx.var.ssl_client_s_dn = "CN=non-matching, O=example"
		local ctx = {}

		local status, body = plugin.access({}, ctx)

		assert.are.same(403, status)
		assert.are.same({ message = "No matching consumer for identifier or CN" }, body)
		assert.is_nil(attached_consumer_call)
	end)
end)
