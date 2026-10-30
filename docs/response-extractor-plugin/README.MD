# Response extractor Plugin

## Description:
A plugin to extract values from JSON responses to be used later by plugins and logging 

## Features:
- Extracts values from JSON responses using JSONPath
- Makes them available as context variables for downstream plugins and logging

## Requirements:


## Behavior: 
Is triggered on incoming requests(specifically within the body filtering) Checks content type, if it matches it adds the required variables to the session to be used by later plugins. 
If in any part the extraction process fails, the results are skipped. 

## Known issues:
- Perhaps it should send internal server error if response extraction fail, or atleast give the option to. 
- The priority might be too high, should maybe be set lower so it executes before logging plugins?(Not encounted issues yet)
## Configuration:

### Plugin Metadata: 
Name: response-extractor
Type: generic 
Priority: 1000 

### Plugin Schema

| Property                    | Type            | Required | Default                   | Description                                 |
|-----------------------------|-----------------|----------|---------------------------|---------------------------------------------|
| <NameOfField>             | <Type>        | <Required>| <DefaultValue>       | <Description>            |
| fields | object <key>:<value | Yes | - | The fields to be retrieved, json path can be used here to retrieve a value. |
| max_body_size | Integer |No |1048576 | The max body size in bytes |   
|content_types | Array | No | ["application/json"] | content types that are allowed in the response| 
### Configuration example
```yaml
    plugins:
      response-extractor:
        fields:
          ip: "$.headers['X-Real-Ip']"
      file-logger: 
        path: /usr/local/apisix/logs/response.log
        log_format:
          ip: $ip

```

### Configuration specifics 

## Examples 