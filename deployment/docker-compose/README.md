# APISIX Traditional mode including dashboard using Docker-Compose
This uses the example Docker-compose provided by Apacke APISIX to deploy APISIX traditional locally. This is especially convenient when experimenting with Apache APISIX configuration without needing custom images or a Kubernetes cluster. 

This setup contains:
- APISIX gateway
- APISIX dashboard
- ETCD
- Prometheus
- Grafana
- Upstream services for testing (you can also use your own)

`Note` although very convenient for testing out of the box features from APISIX, some things are more difficult to achieve using this out of the box setup. Most notalbly adding and using custom plugins. 

## Getting started
This uses the Docker compose provided configuration by Apache APISIX. 
Clone the following repo: 
```shell
git clone https://github.com/apache/apisix-docker.git
cd apisix-docker/example
```
Before starting the containers overwrite the file `config.yaml` in the `apisix-docker/example/apisix_conf` directory.
With the correct config file in place start the containers from the `apisix-docker/example` directory using:
```
docker-compose -p docker-apisix up -d
```

## Configuring APISIX with a SOAP service 
This example contains an APISIX Route, Service and Upstream invoking a free SOAP service. The purpose is to test the SOAP features of APISIX using out of the box configurations and plugins.

To configure APISIX we can use the `dashboard admin API`.
Before we submit the configuration file we must obtain an authenticatin token with the following request:
```shell
ACCESS_TOKEN=$(curl --location 'http://localhost:9000/apisix/admin/user/login' \
--header 'Content-Type: application/json' \
--data '{
    "username": "admin",
    "password": "admin"
}' | jq -j .data.token)
```
With the access token can submit the configuration using:
```shell
curl --location 'http://localhost:9000/apisix/admin/migrate/import' \
--header "Authorization: $ACCESS_TOKEN" \
--form 'mode="overwrite"' \
--form 'file=@"./apisix-config.bak"'
```

With the configuration created issue request using the provided Postman collection: `SOAPDemo.postman_collection.json`

Finally observe the custom labelled metrics in [Prometheus](http://localhost:9090/graph?g0.expr=apisix_http_status%7Bsoap_action%3D~%22http.*%22%7D&g0.tab=1&g0.stacked=0&g0.range_input=1h)
![prometheus-soap-action](/docs/diagrams/apisix-prometheus-soap-action.png)