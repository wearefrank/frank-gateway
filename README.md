# frank-api-gateway

[Kubernetes Architecture scenarios](docs/kubernetes-architecture.md)

## Layout & Structure

This repository contains three components:
1) deployment configurations
2) source code for FSC plugin
3) PoC for generating Apisix configurations for multiple deployment architectures

### Deployment configurations
The directory `deployment` contains three deployment scenarios for deploying APISIX. Note, this deploys vanilla APISIX without the FSC plugin.

- kind -> deploys APISIX in normal mode on a local Kubernetes cluster using Kind
- kind-ingress -> deploys APISIX as a Kubernetes ingress on a local cluster using Kind
- rancher -> deploys APISIX as a Kubernetes ingress on the WAF rancher cluster

Instructions on how to deploy these setups and what components they consist of can be found in the README.md of the subdirectories in deployment. 

### FSC plugin
In order to use APISIX as an `FSC Inway` a custom plugin is created. The source code for this plugn as well as some required directories for running the plugin locally are part of this repository. More information about an FSC Inway can be found [here](docs/nlx/README.md)

The plugin runs APISIX in standalone mode, so no ETCD is needed. This is convenient for easy local testing the plugin.
There are three subdirectories of this template:
- conf
- logs
- src

The `conf` directory contains the configuration files for APISIX to run and configure in standalone mode. A minimal configuration is provided to get you up and running. 

The `logs` directory contains the log files (access.log and error.log) from the container for easier troubleshooting. 

The `src` directory contains the source code for the custom plugin. Here you can place your lua files and subdirecties for developing your custom plugin. For more information regarding the development of a custom APISIX plugin see the official docs: https://apisix.apache.org/docs/apisix/plugin-develop/


The directories mentioned above are mounted in the container as follows:
conf/config.yaml -> /usr/local/apisix/conf/config.yaml
conf/apisix.yaml -> /usr/local/apisix/conf/apisix.yaml
logs/ -> /usr/local/apisix/logs
src/ -> /usr/local/apisix/custom-plugins

### Running the FSC plugin locally 
APISIX containing your custom configuration and plugin are run using the APISIX Docker container. While perfectly possible to use the Docker CLI to run APISIX a Makefile is created for convenience. 

The Makefile contains the following commands:
- dev-startup -> creates and start the docker container with the appropriate volume mounts
- dev-start -> starts an existing container
- dev-stop -> stops the container
- dev-rm -> removes the container
- dev-reload -> issues the `apisix reload` command inside the container

When the container is started a container with the name of `apache-apisix-standalone` is run. 

To startup the container for the first time:
```shell
make dev-startup
```

The container exposes port `9080` as the traffic port of APISIX.

### Testing the FSC Plugin

The FSC plugin does need to know the location of the authentication server and more specifically the JWKS URL of the authentication server. This is configured as a parameter of the plugin in the file `apisix.yaml`.

`Note, unfortunately Postman does not support mTLS for requesting Access tokens via the Authorization functionality. Access tokens must be retrieved via another method e.g. curl` 

### Testing via Keycloak for mTLS
The FSC plugin can also be tested with Keycloak as Authorization server. 

In order to start Keycloak run from the root directory of the project the following command to run Keycloak in Docker using the test keys and certificates for the mTLS configuration.
```shell
docker run -p 8080:8080 -p 8443:8443 --name keycloak-standalone \
-e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin \
-e KC_HTTPS_PORT=8443 \
-e KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/ssl/server/server.crt \
-e KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/ssl/server/server.key \
-e KC_HTTPS_TRUST_STORE_FILE=/opt/keycloak/ssl/CA/keyStore.p12 \
-e KC_HTTPS_TRUST_STORE_PASSWORD=test \
-e KC_HTTPS_CLIENT_AUTH=request \
-v $(pwd)/test-certs/keycloak/data:/opt/keycloak/data/import \
-v $(pwd)/keycloak/ssl:/opt/keycloak/ssl \
quay.io/keycloak/keycloak:21.0.2 start-dev --import-realm
```

Keycloak needs to be configured with:
- mTLS token endpoint
- client with Oauth 2.0 Mutual TLS enabled. (to implement RFC 8705)

Unfortunately the latter cannot be ex-/imported with the realm import and need to be configured via the admin console:
- login the admin console: http://localhost:8080/ with admin/admin
- go to: http://localhost:8080/admin/master/console/#/apisix_test_realm/clients/9c98f7c9-8baf-4b4b-b01f-fa2040bb1230/advanced
- toggle the "OAuth 2.0 Mutual TLS Certificate Bound Access Tokens Enabled" to true and save
[Certificate bound tokens](docs/diagrams/Oauth2_mutual_tls_certificate_bound_tokens.png)

### Testing with cURL
With both Keycloak and APISIX running the plugin can be tested. With the mTLS configured the easiers way is to test via cURL:

```shell
curl -kv -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=apisix&client_secret=crTxqWBACD2cnFXn72HUIHmYxrCd7tkz" https://localhost:8443/realms/apisix_test_realm/protocol/openid-connect/token --cert test-certs/client.cer --key test-certs/client.key

ACCESS_TOKEN=$(curl -kv -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=client_credentials&client_id=apisix&client_secret=crTxqWBACD2cnFXn72HUIHmYxrCd7tkz" https://localhost:8443/realms/apisix_test_realm/protocol/openid-connect/token --cert test-certs/client.cer --key test-certs/client.key | jq -j '.access_token')
```

