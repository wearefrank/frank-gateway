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

### Minimum requirements
**Minimum:**
| Resource | Minimum                            |
| -------- | ---------------------------------- |
| CPU      | 1 vCPU                             |
| Memory   | 256–512 MB RAM                     |
| Storage  | 1+ GB container image + logs       |

**Recommended:**
| Resource | Recommended                        |
| -------- | ---------------------------------------- |
| CPU      | 2 vCPU                                   |
| Memory   | 1–2 GB RAM                               |
| Storage  | 1+ GB container image + logs             |


### Versioning and Release strategy

Versioning & Release Strategy

This project follows Semantic Versioning (SemVer):
```
MAJOR.MINOR.PATCH
```
Example:
```
v1.2.3
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
4) Generic OAuth client
5) Limit size
6) Response extractor
7) Cert Auth
8) Frank sender 
9) JWT client

