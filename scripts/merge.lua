local lfs = require("lfs")

local INPUT_DIRECTORY = "/usr/local/apisix/conf/mergeconfigs"
local OUTPUT_FILE = "/usr/local/apisix/conf/apisix.yaml"
local INTERVAL_SECONDS = 2

local SECTION_ORDER = {
    "ssls", "consumers", "consumer_groups", "services", "routes",
    "stream_routes", "upstreams", "global_rules", "plugin_configs",
    "plugin_metadata", "secrets"
}

--------------------------------------------------
-- TIME
--------------------------------------------------
local function get_timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

--------------------------------------------------
-- FILE HELPERS
--------------------------------------------------
local function read_file(file_path)
    local file_handle = io.open(file_path, "r")
    if not file_handle then return "" end
    local content = file_handle:read("*a")
    file_handle:close()
    return content
end

local function trim_right_whitespace(text)
    return (text:gsub("%s+$", ""))
end

local function list_yaml_files()
    local files = {}
    for file_name in lfs.dir(INPUT_DIRECTORY) do
        if file_name:match("%.ya?ml$") then
            table.insert(files, file_name)
        end
    end
    table.sort(files)
    return files
end

--------------------------------------------------
-- STATE TRACKING
--------------------------------------------------
local function file_modification_time(file_path)
    local attributes = lfs.attributes(file_path)
    return attributes and attributes.modification
end

local function directory_state()
    local state = {}
    for file_name in lfs.dir(INPUT_DIRECTORY) do
        if file_name:match("%.ya?ml$") then
            state[file_name] = file_modification_time(INPUT_DIRECTORY .. "/" .. file_name)
        end
    end
    return state
end

local function has_changes(previous_state, current_state)
    for key, value in pairs(current_state) do
        if previous_state[key] ~= value then return true end
    end
    for key in pairs(previous_state) do
        if current_state[key] == nil then return true end
    end
    return false
end

--------------------------------------------------
-- YAML SECTION EXTRACTION
--------------------------------------------------
local function extract_section(text, section_name, source_file)
    local items = {}
    local in_section, section_indent, item_indent
    local current_item, current_line
    local line_number = 0

    for line in text:gmatch("[^\n]+") do
        line_number = line_number + 1
        local indent = #(line:match("^(%s*)") or "")

        if line:match("^%s*" .. section_name .. "%s*:%s*$") then
            in_section, section_indent, item_indent = true, indent, nil
            current_item, current_line = nil, nil

        elseif in_section then
            if indent <= (section_indent or 0) and line:match("^%S") then
                break
            end

            if line:match("^%s*-%s") then
                if not item_indent then item_indent = indent end

                if indent == item_indent then
                    if current_item then
                        table.insert(items, {
                            configuration_item_text = trim_right_whitespace(current_item),
                            source_file_name = source_file,
                            source_line_number = current_line
                        })
                    end
                    current_item, current_line = line, line_number
                else
                    current_item = current_item .. "\n" .. line
                end
            elseif current_item then
                current_item = current_item .. "\n" .. line
            end
        end
    end

    if current_item then
        table.insert(items, {
            configuration_item_text = trim_right_whitespace(current_item),
            source_file_name = source_file,
            source_line_number = current_line
        })
    end

    return items
end

--------------------------------------------------
-- EXTRACTORS
--------------------------------------------------
local function extract_id(text)
    return tonumber(text:match("id:%s*(%d+)"))
end

local function extract_name(text)
    return text:match("name:%s*['\"]?([%w%-%_]+)['\"]?")
end

--------------------------------------------------
-- DUPLICATE DETECTION
--------------------------------------------------
local function detect_duplicates(section_name, items, log)
    local seen_ids = {}
    local seen_names = {}

    for _, entry in ipairs(items) do
        local text = entry.configuration_item_text

        local id = extract_id(text)
        if id then
            if seen_ids[id] then
                io.stderr:write(string.format(
                    "[ERROR] DUPLICATE ID=%s | section=%s | file=%s | line=%s\n",
                    id, section_name, entry.source_file_name, entry.source_line_number
                ))

                table.insert(log.duplicate_ids, {
                    id = id,
                    section_name = section_name,
                    file_name = entry.source_file_name,
                    line_number = entry.source_line_number
                })
            else
                seen_ids[id] = true
            end
        end

        local name = extract_name(text)
        if name then
            if seen_names[name] then
                io.stderr:write(string.format(
                    "[ERROR] DUPLICATE NAME=%s | section=%s | file=%s | line=%s\n",
                    name, section_name, entry.source_file_name, entry.source_line_number
                ))

                table.insert(log.duplicate_names, {
                    name = name,
                    section_name = section_name,
                    file_name = entry.source_file_name,
                    line_number = entry.source_line_number
                })
            else
                seen_names[name] = true
            end
        end
    end
