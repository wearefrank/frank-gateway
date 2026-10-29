# Soap action router Plugin

## Description:
Allows the Frank!Gateway to route based upon soap action.

## Features:
- Routes to upstream based on the SOAP action (in the header, Content-Type, or body)

## Requirements:

## Behavior: 
On receiving a request, this plugin is triggered(specifically on the access function) it checks the headers, then the content-type, and lastly the body to find a soap action. It then checks the schema to find the related upstream. 

## Known issues:
- Adding a plugin specific per soap action might be needed, for example to trigger a rewrite on specific actions(this might be better as a seperate plugin)
- Multiple actions for one upstream currently requires adding seperate entries
- Sending to a service instead of upstream might be needed and is no longer supported

## Configuration:

### Plugin Metadata: 
Name:	soap-action-router
Type:	generic
Priority: 967

### Plugin Schema

| Property                    | Type            | Required | Default                   | Description                                 |
|-----------------------------|-----------------|----------|---------------------------|---------------------------------------------|
| <NameOfField>             | <Type>        | <Required>| <DefaultValue>       | <Description>            |
| routes | array | Yes | - | List of all possible routes | 
| route.upstream_id | string | Either upstream_id or upstream| - | The upstream the soap action should be routed to|
| route.upstream | object | Either upstream_id or upstream| - | The upstream the soap action should be routed to|
| route.soap_action | string | yes | - | The soap action that the route should match| 

### Configuration example

```yaml 
routes:
  - name: traffic-split-service
    uri: /soap/myservice
    plugins:
          proxy-rewrite:
               uri: /anything
          soap-action-router:
               routes:
                  - soapAction: testTwo
                    upstream_id: testTwo
                  - soapAction: testOne
                    upstream_id: testOne
upstreams:
  - name: httpbun
    scheme: http
    pass_host: node
    id: testOne
    nodes:
      "httpbun:80": 1
    type: roundrobin
  - name: httpbun
    scheme: http
    id: testTwo
    nodes:
      "httpbun:80": 1
    type: roundrobin


#END
```

### Configuration specifics 

## Examples 