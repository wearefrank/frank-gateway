local core = require("apisix.core")
local lfs = require("lfs")
local yaml = require("lyaml")
local ngx = ngx

local plugin_name = "merge-config"
local LOCK_KEY = "merge-config-lock"
local LOCK_TTL = 60  -- seconds; safety release if the worker dies mid-run

local DEFAULT_SECTION_ORDER = {
	"ssls", "consumers", "consumer_groups", "services", "routes",
	"stream_routes", "upstreams", "global_rules", "plugin_configs",
	"plugin_metadata", "secrets"
}

local plugin_conf_schema = {
	type = "object",
	properties = {
		input_directory = {
			type = "string",
			minLength = 1,
			default = "/usr/local/apisix/conf/mergeconfigs"
		},
		output_file = {
			type = "string",
			minLength = 1,
			default = "/usr/local/apisix/conf/apisix.yaml"
		},
		section_order = {
			type = "array",
			minItems = 1,
			items = { type = "string" },
			default = DEFAULT_SECTION_ORDER
		},
		interval = {
			type = "integer",
			minimum = 1,
			default = 2,
			description = "How often (in seconds) to check for changes and rebuild"
		},
		enabled = {
			type = "boolean",
			default = false,
			description = "Set to true to activate the background merge timer"
		}
	},
	additionalProperties = false
}

local _M = {
	version = 1,
	priority = 1,
	name = plugin_name,
	schema = plugin_conf_schema
}

local timer_started = false

local function get_plugin_attr_conf()
	local ok, local_conf = pcall(core.config.local_conf)
	if not ok or type(local_conf) ~= "table" then
		return {}
	end

	local plugin_attr = local_conf.plugin_attr
	if type(plugin_attr) ~= "table" then
		return {}
	end

	local conf = plugin_attr[plugin_name]
	if type(conf) ~= "table" then
		return {}
	end

	return conf
end

function _M.check_schema(conf)
	return core.schema.check(_M.schema, conf)
end

local function get_timestamp()
	return os.date("%Y-%m-%d %H:%M:%S")
end

local function read_file(file_path)
	local file_handle = io.open(file_path, "r")
	if not file_handle then
		return ""
	end

	local content = file_handle:read("*a")
	file_handle:close()
	return content
end

local function list_yaml_files(input_directory)
	local files = {}
	local ok, err = pcall(function()
		for file_name in lfs.dir(input_directory) do
			if file_name:match("%.ya?ml$") then
				table.insert(files, file_name)
			end
		end
	end)

	if not ok then
		return nil, err
	end

	table.sort(files)
	return files
end

local function parse_yaml_file(file_path)
	local content = read_file(file_path)
	if content == "" then
		return nil, "failed to read file"
	end

	local ok, parsed = pcall(yaml.load, content)
	if not ok then
		return nil, parsed
	end

	if type(parsed) ~= "table" then
		return nil, "YAML root must be a mapping"
	end

	return parsed
end

local function locate_section_item_lines(text, section_name)
	local line_numbers = {}
	local in_section = false
	local section_indent = nil
	local item_indent = nil
	local line_number = 0

	for line in text:gmatch("[^\n]+") do
		line_number = line_number + 1
		local indent = #(line:match("^(%s*)") or "")

		if not in_section then
			if line:match("^%s*" .. section_name .. "%s*:%s*$") then
				in_section = true
				section_indent = indent
				item_indent = nil
			end
		elseif indent <= section_indent and line:match("^%S") then
			break
		elseif line:match("^%s*-%s") then
			if not item_indent then
				item_indent = indent
			end

			if indent == item_indent then
				table.insert(line_numbers, line_number)
			end
		end
	end

	return line_numbers
end

local function collect_section_items(parsed_yaml, raw_content, section_name, source_file)
	local section_value = parsed_yaml[section_name]
	if section_value == nil then
		return {}
	end

	if type(section_value) ~= "table" then
		return nil, string.format("section '%s' must be a YAML sequence", section_name)
	end

	local item_line_numbers = locate_section_item_lines(raw_content, section_name)
	local items = {}
	for i, item in ipairs(section_value) do
		table.insert(items, {
			configuration_item = item,
			source_file_name = source_file,
			source_line_number = item_line_numbers[i] or "n/a",
			section_index = i
		})
	end

	return items
