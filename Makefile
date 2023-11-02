dev-startup:
	docker run -d --name apache-apisix-standalone \
  	-p 9080:9080 \
  	-p 9443:9443 \
  	-p 9090:9090 \
	-v $(shell pwd)/conf/config.yaml:/usr/local/apisix/conf/config.yaml \
	-v $(shell pwd)/conf/apisix.yaml:/usr/local/apisix/conf/apisix.yaml \
	-v $(shell pwd)/logs:/usr/local/apisix/logs \
	-v $(shell pwd)/src:/usr/local/apisix/custom-plugins \
	-v $(shell pwd)/lib:/usr/local/apisix/custom-plugin-libs \
	--add-host=host.docker.internal:host-gateway \
	--add-host=manager.organization-a.nlx.local:host-gateway \
  	apache/apisix:latest

dev-start:
	docker start apache-apisix-standalone

dev-stop:
	docker stop apache-apisix-standalone

dev-rm:
	docker rm apache-apisix-standalone

dev-reload:
	docker exec -it apache-apisix-standalone apisix reload

dev-shell:
	docker exec -it apache-apisix-standalone /bin/bash

dev-build:
	docker build --build-arg BUILD_DATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ') -t frank-api-gateway .

# Uses the frank-api-gateway build with the local config files to run the gateway in standalone mode
gw-startup:
	docker run -d --name frank-api-gateway-standalone \
  	-p 9080:9080 \
  	-p 9443:9443 \
  	-p 9090:9090 \
	-v $(shell pwd)/conf/config.yaml:/usr/local/apisix/conf/config.yaml \
	-v $(shell pwd)/conf/apisix.yaml:/usr/local/apisix/conf/apisix.yaml \
	--add-host=host.docker.internal:host-gateway \
	--add-host=manager.organization-a.nlx.local:host-gateway \
  	frank-api-gateway:latest

gw-rm:
	docker rm frank-api-gateway-standalone

gw-start:
	docker start frank-api-gateway-standalone

gw-stop:
	docker stop frank-api-gateway-standalone

gw-reload:
	docker exec -it frank-api-gateway-standalone apisix reload

gw-shell:
	docker exec -it frank-api-gateway-standalone /bin/bash

gw-image-rm:
	docker rmi frank-api-gateway

gw-logs:
	docker logs --follow frank-api-gateway-standalone