With the access token in the response the API can be invoked:
```shell
curl -kv \
-H "Fsc-Authorization: Bearer $ACCESS_TOKEN" \
https://localhost:9443/hello \
--cert test-certs/client.cer --key test-certs/client.key

```

If everything works as expected a 200 is returned with your requested "echoed" back.


### Testing with a local NLX/FSC cluster
In order to test the FSC plugin with a local FSC cluster first make sure a local FSC cluster is installed and running locally using the instructions [here](https://gitlab.com/commonground/nlx/fsc-nlx)

With all FSC components running the next step is to register the APISIX gateway including the FSC plugin as a FSC Inway. This can be done with a gRPC request using grpcurl:
```shell
grpcurl -d '{"name":"frank-api-gateway","address":"localhost:9443"}' -proto=controller.proto -import-path=/home/pimg/klanten/we-are-frank/fsc-nlx/controller/ports/internalgrpc/api -key=./pki/internal/organization-a/certs/manager/key.pem -cert=./pki/internal/organization-a/certs/manager/cert.pem -cacert=./pki/internal/organization-a/ca/root.pem -H 'Authorization: Basic YWRtaW5Abmx4LmxvY2FsOmRldmVsb3BtZW50' controller-api.organization-a.nlx.local:443 nlx.controller_internal.ControllerService/RegisterInway
```

APISIX uses SNI to match an incoming request with the correct keypair to establish the TLS connection. In order for this to work locally add the following entry to your `hosts` file:
`127.0.0.1 frank-api-gateway.organization-a.nlx.local`

with custom frank-api-gateway certificates:
```shell
grpcurl -d '{"name":"frank-api-gateway","address":"https://frank-api-gateway.organization-a.nlx.local:9443"}' -proto=controller.proto -import-path=/home/pimg/klanten/we-are-frank/fsc-nlx/controller/ports/internalgrpc/api -key=./pki/internal/organization-a/certs/manager/key.pem -cert=./pki/internal/organization-a/certs/manager/cert.pem -cacert=./pki/internal/organization-a/ca/root.pem -H 'Authorization: Basic YWRtaW5Abmx4LmxvY2FsOmRldmVsb3BtZW50' controller-api.organization-a.nlx.local:443 nlx.controller_internal.ControllerService/RegisterInway
```

### Current status
Both The FSC standard as well the plugin is currently work in progress:
- [x] Perform mTLS (this is not a feature of the plugin but rather a feature of APISIX that needs to be configured)
- [x] Extract the Peer_ID (Organization number) from the TLS client certificate
- [x] retrieve the public certificate from a JWKS endpoint
- [x] Validate the JWT in the `Fsc-Authorization` header
- [x] Perform `certificate bound token validation` according to: [RFC 8705](https://www.rfc-editor.org/rfc/rfc8705#name-jwt-certificate-thumbprint-)
- [x] Respond with FSC error codes
- [x] Enable caching for JWKS keys 
- [ ] Tests
- [ ] FSC logging (waiting for FSC-NLX issue: https://gitlab.com/commonground/nlx/fsc-nlx/-/issues/41)
- [ ] Optional routing based on JWT claim servicename (APISIX can likely handle all routing requirements out of the box. If FSC token based routing needs to be implemented see: https://api7.ai/blog/dynamic-routing-based-on-user-credentials)
- [ ] Optional get JWKS via endpoint (waiting for FSC-NLX issue: https://gitlab.com/commonground/nlx/fsc-nlx/-/issues/42)
- [ ] Optional register Inway automatically by the manager of the organization (waiting for FSC-NLX issue: https://gitlab.com/commonground/nlx/fsc-nlx/-/issues/41)

### APISIX config generation
Integration with `Frank Framework` is defined as the ability to configure APISIX for specific API's from the Frank Framework. This enables te creation of API's and their respective configuration needed in APISIX to be managed from a single place, the Frank Framework.

Key aspect of this integration is the ability of generating APISIX configurations.

There are several challenges with generating APISIX configuration:
- APISIX configuration differs between deployment architectures (Kubernetes ingress, Standalone and Traditional)
- APISIX configurations can become large and complex especially when plugins are involved which have specific configuration

The various deployment architectures from APISIX have the following characteristics:
- Kubernets Ingress 
    - configured using Kubernetes CRD's (yaml manifests)
        - can be managed via git
        - can be kept in sync with ArgoCD
        - declarative configuration
- Standalone
    - configured using a single yaml configuration file
        - can be managed via git
        - declarative configuration
- Traditional
    - configured using the admin API (JSON)
    - can be configured using the dashboard (grafical user interface)

`It is important to note that the various configuration models have syntax differences. For example simly converting the json document to yaml does not yield a valid apisix configuration for standalon or ingress setups`.

It is however possible to use one base configuration and generate the required config files for a specific architecture. 
This "SPI like" approach can be outlined as followed:
!["APISIX configuration generation"](docs/diagrams/spi_FF_integration.png)

Regading the complexity and size of the APISIX configuration. There are several different configuration objects. However the core functionality of APSIX is available is the following configuration objects:
- Routes - defines the various rules on which incoming requests are matched and dispatched to services and upstreams. For example path or header based routing rules [more info](https://apisix.apache.org/docs/apisix/terminology/route/)
- Service - defines an abstraction of a backend service that can be exposed via one or multiple routes [more info](https://apisix.apache.org/docs/apisix/terminology/service/)
- Upstream - defines the configuration (eg. host, port) of the backend API [more info](https://apisix.apache.org/docs/apisix/terminology/upstream/)

Detailed information about the different configuration parameters can be found [here](https://apisix.apache.org/docs/apisix/admin-api/)

