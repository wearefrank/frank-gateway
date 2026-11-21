-- General plugin example template, for more information 
-- see https://apisix.apache.org/docs/apisix/plugin-develop
local core = require("apisix.core")
local plugin_name = "example-plugin"

local schema = {
    type = "object",
    properties = {
        example = {
            type = "string",
        },
    },
    required = { "example" },
}

local consumer_schema = {
    type = "object",
    properties = {
        example = {
            type = "string",
        },
    },
    required = { "example" },
}

local metadata_schema = {
    type = "object",
    properties = {
        ikey = {type = "number", minimum = 0},
        skey = {type = "string"},
    },
    required = {"ikey", "skey"},
}

local _M = {
    version = 0.1, 
    priority = 0, -- Set the plugin priority here, PLEASE DO NOT JUST SET 1, choose an appropriate priority based on your plugin's execution order. https://apisix.apache.org/docs/apisix/plugin-develop/#choose-phase-to-run 
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
    consumer_schema = consumer_schema,
}

function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    end
    return core.schema.check(schema, conf)
end

-- The following functions implement the various plugin phases as defined by APISIX. These are all optional.

function _M.init()
    -- call this function when plugin is loaded
end


function _M.destroy()
    -- call this function when plugin is unloaded
end


function _M.rewrite(conf, ctx)
	-- Implement your rewrite logic here
end


function _M.access(conf, ctx)
   -- Implement your access logic here
end

function _M.header_filter(conf, ctx)
    -- Implement your header filter logic here
end


function _M.body_filter(conf, ctx)
    -- Implement your body filter logic here
end


function _M.delayed_body_filter(conf, ctx)
    -- Implement your delayed body filter logic here
end

function _M.log(conf, ctx)
    -- Implement your log phase logic here
end


function _M.ws_handshake(conf, ctx)
    -- Implement your ws_handshake logic here
end


function _M.ws_client_frame(conf, ctx)
    -- Implement your ws_client_frame logic here
end


function _M.ws_upstream_frame(conf, ctx)
    -- Implement your ws_upstream_frame logic here
end


function _M.ws_close(conf, ctx)
    -- Implement your ws_close logic here
end
