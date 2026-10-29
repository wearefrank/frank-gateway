describe("soap-action-router plugin", function()
    local plugin
    local headers
    local body_tree
    local lookups
    local upstreams
    local conf
    local registered
    local schema_error
    local scheme_conf
    local modules = {
        "apisix.core",
        "apisix.schema_def",
        "apisix.upstream",
        "xml2lua",
        "xmlhandler.tree",
        "ngx",
        "resty.ipmatcher",
        "apisix.plugins.soap-action-router"
    }
    local saved_loaded
    local saved_preload

    before_each(function()
        saved_loaded = {}
        saved_preload = {}
        for _, name in ipairs(modules) do
            saved_loaded[name] = package.loaded[name]
            saved_preload[name] = package.preload[name]
            package.loaded[name] = nil
        end

        headers = { SOAPAction = "testOne" }
        body_tree = {}
        lookups = {}
        registered = {}
        schema_error = nil
        scheme_conf = nil
        upstreams = { testOne = {}, testTwo = {} }
        conf = {
            routes = {
                { soap_action = "testTwo", upstream_id = "testTwo" },
                { soap_action = "testOne", upstream_id = "testOne" }
            }
        }

        package.preload["apisix.core"] = function()
            return {
                log = {
                    info = function() end,
                    warn = function() end,
                    error = function() end
                },
                request = { get_body = function() return "<Envelope/>" end },
                table = {
                    isarray = function(value) return value[1] ~= nil end,
                    clone = function(value)
                        local copy = {}
                        for key, item in pairs(value) do
                            copy[key] = item
                        end
                        return copy
                    end
                },
                utils = {
                    parse_addr = function(addr)
                        local host, port = addr:match("^([^:]+):(%d+)$")
                        return host, tonumber(port)
                    end
                },
                resolver = {
                    parse_domain = function() return "127.0.0.1" end
                }
            }
        end
        package.preload["apisix.schema_def"] = function() return {} end
        package.preload["apisix.upstream"] = function()
            return {
                get_by_id = function(id)
                    table.insert(lookups, id)
                    return upstreams[id]
                end,
                check_schema = function()
                    return schema_error == nil, schema_error
                end,
                set = function(ctx, key, version, upstream_conf)
                    table.insert(registered, {
                        ctx = ctx, key = key, version = version, conf = upstream_conf
                    })
                end,
                set_scheme = function(_, upstream_conf)
                    scheme_conf = upstream_conf
                end
            }
        end
        package.preload["ngx"] = function()
            return { req = { get_headers = function() return headers end } }
        end
        package.preload["resty.ipmatcher"] = function()
            return {
                parse_ipv4 = function(host) return host == "127.0.0.1" end,
                parse_ipv6 = function() return false end
            }
        end
        package.preload["xmlhandler.tree"] = function()
            return { new = function() return { root = body_tree } end }
        end
        package.preload["xml2lua"] = function()
            return { parser = function() return { parse = function() end } end }
        end

        plugin = require("apisix.plugins.soap-action-router")
    end)

    after_each(function()
        for _, name in ipairs(modules) do
            package.loaded[name] = saved_loaded[name]
            package.preload[name] = saved_preload[name]
        end
    end)

    it("defines soap_action without an unused route weight", function()
        local properties = plugin.schema.properties.routes.items.properties

        assert.are.equal("string", properties.soap_action.type)
        assert.is_nil(properties.soapAction)
        assert.is_nil(properties.weight)
    end)

    it("matches a later route without looking up non-matching upstreams", function()
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testOne", ctx.upstream_id)
        assert.are.same({ "testOne" }, lookups)
    end)

    it("still matches the first route", function()
        headers.SOAPAction = "testTwo"
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testTwo", ctx.upstream_id)
        assert.are.same({ "testTwo" }, lookups)
    end)

    it("skips entries without a soap_action", function()
        table.insert(conf.routes, 1, { upstream_id = "unused" })
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testOne", ctx.upstream_id)
        assert.are.same({ "testOne" }, lookups)
    end)

    it("matches a later route using the Content-Type action", function()
        headers = { ["Content-Type"] = 'application/soap+xml; action="testOne"' }
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testOne", ctx.upstream_id)
    end)

    it("matches a later route using an action extracted from the SOAP tree", function()
        headers = {}
        body_tree = {
            ["soapenv:Envelope"] = {
                ["soapenv:Header"] = { ["soapenv:Action"] = "testOne" },
                ["soapenv:Body"] = { ["urn:MyAction"] = { Action = "testOne" } }
            }
        }
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testOne", ctx.upstream_id)
        assert.are.same({ "testOne" }, lookups)
    end)

    it("extracts action text from an element with a namespace declaration", function()
        headers = {}
        body_tree = {
            Envelope = {
                _attr = { xmlns = "http://schemas.xmlsoap.org/soap/envelope/" },
                Body = {
                    Action = { "testOne", _attr = { xmlns = "urn:example" } }
                }
            }
        }
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testOne", ctx.upstream_id)
        assert.are.same({ "testOne" }, lookups)
    end)

    it("extracts text from a prefixed action with attributes", function()
        headers = {}
        body_tree = {
            ["s:Envelope"] = {
                ["s:Header"] = {
                    ["wsa:Action"] = {
                        "testTwo",
                        _attr = { ["s:mustUnderstand"] = "1" }
                    }
                }
            }
        }
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testTwo", ctx.upstream_id)
    end)

    it("does not interpret XML attributes as action elements", function()
        headers = {}
        body_tree = { Envelope = { _attr = { Action = "testOne" }, Body = {} } }

        local status, err = plugin.access(conf, {})

        assert.are.equal(403, status)
        assert.are.same({ message = "Forbidden: Invalid or missing SOAPAction." }, err)
        assert.are.same({}, lookups)
    end)

    it("rejects an empty action element with namespace attributes", function()
        headers = {}
        body_tree = { Envelope = { Body = { Action = { _attr = { xmlns = "urn:example" } } } } }

        local status, err = plugin.access(conf, {})

        assert.are.equal(403, status)
        assert.are.same({ message = "Forbidden: Invalid or missing SOAPAction." }, err)
        assert.are.same({}, lookups)
    end)

    for _, name in ipairs({ "Transaction", "urn:transaction", "ActionResult", "MyAction", "SOAPActionSuffix" }) do
        it("does not extract an action from " .. name, function()
            headers = {}
            body_tree = { Envelope = { Body = { [name] = "testOne" } } }

            local status, err = plugin.access(conf, {})

            assert.are.equal(403, status)
            assert.are.same({ message = "Forbidden: Invalid or missing SOAPAction." }, err)
            assert.are.same({}, lookups)
        end)
    end

    it("finds the actual action alongside a transaction field", function()
        headers = {}
        body_tree = {
            Envelope = { Body = { Transaction = "wrong", Action = "testOne" } }
        }
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testOne", ctx.upstream_id)
    end)

    it("extracts a complete SOAPAction element name with a namespace prefix", function()
        headers = {}
        body_tree = { Envelope = { Body = { ["urn:SOAPAction"] = "testTwo" } } }
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testTwo", ctx.upstream_id)
    end)

    it("registers an inline upstream without looking up an upstream id", function()
        conf.routes[2] = {
            soap_action = "testOne",
            upstream = {
                type = "roundrobin", scheme = "http", pass_host = "node",
                nodes = { ["httpbun:80"] = 1 }
            }
        }
        local ctx = { matched_route = { value = { id = "soap" } }, conf_version = 7 }

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.same({}, lookups)
        assert.are.equal(1, #registered)
        assert.are.equal("roundrobin#route_soap_soap_action_2", registered[1].key)
        assert.are.equal(7, registered[1].version)
        assert.are.equal(ctx, registered[1].ctx)
        assert.are.equal(ctx.matched_route, registered[1].conf.parent)
        assert.are.equal("http", registered[1].conf.scheme)
        assert.are.equal("node", registered[1].conf.pass_host)
        assert.are.same({
            { host = "127.0.0.1", domain = "httpbun", port = 80, weight = 1 }
        }, registered[1].conf.nodes)
        assert.is_nil(scheme_conf)
    end)

    it("registers HTTPS inline array nodes without mutating configuration", function()
        local node = { host = "httpbun", port = 443, weight = 1 }
        conf.routes[2] = {
            soap_action = "testOne",
            upstream = { type = "roundrobin", scheme = "https", nodes = { node } }
        }
        local ctx = { matched_route = { value = { id = "soap" } }, conf_version = 7 }

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.same({}, lookups)
        assert.are.equal(1, #registered)
        assert.are.equal(registered[1].conf, scheme_conf)
        assert.are.equal("127.0.0.1", registered[1].conf.nodes[1].host)
        assert.are.same({ host = "httpbun", port = 443, weight = 1 }, node)
    end)

    it("uses distinct registration keys for different inline routes", function()
        for _, route in ipairs(conf.routes) do
            route.upstream_id = nil
            route.upstream = { type = "roundrobin", nodes = { ["127.0.0.1:80"] = 1 } }
        end
        local ctx = { matched_route = { value = { id = "soap" } }, conf_version = 7 }

        assert.is_nil(plugin.access(conf, ctx))
        headers.SOAPAction = "testTwo"
        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal(2, #registered)
        assert.are_not.equal(registered[1].key, registered[2].key)
    end)

    it("surfaces inline upstream validation failures without registering it", function()
        conf.routes[2] = {
            soap_action = "testOne",
            upstream = { type = "invalid", nodes = { ["127.0.0.1:80"] = 1 } }
        }
        schema_error = "invalid upstream type"

        local status, err = plugin.access(conf, {})

        assert.are.equal(500, status)
        assert.are.equal(schema_error, err)
        assert.are.same({}, lookups)
        assert.are.same({}, registered)
    end)

    it("reports a missing upstream instead of looking up a nil id", function()
        conf.routes[2] = { soap_action = "testOne" }

        local status, err = plugin.access(conf, {})

        assert.are.equal(500, status)
        assert.are.equal("missing upstream for SOAPAction: testOne", err)
        assert.are.same({}, lookups)
    end)

    it("returns the existing error when no route matches", function()
        headers.SOAPAction = "unknown"
        local ctx = {}

        local status, err = plugin.access(conf, ctx)

        assert.are.equal(500, status)
        assert.are.equal("No matching route found for SOAPAction: unknown", err)
        assert.is_nil(ctx.upstream_id)
        assert.are.same({}, lookups)
    end)

    it("preserves the error for a missing matched upstream", function()
        upstreams.testOne = nil
        local ctx = {}

        local status, err = plugin.access(conf, ctx)

        assert.are.equal(500, status)
        assert.are.equal("failed to fetch upstream info by upstream id: testOne", err)
        assert.is_nil(ctx.upstream_id)
        assert.are.same({ "testOne" }, lookups)
    end)

    it("preserves the forbidden response when no action is found", function()
        headers = {}

        local status, err = plugin.access(conf, {})

        assert.are.equal(403, status)
        assert.are.same({ message = "Forbidden: Invalid or missing SOAPAction." }, err)
        assert.are.same({}, lookups)
    end)
end)
