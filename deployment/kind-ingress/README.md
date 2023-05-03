# APISIX Ingress using Kind
Setup a minimal local kubernetes cluster using [kind](https://kind.sigs.k8s.io/) and deploy the APISIX ingress controller. 

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
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### Install APISIX Ingress via Helm charts
Create a namespace for the APISIX Ingress
```shell
kubectl create ns ingress-apisix
```

Install Prometheus
```shell
helm install -n monitoring prometheus prometheus-community/kube-prometheus-stack \
  --create-namespace \
  --set 'prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false'
```

After Prometheus is installed we can install APISIX.

Install APISIX Ingress
```shell
helm install apisix apisix/apisix \
  --set gateway.type=NodePort \
  --set ingress-controller.enabled=true \
  --set serviceMonitor.enabled=true \
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

In order to access the Grafana dashboard from the localhost we need to change the port from ClusterIP to Nodeport for the prometheus-grafana service:
```shell
kubectl patch svc prometheus-grafana -n monitoring --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"}'
```

With the service now exposed via a nodeport we can assign the correct nodeport to correspond with our Kind extraportmapping

```shell
kubectl patch svc prometheus-grafana -n monitoring --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"},{"op":"replace","path":"/spec/ports/0/nodePort","value":30300}]'
```

### Install Upstream API's
Installs two upstream (backend) API's `Foo` and `Bar`
```shell
kubectl apply -f upstream-apis.yaml
```

### Apply the APISIX ingress routing rules
The APISIX routing rules are Host based `'Host: foo.org'` will route to the `foo` service. `'Host: bar.org'` will route to the `bar` service.

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

## Configure Grafana to view the APISIX dashboard
With Prometheus and Grafana installed the APISIX dashboard can be imported.
In order to login to Grafana visit: http://localhost:3000
Since we did not change the default password for this local install login with:
username: admin
password: prom-operator

when logged in import the APISIX dashboard ID: `11719`

To visit the APISIX dashboard select the dashboard: `Apache APISIX`

This should look like this:
![APISIX Grafana dashboard](../../docs/diagrams/grafana-apisix-dashboard.png)