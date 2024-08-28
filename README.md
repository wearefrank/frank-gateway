# frank-api-gateway

The Frank API Gateway is based on Apache APISIX, see https://apisix.apache.org/ for an introduction to Apache APISIX.

The main characteristics of Apache APISIX are:
- Fully Open Source – part of the Apache foundation as a top level project with large contributor base
- Run everywhere (including ARM64)
    - Bare metal
    - Kubernetes
    - Cloud
    - VM
- Pluggable configuration based on a rich plugin ecosystem
- Top ranked for performance

The Frank API Gateway is a superset of Apache APISIX.
- Improved functionality for SOAP services
    - Routing based on SOAP action
    - Analytics based on SOAP action
- FSC NLX Inway
    - Can act as a Inway in a FSC NLX group
    - Can combine the FSC NLX Inway with different APISIX plugins 

## Layout & Structure
This repository contains two components:
1) deployment configurations & examples which can be found on the directory `deployment-examples`
2) source code for custom plugins

### Building the images
The Frank!Gateway can be built using the following command:
```shell
docker build --build-arg BUILD_DATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ') -t frank-api-gateway .
```

The accompanying dashboard can be built with the following command:
```shell
docker build -f dashboard/Dockerfile --build-arg BUILD_DATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ') -t frank-api-dashboard .
``` 

### Deployment configurations & examples
The directory `deployment-examples` contains four deployment scenarios for deploying APISIX. Note, this deploys vanilla APISIX without the FSC plugin.
The goal of these deployment examples is for experimenting with Apache APISIX in different deployment approaches.

Without any prior Apache APISIX experience it is recommended to start with the `docker-compose` deployment-example since this is the easiest one to get started.

The `docker-compose deployment` does contain the `improved SOAP functionality` mentioned above. 

- docker-compose -> deploys APISIX via Docker compose [instructions](deployment-examples/docker-compose/README.md)
- kind -> deploys APISIX in normal mode on a local Kubernetes cluster using Kind [instructions](deployment-examples/kind/README.md)
- kind-ingress -> deploys APISIX as a Kubernetes ingress on a local cluster using Kind [instructions](deployment-examples/kind-ingress/README.md)
- rancher -> deploys APISIX as a Kubernetes ingress on the WAF rancher cluster [instructions](deployment-examples/rancher/README.md)

### Custom plugins
Custom plugins have been created for the Frank!Gateway enhancing the functionality.

The following plugins have been created:
1) FSC
2) SOAP action router
3) OIDC client
4) Limit size

#### FSC 
The FSC plugin:
- Can act as a Inway in a FSC NLX group
- Can combine the FSC NLX Inway with different APISIX plugins 

Detailed documentation on the FSC plugin and how to run and test the FSC plugin locally can be found [here](deployment-examples/fsc/FSC-NLX.md)

#### SOAP action router
APISIX can create routing rules based on HTTP headers. However, within SOAP the specific operation is determined by the SOAP action, this SOAP action can either be in a HTTP header, Content-Type header or body.
The plugin can extract the SOAP action and trigger the router enabling the possibility to create routes per SOAP action.

Detailed documentation on the SOAP action router can be found [here](deployment-examples/docker-compose/README.md)

#### OIDC client
APISIX has existing OpenID connect and JWT plugins, but these plugins are for protecting routes. In these plugins the clients of APISIX need to authenticate and APISIX checks the access tokens.
The OIDC client plugin enables the Frank!Gateway to a OIDC client that can authenticate with a external IDP and use the client_credentials flow to authenticate with a upstream.

Detailed documentation on the OIDC client can be found here [here](deployment-examples/oidc-client/OIDC-client.md)

#### Limit size
blocks either requests and or responses if the payload or entire request or response is larger than a pre-configured threshold.