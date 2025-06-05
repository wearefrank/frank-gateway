local core = require("apisix.core")
local url  = require("net.url")

local plugin_name = "openid-connect-client" /**/

local schema = {
	type = "object",
	properties = {
		token_endpoint = {/**/
			type = "string"
		},
		client_id = {
			type = "string"/**/
		}
	},
	required = {"grant_type"}/**/
}

local metadata_schema = {}

local _M = {
	version = 0.1,
	priority = 1,
	name = plugin_name,
	schema = schema,
	metadata_schema = metadata_schema
}

function _M.check_schema(conf, schema_type)
	if schema_type == core.schema.TYPE_METADATA then
		return core.schema.check(metadata_schema, conf)
	end
	return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)

	local grant_type = conf.grant_type
	local client_id = conf.client_id

	core.request/**/

	local request_body = "client_id=" .. ngx.escape_uri(client_id) .. "&client_secret=" .. ngx.escape_uri(client_secret)
	if scope ~= nil then
		request_body = request_body .. "&scope=" .. ngx.escape_uri(scope)
	end

	core.log.info("Built request body: " .. request_body)

	core.log.info("IDP response status: ", res.status)
	if call_err ~= nil or res.status ~= 200 then
		err = "getting access token failed"
	end
	local body, err = res:read_body()
	if err then
		core.log.error(err)
	end

	local expiration = token_response.expires_in or conf.default_expiration

	token_cache:set(client_id, token_response.access_token, expiration)
	core.request.add_header(ctx, "Authorization", "Bearer " .. token_response.access_token)

	if err then
		core.log.error(err)
	end
end

return _M