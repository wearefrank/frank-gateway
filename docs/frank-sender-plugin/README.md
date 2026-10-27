# Frank-sender Plugin

## Description:

the `frank-sender` sends the incoming request to a configured Frank endpoint first, reads Frank's response body, and replaces the original request body with that response body before the request continues to the configured upstream.

In short: it is a pre-processing step that can transform payloads.

## Features:
- Request payload transformation before the actual upstream receives the request.
- Centralized translation/mapping logic in an external Frank service.
- Reusing the same transformation behavior across multiple routes.

## Requirements:

## Behavior

In the `access` phase, the plugin currently does the following:

1. Reads the incoming request body.
2. Parses `frank_endpoint`.
3. Builds an HTTP request to Frank using:
   - The incoming HTTP method.
   - Incoming request headers.
   - Incoming request body (if present).
   - Query string from `frank_endpoint` (if present).
4. Calls Frank via `resty.http`.
5. Reads Frank's response body.
6. Replaces the Gateway in-flight request body with Frank's response body.
7. Continues normal routing to the configured upstream.

## Known issues: 

- TLS verification is disabled for the Frank call (`ssl_verify = false`).
- Non-200 responses from Frank are logged as errors, but processing is not explicitly aborted.
- Response headers from Frank are not copied to the in-flight request.
- Query parameters from the original request URL are not explicitly forwarded unless present in copied headers or body.
- Error handling can be improved because `assert(httpc:request(...))` may raise and stop request processing.


## Configuration

### Plugin Metadata 
| Name | Type | Priority |
| --- | --- | --- |
| `frank-sender` | `default` | `1` |

### Plugin Schema

The plugin has one required field:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| frank_endpoint | string | Yes | Full URL of the Frank service endpoint that receives the request copy and returns the transformed body |

### Configuration Example 

```yaml
routes:
  - name: frank-test
    id: 3
    uri: /frank-sender
    upstream_id: 1
    plugins:
      proxy-rewrite:
        uri: /any
      frank-sender:
        frank_endpoint: http://host.docker.internal:8080/api/frank-test
```




