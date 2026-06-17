### Authzen NLGOV plugin

auth-zen is an Apache APISIX authentication plugin that integrates with an external AuthZEN-compatible authorization service following the NLGOV standards to evaluate access decisions before proxying requests upstream.

### The plugin:

- Sends a structured authorization request to an AuthZEN endpoint
- Supports dynamic placeholder lookup using APISIX variables
- Blocks requests by default when authorization fails or the auth service is unavailable
- Optionally forwards selected request headers to AuthZEN
- Optionally forwards selected response headers from AuthZEN upstream
- Supports configurable timeout and TLS verification

### Plugin Metadata
Name	auth-zen

Type	auth

Priority	1999

### Configuration
## Plugin Schema

| Property                    | Type            | Required | Default                   | Description                                 |
|-----------------------------|-----------------|----------|---------------------------|---------------------------------------------|
| `host`                      | `string`        | Yes      | -                         | Base URL of the AuthZEN service             |
| `endpoint`                  | `string`        | No       | `/access/v1/evaluation`   | Authorization evaluation endpoint           |
| `body`                      | `object`        | Yes      | -                         | AuthZEN request body                        |
| `timeout`                   | `integer`       | No       | `3000`                    | Timeout in milliseconds                     |
| `ssl_verify`                | `boolean`       | No       | `true`                    | Enable TLS certificate verification         |
| `send_headers_to_authzen`   | `array[string]` | No       | -                         | Request headers forwarded to AuthZEN        |
| `send_headers_upstream`     | `array[string]` | No       | -                         | Response headers forwarded upstream         |
| `X_Request_Id`              | `string`        | No       | -                         | Optional request ID header                  |

---

## Request Body Structure

The plugin sends the configured `body` object to the AuthZEN service after resolving placeholders from `ctx.var`.

Any string value beginning with $ or containing $variable is resolved using ctx.var. This way, you can retrieve data from the body with a serverless-pre-function and set these as variables 


### Structure

```
{
  "subject": {
    "type": "user",
    "id": "$consumer_name",
    "properties": {
      "ip": "$remote_addr"
    }
  },

  "resource": {
    "type": "api",
    "id": "$uri",
    "properties": {}
  },

  "action": {
    "type": "operation",
    "name": "$request_method",
    "properties": {}
  },

  "context": {
    "request_id": "$request_id"
  }
}
````

## Response

AuthZEN responds with:

Allow
```
{
  "decision": true
}
```

Deny
```
{
  "decision": false
}
```
Deny with Context
```
{
  "decision": false,
  "context": {
    
  }
}
```
The plugin will then block or allow the request depending on the response 


When context exists on deny, it is returned as the response body.

## Header Forwarding
Forward Incoming Headers to AuthZEN
```
"send_headers_to_authzen": [
  "Authorization",
  "X-Forwarded-For"
]
```
These headers are forwarded from the incoming request onto the authorization request to the authzen agent 
#

Forward AuthZEN Response Headers to Upstream
```
"send_headers_upstream": [
  "x-user-id",
  "x-user-role"
]
```
These headers are copied from the AuthZEN response into the upstream request.
