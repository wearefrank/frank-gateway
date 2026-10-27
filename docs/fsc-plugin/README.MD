# FSC Plugin

## Description:
Allows the Frank!Gateway to act as a FSC-Inway 

## Features:
- Register the Frank!Gateway as a FSC-Inway
- Requires clients to provide FSC authorization
- Send logging to the FSC stack 
- Changes status code/Error messages to align with FSC standard
- Registers variables (group_id, direction, created_at, transaction_id, source, destination, service_name, grant_hash to be used by other plugins)

## Requirements:
 - It can only function as a FSC inway
 - The full FSC stack should be set up
 - Inway also should be configured manually within the FSC stack itself  

## Behavior: 

When a request reaches a route using the plugin, it validates the JWT in the `Fsc-Authorization` header with the configured manager public key. It also checks that the token is bound to the presented client certificate, using the certificate's SHA-256 thumbprint, and that the token's group ID matches the configured `fsc_group_id`.

After validation, the plugin requires an `Fsc-Transaction-Id` header and creates an incoming transaction log record from the token claims and request metadata. If `tx_log_url` is configured, it sends that record to the FSC Transaction Log using the configured internal certificate and key. It registers the record fields as APISIX variables so logging plugins can use them.

Authentication failures, group ID mismatches, missing transaction IDs, and transaction-log write failures stop request processing with an FSC-formatted JSON error. The plugin also translates upstream `404` responses into FSC `404` errors and `503` responses into FSC `502` service-unreachable errors. FSC errors include the `Fsc-Error-Code` response header.


## Known issues:

## Configuration:

### Plugin Metadata: 

| Name | Type | Priority |
| --- | --- | --- |
| `fsc` | Generic | `1` |

### Plugin Schema

| Property | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `manager_public_key` | string | Yes | — | PEM-encoded public key used to verify FSC access tokens. |
| `fsc_group_id` | string | Yes | — | FSC group ID expected in the validated access token. |
| `internal_cert_chain` | string | Yes | — | Internal client certificate chain used for Inway registration and optional transaction-log requests. |
| `internal_key` | string | Yes | — | Private key corresponding to `internal_cert_chain`. |
| `registration` | object | Yes | — | Inway registration settings; all nested properties below are required. |
| `registration.controller_uri` | string | Yes | — | HTTPS URI of the FSC controller. |
| `registration.inway_address` | string | Yes | — | Network address at which the Inway can be reached. |
| `registration.inway_name` | string | Yes | — | Inway name registered with the FSC controller. |
| `tx_log_url` | string | No | — | Optional FSC Transaction Log URL. When set, transaction records are sent to this endpoint. |

### Configuration example

Configure the plugin on each route that should use FSC authentication, or globablly if all need it. Replace the PEM placeholders and example FSC values with those for your deployment.

```yaml
routes:
  - uri: /my-service
    upstream:
      type: roundrobin
      nodes:
        "my-service:8080": 1
    plugins:
      fsc:
        manager_public_key: "<PEM-encoded FSC manager public key>"
        fsc_group_id: "<FSC group ID>"
        internal_cert_chain: "<PEM-encoded Inway certificate chain>"
        internal_key: "<PEM-encoded Inway private key>"
        registration:
          controller_uri: "https://controller.example.org"
          inway_address: "https://inway.example.org"
          inway_name: "frank-gateway"
        # Optional: enable transaction-log delivery.
        tx_log_url: "https://transaction-log.example.org/v1/records"
```

### Configuration specifics 

## Examples 