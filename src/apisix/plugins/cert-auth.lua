local core = require("apisix.core")
local plugin_name = "cert-auth"
local consumer_mod = require("apisix.consumer")
local ok_x509, x509_mod = pcall(require, "resty.openssl.x509")

local schema = {}

local consumer_schema = {
	type = "object",
	properties = {
		cn = {type = "string"},
		identifier = {type = "string"},
	},
	oneOf = {
		{ required = {"cn"} }, -- cn is kept around so existing consumer configs don't break, but identifier is the preferred field going forward.
		{ required = {"identifier"} },
	},
}

local _M = {
	version = 0.2,
	priority = 2401,
	name = plugin_name,
	type = "auth", -- marks this as an authentication plugin, so APISIX knows it must pick a consumer
	schema = schema,
	consumer_schema = consumer_schema
}

-- Authentication plugins are responsible for picking a consumer at the end of their run.
-- The consumer_schema tells APISIX what fields are valid when an admin configures this plugin on a consumer.

function _M.check_schema(conf, schema_type)
	if schema_type == core.schema.TYPE_CONSUMER then
		return core.schema.check(consumer_schema, conf)
	end
	return core.schema.check(schema, conf)
end

-- Adds a hostname to the output list, stripping any label prefix (e.g. "DNS:" or "DNSName:")
-- that the certificate library may have added, and skipping values we have already seen.
local function append_dns_name(out, seen, value)
	if type(value) == "userdata" then
		value = tostring(value) -- some certificate library types are not plain strings; convert them first
	end
	if type(value) ~= "string" then
		return -- nothing usable, skip
	end
	-- Depending on the certificate library and its version, a DNS name may come back as
	-- "example.org", "DNS:example.org", or "DNSName:example.org". Strip the prefix so we
	-- always store just the plain hostname.
	local from_prefixed = string.match(value, "^%s*[Dd][Nn][Ss]:%s*(.+)$")
		or string.match(value, "^%s*[Dd][Nn][Ss][Nn][Aa][Mm][Ee]:%s*(.+)$")
	if from_prefixed then
		value = from_prefixed
	end
	value = string.gsub(value, "^%s+", "")
	value = string.gsub(value, "%s+$", "") -- trim any surrounding whitespace
	if value == "" or seen[value] then
		return
	end
	seen[value] = true
	out[#out + 1] = value
end

-- Cleans up the certificate text that NGINX gives us so the certificate parser can read it.
-- NGINX can pass the cert in slightly different shapes depending on the variable used.
local function normalize_client_cert_pem(value)
	if type(value) ~= "string" then
		return nil
	end

	local cert = value
	cert = string.gsub(cert, "\r\n", "\n") -- Windows-style line endings to Unix
	cert = string.gsub(cert, "\\n", "\n") -- literal backslash-n sequences to real newlines
	cert = string.gsub(cert, "\n\t+", "\n") -- remove leading tabs on each line
	cert = string.gsub(cert, "\n[ ]+", "\n") -- remove leading spaces on each line
	cert = string.gsub(cert, "^%s+", "") -- trim the front
	cert = string.gsub(cert, "%s+$", "") -- trim the end

	if cert == "" then
		return nil
	end

	return cert .. "\n" -- some parsers are strict about the certificate ending with a newline
end

-- Pulls a single named field out of a certificate subject string.
-- For example, given "CN=alice, O=example" and asking for "CN", returns "alice".
local function extract_dn_attr(full_dn, attr)
	if type(full_dn) ~= "string" or type(attr) ~= "string" then
		return nil
	end

	local value = string.match(full_dn, attr .. "%s*=%s*([^,/]+)") -- allow optional spaces around the equals sign
	if not value then
		return nil
	end

	value = string.gsub(value, "^%s+", "") -- trim
	value = string.gsub(value, "%s+$", "")
	if value == "" then
		return nil
	end

	return value
end

-- Reads the list of DNS names from the client certificate's Subject Alternative Names.
-- Returns an empty list if the certificate has no DNS names in its SAN.
local function extract_dns_sans(client_cert_pem)
	if not ok_x509 then
		return nil, "resty.openssl.x509 not available"
	end

	local cert, err = x509_mod.new(client_cert_pem, "PEM")
	if not cert then
		return nil, "failed to parse cert: " .. (err or "unknown")
	end

	-- Ask the certificate library for the Subject Alternative Names.
	local san, san_err = cert:get_subject_alt_name()
	if not san then
		if san_err then
			return nil, "failed to read SAN: " .. san_err
		end
		return {}, nil
	end

	local dns_names = {}
	local seen = {}

	-- Picks DNS names out of a plain-text SAN representation, e.g. "DNS:foo.com, IP:1.2.3.4".
	local function collect_dns_from_text(text)
		if type(text) ~= "string" then return end
		for name in string.gmatch(text, "[Dd][Nn][Ss]%s*:%s*([^,%s\n]+)") do
			append_dns_name(dns_names, seen, name)
		end
	end

	-- Some certificate library versions hand back the entire SAN block as a single string rather
	-- than a structured list. Fall back to text parsing in that case.
	if type(san) ~= "table" then
		collect_dns_from_text(tostring(san))
		return dns_names
	end

	local dns_fields = {"DNS", "dNSName"}

	local function append_dns_value(value)
		if type(value) == "table" then
			for _, name in ipairs(value) do
				append_dns_name(dns_names, seen, name)
			end
			return
		end
		append_dns_name(dns_names, seen, value)
	end

	-- Some versions give back a table with named keys, e.g. san.DNS = "foo.com"
	-- or san.dNSName = {"foo.com", "bar.com"}. Try those first.
	for _, field in ipairs(dns_fields) do
		local v = san[field]
		if v ~= nil then
			append_dns_value(v)
		end
	end

	-- Other versions give back a numbered list where each item represents one SAN entry.
	for _, entry in ipairs(san) do
		if type(entry) ~= "table" then
			-- A plain value with no structure — treat it as a hostname directly.
			append_dns_name(dns_names, seen, entry)
		else
			-- Check for named fields on the entry first.
			for _, field in ipairs(dns_fields) do
				if entry[field] ~= nil then
					append_dns_value(entry[field])
				end
			end

			-- Some entries use a type/value pair instead of named fields.
			-- The type can be the string "dns" or the number 2 (OpenSSL's internal code for DNS names).
			local t = entry.type or entry.name
			local v = entry.value or entry.val or entry[1]
			local t_lower = type(t) == "string" and string.lower(t) or nil
			if t_lower == "dns" or t_lower == "dnsname" or t == 2 then
				append_dns_name(dns_names, seen, v)
			end
		end
	end

	-- Nothing worked yet — try converting the whole SAN value to a string and parsing that.
	if #dns_names == 0 then
		collect_dns_from_text(tostring(san))
		local ext = cert:get_extension("subjectAltName")
		if ext then
			collect_dns_from_text(tostring(ext))
		end
	end

	return dns_names
end

-- Looks up a consumer by checking their plugin configuration for a matching field value.
-- Used to find who owns a given identifier or CN.
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
    -- Read the client's certificate and subject information that NGINX extracted during the TLS handshake.
    local full_dn = ngx.var.ssl_client_s_dn
	local client_cert = normalize_client_cert_pem(ngx.var.ssl_client_raw_cert or ngx.var.ssl_client_cert)

	if not client_cert then
		-- No certificate means we cannot identify the caller.
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
		-- A consumer's identifier field might be stored as "example.org", "DNS:example.org", or
		-- "DNSName:example.org" depending on how the admin set it up. Add all three so any of them match.
		for _, name in ipairs(dns_sans) do
			identifier_candidates[#identifier_candidates + 1] = name
			identifier_candidates[#identifier_candidates + 1] = "DNS:" .. name
			identifier_candidates[#identifier_candidates + 1] = "DNSName:" .. name
		end
	end

	if full_dn then
		core.log.info("Client CN: ", full_dn)

		local serial = extract_dn_attr(full_dn, "[Ss][Ee][Rr][Ii][Aa][Ll][Nn][Uu][Mm][Bb][Ee][Rr]")
		if serial then
			-- A certificate serial number can also serve as an identifier.
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

	-- Try each identifier variant until we find a matching consumer.
	-- If nothing matches, fall back to the common name (CN) for older consumer configs.
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
	-- Make the consumer name available to downstream plugins and log entries.
	ctx.consumer_name = consumer.username or consumer.consumer_name

	return
end

return _M