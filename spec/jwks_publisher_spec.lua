describe("jwks-publisher", function()
    local plugin, method

    before_each(function()
        for _, name in ipairs({"apisix.core", "resty.openssl.pkey", "ngx.base64",
                               "apisix.plugins.jwks-publisher"}) do
            package.loaded[name] = nil
        end
        package.preload["apisix.core"] = function()
            return {
                schema = {check = function() return true end},
                log = {error = function() end},
            }
        end
        package.preload["ngx.base64"] = function()
            return {encode_base64url = function(value) return "encoded:" .. value end}
        end
        package.preload["resty.openssl.pkey"] = function()
            return {new = function(key, options)
                assert.equal("pu", options.type)
                if key == "private" then return nil, "not a public key" end
                return {
                    get_key_type = function() return {sn = "rsaEncryption"} end,
                    get_parameters = function()
                        return {
                            n = {to_binary = function() return string.char(128) .. string.rep("n", 255) end},
                            e = {to_binary = function() return "exponent" end},
                            d = "private material must not be published",
                        }
                    end,
                }
            end}
        end
        method = "GET"
        _G.ngx = {req = {get_method = function() return method end}, header = {}}
        plugin = require("apisix.plugins.jwks-publisher")
    end)

    it("publishes only public RSA parameters for each configured key", function()
        local status, body = plugin.access({keys = {
            {kid = "old", public_key = "public"},
            {kid = "new", public_key = "public"},
        }})
        assert.equal(200, status)
        assert.same({
            kty = "RSA", use = "sig", alg = "RS256", kid = "old",
            n = "encoded:" .. string.char(128) .. string.rep("n", 255), e = "encoded:exponent",
        }, body.keys[1])
        assert.equal("new", body.keys[2].kid)
        assert.equal("no-cache", ngx.header["Cache-Control"])
        assert.equal("application/json", ngx.header["Content-Type"])
    end)

    it("rejects duplicate key IDs and private keys", function()
        assert.is_false(plugin.check_schema({keys = {{kid = "x"}, {kid = "x"}}}))
        local status, body = plugin.access({keys = {{kid = "x", public_key = "private"}}})
        assert.equal(500, status)
        assert.is_nil(body.keys)
    end)

    it("only responds to GET", function()
        method = "POST"
        assert.equal(405, plugin.access({keys = {}}))
        assert.equal("GET", ngx.header.Allow)
    end)
end)
