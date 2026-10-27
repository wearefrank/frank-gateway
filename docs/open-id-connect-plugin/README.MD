# OpenID Connect Client Plugin

## Description:
This plugin allows for connecting to upstreams requiring OpenID Connect authorization. It makes a request to a separate identity provider to obtain a token, and uses this token to authenticate to the upstream

## Features:
- Obtain a token from a separate identity provider using the client credentials flow
- Optionally enable SSL verify for identity provider
- Configure client ID and client secret
- Caching of token
- Add optional scope and resource server to token request

## Requirements:
- Configure the `openid-connect-client-cache` shared dictionary in APISIX; the plugin writes acquired tokens to it.

## Behavior:

For each request, the plugin looks for a cached access token using `client_id` as the cache key. When `use_cache` is enabled and a token is present, it sets the upstream `Authorization` header to use that access token.

If there is no usable cached token, the plugin sends a POST request to `token_endpoint` with a form-urlencoded body containing `client_id`, `client_secret`, and `grant_type`. If configured, `scope` and `resource_server` (sent as `resourceServer`) are added as additional parameters. On a successful HTTP 200 response, it reads `access_token` and `expires_in` from the JSON response, caches the token for the supplied expiration (or `default_expiration` if none is supplied), and sets the upstream `Authorization` header using the access token. Setting `use_cache: false` skips cache reads, but the plugin still writes acquired tokens to the shared dictionary. Connection errors and non-200 identity-provider responses stop request processing and return an error.

## Known issues:

## Configuration:

### Plugin Metadata:

| Name | Type | Priority |
| --- | --- | --- |
| `openid-connect-client` | Generic | `1` |

### Plugin Schema

| Property | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `token_endpoint` | string | Yes | — | URL of the identity provider's token endpoint. |
| `client_id` | string | Yes | — | Client ID configured for the client in the identity provider. |
| `client_secret` | string | Yes | — | Client secret configured for the client in the identity provider. |
| `grant_type` | string | Yes | `client_credentials` | OAuth grant type. This plugin supports the client credentials flow. |
| `ssl_verify` | boolean | No | `false` | Whether to verify the identity provider's TLS certificate. |
| `use_cache` | boolean | No | `true` | Whether to use a cached access token when available. |
| `default_expiration` | integer (1–100000) | No | `300` seconds | Cache lifetime in seconds when the identity-provider response does not include `expires_in`. |
| `scope` | string | No | — | Optional scope sent in the token request. |
| `resource_server` | string | No | — | Optional resource server sent in the token request. |

### Configuration example

This example enables token caching and TLS certificate verification for the identity provider. Replace the endpoint and placeholder credentials with deployment-specific values.

```yaml
services:
  - id: 1
    name: protected-service
    upstream:
      type: roundrobin
      nodes:
        "api.example.org:443": 1
    plugins:
      openid-connect-client:
        token_endpoint: "https://identity.example.org/realms/example/protocol/openid-connect/token"
        client_id: "<client-id>"
        client_secret: "<client-secret>"
        grant_type: "client_credentials"
        ssl_verify: true
        use_cache: true
        default_expiration: 300

routes:
  - uri: /protected/*
    service_id: 1
```

### Configuration specifics

- The token request uses `application/x-www-form-urlencoded`; configured values are URL-encoded.
- A successful identity-provider response must be JSON containing `access_token`. The optional `expires_in` value determines the token's cache lifetime; `default_expiration` is used when it is absent.
- Tokens are cached by `client_id` in the `openid-connect-client-cache` shared dictionary. Ensure this dictionary is configured in APISIX, even when `use_cache` is disabled, because acquired tokens are still written to it.
- TLS verification for the identity provider is disabled by default. Set `ssl_verify: true` when the endpoint uses a certificate trusted by the gateway.
- Keep credentials such as client secrets out of source control; use your deployment's secret-management mechanism.
