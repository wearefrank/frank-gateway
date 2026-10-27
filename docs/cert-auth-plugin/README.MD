# Cert-auth Plugin

## Description:

The `cert-auth` plugin authenticates a client by matching its TLS client certificate to a configured Frank-Gateway consumer.

## Features:

- Identifies consumers using a certificate's DNS Subject Alternative Name (SAN) or subject serial number.
- Supports matching the certificate Common Name (CN) for existing consumer configurations.
- Works with `consumer-restriction` to authorize authenticated consumers on individual routes.

## Requirements:

- Enable the plugin in `config.yaml`.
- Configure TLS client-certificate authentication so APISIX receives the client's certificate.
- Configure a consumer with either a `cert-auth.identifier` or `cert-auth.cn` value.
- Add `cert-auth: {}` to routes that require certificate authentication.
- Use `consumer-restriction` if access should be limited to specific authenticated consumers.

## Behavior:

The plugin checks the client certificate against configured consumers. It first tries the certificate's DNS SAN and subject serial number against the consumer's `identifier` field, then falls back to the certificate's CN and the consumer's `cn` field.

A missing client certificate returns HTTP `401`. If the certificate has no usable identity or no consumer matches it, the plugin returns HTTP `403`.

## Known issues:

None currently documented.

## Configuration:

### Plugin Metadata:

| Name | Type | Priority |
| --- | --- | --- |
| `cert-auth` | `auth` | `2401` |

### Plugin Schema

The route-level plugin has no configuration fields; enable it with `cert-auth: {}`. The following schema applies to the plugin configuration on a consumer:

| Property | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `cn` | string | Exactly one of `cn` or `identifier` | — | Certificate Common Name (CN) used to identify the consumer. Retained for compatibility. |
| `identifier` | string | Exactly one of `cn` or `identifier` | — | Preferred identity value, matched against the certificate's DNS SAN or subject serial number. |

### Configuration example

```yaml
consumers:
  - username: certuser
    plugins:
      cert-auth:
        identifier: api.example.org

routes:
  - uri: /anything
    plugins:
      cert-auth: {}
      consumer-restriction:
        whitelist:
          - certuser
```

### Configuration specifics

- Configure either `identifier` or `cn` on each consumer; the consumer schema requires exactly one.
- A DNS SAN can be configured as the plain hostname, such as `api.example.org`. The plugin also recognizes values prefixed with `DNS:` or `DNSName:`.
- The plugin authenticates the consumer; `consumer-restriction` is what limits a route to a consumer whitelist.
- For a full local setup and additional context, see [`tests/cert-auth/README.MD`](../../tests/cert-auth/README.MD).

## Examples

The local test configuration demonstrates routes protected by `cert-auth` and restricted to different consumers. It also demonstrates authenticating with a CN-backed consumer before rewriting the request to another URI. See [`tests/cert-auth/apisix-standalone-config.yaml`](../../tests/cert-auth/apisix-standalone-config.yaml).
