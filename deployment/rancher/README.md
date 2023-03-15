# APISIX Ingress using We Are Frank Rancher
Deploying the APISIX ingress controller into the We Are Frank Kubernetes cluster. 

## Prerequisites
In order to deploy the APISIX ingress and hello world API's the following is needed:
- Access to the Kubernetes cluster
- Helm installed
- Helm charts installed 
    - https://charts.bitnami.com/bitnami
    - https://charts.apiseven.com
- Namespaces created in Rancher (in the API Management project)
    - ingress-apisix
    - hello-world-api

## Installation

### Installation of the APISIX ingress controller
Install APISIX Ingress
```shell
helm install apisix apisix/apisix \
  --set gateway.type=LoadBalancer \
  --set ingress-controller.enabled=true \
  --namespace ingress-apisix \
  --set ingress-controller.config.apisix.serviceNamespace=ingress-apisix
```


```shell
kubectl port-forward svc/apisix-gateway 8080:80 -n ingress-apisix
```


### Install Upstream API's
Installs two upstream (backend) API's `Foo` and `Bar`
```shell
kubectl apply -f upstream-apis.yaml -n hello-world-api
```

### Apply the APISIX ingress routing rules
The APISIX routing rules are Host based `'Host: foo.org'` will route to the `foo` service. `'Host: bar.org'` will route to the `bar` service.

`note: the APISIX CRD needs to be created in the same namespace as the backendAPI for the API Ignress controllers' service discovery to work. In this example this is: "hello-world-api"`

```shell
kubectl apply -f http-route.yaml -n hello-world-api
```

### Verify the APISIX routes
Invoke the foo service via APISIX
```shell
curl -v localhost/hostname -H 'Host: foo.org'
```
If everything is setup correctly the output should be:
foo-app

Invoke the bar service via APISIX
```shell
curl -v localhost/hostname -H 'Host: bar.org'
```
If everything is setup correctly the output should be:
bar-app