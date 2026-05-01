local core = require("apisix.core")
local plugin_name = "cert-auth"
local consumer_mod = require("apisix.consumer")
local ok_x509, x509_mod = pcall(require, "resty.openssl.x509")

local schema = {
}

local consumer_schema = {
	type = "object",
	properties = {
		cn = {type = "string"},
		identifier = {type = "string"},
	},
	oneOf = {
		{ required = {"cn"} }, --CN is still kept so old configurations won't break, but identifier is preferred.
		{ required = {"identifier"} },
	},
}

local _M = {
	version = 0.1,
	priority = 2401,
	name = plugin_name,
	type = "auth", -- This means authentication plugin
	schema = schema,
	consumer_schema = consumer_schema
}

-- If its an authentication plugin then it needs to choose a consumer after execution
-- To interact with the consumer resource, this type of plugin needs to provide a consumer_schema to check the plugins configuration in the consumer.
-- The consumer schema is used to create the consumer object.

function _M.check_schema(conf, schema_type)
	if schema_type == core.schema.TYPE_CONSUMER then
		return core.schema.check(consumer_schema, conf)
	end
	return core.schema.check(schema, conf)
end

local function append_dns_name(out, seen, value)
	if type(value) == "userdata" then
		value = tostring(value)
	end
	if type(value) ~= "string" then
		return
	end
	local from_prefixed = string.match(value, "^%s*[Dd][Nn][Ss]:%s*(.+)$")
	if not from_prefixed then
		from_prefixed = string.match(value, "^%s*[Dd][Nn][Ss][Nn][Aa][Mm][Ee]:%s*(.+)$")
	end
	if from_prefixed then
		value = from_prefixed
	end
	value = string.gsub(value, "^%s+", "")
	value = string.gsub(value, "%s+$", "")
	if value == "" or seen[value] then
		return
	end
	seen[value] = true
	out[#out + 1] = value
end

local function normalize_client_cert_pem(value)
	if type(value) ~= "string" then
		return nil
	end

	local cert = value
	cert = string.gsub(cert, "\r\n", "\n")
	cert = string.gsub(cert, "\\n", "\n")
	cert = string.gsub(cert, "\n\t+", "\n")
	cert = string.gsub(cert, "\n[ ]+", "\n")
	cert = string.gsub(cert, "^%s+", "")
	cert = string.gsub(cert, "%s+$", "")

	if cert == "" then
		return nil
	end

	return cert .. "\n"
end

local function extract_dn_attr(full_dn, attr)
	if type(full_dn) ~= "string" or type(attr) ~= "string" then
		return nil
	end

	local value = string.match(full_dn, attr .. "%s*=%s*([^,/]+)")
	if not value then
		return nil
	end

	value = string.gsub(value, "^%s+", "")
	value = string.gsub(value, "%s+$", "")
	if value == "" then
		return nil
	end

	return value
end

local function extract_dns_sans(client_cert_pem)
	if not ok_x509 then
		return nil, "resty.openssl.x509 not available"
	end

	local cert, err = x509_mod.new(client_cert_pem, "PEM")
	if not cert then
		return nil, "failed to parse cert: " .. (err or "unknown")
	end

	local san, san_err = cert:get_subject_alt_name()
	if not san then
		if san_err then
			return nil, "failed to read SAN: " .. san_err
		end
		return {}, nil
	end

	local dns_names = {}
	local seen = {}

	local function append_dns_from_text(text)
		if type(text) ~= "string" then
			return
		end

		for name in string.gmatch(text, "[Dd][Nn][Ss]%s*:%s*([^,%s\n]+)") do
			append_dns_name(dns_names, seen, name)
		end
	end

	local function append_dns_field(value)
		if type(value) == "string" or type(value) == "userdata" then
			append_dns_name(dns_names, seen, value)
		elseif type(value) == "table" then
			for _, name in ipairs(value) do
				append_dns_name(dns_names, seen, name)
			end
		end
	end

	if type(san) ~= "table" then
		append_dns_from_text(tostring(san))
		return dns_names
	end

	append_dns_field(san.DNS)
	append_dns_field(san.dNSName)

	for _, entry in ipairs(san) do
		if type(entry) == "table" then
			append_dns_field(entry.DNS)
			append_dns_field(entry.dNSName)

			local t = entry.type or entry.name
			local v = entry.value or entry.val or entry[1]
			if type(t) == "string" then
				local t_lower = string.lower(t)
				if t_lower == "dns" or t_lower == "dnsname" then
					append_dns_name(dns_names, seen, v)
				end
			elseif type(t) == "number" and t == 2 then
				-- OpenSSL GEN_DNS is type 2 in many bindings.
				append_dns_name(dns_names, seen, v)
			end
		else
			append_dns_name(dns_names, seen, entry)
		end
	end

	if #dns_names == 0 then
		append_dns_from_text(tostring(san))
		local ext = cert:get_extension("subjectAltName")
		if ext then
			append_dns_from_text(tostring(ext))
		end
	end

	return dns_names
end

local function find_consumer_by_field(field, value)
	if type(value) ~= "string" or value == "" then
		return nil, nil, "invalid lookup value"
	end

	local consumer_conf = consumer_mod.plugin(plugin_name)
	if not consumer_conf or type(consumer_conf.nodes) ~= "table" then
		return nil, nil, "Missing related consumer"
	end

	for _, consumer in ipairs(consumer_conf.nodes) do
		local auth_conf = consumer and consumer.auth_conf
		if type(auth_conf) == "table" and auth_conf[field] == value then
			return consumer, consumer_conf, nil
		end
	end

	return nil, consumer_conf, "not found"
end

function _M.access(conf, ctx)
    local full_dn = ngx.var.ssl_client_s_dn
	local client_cert = normalize_client_cert_pem(ngx.var.ssl_client_raw_cert or ngx.var.ssl_client_cert)


	if not client_cert then
		return 401, {message = "Client certificate required"}
	end

	local dns_sans, san_err = extract_dns_sans(client_cert)
	if dns_sans then
		core.log.info("[cert-auth] SAN object parse result count=", #dns_sans)
		ctx.cert_auth_dns_sans = dns_sans
		if #dns_sans > 0 then
			core.log.info("[cert-auth] dns SANs: ", table.concat(dns_sans, ","))
		else
			core.log.info("[cert-auth] no dNSName SAN present")
		end
	else
		core.log.info("[cert-auth] dns SAN extraction skipped: ", san_err)
	end

	local identifier_candidates = {}
	if dns_sans and #dns_sans > 0 then
		for _, name in ipairs(dns_sans) do
			identifier_candidates[#identifier_candidates + 1] = name
		end
	end

	if full_dn then
		core.log.info("Client CN: ", full_dn)

		local serial = extract_dn_attr(full_dn, "[Ss][Ee][Rr][Ii][Aa][Ll][Nn][Uu][Mm][Bb][Ee][Rr]")
		if serial then
			identifier_candidates[#identifier_candidates + 1] = serial
		end
	else
		core.log.warn("Client DN is nil. CN fallback will be skipped.")
	end

	local cn = full_dn and extract_dn_attr(full_dn, "[Cc][Nn]") or nil
	if cn then
		core.log.info("Extracted CN: ", cn)
	end

	if #identifier_candidates == 0 and not cn then
		return 403, { message = "Failed to extract identifier or CN" }
	end

	local consumer, consumer_conf, err
	for _, identifier in ipairs(identifier_candidates) do
		core.log.info("Trying identifier: ", identifier)
		consumer, consumer_conf, err = find_consumer_by_field("identifier", identifier)
		if consumer then
			break
		end
	end

	if not consumer and cn then
		consumer, consumer_conf, err = find_consumer_by_field("cn", cn)
	end

    core.log.info("consumer: ", core.json.delay_encode(consumer))
    if not consumer then
		core.log.warn("No consumer found for identifier/CN: ", err or "invalid identity")
	    	return 403, {message = "No matching consumer for identifier or CN"}
    end

    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
	
	if consumer and consumer.username then
    	ctx.consumer_name = consumer.username
	elseif consumer and consumer.consumer_name then
		ctx.consumer_name = consumer.consumer_name
	end

	return
end

return _M