end

local function extract_id(item)
	if type(item) ~= "table" then
		return nil
	end

	if item.id == nil then
		return nil
	end

	if type(item.id) == "number" then
		return item.id
	end

	if type(item.id) == "string" then
		local id = tonumber(item.id)
		if id then
			return id
		end
	end

	return nil
end

local function extract_name(item)
	if type(item) ~= "table" then
		return nil
	end

	if type(item.name) == "string" then
		return item.name
	end

	return nil
end

local function detect_duplicates(section_name, items, log)
	local seen_ids = {}
	local seen_names = {}
	local filtered_items = {}
	local excluded_entries = {}

	for _, entry in ipairs(items) do
		local item = entry.configuration_item
		local is_duplicate = false

		local id = extract_id(item)
		if id then
			local first_entry = seen_ids[id]
			if first_entry then
				is_duplicate = true
				core.log.error(
					"duplicate id=", id,
					" section=", section_name,
					" first_file=", first_entry.source_file_name,
					" first_line=", first_entry.source_line_number,
					" duplicate_file=", entry.source_file_name,
					" duplicate_line=", entry.source_line_number
				)

				table.insert(log.duplicate_ids, {
					id = id,
					section_name = section_name,
					first_file_name = first_entry.source_file_name,
					first_line_number = first_entry.source_line_number,
					duplicate_file_name = entry.source_file_name,
					duplicate_line_number = entry.source_line_number
				})
			else
				seen_ids[id] = entry
			end
		end

		local name = extract_name(item)
		if name then
			local first_entry = seen_names[name]
			if first_entry then
				is_duplicate = true
				core.log.error(
					"duplicate name=", name,
					" section=", section_name,
					" first_file=", first_entry.source_file_name,
					" first_line=", first_entry.source_line_number,
					" duplicate_file=", entry.source_file_name,
					" duplicate_line=", entry.source_line_number
				)

				table.insert(log.duplicate_names, {
					name = name,
					section_name = section_name,
					first_file_name = first_entry.source_file_name,
					first_line_number = first_entry.source_line_number,
					duplicate_file_name = entry.source_file_name,
					duplicate_line_number = entry.source_line_number
				})
			else
				seen_names[name] = entry
			end
		end

		if is_duplicate then
			excluded_entries[entry] = true
		else
			table.insert(filtered_items, entry)
		end
	end

	return filtered_items
end

local function trim_yaml_document_markers(text)
	local without_start = text:gsub("^%-%-%-%s*\n", "")
	return without_start:gsub("\n?%.%.%.%s*$", "")
end

local function indent_lines(text, indent)
	local prefix = string.rep(" ", indent)
	return prefix .. text:gsub("\n", "\n" .. prefix)
end

local function dump_yaml_sequence(items)
	if #items == 0 then
		return "[]"
	end

	local ok, dumped = pcall(yaml.dump, items)
	if not ok then
		return nil, dumped
	end

	local documents = {}
	local current_doc = nil

	for line in dumped:gmatch("[^\n]+") do
		if line:match("^%s*%-%-%-%s*$") then
			current_doc = {}
		elseif line:match("^%s*%.%.%.%s*$") then
			if current_doc and #current_doc > 0 then
				table.insert(documents, current_doc)
			end
			current_doc = nil
		else
			if current_doc ~= nil then
				table.insert(current_doc, line)
			end
		end
	end

	if #documents == 0 then
		local normalized = trim_yaml_document_markers(dumped)
		normalized = normalized:gsub("%s+$", "")
		return normalized
	end

	local rendered = {}
	for _, doc_lines in ipairs(documents) do
		table.insert(rendered, "- " .. doc_lines[1])
		for i = 2, #doc_lines do
			table.insert(rendered, "  " .. doc_lines[i])
		end
	end

	return table.concat(rendered, "\n")
end

