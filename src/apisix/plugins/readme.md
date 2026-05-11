For developing custom plugins, follow these guidelines.

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

For an auth plugin, for example:

- No token -> returns `403`
- Unauthorized token -> returns `403`
- Valid token -> returns `200`