# Opa Plugin

## Description:
The Frank!Gateway opa plugin is a patched version of the current Apisix plugin to allow for forwarding of the request body. 

[base documentation](https://apisix.apache.org/docs/apisix/plugins/opa/) 

## Features:
- All base features of the opa plugin
- The body of the request can now be forwarded to opa 

### Additional plugin Schema

| Property                    | Type            | Required | Default                   | Description                                 |
|-----------------------------|-----------------|----------|---------------------------|---------------------------------------------|
| with_body | Boolean | No | False| Forwards the request body to opa|
### Configuration example

```yaml
routes:
  - name: opa-auth-check
    uri: /any/opa-auth
    service_id: 1

services:
  - id: 1
    name: opa-auth-service
    upstream_id: 1
    plugins:
      opa:
        host: http://opa:8181
        policy: apisix/authz/result
        with_body: true
        with_route: true
        send_headers_upstream:
          - x-opa-user

upstreams:
  - id: 1
    name: echo-upstream
    desc: echo API
    type: roundrobin
    nodes:
      "httpbun:80": 1
#END

```

### Configuration specifics 

## Examples 