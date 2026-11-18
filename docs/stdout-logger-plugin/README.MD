# Std out logging Plugin

## Description:
Allows the user the define a custom format for logging to the console within apisix

## Features:
- Allows for defining a custom log format 
- Allows for setting log output 
- Allows for setting log labels 
- Has a similiar schema to Loki-Logger plugin to allow for easy switching 
- Allows for passing response/request body and headers 
- Can be set on a specific route/consumer or globablly 


## Requirements:
- If a external logging stack is used, this most likely needs to be configured to properly read the log labels 

## Behavior: 
Allows for custom logging to the console instead of logging. The plugin hooks into the access and filter methods of apisix to collec data about the request, the logging is then triggered upon the "log" lifecycle method of apisix. 

## Known issues:

## Configuration:

### Plugin Metadata: 
Name: stdout-logger

Type: Logging

Priority: 430

### Plugin Schema

| Property                    | Type            | Required | Default                   | Description                                 |
|-----------------------------|-----------------|----------|---------------------------|---------------------------------------------|
| log_format | object | Yes | - | Template for each log line. String leaf values starting with '$' are resolved as APISIX/nginx variables, other leaf values (and nested objects) are copied as-is | 
| labels | object | No | - |  Key-value map of log labels. String leaf values starting with '$' are resolved as APISIX/nginx variables, other leaf values (and nested objects) are copied as-is|
| include_req_body | boolean | No | false | Makes the request body available as variable in your log, under $request_body|
| include_req_body_expr | array | No | - | Makes the request body available as variable in your log, only if expression evaluates as true, under $request_body| 
| include_resp_body | boolean | No | false | Makes the response body available as variable in your log, under $response_body|
| include_resp_body_expr | array | No | - | Makes the response body available as variable in your log, only if expression evaluates as true, under $response_body| 
| include_req_headers | boolean | No | false | Makes the request headers available as variable in your log, under $request_headers|
| include_resp_headers | boolean | No | false | Makes the response headers available as variable in your log, under $response_headers|



### Configuration example
```yaml
routes:
  - id: 1
    name: upstream-test
    uri: /*
    upstream_id: 1
    status: 1
    plugins:
      stdout-logger:
        log_output: json
        labels:
          log_type: "$log_type"
          env: "prod"
        log_format:
          log_type: "$log_type"        
          timestamp: "$time_iso8601"
          gemeente_code: "1234"
          request:
            request_method: "$request_method"
            request_path: "$uri"
            request_host: "$host"
            request_body: "$request_body"
            request_headers: "$request_headers"
          response:
            status: "$status"
            upstream_latency_ms: "$upstream_response_time"
            response_body: "$response_body"
            response_headers: "$response_headers"
          audit:
            route_id: "$route_id"
        include_req_body: true
        include_resp_body: true
        include_req_headers: true
        include_resp_headers: true
```

### Configuration specifics 

## Examples

The Stdout Logger plugin writes one structured JSON log line per request to the container's stdout. `log_format` is a template: string leaf values starting with `$` are resolved as APISIX/nginx variables or plugin pseudo-variables, while other leaf values and nested objects are copied as-is.

An optional `labels` map is output as a dedicated key-value map under `"labels"` in the serialized JSON log entry. String leaf values starting with `$` inside `labels` are also resolved as variables.

The plugin exposes pseudo-variables that can be referenced from `log_format` or `labels`:
- `$request_body` / `$response_body`: populated only when `include_req_body`/`include_resp_body`, or the matching `include_req_body_expr`/`include_resp_body_expr`, is set
- `$request_headers` / `$response_headers`: populated only when `include_req_headers`/`include_resp_headers` is set
- `$log_type`: always set to `Error` (status >= 500), `Warn` (status >= 400), or `Info` (otherwise)

### Basic configuration

```yaml
stdout-logger:
  log_output: json
  labels:
    log_type: "$log_type"
    env: "production"
    route_id: "$route_id"
  log_format:
    timestamp: "$time_iso8601"
    request:
      method: "$request_method"
      path: "$uri"
```

The `_expr` options accept an APISIX-style condition rule evaluated via `resty.expr.v1`, so body capture can be conditional. For example, capture the response body only for failed requests:

```yaml
stdout-logger:
  include_resp_body_expr:
    - ["status", ">=", 400]
```

Example configuration and tests can be found [here](../../tests/stdout-logger/apisix.yaml).