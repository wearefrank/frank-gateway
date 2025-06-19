.PHONY: dev-startup
dev-startup:
	docker run -d --name apache-apisix-standalone \
  	-p 9080:9080 \
  	-p 9443:9443 \
  	-p 9090:9090 \
	-v $(shell pwd)/../config-default.yaml:/usr/local/apisix/conf/config-default.yaml \
	-v $(shell pwd)/../config.yaml:/usr/local/apisix/conf/config.yaml \
	-v $(shell pwd)/apisix.yaml:/usr/local/apisix/conf/apisix.yaml \
	-v $(shell pwd)/../../src:/usr/local/apisix/custom-plugins \
	-v $(shell pwd)/../../lib:/usr/local/apisix/custom-plugin-libs \
	--add-host=host.docker.internal:host-gateway \
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