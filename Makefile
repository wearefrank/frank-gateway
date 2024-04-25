.PHONY: dev-startup
dev-startup:
	docker run -d --name apache-apisix-standalone \
  	-p 9080:9080 \
  	-p 9443:9443 \
  	-p 9090:9090 \
	-v $(shell pwd)/conf/config-default.yaml:/usr/local/apisix/conf/config-default.yaml \
	-v $(shell pwd)/conf/config.yaml:/usr/local/apisix/conf/config.yaml \
	-v $(shell pwd)/conf/apisix.yaml:/usr/local/apisix/conf/apisix.yaml \
	-v $(shell pwd)/src:/usr/local/apisix/custom-plugins \
	-v $(shell pwd)/lib:/usr/local/apisix/custom-plugin-libs \
	--add-host=host.docker.internal:host-gateway \
	--add-host=manager.organization-a.nlx.local:host-gateway \
	--add-host=controller-api.organization-a.nlx.local:host-gateway \
	--add-host=txlog-api.organization-a.nlx.local:host-gateway \
  	apache/apisix:3.8.0-debian

.PHONY: dev-start
dev-start:
	docker start apache-apisix-standalone

.PHONY: dev-stop
dev-stop:
	docker stop apache-apisix-standalone

.PHONY: dev-rm
dev-rm:
	docker rm apache-apisix-standalone

.PHONY: dev-reload
dev-reload:
	docker exec -it apache-apisix-standalone apisix reload

.PHONY: dev-shell
dev-shell:
	docker exec -it apache-apisix-standalone /bin/bash

.PHONY: dev-build
dev-build:
	docker build --build-arg BUILD_DATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ') -t frank-api-gateway .

# Uses the frank-api-gateway build with the local config files to run the gateway in standalone mode
.PHONY: gw-startup
gw-startup:
	docker run -d --name frank-api-gateway-standalone \
  	-p 9080:9080 \
  	-p 9443:9443 \
  	-p 9090:9090 \
	-v $(shell pwd)/conf/config.yaml:/usr/local/apisix/conf/config.yaml \
	-v $(shell pwd)/conf/apisix.yaml:/usr/local/apisix/conf/apisix.yaml \
	--add-host=host.docker.internal:host-gateway \
	--add-host=manager.organization-a.nlx.local:host-gateway \
	--add-host=controller-api.organization-a.nlx.local:host-gateway \
	--add-host=txlog-api.organization-a.nlx.local:host-gateway \
  	frank-api-gateway:latest

.PHONY: gw-rm
gw-rm:
	docker rm frank-api-gateway-standalone

.PHONY: gw-start
gw-start:
	docker start frank-api-gateway-standalone

.PHONY: gw-stop
gw-stop:
	docker stop frank-api-gateway-standalone

.PHONY: gw-reload
gw-reload:
	docker exec -it frank-api-gateway-standalone apisix reload

.PHONY: gw-shell
gw-shell:
	docker exec -it frank-api-gateway-standalone /bin/bash

.PHONY: gw-image-rm
gw-image-rm:
	docker rmi frank-api-gateway

.PHONY: gw-logs
gw-logs:
	docker logs --follow frank-api-gateway-standalone

.PHONY: dashboard-build
dashboard-build:
	docker build -f dashboard/Dockerfile --build-arg BUILD_DATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ') -t frank-api-dashboard .
