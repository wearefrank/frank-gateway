# frank-api-gateway

[Kubernetes Architecture scenarios](docs/kubernetes-architecture.md)

## Layout & Structure

This repository contains two components:
1) deployment configurations
2) source code for FSC plugin

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
In order to test the plugin a OAuth2 authentication server setup for the client credentials flow and offering a JWKS endpoint is needed. This is to mimic the behavior of the FSC Manager. It is possible to use the keycloak configuration detailed [here](deployment/kind-ingress/README.md) or you can provide your own.

The FSC plugin does need to know the location of the authentication server and more specifically the JWKS URL of the authentication server. This is configured as a parameter of the plugin in the file `apisix.yaml`.

When configured correctly the API can be invoked. Obtain a JWT Access token and issue the following request:
```shell
curl --location 'http://localhost:9080/hello' \
--header 'Fsc-Authorization: Bearer [YOUR JWT ACCESS TOKEN]' 
```
If everything works as expected a 200 is returned with your requested "echoed" back.

**Helper pre-request script for Postman**
Since FSC does not use the default `Authorization` header but rather the `Fsc-Authorization` header the out of the box functionality from Postman for requesting and using an Access token does not work. In order to automatically change the `Authorization` header to the `Fsc-Authorization` header add the following snippet as `pre-request script`:

```javascript
let accessToken = pm.request.auth.parameters().get("accessToken");

pm.request.headers.add({
    key: "Fsc-Authorization",
    value: "Bearer " + accessToken
});

pm.request.auth.parameters().clear();
```

### Current status
Both The FSC standard as well the plugin is currently work in progress:
- [ ] Perform mTLS (this is not a feature of the plugin but rather a feature of APISIX that needs to be configured)
- [ ] Extract the Peer_ID (Organization number) from the TLS client certificate
- [x] retrieve the public certificate from a JWKS endpoint
- [x] Validate the JWT in the `Fsc-Authorization` header
- [x] Perform `certificate bound token validation` according to: [RFC 8705](https://www.rfc-editor.org/rfc/rfc8705#name-jwt-certificate-thumbprint-)
- [ ] Respond with FSC error codes
- [x] Enable caching for JWKS keys 
- [ ] Tests
