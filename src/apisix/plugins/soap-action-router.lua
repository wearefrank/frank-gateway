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
	for k,v in pairs(element) do
		if type(v) ~= "table" then
			if type(k) == "string" and k:match("Action") then
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

function _M:match_soap_action(target_action)
	local soap_action = ngx.req.get_headers()['SOAPAction']
	if soap_action ~= nil then
	else
		local content_type = ngx.req.get_headers()['Content-Type']
		for k in string.gmatch(content_type, "[^;]+") do
			local key, value = k:match("([^=]+)=(.*)")
			if key == "action" then
				soap_action = value:gsub("^%s*[\"']*(.-)[\"']*%s*$", "%1")
			end
		end
	end

	if soap_action == nil then
		local body = core.request.get_body()
		if body ~= nil then
			local handler = xmlhandler:new()
			local parser = xml2lua.parser(handler)
			parser:parse(body)
			local flat_tbl = {}
			find_action_in_body(handler.root, target_action, flat_tbl)
			soap_action = flat_tbl["SOAPAction"]
		end
	end

	if soap_action == target_action then
		core.request.add_header("SOAPAction", soap_action)
		return true
	else
		return false
	end
end

return _M
