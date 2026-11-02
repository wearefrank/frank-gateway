# Limit size Plugin

## Description:
Allows the Frank!Gateway to put a limit on the size of incoming requests.

## Features:
- Limit the max size of a request 
- Specify if only the body should be counter
- set a rejected code 
- set a rejection message 

## Requirements:

## Behavior: 
On an incoming request, calculates the size of specified part(Whole request/body). If it's bigger then the specified value, returns specified error code(On default 413)
## Known issues:
- request_limit_unit is case sensitive 

## Configuration:

### Plugin Metadata: 
Name: limit-size 
Type: generic 
Priority: 1

### Plugin Schema

| Property                    | Type            | Required | Default                   | Description                                 |
|-----------------------------|-----------------|----------|---------------------------|---------------------------------------------|
| request_limit | Integer | No | - | The limit of the request | 
| request_limit_unit | Enum | No | bytes | unit of the limit, can be bytes, kilobytes, megabytes. This field is case sensitive! |
| full_request | Boolean | No | false | when set to false it only checks the request body. When set to true it checks the entire HTTP request |
| response_limit | Integer | No | - | The limit of the response | 
| response_limit_unit | Enum | No | bytes | unit of the limit, can be bytes, kilobytes, megabytes. This field is case sensitive! |
 | full_response | Integer | No | - | Omit to check only the response body. Any configured integer, including 0, selects the full-response check; boolean values are not accepted by the current schema. |
| rejected_code | Integer | No | 413 | The status code that is used for a blocked request, can be a value between 200 and 599 |
| rejected_msg | String | No | size is too large | The message that is returned upon a blocked request | 
 
### Configuration example
```yaml
routes:
  - name: post-limit-size-test
    id: 1
    uri: /bytes/*
    methods:
      - POST
    plugins:
      limit-size:
        request_limit: 300
        request_limit_unit: bytes
        full_request: false         # count request body
    upstream_id: 1
    status: 1
```

### Configuration specifics 

## Examples 