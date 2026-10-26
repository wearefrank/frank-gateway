# Authzen NLGOV plugin

## Description: 
auth-zen is a Frank!Gateway authentication plugin that integrates with an external AuthZEN-compatible authorization service following the NLGOV standards to evaluate access decisions before proxying requests upstream.

## Features:

- Sends a structured authorization request to an AuthZEN endpoint
- Supports dynamic placeholder lookup using Frank!Gateway variables
- Blocks requests by default when authorization fails or the auth service is unavailable
- Optionally forwards selected request headers to AuthZEN
- Optionally forwards selected response headers from AuthZEN upstream
- Supports configurable timeout and TLS verification

## Requirements:
- Enabled in the config.yaml 
- Requires a seperate Authzen server
-

## Behavior:
Can be configured on a Route, Consumer or Globally. 
The plugin sends the configured values(for example fields in the body) and lets the PDP decide if the request is allowed or not. The plugin then checks the value of decision in the response body, if this value is false, the gateway will return a 403.  If this request fails in some way, it will return a 503

## Known issues

## Configuration

### Plugin Metadata
Name	auth-zen

Type	auth

Priority	1999

### Options

Configure these options under `plugins.auth-zen` on a Route, Consumer, or globally. `host` and `body` are required.

| Option | Required | Description | Default |
| --- | --- | --- | --- |
| `host` | Yes | Base URL of the AuthZEN service, such as `https://authzen.example.com`. | — |
| `endpoint` | No | Path appended to `host` for the authorization request. | `/access/v1/evaluation` |
| `body` | Yes | JSON object sent to AuthZEN. It must include `subject`, `resource`, and `action`; see [Request Body Structure](#request-body-structure). | — |
| `timeout` | No | Timeout for the AuthZEN request, in milliseconds. Must be a positive integer. | `3000` |
| `ssl_verify` | No | Verify the AuthZEN service's TLS certificate. | `true` |
| `pdp_auth` | No | Authentication used when calling the PDP. See the examples below. | None |
| `send_headers_to_authzen` | No | Incoming request headers to copy to the AuthZEN request. Only headers present in the request are forwarded. | None |
| `send_headers_upstream` | No | AuthZEN response headers to copy into the request sent upstream. Only headers present in the PDP response are copied. | None |
| `x_request_id` | No | Value to send to AuthZEN in the `X-Request-ID` header. Supports a variable placeholder. | None |

### Configuration examples

Basic configuration:

```json
{
  "host": "https://authzen.example.com",
  "body": {
    "subject": {
      "type": "user",
      "id": "$consumer_name"
    },
    "resource": {
      "type": "api",
      "id": "$uri"
    },
    "action": {
      "name": "$request_method"
    }
  }
}
```

Bearer authentication can be configured with a literal token or a variable. `bearer_header` and `bearer_prefix` are optional and default to `Authorization` and `Bearer `:

```json
{
  "pdp_auth": {
    "mode": "bearer",
    "bearer_token": "$http_x_pdp_token"
  }
}
```

For mutual TLS, enable `mtls` and provide both the PEM-encoded client certificate and private key. Bearer authentication and mTLS may be used together:

```json
{
  "pdp_auth": {
    "mode": "none",
    "mtls": {
      "enabled": true,
      "client_cert": "$authzen_client_cert",
      "client_key": "$authzen_client_key"
    }
  }
}
```

To forward request headers to AuthZEN or copy response headers to the upstream request, configure lists of header names:

```json
{
  "send_headers_to_authzen": [
    "Authorization",
    "X-Forwarded-For"
  ],
  "send_headers_upstream": [
    "x-user-id",
    "x-user-role"
  ],
  "x_request_id": "$request_id"
}
```

---

### Request Body Structure

The plugin sends the configured `body` object to the AuthZEN service after resolving placeholders from `ctx.var`.

Any string value beginning with $ or containing $variable is resolved using ctx.var. This way, you can retrieve data from the body with a serverless-pre-function and set these as variables 


### Examples

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
```

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

### Header Forwarding
Forward Incoming Headers to AuthZEN
```
"send_headers_to_authzen": [
  "Authorization",
  "X-Forwarded-For"
]
```
These headers are forwarded from the incoming request onto the authorization request to the authzen agent 


Forward AuthZEN Response Headers to Upstream
```
"send_headers_upstream": [
  "x-user-id",
  "x-user-role"
]
```
These headers are copied from the AuthZEN response into the upstream request.
