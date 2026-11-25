describe("soap-action-router plugin", function()
    local plugin
    local headers
    local body_tree
    local lookups
    local upstreams
    local conf
    local body_reads
    local header_reads
    local modules = {
        "apisix.core",
        "apisix.schema_def",
        "apisix.upstream",
        "xml2lua",
        "xmlhandler.tree",
        "ngx",
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
        body_reads = 0
        header_reads = 0
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
                request = { get_body = function()
                    body_reads = body_reads + 1
                    return "<Envelope/>"
                end }
            }
        end
        package.preload["apisix.schema_def"] = function() return {} end
        package.preload["apisix.upstream"] = function()
            return {
                get_by_id = function(id)
                    table.insert(lookups, id)
                    return upstreams[id]
                end
            }
        end
        package.preload["ngx"] = function()
            return { req = { get_headers = function()
                header_reads = header_reads + 1
                return headers
            end } }
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

    it("requires SOAP actions and upstream ids without allowing inline upstreams", function()
        local route_schema = plugin.schema.properties.routes.items

        assert.are.same({ "soap_action", "upstream_id" }, route_schema.required)
        assert.is_false(route_schema.additionalProperties)
        assert.is_nil(route_schema.properties.upstream)
    end)

    it("defines an optional restricted SOAP action source", function()
        local source_schema = plugin.schema.properties.soap_action_source

        assert.are.equal("string", source_schema.type)
        assert.are.same({ "header", "content_type", "body" }, source_schema.enum)
        assert.are.same({ "routes" }, plugin.schema.required)
    end)

    for _, source in ipairs({ "header", "content_type", "body" }) do
        it("only uses the selected " .. source .. " source", function()
            conf.soap_action_source = source
            headers = {
                SOAPAction = source == "header" and "testOne" or "testTwo",
                ["Content-Type"] = 'application/soap+xml; action="' ..
                    (source == "content_type" and "testOne" or "testTwo") .. '"'
            }
            body_tree = { Envelope = { Body = {
                Action = source == "body" and "testOne" or "testTwo"
            } } }
            local ctx = {}

            assert.is_nil(plugin.access(conf, ctx))
            assert.are.equal("testOne", ctx.upstream_id)
            assert.are.equal(source == "body" and 1 or 0, body_reads)
            assert.are.equal(source == "body" and 0 or 1, header_reads)
        end)

        it("does not fall back when the selected " .. source .. " source is missing", function()
            conf.soap_action_source = source
            headers = {
                SOAPAction = "testOne",
                ["Content-Type"] = 'application/soap+xml; action="testOne"'
            }
            body_tree = { Envelope = { Body = { Action = "testOne" } } }
            if source == "header" then
                headers.SOAPAction = nil
            elseif source == "content_type" then
                headers["Content-Type"] = "application/soap+xml; charset=utf-8"
            else
                body_tree = {}
            end

            local status = plugin.access(conf, {})

            assert.are.equal(403, status)
            assert.are.same({}, lookups)
            assert.are.equal(source == "body" and 1 or 0, body_reads)
            assert.are.equal(source == "body" and 0 or 1, header_reads)
        end)

        it("does not fall back when the selected " .. source .. " action is unmatched", function()
            conf.soap_action_source = source
            headers = {
                SOAPAction = source == "header" and "unknown" or "testOne",
                ["Content-Type"] = 'application/soap+xml; action="' ..
                    (source == "content_type" and "unknown" or "testOne") .. '"'
            }
            body_tree = { Envelope = { Body = {
                Action = source == "body" and "unknown" or "testOne"
            } } }

            local status, err = plugin.access(conf, {})

            assert.are.equal(500, status)
            assert.are.equal("No matching route found for SOAPAction: unknown", err)
            assert.are.same({}, lookups)
        end)
    end

    it("prefers SOAPAction when all sources are present without a selected source", function()
        headers = {
            SOAPAction = "testOne",
            ["Content-Type"] = 'application/soap+xml; action="testTwo"'
        }
        body_tree = { Envelope = { Body = { Action = "testTwo" } } }
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testOne", ctx.upstream_id)
        assert.are.same({ "testOne" }, lookups)
        assert.are.equal(0, body_reads)
    end)

    it("prefers Content-Type over XML without a selected source or SOAPAction header", function()
        headers = { ["Content-Type"] = 'application/soap+xml; action="testOne"' }
        body_tree = { Envelope = { Body = { Action = "testTwo" } } }
        local ctx = {}

        assert.is_nil(plugin.access(conf, ctx))
        assert.are.equal("testOne", ctx.upstream_id)
        assert.are.same({ "testOne" }, lookups)
        assert.are.equal(0, body_reads)
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
