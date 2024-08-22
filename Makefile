.PHONY: build-gateway
dev-build:
	docker build --build-arg BUILD_DATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ') -t frank-api-gateway .

.PHONY: build-dashboard
dashboard-build:
	docker build -f dashboard/Dockerfile --build-arg BUILD_DATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ') -t frank-api-dashboard .
