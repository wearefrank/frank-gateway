.PHONY: dev-startup
dev-startup:
	docker run -it --name apache-apisix-standalone \
  	-p 9080:9080 \
  	-p 9443:9443 \
  	-p 9090:9090 \
	-v //$(pwd)/../config.yaml:/usr/local/apisix/conf/config.yaml \
	-v //$(pwd)/apisix.yaml:/usr/local/apisix/conf/apisix.yaml \
	-v //$(pwd)/../../src:/usr/local/apisix/custom-plugins \
	-v //$(pwd)/../../lib:/usr/local/apisix/custom-plugin-libs \
	--add-host=host.docker.internal:host-gateway \
	--add-host=manager.organization-a.open-fsc.localhost:host-gateway \
	--add-host=controller-api.organization-a.open-fsc.localhost:host-gateway \
	--add-host=txlog-api.organization-a.open-fsc.localhost:host-gateway \
  	apache/apisix:3.12.0-debian

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