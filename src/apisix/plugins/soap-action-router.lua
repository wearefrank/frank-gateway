local core          = require("apisix.core")
local xml2lua 		= require('xml2lua')
local xmlhandler 	= require('xmlhandler.tree')
local ngx 			= require("ngx")

local plugin_name = "soap-action-router"

local schema = {
}

local metadata_schema = {}

local _M = {
	version = 0.1,
	priority = 1,
	name = plugin_name,
	schema = schema,
	metadata_schema = metadata_schema
}

-- need to traverse the table since we do not know the xmlns prefixes beforehand
local function find_action_in_body(element, soap_action_match, target_tbl)
	core.log.info("Finding SOAPAction in body")
	for k,v in pairs(element) do
		if type(v) ~= "table" then
			if type(k) == "string" and k:match('Action') then
                if v == soap_action_match then
					target_tbl["SOAPAction"] = v
				end
			end
		end
		if type(v) == "table" then
			find_action_in_body(v, soap_action_match, target_tbl)
		end
	end
end

function _M.access(conf, ctx)
    local matched = _M:match_soap_action(conf.match_action)
    if matched then
        core.log.info("Matched SOAPAction. Header was added.")
    else
        core.log.info("No match for SOAPAction.")
        return 403, { message = "Forbidden: Invalid or missing SOAPAction." }
    end
end

function _M:match_soap_action(target_action)
    local headers = ngx.req.get_headers()
    local soap_action = headers["SOAPAction"]

    if soap_action then
        soap_action = soap_action:gsub("^%s*[\"']*(.-)[\"']*%s*$", "%1")  -- remove quotes and whitespace
        if soap_action == target_action then
            core.log.info("SOAPAction matches target action: ", target_action)
            return true
        end
        return false
    end

    -- If no match or SOAPAction missing, try to get from Content-Type (SOAP 1.2)
    local content_type = headers["Content-Type"]
    if content_type then
        for k in string.gmatch(content_type, "[^;]+") do
            local key, value = k:match("^%s*([^=]+)%s*=%s*\"?([^\";]+)\"?")
            if key and key:lower() == "action" then
                soap_action = value
                if soap_action == target_action then
                    core.request.add_header("SOAPAction", soap_action)
                    core.log.info("Matched action from Content-Type header: ", soap_action)
                    return true
                end
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

    local found_tbl = {}
    find_action_in_body(handler.root, target_action, found_tbl)
    if found_tbl["SOAPAction"] then
        core.request.add_header("SOAPAction", found_tbl["SOAPAction"])
        core.log.info("SOAPAction extracted from body and added: ", found_tbl["SOAPAction"])
        return true
    end
    return false
end

return _M
