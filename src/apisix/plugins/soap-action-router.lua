local core          = require("apisix.core")
local xml2lua 		= require('xml2lua')
local xmlhandler 	= require('xmlhandler.tree')
local ngx 			= require("ngx")
local schema_def = require("apisix.schema_def")
local upstream   = require("apisix.upstream")
local plugin_name = "soap-action-router"
local ipmatcher  = require("resty.ipmatcher")


local soap_routes_schema = {
    type = "array",
    items = {
        type = "object",
        properties = {
            upstream_id = schema_def.id_schema,
            upstream = schema_def.upstream,
            soap_action = {
                type = "string",
                description = "The SOAP action to match against the SOAPAction header or Content-Type header or body."
            }
        }
    }
}
local schema = {
	type = "object",
	properties = {
		routes = soap_routes_schema
	},
	description = "Matches the SOAPAction header, Content-Type action, or body action and routes accordingly."
}

local metadata_schema = {}

local _M = {
	version = 0.1,
	priority = 967,
	name = plugin_name,
	schema = schema,
	metadata_schema = metadata_schema
}

-- need to traverse the table since we do not know the xmlns prefixes beforehand
local function find_action_in_body(body)
	core.log.info("Finding SOAPAction in body")
	for key, value in pairs(body) do

		if key ~= "_attr" then
			if type(key) == "string" and key:lower():match("action") then
				if type(value) == "string" then
					return value
				elseif type(value) == "table" and type(value[1]) == "string" then
					-- xml2lua retains text in a table when the element has attributes.
					return value[1]
				end
			end
			if type(value) == "table" then
				local found = find_action_in_body(value)
				if found then
					return found
				end
			end
		end
	end
end

local function find_soap_action()
    local headers = ngx.req.get_headers()
    local soap_action = headers["SOAPAction"]

    if soap_action then
        return soap_action
    end

    -- If no match or SOAPAction missing, try to get from Content-Type (SOAP 1.2)
    local content_type = headers["Content-Type"]
    if content_type then
        for k in string.gmatch(content_type, "[^;]+") do
            local key, value = k:match("^%s*([^=]+)%s*=%s*\"?([^\";]+)\"?")
            if key and key:lower() == "action" then
                return value
            end
        end
    end

    -- Final fallback: parse body for action
    core.log.info("Trying to find SOAPAction in body")
    local body, err = core.request.get_body()
    if not body then
        core.log.warn("Could not get request body: ", err)
        return false
    end

    local handler = xmlhandler:new()
    local parser = xml2lua.parser(handler)

    local ok, parse_err = pcall(function() parser:parse(body) end)
    if not ok then
        core.log.error("Failed to parse XML body: ", parse_err)
        return false
    end

    local found_action = find_action_in_body(handler.root)
    if found_action then
        -- Might be useful as an optional setting?
        -- core.request.add_header("SOAPAction", found_action)
        core.log.info("SOAPAction extracted from body and added: ", found_action)
        return found_action
    end
    return false
end
local function parse_domain_for_node(node)
    local host = node.domain or node.host
    if not ipmatcher.parse_ipv4(host)
       and not ipmatcher.parse_ipv6(host)
    then
        node.domain = host

        local ip, err = core.resolver.parse_domain(host)
        if ip then
            node.host = ip
        end

        if err then
            core.log.error("dns resolver domain: ", host, " error: ", err)
        end
    end
end
local function register_upstream(upstream_info, ctx)
    local nodes = upstream_info.nodes
    local new_nodes = {}
    if core.table.isarray(nodes) then
        for _, node in ipairs(nodes) do
            parse_domain_for_node(node)
            table.insert(new_nodes, node)
        end
    else
        for addr, weight in pairs(nodes) do
            local node = {}
            local port, host
            host, port = core.utils.parse_addr(addr)
            node.host = host
            parse_domain_for_node(node)
            node.port = port
            node.weight = weight
            table.insert(new_nodes, node)
        end
    end

    local up_conf = {
        name = upstream_info.name,
        type = upstream_info.type,
        hash_on = upstream_info.hash_on,
        pass_host = upstream_info.pass_host,
        upstream_host = upstream_info.upstream_host,
        key = upstream_info.key,
        nodes = new_nodes,
        timeout = upstream_info.timeout,
        scheme = upstream_info.scheme,
        tls = upstream_info.tls,
        keepalive_pool = upstream_info.keepalive_pool,
    }

    local ok, err = upstream.check_schema(up_conf)
    if not ok then
        core.log.error("failed to validate generated upstream: ", err)
        return 500, err
    end

    local matched_route = ctx.matched_route
    up_conf.parent = matched_route
    local upstream_key = up_conf.type .. "#route_" ..
                         matched_route.value.id .. "_" .. upstream_info.vid
    if upstream_info.node_tid then
        upstream_key = upstream_key .. "_" .. upstream_info.node_tid
    end
    core.log.info("upstream_key: ", upstream_key)
    upstream.set(ctx, upstream_key, ctx.conf_version, up_conf)
    -- the schemes handle_upstream() dispatches on ctx.upstream_scheme for
    local scheme = upstream_info.scheme
    if scheme == "https" or scheme == "ws" or scheme == "wss" then
        upstream.set_scheme(ctx, up_conf)
    end
    return
end

function _M.access(conf, ctx)
    local soap_action = find_soap_action()
    if soap_action then
        for _, route in ipairs(conf.routes) do
            if route.soap_action and route.soap_action == soap_action then
                local found_upstream = upstream.get_by_id(route.upstream_id)
                if not found_upstream then
                    return 500, "failed to fetch upstream info by "
                                .. "upstream id: " .. route.upstream_id
                end
                if found_upstream and type(route.upstream) == "table" then
                    core.log.info("upstream: ", core.json.encode(found_upstream))
                    return register_upstream(route.upstream, ctx)
                elseif found_upstream and found_upstream ~= "plugin#upstream#is#empty" then
                    ctx.upstream_id = route.upstream_id
                    core.log.info("upstream_id: ", route.upstream_id)
                    return
                end
            end
        end
        return 500, "No matching route found for SOAPAction: " .. soap_action

    else
        core.log.info("No soap action found")
        return 403, { message = "Forbidden: Invalid or missing SOAPAction." }
    end
end



return _M
