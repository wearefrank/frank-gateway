For developing custom plugins, follow these guidelines.
# Integration Testing

## 1. Create a test environment

Create a single dedicated test environment that can be used for:

- Automated testing pipelines
- Local development

To do this, create a folder under `tests` using the plugin name. Include a `docker-compose.yaml` and the relevant configuration files.

## 2. Add a Bruno collection

Add a Bruno collection under `tests/bruno`.

Each plugin must have its own collection file so it can be detected by the test setup.

Example collection file(this is all you need for most plugins):

```json
{
  "version": 1,
  "name": "plugin-name",
  "type": "collection"
}
```

## 3. Add Bruno environment files

Define both `docker.bru` and `local.bru`.

`docker.bru`:

```text
vars {
  baseUrl: http://host.docker.internal:9080
}
```

`local.bru`:

```text
vars {
  baseUrl: http://127.0.0.1.nip.io:9080
}
```

## 4. Add requests and tests

Add relevant requests and tests to the Bruno collection.

You do not need to cover every edge case, but include at least:

- A happy scenario
- A failure scenario

For example, for an auth plugin:

- No token -> returns `403`
- Unauthorized token -> returns `403`
- Valid token -> returns `200`

# Unit Testing

### 1. Shared test-runner Dockerfile

A single `spec/Dockerfile` installs Lua 5.1, LuaRocks and Busted. It is shared across all plugin test suites.

```dockerfile
FROM alpine:3.20

RUN apk add --no-cache \
    lua5.1 \
    lua5.1-dev \
    luarocks \
    gcc \
    musl-dev \
    make

RUN luarocks-5.1 install busted

WORKDIR /frank-gateway

CMD ["busted", "spec"]
```

### 2. Add the `lua-unit-test` service to the plugin's `docker-compose.yaml`

Each plugin has a compose file under `tests/<plugin-name>/docker-compose.yaml`. Add the following service to it. The `context` is the repository root so the `spec/Dockerfile` can be resolved and the entire repo is mounted into the container.

```yaml
lua-unit-test:
  build:
    context: ../../
    dockerfile: spec/Dockerfile
  volumes:
    - ../../:/frank-gateway
  working_dir: /frank-gateway
  command: ["busted", "spec"]
  networks:
    apisix:
```

### 3. Spec file location and naming

Place the spec file next to the other specs in `spec/`. Busted discovers files automatically by the `_spec.lua` suffix.

```
spec/
  my_plugin_spec.lua       ← unit tests live here
src/
  apisix/plugins/
    my-plugin.lua
```

### 4. Mock dependencies in `before_each`

Plugins `require` APISIX runtime modules (`apisix.core`, `resty.http`, etc.) that are not available outside of NGINX. Stub them before requiring the plugin:

```lua
before_each(function()
    -- 1. Clear cached modules so tests are isolated from each other
    package.loaded["apisix.core"] = nil
    package.loaded["apisix.plugins.my-plugin"] = nil
    -- ... clear any other modules the plugin requires

    -- 2. Register lightweight fakes
    package.preload["apisix.core"] = function()
        return {
            schema = { check = function(...) return true end },
            log    = { info = function() end, error = function() end },
            -- add whatever the plugin calls
        }
    end

    -- 3. Stub _G.ngx if the plugin reads ngx.var / ngx.req
    --    If the plugin does `local ngx = require("ngx")`, register a preload instead:
    package.preload["ngx"] = function()
        return { req = { get_headers = function() return {} end } }
    end

    -- 4. Require the plugin last, after all stubs are registered
    plugin = require("apisix.plugins.my-plugin")
end)
```

### 5. Write the unit tests

Test each meaningful branch of the plugin:

```lua
it("returns 401 when no credential is present", function()
    local status, body = plugin.access({}, {})
    assert.are.same(401, status)
end)
```

### 6. Run the tests

From the repository root:

```bash
docker compose -f tests/<your-plugin>/docker-compose.yaml run --rm lua-unit-test
```

> ❗ This runs **all** `*_spec.lua` files found in the `spec/` folder, not only the tests for the plugin whose compose file you specified. A single run validates the entire unit-test suite.