end

--------------------------------------------------
-- BUILD
--------------------------------------------------
local function build()
    local log = {
        duplicate_ids = {},
        duplicate_names = {}
    }

    local merged_sections = {}
    for _, section in ipairs(SECTION_ORDER) do
        merged_sections[section] = {}
    end

    for _, file_name in ipairs(list_yaml_files()) do
        local file_path = INPUT_DIRECTORY .. "/" .. file_name
        local content = read_file(file_path)

        for _, section in ipairs(SECTION_ORDER) do
            for _, item in ipairs(extract_section(content, section, file_name)) do
                table.insert(merged_sections[section], item)
            end
        end
    end

    for _, section in ipairs(SECTION_ORDER) do
        detect_duplicates(section, merged_sections[section], log)
    end

    local output_handle = assert(io.open(OUTPUT_FILE, "w"))

    output_handle:write("# AUTO-GENERATED APISIX CONFIG\n")
    output_handle:write("# Last generated: " .. get_timestamp() .. "\n\n")

    --------------------------------------------------
    -- ERROR HEADER (FIXED)
    --------------------------------------------------
    if (#log.duplicate_ids > 0) or (#log.duplicate_names > 0) then
        output_handle:write("# ==================================================\n")
        output_handle:write("# CONFIG MERGE ERRORS\n")
        output_handle:write("# ==================================================\n\n")

        if #log.duplicate_ids > 0 then
            output_handle:write("# --- DUPLICATE IDS ---\n")
            for _, entry in ipairs(log.duplicate_ids) do
                output_handle:write(string.format(
                    "# id=%s | section=%s | file=%s | line=%s\n",
                    entry.id,
                    entry.section_name,
                    entry.file_name,
                    entry.line_number
                ))
            end
            output_handle:write("\n")
        end

        if #log.duplicate_names > 0 then
            output_handle:write("# --- DUPLICATE NAMES ---\n")
            for _, entry in ipairs(log.duplicate_names) do
                output_handle:write(string.format(
                    "# name=%s | section=%s | file=%s | line=%s\n",
                    entry.name,
                    entry.section_name,
                    entry.file_name,
                    entry.line_number
                ))
            end
            output_handle:write("\n")
        end
    end

    --------------------------------------------------
    -- SECTION OUTPUT
    --------------------------------------------------
    for _, section in ipairs(SECTION_ORDER) do
        output_handle:write(string.rep("#", 60), "\n")
        output_handle:write("# ", section:upper(), "\n")
        output_handle:write(string.rep("#", 60), "\n")
        output_handle:write(section .. ":")

        local items = merged_sections[section]

        if #items == 0 then
            output_handle:write(" []\n\n")
        else
            output_handle:write("\n")
            for _, entry in ipairs(items) do
                output_handle:write("  " .. entry.configuration_item_text:gsub("\n", "\n  ") .. "\n")
            end
            output_handle:write("\n")
        end
    end

    output_handle:write("#END\n")

    local ok_close, close_err = pcall(function()
        output_handle:close()
    end)

    if not ok_close then
        io.stderr:write("[merge] close failed: " .. tostring(close_err) .. "\n")
    end

    io.stderr:write(
        "[merge] written: " .. OUTPUT_FILE ..
        " | finished at: " .. get_timestamp() .. "\n"
    )
end

--------------------------------------------------
-- WATCH LOOP
--------------------------------------------------
local function watch_directory()
    io.stderr:write("[watch] monitoring: " .. INPUT_DIRECTORY .. "\n")

    local previous_state = directory_state()
    build()

    while true do
        local current_state = directory_state()

        if has_changes(previous_state, current_state) then
            io.stderr:write("[watch] change detected -> rebuilding...\n")

            local success, error_message = pcall(build)
            if not success then
                io.stderr:write("[watch] build error: " .. tostring(error_message) .. "\n")
            else
                io.stderr:write("[watch] build completed at: " .. get_timestamp() .. "\n")
            end

            previous_state = current_state
        end

        os.execute("sleep " .. INTERVAL_SECONDS)
    end
end

watch_directory()