# Soap action router Plugin

## Description:
Allows the Frank!Gateway to route based upon soap action.

## Features:
- Routes based on the SOAP action (in the header, Content-Type, or body)
- Enables routes per specific SOAP operation
- This plugin matches the SOAPAction header or the action in the Content-Type header or body, and adds a header if it matches.

## Requirements:

## Behavior: 
On receiving a request, this plugin is triggered(specifically on the access function) it checks the headers, then the content-type, and lastly the body to find a soap action. If this matches the declared soap action a request is allowed, otherwise a 403 is returned 

## Known issues:
- the plugin falls back upon header and body if it can't find the soap-action in the designed spot, this might cause unintended behavior if the user only wants it to look in one spot 
- Only allows one soap action per endpoint 
- Doesn't do any actual routing 


## Configuration:

### Plugin Metadata: 
Name	<Name>

Type	<Type>

Priority	<Priority>

### Plugin Schema

| Property                    | Type            | Required | Default                   | Description                                 |
|-----------------------------|-----------------|----------|---------------------------|---------------------------------------------|
| <NameOfField>             | <Type>        | <Required>| <DefaultValue>       | <Description>            |
### Configuration example

```yaml 
routes:
  - name: soapaction-test
    id: 1
    uri: /soap/myservice
    plugins:
      soap-action-router:
        match_action: "TestAction"
      proxy-rewrite:
        uri: /any
    upstream_id: 1
    status: 1 


upstreams:
  - name: httpbun
    id: 1
    nodes:
      "httpbun:80": 1
    type: roundrobin

#END
```

### Configuration specifics 

## Examples 