# FCS requires mTLS for connections to the Inway.

'All keys and certificates in this directory are for testing purposes only. These should never be used in a live production environment!!!'

The keys and certificates where created using the following commands:
```shell
openssl genrsa -out ca.key 2048
openssl req -new -sha256 -key ca.key -out ca.csr -subj "/CN=ROOTCA"
openssl x509 -req -days 36500 -sha256 -extensions v3_ca -signkey ca.key -in ca.csr -out ca.cer
openssl genrsa -out server.key 2048
openssl req -new -sha256 -key server.key -out server.csr -subj "/CN=localhost"
openssl x509 -req -days 36500 -sha256 -extensions v3_req  -CA  ca.cer -CAkey ca.key  -CAserial ca.srl  -CAcreateserial -in server.csr -out server.cer
openssl genrsa -out client.key 2048
openssl req -new -sha256 -key client.key  -out client.csr -subj "/CN=CLIENT"
openssl x509 -req -days 36500 -sha256 -extensions v3_req  -CA  ca.cer -CAkey ca.key  -CAserial ca.srl  -CAcreateserial -in client.csr -out client.cer


openssl pkcs12 -export -out keyStore.p12 -inkey ca.key -in ca.cer
```

Keycloak does need some additional permissions from the key and keystore files:
```shell
chmod 664 keycloak/ssl/server/server.key
chmod 664 keycloak/ssl/CA/keyStore.p12
```