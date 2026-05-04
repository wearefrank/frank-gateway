# mTLS Test Certificates for APISIX Standalone

> Important:
> All keys and certificates in this directory are for testing and development only.
> Never use them in production.

## Overview

This directory contains certificate files used for cert-auth mTLS tests.

- Certuser certificate: client/certuser-new.pem
- Certuser private key: client/certuser-new.key
- Testuser keystore: keystore/client.p12

## Quick start

Build the Frank Gateway image from repository root:

```shell
docker build -t frank-gateway:local .
```

Start the cert-auth test stack:

```shell
cd tests/cert-auth
docker compose up -d --force-recreate
```

## Bruno

You can also run these tests with the Bruno collection in tests/cert-auth/bruno.
Use the local environment and run the requests for certuser and testuser.

## Commands

Certuser test:

```shell
openssl s_client -connect localhost:9443 -servername localhost -cert client/certuser-new.pem -key client/certuser-new.key
```

Testuser test:

```shell
openssl pkcs12 -in keystore/client.p12 -clcerts -nokeys -out keystore/testuser-cert.pem -passin pass:
openssl pkcs12 -in keystore/client.p12 -nocerts -nodes -out keystore/testuser-key.pem -passin pass:
openssl s_client -connect localhost:9443 -servername apisix.localhost -cert keystore/testuser-cert.pem -key keystore/testuser-key.pem
```




