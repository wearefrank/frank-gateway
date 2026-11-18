#!/bin/sh
set -eu

cp -R /usr/local/apisix/conf/. /generated/
mkdir -p /generated/test
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
    -out /generated/test/signing-key.pem 2>/dev/null
openssl pkey -in /generated/test/signing-key.pem -pubout \
    -out /generated/test/signing-public.pem
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
    -out /generated/test/wrong-signing-key.pem 2>/dev/null
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -keyout /generated/test/tls-key.pem -out /generated/test/tls-cert.pem \
    -subj /CN=mock-idp -addext subjectAltName=DNS:mock-idp 2>/dev/null

sed 's|# ssl_trusted_certificate: /path/to/ca-cert.*|ssl_trusted_certificate: /usr/local/apisix/conf/test/tls-cert.pem|' \
    /test/config.yaml > /generated/config.yaml
grep -q 'ssl_trusted_certificate: /usr/local/apisix/conf/test/tls-cert.pem' /generated/config.yaml
cp /test/apisix.yaml /generated/apisix.yaml
chown -R apisix:apisix /generated
