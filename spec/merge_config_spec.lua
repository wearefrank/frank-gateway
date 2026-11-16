describe("merge-config plugin", function()
	local plugin
	local error_logs
	local info_logs
	local warn_logs
	local schema_check_args
	local local_conf_value
	local vfs_files
	local vfs_written
	local yaml_docs
	local yaml_parse_errors
	local timer_at_calls
	local timer_every_calls
	local shared_dict_store
	local shared_dict
	local os_execute_calls
	local real_io_open
	local real_os_execute

	local INPUT_DIR = "/vfs/mergeconfigs"
	local OUTPUT_FILE = "/vfs/apisix.yaml"

	local function base_conf(overrides)
		local conf = {
			input_directory = INPUT_DIR,
			output_file = OUTPUT_FILE,
			section_order = { "routes", "upstreams" },
		}
		for key, value in pairs(overrides or {}) do
			conf[key] = value
		end
		return conf
	end

	local function add_yaml_file(name, content, parsed)
		vfs_files[INPUT_DIR .. "/" .. name] = content
		yaml_docs[content] = parsed
	end

	before_each(function()
		package.loaded["apisix.core"] = nil
		package.loaded["lfs"] = nil
		package.loaded["lyaml"] = nil
		package.loaded["apisix.plugins.merge-config"] = nil

		error_logs = {}
		info_logs = {}
		warn_logs = {}
		schema_check_args = nil
		local_conf_value = {}
		vfs_files = {}
		vfs_written = {}
		yaml_docs = {}
		yaml_parse_errors = {}
		timer_at_calls = {}
		timer_every_calls = {}
		shared_dict_store = {}
		os_execute_calls = {}

		package.preload["apisix.core"] = function()
			return {
				config = {
					local_conf = function()
						return local_conf_value
					end,
				},
				schema = {
					check = function(schema, conf)
						schema_check_args = { schema = schema, conf = conf }
						return true
					end,
				},
				log = {
					error = function(...) table.insert(error_logs, { ... }) end,
					warn = function(...) table.insert(warn_logs, { ... }) end,
					info = function(...) table.insert(info_logs, { ... }) end,
					debug = function() end,
				},
			}
		end

		package.preload["lfs"] = function()
			return {
				dir = function(path)
					local prefix = path .. "/"
					local names = {}
					for full_path in pairs(vfs_files) do
						if full_path:sub(1, #prefix) == prefix then
							local rest = full_path:sub(#prefix + 1)
							if not rest:find("/", 1, true) then
								table.insert(names, rest)
							end
						end
					end
					local index = 0
					return function()
						index = index + 1
						return names[index]
					end
				end,
			}
		end

		package.preload["lyaml"] = function()
			return {
				load = function(content)
					if yaml_parse_errors[content] then
						error(yaml_parse_errors[content])
					end
					return yaml_docs[content]
				end,
				dump = function(items)
					-- Emulates lyaml document output: one document per item
					local lines = {}
					for _, item in ipairs(items) do
						table.insert(lines, "---")
						local keys = {}
						for key in pairs(item) do
							table.insert(keys, key)
						end
						table.sort(keys)
						for _, key in ipairs(keys) do
							table.insert(lines, key .. ": " .. tostring(item[key]))
						end
						table.insert(lines, "...")
					end
					return table.concat(lines, "\n") .. "\n"
				end,
			}
		end

		shared_dict = {
			add = function(self, key, value, ttl)
				if shared_dict_store[key] ~= nil then
					return false, "exists"
				end
				shared_dict_store[key] = value
				return true
			end,
			delete = function(self, key)
				shared_dict_store[key] = nil
			end,
		}

		_G.ngx = {
			shared = { ["merge-config"] = shared_dict },
			timer = {
				at = function(delay, handler, conf)
					table.insert(timer_at_calls, { delay = delay, handler = handler, conf = conf })
					return true
				end,
				every = function(interval, handler, conf)
					table.insert(timer_every_calls, { interval = interval, handler = handler, conf = conf })
					return true
				end,
			},
			worker = {
				id = function() return 0 end,
			},
		}

		-- Virtual file system: intercept io.open for /vfs paths only
		real_io_open = io.open
		io.open = function(path, mode)
			mode = mode or "r"
			if path:sub(1, 5) ~= "/vfs/" then
				return real_io_open(path, mode)
			end
			if mode:find("w", 1, true) then
				local buffer = {}
				return {
					write = function(self, ...)
						for _, chunk in ipairs({ ... }) do
							table.insert(buffer, tostring(chunk))
						end
					end,
					close = function(self)
						vfs_written[path] = table.concat(buffer)
						return true
					end,
				}
			end
			local content = vfs_files[path]
			if content == nil then
				return nil, path .. ": no such file"
			end
			return {
				read = function(self, format)
					return content
				end,
				close = function(self) return true end,
			}
		end

		real_os_execute = os.execute
		os.execute = function(command)
			table.insert(os_execute_calls, command)
			return true
		end

		plugin = require("apisix.plugins.merge-config")
	end)

	after_each(function()
		io.open = real_io_open
		os.execute = real_os_execute
	end)

	-- -------------------------------------------------------------------------
	-- check_schema
	-- -------------------------------------------------------------------------

	it("delegates schema checks to the plugin schema", function()
		local conf = { enabled = true }

		local ok = plugin.check_schema(conf)

		assert.is_true(ok)
		assert.are.equal(plugin.schema, schema_check_args.schema)
		assert.are.same(conf, schema_check_args.conf)
	end)

	-- -------------------------------------------------------------------------
	-- run_once – merging
	-- -------------------------------------------------------------------------

	it("run_once merges sections from multiple files into the output file", function()
		add_yaml_file("a.yaml", "routes:\n  - id: 1\n    name: route-a\n",
			{ routes = { { id = 1, name = "route-a" } } })
		add_yaml_file("b.yaml", "routes:\n  - id: 2\n    name: route-b\n",
			{ routes = { { id = 2, name = "route-b" } } })

		local result, err = plugin.run_once(base_conf())

		assert.is_nil(err)
		assert.are.same(OUTPUT_FILE, result.output_file)
		assert.are.same(0, result.duplicate_ids)
		assert.are.same(0, result.duplicate_names)

		local output = vfs_written[OUTPUT_FILE]
		assert.is_not_nil(output)
		assert.is_truthy(output:find("# AUTO-GENERATED APISIX CONFIG", 1, true))
		assert.is_truthy(output:find("routes:", 1, true))
		assert.is_truthy(output:find("name: route-a", 1, true))
		assert.is_truthy(output:find("name: route-b", 1, true))
		assert.is_truthy(output:find("upstreams: []", 1, true))
		assert.is_truthy(output:find("#END", 1, true))
	end)

	it("run_once ignores non-yaml files in the input directory", function()
		add_yaml_file("a.yaml", "routes:\n  - id: 1\n    name: route-a\n",
			{ routes = { { id = 1, name = "route-a" } } })
		vfs_files[INPUT_DIR .. "/notes.txt"] = "not yaml"

		local result, err = plugin.run_once(base_conf())

		assert.is_nil(err)
		assert.is_not_nil(result)
		assert.is_truthy(vfs_written[OUTPUT_FILE]:find("name: route-a", 1, true))
	end)

	it("run_once excludes items with duplicate ids and documents them", function()
		add_yaml_file("dup.yaml",
			"routes:\n  - id: 1\n    name: route-a\n  - id: 1\n    name: route-b\n",
			{ routes = { { id = 1, name = "route-a" }, { id = 1, name = "route-b" } } })

		local result, err = plugin.run_once(base_conf())

		assert.is_nil(err)
		assert.are.same(1, result.duplicate_ids)

		local output = vfs_written[OUTPUT_FILE]
		assert.is_truthy(output:find("# --- DUPLICATE IDS ---", 1, true))
		assert.is_truthy(output:find(
			"# id=1 | section=routes | first_file=dup.yaml | first_line=2 | duplicate_file=dup.yaml | duplicate_line=4",
			1, true))
		assert.is_truthy(output:find("name: route-a", 1, true))
		assert.is_falsy(output:find("name: route-b", 1, true))
		assert.is_true(#error_logs > 0)
	end)

	it("run_once excludes items with duplicate names across files", function()
		add_yaml_file("a.yaml", "routes:\n  - id: 1\n    name: same\n",
			{ routes = { { id = 1, name = "same" } } })
		add_yaml_file("b.yaml", "routes:\n  - id: 2\n    name: same\n",
			{ routes = { { id = 2, name = "same" } } })

		local result, err = plugin.run_once(base_conf())

		assert.is_nil(err)
		assert.are.same(1, result.duplicate_names)

		local output = vfs_written[OUTPUT_FILE]
		assert.is_truthy(output:find("# --- DUPLICATE NAMES ---", 1, true))
		assert.is_truthy(output:find("id: 1", 1, true))
		assert.is_falsy(output:find("id: 2", 1, true))
	end)

	-- -------------------------------------------------------------------------
	-- run_once – error handling
	-- -------------------------------------------------------------------------

	it("run_once fails when a YAML file cannot be parsed", function()
		add_yaml_file("broken.yaml", "routes: [", nil)
		yaml_parse_errors["routes: ["] = "unexpected end of stream"

		local result, err = plugin.run_once(base_conf())

		assert.is_nil(result)
		assert.is_truthy(err:find("failed to parse YAML file 'broken.yaml'", 1, true))
		assert.is_true(#error_logs > 0)
	end)

	it("run_once fails when a YAML file is empty", function()
		add_yaml_file("empty.yaml", "", nil)

		local result, err = plugin.run_once(base_conf())

		assert.is_nil(result)
		assert.is_truthy(err:find("failed to read YAML file 'empty.yaml'", 1, true))
	end)

	it("run_once fails when the YAML root is not a mapping", function()
		add_yaml_file("scalar.yaml", "just a string\n", "just a string")

		local result, err = plugin.run_once(base_conf())

		assert.is_nil(result)
		assert.is_truthy(err:find("failed to parse YAML file 'scalar.yaml'", 1, true))
	end)

	it("run_once fails when a section is not a sequence", function()
		add_yaml_file("bad-section.yaml", "routes: nope\n", { routes = "nope" })

		local result, err = plugin.run_once(base_conf())

		assert.is_nil(result)
		assert.is_truthy(err:find("invalid section in file 'bad-section.yaml'", 1, true))
	end)

	-- -------------------------------------------------------------------------
	-- workflow_handler – background timer
	-- -------------------------------------------------------------------------

	it("workflow_handler does not start timers when disabled", function()
		local_conf_value = { plugin_attr = { ["merge-config"] = { enabled = false } } }

		plugin.workflow_handler()

		assert.are.same(0, #timer_at_calls)
		assert.are.same(0, #timer_every_calls)
	end)

	it("workflow_handler does not start timers without plugin_attr config", function()
		local_conf_value = {}

		plugin.workflow_handler()

		assert.are.same(0, #timer_at_calls)
		assert.are.same(0, #timer_every_calls)
	end)

	it("workflow_handler starts an immediate and a recurring timer when enabled", function()
		local_conf_value = {
			plugin_attr = {
				["merge-config"] = base_conf({ enabled = true, interval = 5 }),
			},
		}

		plugin.workflow_handler()

		assert.are.same(1, #timer_at_calls)
		assert.are.same(0, timer_at_calls[1].delay)
		assert.are.same(1, #timer_every_calls)
		assert.are.same(5, timer_every_calls[1].interval)
	end)

	it("workflow_handler starts timers only once", function()
		local_conf_value = {
			plugin_attr = {
				["merge-config"] = base_conf({ enabled = true, interval = 5 }),
			},
		}

		plugin.workflow_handler()
		plugin.workflow_handler()

		assert.are.same(1, #timer_at_calls)
		assert.are.same(1, #timer_every_calls)
	end)

	-- -------------------------------------------------------------------------
	-- timer handler behaviour
	-- -------------------------------------------------------------------------

	local function start_timer_and_get_handler()
		local conf = base_conf({ enabled = true, interval = 5 })
		local_conf_value = { plugin_attr = { ["merge-config"] = conf } }
		plugin.workflow_handler()
		return timer_at_calls[1].handler, timer_at_calls[1].conf
	end

	it("timer handler builds the merged config and releases the lock", function()
		add_yaml_file("a.yaml", "routes:\n  - id: 1\n    name: route-a\n",
			{ routes = { { id = 1, name = "route-a" } } })
		local handler, conf = start_timer_and_get_handler()

		handler(false, conf)

		assert.is_not_nil(vfs_written[OUTPUT_FILE])
		assert.is_nil(shared_dict_store["merge-config-lock"])
	end)

	it("timer handler exits immediately on premature shutdown", function()
		add_yaml_file("a.yaml", "routes:\n  - id: 1\n    name: route-a\n",
			{ routes = { { id = 1, name = "route-a" } } })
		local handler, conf = start_timer_and_get_handler()

		handler(true, conf)

		assert.is_nil(vfs_written[OUTPUT_FILE])
	end)

	it("timer handler skips the run when another worker holds the lock", function()
		add_yaml_file("a.yaml", "routes:\n  - id: 1\n    name: route-a\n",
			{ routes = { { id = 1, name = "route-a" } } })
		shared_dict_store["merge-config-lock"] = 1
		local handler, conf = start_timer_and_get_handler()

		handler(false, conf)

		assert.is_nil(vfs_written[OUTPUT_FILE])
	end)

	it("timer handler logs an error when the shared dict is missing", function()
		local handler, conf = start_timer_and_get_handler()
		ngx.shared["merge-config"] = nil

		handler(false, conf)

		assert.is_nil(vfs_written[OUTPUT_FILE])
		assert.is_true(#error_logs > 0)
	end)

	-- -------------------------------------------------------------------------
	-- init – initial build in master process
	-- -------------------------------------------------------------------------

	it("init does nothing when the plugin is disabled", function()
		local_conf_value = { plugin_attr = { ["merge-config"] = { enabled = false } } }

		plugin.init()

		assert.is_nil(vfs_written[OUTPUT_FILE])
		assert.are.same(0, #os_execute_calls)
	end)

	it("init runs the initial build and makes the output writable", function()
		add_yaml_file("a.yaml", "routes:\n  - id: 1\n    name: route-a\n",
			{ routes = { { id = 1, name = "route-a" } } })
		local_conf_value = {
			plugin_attr = { ["merge-config"] = base_conf({ enabled = true }) },
		}

		plugin.init()

		assert.is_not_nil(vfs_written[OUTPUT_FILE])
		assert.are.same("chmod 666 " .. OUTPUT_FILE, os_execute_calls[1])
	end)

	it("init logs an error when the initial build fails", function()
		add_yaml_file("broken.yaml", "routes: [", nil)
		yaml_parse_errors["routes: ["] = "unexpected end of stream"
		local_conf_value = {
			plugin_attr = { ["merge-config"] = base_conf({ enabled = true }) },
		}

		plugin.init()

		assert.is_nil(vfs_written[OUTPUT_FILE])
		assert.is_true(#error_logs > 0)
		assert.are.same(0, #os_execute_calls)
	end)
end)
