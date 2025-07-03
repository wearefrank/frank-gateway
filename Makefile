up:
	@export SERVER_CERT="$$(cat certs/test/apisix.pem)" && \
	export SERVER_KEY="$$(cat certs/test/apisix-key.pem)" && \
	export BULT_CLIENT_CHAIN="$$(cat certs/test/ca-bundle.pem)" && \
	docker compose up