local function write_output(output_file, merged_sections, section_order, log)
	local output_handle, open_err = io.open(output_file, "w")
	if not output_handle then
		return nil, open_err
	end

	output_handle:write("# AUTO-GENERATED APISIX CONFIG\n")
	output_handle:write("# Last generated: " .. get_timestamp() .. "\n\n")

	if (#log.duplicate_ids > 0) or (#log.duplicate_names > 0) then
		output_handle:write("# ==================================================\n")
		output_handle:write("# CONFIG MERGE ERRORS\n")
		output_handle:write("# ==================================================\n\n")

		if #log.duplicate_ids > 0 then
			output_handle:write("# --- DUPLICATE IDS ---\n")
			for _, entry in ipairs(log.duplicate_ids) do
				output_handle:write(string.format(
					"# id=%s | section=%s | first_file=%s | first_line=%s | duplicate_file=%s | duplicate_line=%s\n",
					entry.id,
					entry.section_name,
					entry.first_file_name,
					entry.first_line_number,
					entry.duplicate_file_name,
					entry.duplicate_line_number
				))
			end
			output_handle:write("\n")
		end

		if #log.duplicate_names > 0 then
			output_handle:write("# --- DUPLICATE NAMES ---\n")
			for _, entry in ipairs(log.duplicate_names) do
				output_handle:write(string.format(
					"# name=%s | section=%s | first_file=%s | first_line=%s | duplicate_file=%s | duplicate_line=%s\n",
					entry.name,
					entry.section_name,
					entry.first_file_name,
					entry.first_line_number,
					entry.duplicate_file_name,
					entry.duplicate_line_number
				))
			end
			output_handle:write("\n")
		end
	end

	for _, section in ipairs(section_order) do
		output_handle:write(string.rep("#", 60), "\n")
		output_handle:write("# ", section:upper(), "\n")
		output_handle:write(string.rep("#", 60), "\n")
		output_handle:write(section .. ":")

		local entries = merged_sections[section]
		if #entries == 0 then
			output_handle:write(" []\n\n")
		else
			local items = {}
			for _, entry in ipairs(entries) do
				table.insert(items, entry.configuration_item)
			end

			local dumped, dump_err = dump_yaml_sequence(items)
			if not dumped then
				output_handle:close()
				return nil, "failed to dump YAML section '" .. section .. "': " .. tostring(dump_err)
			end

			output_handle:write("\n")
			output_handle:write(indent_lines(dumped, 2), "\n")
			output_handle:write("\n")
		end
	end

	output_handle:write("#END\n")

	local ok_close, close_err = pcall(function()
		output_handle:close()
	end)

	if not ok_close then
		return nil, close_err
	end

	return true
end

local function build(conf)
	local section_order = conf.section_order or DEFAULT_SECTION_ORDER
	local input_directory = conf.input_directory or "/usr/local/apisix/conf/mergeconfigs"
	local output_file = conf.output_file or "/usr/local/apisix/conf/apisix.yaml"

	local files, list_err = list_yaml_files(input_directory)
	if not files then
		return nil, list_err
	end

	local log = {
		duplicate_ids = {},
		duplicate_names = {}
	}

	local merged_sections = {}
	for _, section in ipairs(section_order) do
		merged_sections[section] = {}
	end

	for _, file_name in ipairs(files) do
		local file_path = input_directory .. "/" .. file_name
		local raw_content = read_file(file_path)
		if raw_content == "" then
			return nil, "failed to read YAML file '" .. file_name .. "'"
		end

		local parsed_yaml, parse_err = parse_yaml_file(file_path)
		if not parsed_yaml then
			return nil, "failed to parse YAML file '" .. file_name .. "': " .. tostring(parse_err)
		end

		for _, section in ipairs(section_order) do
			local section_items, section_err = collect_section_items(parsed_yaml, raw_content, section, file_name)
			if not section_items then
				return nil, "invalid section in file '" .. file_name .. "': " .. tostring(section_err)
			end

			for _, item in ipairs(section_items) do
				table.insert(merged_sections[section], item)
			end
		end
	end

	for _, section in ipairs(section_order) do
		merged_sections[section] = detect_duplicates(section, merged_sections[section], log)
	end

	local ok, write_err = write_output(output_file, merged_sections, section_order, log)
	if not ok then
		return nil, write_err
	end

	return {
		output_file = output_file,
		duplicate_ids = #log.duplicate_ids,
		duplicate_names = #log.duplicate_names,
		generated_at = get_timestamp()
	}
end

function _M.run_once(conf)
	local result, err = build(conf or {})
	if not result then
		core.log.error("merge-config build failed: ", err)
		return nil, err
	end

	core.log.info(
		"merge-config written: ", result.output_file,
		" duplicate_ids=", result.duplicate_ids,
		" duplicate_names=", result.duplicate_names,
		" generated_at=", result.generated_at
	)

	return result
end

--------------------------------------------------
-- TIMER CALLBACK
--------------------------------------------------
-- Called by ngx.timer.every on every tick. `premature` is true when NGINX
-- is shutting down; we must exit immediately in that case.
local function timer_handler(premature, conf)
	if premature then
		return
	end

	-- Acquire a short-lived shared-dict lock so only one worker runs the
	-- merge at a time. ngx.shared.DICT:add succeeds only when the key does
	-- not yet exist, making it an atomic test-and-set.
	local dict = ngx.shared["merge-config"]
	if not dict then
		core.log.error("merge-config: shared dict 'merge-config' not found; "
			.. "add it to nginx_config.http.custom_lua_shared_dict in config.yaml")
		return
	end

	local ok, _ = dict:add(LOCK_KEY, 1, LOCK_TTL)
	if not ok then
		-- Another worker is already running the merge, skip this tick.
		return
	end

	local success, result_or_nil, run_err = pcall(_M.run_once, conf)
	if not success then
		core.log.error("merge-config timer panic: ", result_or_nil)
	elseif not result_or_nil then
		core.log.error("merge-config timer run failed: ", run_err)
	end

	dict:delete(LOCK_KEY)
end

--------------------------------------------------
-- INIT (master process, runs before workers start)
--------------------------------------------------
-- APISIX calls _M.init() in init_by_lua context, which executes before any
-- worker starts and before the config_yaml watcher tries to stat apisix.yaml.
-- Running the initial merge here guarantees the output file exists by the
-- time APISIX first reads it.
function _M.init()
	local conf = get_plugin_attr_conf()

	if conf.enabled == false then
		return
	end

	core.log.info("merge-config: running initial build in init phase")

	local result, err = build(conf)
	if not result then
		core.log.error("merge-config init: initial build failed: ", err)
		return
	end

	-- The init phase runs as root, while worker timers run as the nginx worker
	-- user (typically nobody). Ensure the generated file remains writable so the
	-- recurring timer can update it after config changes.
	local chmod_ok = os.execute("chmod 666 " .. result.output_file)
	if chmod_ok ~= true and chmod_ok ~= 0 then
		core.log.error("merge-config init: failed to chmod output file: ", result.output_file)
	end

	core.log.info("merge-config init: initial build complete: ", result.output_file)
end

-- APISIX core invokes plugin.workflow_handler() while loading plugins inside
-- its own init_worker path. This is the right place to start background
-- timers for a plugin that is enabled globally but not attached to routes.
function _M.workflow_handler()
	local conf = get_plugin_attr_conf()

	-- Allow the feature to be disabled entirely via plugin_attr.
	if conf.enabled == false then
		core.log.info("merge-config: disabled via plugin_attr, skipping timer")
		return
	end

	if timer_started then
		return
	end

	local interval = conf.interval or 2

	core.log.warn(
		"merge-config: starting background merge timer (interval=", interval,
		"s, worker_id=", tostring(ngx.worker.id()), ")"
	)

	-- Run immediately on startup, then every `interval` seconds.
	local ok, err = ngx.timer.at(0, timer_handler, conf)
	if not ok then
		core.log.error("merge-config: failed to start initial timer: ", err)
		return
	end

	ok, err = ngx.timer.every(interval, timer_handler, conf)
	if not ok then
		core.log.error("merge-config: failed to start recurring timer: ", err)
		return
	end

	timer_started = true
end

return _M
