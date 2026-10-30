local core          = require("apisix.core")
local xml2lua 		= require('xml2lua')
local xmlhandler 	= require('xmlhandler.tree')
local ngx 			= require("ngx")
local schema_def = require("apisix.schema_def")
local upstream   = require("apisix.upstream")
local plugin_name = "soap-action-router"


local soap_routes_schema = {
    type = "array",
    items = {
        type = "object",
        additionalProperties = false,
        required = {"soap_action", "upstream_id"},
        properties = {
            upstream_id = schema_def.id_schema,
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
		routes = soap_routes_schema,
        soap_action_source = {
            type = "string",
            enum = {"header", "content_type", "body"},
            description = "Only inspect this source for the SOAP action. Omit to use the fallback order."
        }
	},
    required = {"routes"},
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

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- need to traverse the table since we do not know the xmlns prefixes beforehand
local function find_action_in_body(body)
	core.log.info("Finding SOAPAction in body")
	for key, value in pairs(body) do

		if key ~= "_attr" then
			local local_name = type(key) == "string" and key:match("([^:]+)$")
			local_name = local_name and local_name:lower()
			if local_name == "action" or local_name == "soapaction" then
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

local function find_soap_action(source)
    local headers
    if source ~= "body" then
        headers = ngx.req.get_headers()
    end

    if not source or source == "header" then
        local soap_action = headers["SOAPAction"]
        if soap_action or source == "header" then
            return soap_action
        end
    end

    if not source or source == "content_type" then
        local content_type = headers["Content-Type"]
        if content_type then
            for k in string.gmatch(content_type, "[^;]+") do
                local key, value = k:match("^%s*([^=]+)%s*=%s*\"?([^\";]+)\"?")
                if key and key:lower() == "action" then
                    return value
                end
            end
        end
        if source == "content_type" then
            return false
        end
    end

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
function _M.access(conf, ctx)
    local soap_action = find_soap_action(conf.soap_action_source)
    if soap_action then
        for _, route in ipairs(conf.routes) do
            if route.soap_action and route.soap_action == soap_action then
                if not route.upstream_id then
                    core.log.error("missing upstream for SOAPAction: ", soap_action)
                    return 500, "missing upstream for SOAPAction: " .. soap_action
                end
                local found_upstream = upstream.get_by_id(route.upstream_id)
                if not found_upstream then
                    return 500, "failed to fetch upstream info by "
                                .. "upstream id: " .. route.upstream_id
                end
                ctx.upstream_id = route.upstream_id
                core.log.info("upstream_id: ", route.upstream_id)
                return
            end
        end
        return 500, "No matching route found for SOAPAction: " .. soap_action

    else
        core.log.info("No soap action found")
        return 403, { message = "Forbidden: Invalid or missing SOAPAction." }
    end
end



return _M
