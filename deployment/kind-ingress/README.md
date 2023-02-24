# APISIX Ingress using Kind
Setup a minimal local kubernetes cluster using [kind](https://kind.sigs.k8s.io/) and deploy the APISIX ingress controller. 

This is a slight variation to https://apisix.apache.org/docs/ingress-controller/deployments/kind/ 

## Prerequisites
- Install [kind](https://kind.sigs.k8s.io/docs/user/quick-start/)
- Install [Helm](https://helm.sh/)
- Install [kubectl](https://kubernetes.io/docs/tasks/tools/)

### Commands

### Setup local Kubernetes cluster
To create a local kind cluster named `apisix-ingress` with a portmapping rule forwarding port 80 of the host to `nodeport` 30965 
```shell
kind create cluster --name apisix-ingress --config=kind-cluster-config.yaml
```

### Install Helm repo's
```shell
helm repo add apisix https://charts.apiseven.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### Install APISIX Ingress via Helm charts
Create a namespace for the APISIX Ingress
```shell
kubectl create ns ingress-apisix
```

Install APISIX Ingress
```shell
helm install apisix apisix/apisix \
  --set gateway.type=NodePort \
  --set ingress-controller.enabled=true \
  --namespace ingress-apisix \
  --set ingress-controller.config.apisix.serviceNamespace=ingress-apisix
```

Verify the service is created
```shell
kubectl get service --namespace ingress-apisix
```

Patch the nodeport for the service
Kubernetes by default assigns a nodeport in the range of 30000-32767

Since we made a kind `extraPortMapping` rule forwarding port `80` to `30965` we need to make sure the nodeport for the APISIX gateway is set to `30965`

```shell
kubectl patch svc apisix-gateway -n ingress-apisix --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"},{"op":"replace","path":"/spec/ports/0/nodePort","value":30965}]'
```

### Install Upstream API's
Installs two upstream (backend) API's `Foo` and `Bar`
```shell
kubectl apply -f upstream-apis.yaml
```

### Apply the APISIX ingress routing rules
The APISIX routing rules are path based `/foo/*` will route to the `foo` service. `/bar/*` will route to the `bar` service.

```shell
kubectl apply -f http-route.yaml
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