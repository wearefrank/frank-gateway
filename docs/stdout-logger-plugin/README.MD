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
| log_output | en
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