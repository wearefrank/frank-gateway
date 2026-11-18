# Private key JWT client and JWKS publisher

## Description

`private-key-jwt-client` authenticates the gateway to an OAuth 2.0 token endpoint using `private_key_jwt` and sends the resulting bearer token to the upstream. `jwks-publisher` serves the corresponding public RSA keys as a JWKS.

The implementation uses RS256 and OAuth client credentials. Confirm that Wigo4it supports RS256, the assertion audience, and the required scopes when its non-production configuration becomes available. The new connection does not use mTLS; this does not change existing Socrates connections.

## Requirements

- A 2048-bit or larger RSA private key in unencrypted PEM format, and its matching PEM public key.
- A registered client ID and a publicly reachable HTTPS JWKS URL registered with the authorization server. The ingress and DNS are deployment responsibilities.
- HTTPS and a trusted certificate for the token endpoint. TLS verification is always enabled.
- The `private-key-jwt-client-cache` shared dictionary when caching is enabled; it is included in the repository's APISIX configuration.
- Accurate gateway system time.

Generate and store the private key securely outside source control. For example, derive the public key from an existing private key with `openssl pkey -in private.pem -pubout -out public.pem`. Supply the private PEM through a Kubernetes Secret and the public PEM through a deployment variable or configuration. Never put the private key in the JWKS route.

## Behavior

For each token request the client signs an assertion with `iss` and `sub` equal to the client ID, `aud` equal to the configured audience or token endpoint, a 60-second expiration, and a random `jti`. It posts `grant_type`, `client_id`, `client_assertion_type`, `client_assertion`, and optional `scope` as form-urlencoded data.

On success the plugin **replaces** the request's `Authorization` header with the acquired bearer token. Tokens with a usable `expires_in` greater than 30 seconds are cached for at most `expires_in - 30` seconds, capped at one day. Tokens without a usable lifetime are not cached. Cache entries are isolated by endpoint, client, signing key, key ID, audience and scope. Errors stop the request; assertions and tokens are not logged.

The JWKS route accepts GET and publishes only the public modulus and exponent. It supports multiple keys for rotation. Set distinct `kid` values, publish the new public key before switching the signing key, and retain the old public key until the authorization server has refreshed its JWKS cache and the old assertions can no longer be used. Coordinate timing with Wigo4it.

## Configuration

| Plugin | Priority | Purpose |
| --- | --- | --- |
| `private-key-jwt-client` | 0 | Acquire and attach an OAuth bearer token after the FSC plugin |
| `jwks-publisher` | 1 | Serve public signing keys |

### `private-key-jwt-client`

| Property | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `token_endpoint` | string | Yes | — | HTTPS token endpoint, including any query string. |
| `client_id` | string | Yes | — | Registered OAuth client ID. |
| `private_key` | string | Yes | — | PEM RSA private key; use secret management. |
| `kid` | string | Yes | — | Key ID matching the corresponding JWKS entry. |
| `audience` | string | No | `token_endpoint` | Assertion audience; use the value required by the authorization server. |
| `scope` | string | No | — | OAuth scope parameter. |
| `use_cache` | boolean | No | `true` | Reuse tokens with a valid lifetime. |
| `timeout` | integer | No | `5000` | Token request timeout in milliseconds, between 1 and 60000. |

### `jwks-publisher`

| Property | Type | Required | Description |
| --- | --- | --- | --- |
| `keys` | array | Yes | One or more objects with unique `kid` and PEM `public_key` strings. |

### Example

This is an APISIX standalone configuration example, not a live Socrates deployment. Add the environment variables using the Helm chart's `extraEnvVars`; obtain the private key from a Kubernetes `secretKeyRef`. Replace URLs, scopes and IDs after registration. Route the JWKS URL through a publicly reachable HTTPS ingress, separately from any authenticated business route.

```yaml
routes:
  - name: oauth-public-keys
    uri: /.well-known/jwks.json
    methods: [GET]
    plugins:
      jwks-publisher:
        keys:
          - kid: "signing-key-1"
            public_key: ${{OAUTH_PUBLIC_KEY}}

  - name: new-socrates-api
    uri: /new-socrates/*
    plugins:
      private-key-jwt-client:
        token_endpoint: "https://authorization.example.org/oauth/token"
        client_id: "registered-client-id"
        private_key: ${{OAUTH_PRIVATE_KEY}}
        kid: "signing-key-1"
        scope: "replace-with-registered-scope"
    upstream:
      type: roundrobin
      scheme: https
      tls:
        verify: true
      nodes:
        "api.example.org:443": 1
#END
```

For example, the private key environment variable can be populated in the Helm values:

```yaml
extraEnvVars:
  - name: OAUTH_PRIVATE_KEY
    valueFrom:
      secretKeyRef:
        name: oauth-signing-key
        key: private.pem
```

Ensure that `OAUTH_PUBLIC_KEY` contains the public key corresponding to that private key. Changing either key or the `kid` requires coordinated deployment and registration; a mismatch causes token requests to fail.

## Local integration tests

Run `docker compose -f tests/private-key-jwt-client/docker-compose.yaml up -d --build`, then run the Bruno collection in `tests/bruno/private-key-jwt-client` in sequence using the `local` environment. The collection is also included in `run-all-tests.bat`. Stop the test environment and remove its generated test keys with `docker compose -f tests/private-key-jwt-client/docker-compose.yaml down --volumes`.

The setup generates disposable RSA and TLS keys in a Docker volume. A mock HTTPS identity provider checks the assertion signature against the gateway's JWKS, claims and form fields; it also acts as the upstream. These fixtures are for local testing only, not Wigo4it credentials or endpoints.
