-- Shared implementation for the token-client plugins (jwt-client,
-- generic-oauth-client, openid-connect-client). Each plugin provides its own
-- schema fields and request-body fields; this module implements the common
-- schema boilerplate, body encoding and flow: cache lookup -> connect to IDP
-- -> POST token request -> cache token -> add Authorization header.
local core = require("apisix.core")
local url  = require("net.url")

local _M = {}

-- Builds a plugin config schema: shared properties (token_endpoint,
-- ssl_verify, use_cache, default_expiration) merged with plugin-specific ones.
-- opts:
--   default_expiration (integer) schema default for default_expiration
--   properties         (table)   plugin-specific properties
--   required           (table)   required property names
function _M.schema(opts)
	local properties = {
		token_endpoint = {
			type = "string"
		},
		ssl_verify = {
			description = "Verify SSL certificate of the IDP host (must be set to false if the IDP is using a self-signed certificate)",
			type = "boolean",
			default = false,
		},
		use_cache = {
			description = "Enable caching of acquired access tokens.",
			type = "boolean",
			default = true,
		},
		default_expiration = {
			type = "integer",
			minimum = 1,
			maximum = 100000,
			default = opts.default_expiration,
			description = "Default expiration time of cached tokens in seconds. Used when expiration is not provided by IDP in response"
		},
	}
	for name, prop in pairs(opts.properties) do
		properties[name] = prop
	end

	return {
		type = "object",
		properties = properties,
		required = opts.required,
	}
end

-- Schema for free-form extra token request parameters.
function _M.custom_parameters_schema(description)
	return {
		description = description,
		type = "object",
		minProperties = 1,
		patternProperties = {
			["^[^:]+$"] = {
				oneOf = {
					{ type = "string" },
					{ type = "number" }
				}
			}
		}
	}
end

-- Encodes an ordered list of { name, value } pairs, plus optional free-form
-- custom parameters, as an x-www-form-urlencoded body.
function _M.encode_form(fields, custom_parameters)
	local parts = {}
	for _, field in ipairs(fields) do
		table.insert(parts, field[1] .. "=" .. ngx.escape_uri(field[2]))
	end
	if custom_parameters ~= nil then
		for param, value in pairs(custom_parameters) do
			table.insert(parts, param .. "=" .. ngx.escape_uri(value))
		end
	end

	return table.concat(parts, "&"), "application/x-www-form-urlencoded"
end

-- Encodes an ordered list of { name, value } pairs, plus optional free-form
-- custom parameters, as a JSON object body with string values.
function _M.encode_json(fields, custom_parameters)
	local parts = {}
	for _, field in ipairs(fields) do
		table.insert(parts, "\"" .. field[1] .. "\":\"" .. field[2] .. "\"")
	end
	if custom_parameters ~= nil then
		for param, value in pairs(custom_parameters) do
			table.insert(parts, "\"" .. param .. "\":\"" .. value .. "\"")
		end
	end

	return "{" .. table.concat(parts, ",") .. "}", "application/json"
end

-- opts:
--   name                (string)   plugin name; also used for the "<name>-cache" shared dict
--   schema              (table)    plugin config schema
--   metadata_schema     (table)    optional metadata schema, defaults to {}
--   get_cache_key       (function) conf -> cache key for the token cache
--   build_request       (function) conf -> request body, content type
--   set_ssl_server_name (boolean)  pass ssl_server_name (SNI) on connect
function _M.new(opts)
	local plugin_name = opts.name
	local token_cache = ngx.shared[plugin_name .. "-cache"]
	local schema = opts.schema
	local metadata_schema = opts.metadata_schema or {}
	local get_cache_key = opts.get_cache_key
	local build_request = opts.build_request
	local set_ssl_server_name = opts.set_ssl_server_name

	local plugin = {
		version = 0.1,
		priority = 1,
		name = plugin_name,
		schema = schema,
		metadata_schema = metadata_schema
	}

	function plugin.check_schema(conf, schema_type)
		if schema_type == core.schema.TYPE_METADATA then
			return core.schema.check(metadata_schema, conf)
		end
		return core.schema.check(schema, conf)
	end

	function plugin.access(conf, ctx)
		local cache_key = get_cache_key(conf)

		local cached_token = token_cache:get(cache_key)
		if cached_token ~= nil and conf.use_cache == true then
			core.log.info("found token in cache, using cached token")
			core.request.add_header(ctx, "Authorization", "Bearer " .. cached_token)
			return
		end

		local parsed_url = url.parse(conf.token_endpoint)

		local httpc = assert(require('resty.http').new())
		local connect_opts = {
			host 	   = parsed_url.host,
			port 	   = parsed_url.port,
			scheme 	   = parsed_url.scheme,
			ssl_verify = conf.ssl_verify
		}
		if set_ssl_server_name then
			connect_opts.ssl_server_name = parsed_url.host
		end
		local _, err = httpc:connect(connect_opts)

		if err then
			core.log.error(err)
			httpc:close()
			return 500, { message = err }
		end

		local request_body, content_type = build_request(conf)
		core.log.info("Built request body: " .. request_body)

		local res, call_err = assert(httpc:request {
			path    = parsed_url.path,
			body    = request_body,
			method  = 'POST',
			headers = {
				["Content-Type"] = content_type,
			},
		})

		local body, _ = res:read_body()
		core.log.info("IDP response status: ", res.status)
		if call_err ~= nil or res.status ~= 200 then
			core.log.error("Http error: ", body)
			core.log.error("Call error: ", call_err)
			httpc:close()
			if body == nil then
				return res.status, { message = "Failed to make request to IDP. No error message was given. Error code: " .. res.status }
			else
				return res.status, { message = body }
			end
		else
			local token_response = core.json.decode(body)
			local expiration = token_response.expires_in or conf.default_expiration

			token_cache:set(cache_key, token_response.access_token, expiration)
			core.request.add_header(ctx, "Authorization", "Bearer " .. token_response.access_token)
			httpc:close()
		end
	end

	return plugin
end

return _M
