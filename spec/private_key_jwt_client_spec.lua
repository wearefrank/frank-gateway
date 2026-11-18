describe("private-key-jwt-client", function()
    local plugin, conf, request, headers, store, logs, signed, payload, response, counter

    before_each(function()
        for _, name in ipairs({
            "apisix.core", "resty.http", "resty.openssl.pkey", "resty.openssl.rand",
            "resty.sha256", "ngx.base64", "apisix.plugins.private-key-jwt-client",
        }) do
            package.loaded[name] = nil
        end
        request, headers, store, logs, signed, payload = nil, {}, {}, {}, nil, nil
        counter = 0
        response = {status = 200, body = "valid"}
        package.preload["apisix.core"] = function()
            return {
                schema = {check = function() return true end},
                log = {error = function(...) logs[#logs + 1] = {...} end},
                request = {set_header = function(_, name, value) headers[name] = value end},
                json = {
                    encode = function(value)
                        if value.iss then
                            payload = value
                            return "payload"
                        elseif value.alg then
                            return "header:" .. value.kid
                        end
                        return table.concat(value, "|")
                    end,
                    decode = function(body)
                        if body == "valid" then
                            return {access_token = "access-token", token_type = "Bearer", expires_in = 120}
                        end
                        if body == "bad-token" then
                            return {access_token = "bad\r\ntoken", token_type = "Bearer"}
                        end
                        return nil
                    end,
                },
            }
        end
        package.preload["resty.http"] = function()
            return {new = function()
                return {
                    set_timeout = function(_, timeout) assert.equal(5000, timeout) end,
                    request_uri = function(_, endpoint, options)
                        request = {endpoint = endpoint, options = options}
                        return response
                    end,
                }
            end}
        end
        package.preload["resty.openssl.pkey"] = function()
            return {
                PADDINGS = {RSA_PKCS1_PADDING = 1},
                new = function(key, options)
                    if key == "invalid" then return nil, "invalid key" end
                    assert.equal("pr", options.type)
                    return {
                        get_key_type = function() return {sn = "rsaEncryption"} end,
                        get_parameters = function()
                            return {n = {to_binary = function() return string.char(128) .. string.rep("a", 255) end}}
                        end,
                        sign = function(_, input, algorithm, padding)
                            signed = {input = input, algorithm = algorithm, padding = padding}
                            return "signature"
                        end,
                    }
                end,
            }
        end
        package.preload["resty.openssl.rand"] = function()
            return {bytes = function()
                counter = counter + 1
                return "random" .. counter
            end}
        end
        package.preload["resty.sha256"] = function()
            return {new = function()
                local data
                return {
                    update = function(_, value) data = value; return true end,
                    final = function() return data end,
                }
            end}
        end
        package.preload["ngx.base64"] = function()
            return {encode_base64url = function(value) return "encoded(" .. value .. ")" end}
        end
        _G.ngx = {
            time = function() return 1000 end,
            encode_args = function(args) return args end,
            shared = {["private-key-jwt-client-cache"] = {
                get = function(_, key) return store[key] and store[key].token end,
                set = function(_, key, token, ttl)
                    store[key] = {token = token, ttl = ttl}
                    return true
                end,
            }},
        }
        conf = {
            token_endpoint = "https://idp.example/token?tenant=x",
            client_id = "client",
            private_key = "private",
            kid = "key-1",
            scope = "api.read",
        }
        plugin = require("apisix.plugins.private-key-jwt-client")
    end)

    it("signs a fresh assertion and sends the OAuth form over verified TLS", function()
        plugin.access(conf, {})
        assert.same({iss = "client", sub = "client", aud = conf.token_endpoint, iat = 1000,
            exp = 1060, jti = "encoded(random1)"}, payload)
        assert.same({input = "encoded(header:key-1).encoded(payload)", algorithm = "sha256", padding = 1}, signed)
        assert.equal(conf.token_endpoint, request.endpoint)
        assert.equal("POST", request.options.method)
        assert.is_true(request.options.ssl_verify)
        assert.equal("application/x-www-form-urlencoded", request.options.headers["Content-Type"])
        assert.same({
            grant_type = "client_credentials",
            client_id = "client",
            client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            client_assertion = "encoded(header:key-1).encoded(payload).encoded(signature)",
            scope = "api.read",
        }, request.options.body)
        assert.equal("Bearer access-token", headers.Authorization)
        for _, entry in pairs(store) do assert.equal(90, entry.ttl) end
    end)

    it("reuses a token only for the same configuration", function()
        plugin.access(conf, {})
        request = nil
        plugin.access(conf, {})
        assert.is_nil(request)
        conf.scope = "other"
        plugin.access(conf, {})
        assert.is_not_nil(request)
        assert.equal("encoded(random2)", payload.jti)
    end)

    it("uses the configured audience and never reads the cache when disabled", function()
        conf.use_cache = false
        conf.audience = "https://issuer.example"
        plugin.access(conf, {})
        plugin.access(conf, {})
        assert.equal("https://issuer.example", payload.aud)
        assert.equal("encoded(random2)", payload.jti)
        assert.is_nil(next(store))
    end)

    it("fails closed on key errors, endpoint failures and malformed responses", function()
        conf.private_key = "invalid"
        assert.equal(502, plugin.access(conf, {}))
        assert.is_nil(request)
        conf.private_key = "private"
        response = {status = 401, body = "secret error"}
        assert.equal(502, plugin.access(conf, {}))
        response = {status = 200, body = "bad-token"}
        assert.equal(502, plugin.access(conf, {}))
        assert.is_nil(headers.Authorization)
        assert.is_nil(next(store))
    end)
end)
