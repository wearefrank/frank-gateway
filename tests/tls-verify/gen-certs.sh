#!/usr/bin/env bash
set -euo pipefail
mkdir -p certs && cd certs

mkca() { openssl req -x509 -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.crt" -subj "/CN=$1" -days 2; }
mkleaf() { # naam, signing-CA, hostnaam in cert
  openssl req -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" -subj "/CN=$3"
  openssl x509 -req -in "$1.csr" -CA "$2.crt" -CAkey "$2.key" -CAcreateserial \
    -out "$1.crt" -days 2 -extfile <(printf "subjectAltName=DNS:%s" "$3")
}

mkca ca        # de CA die APISIX vertrouwt
mkca otherca   # een CA die APISIX niet vertrouwt

mkleaf valid     ca      upstream-valid
mkleaf wronghost ca      other.example        # geldig, maar verkeerde hostnaam
mkleaf untrusted otherca upstream-untrusted   # onbekende root

openssl req -x509 -newkey rsa:2048 -nodes -keyout selfsigned.key -out selfsigned.crt \
  -subj "/CN=upstream-selfsigned" -addext "subjectAltName=DNS:upstream-selfsigned" -days 2
chmod 644 *.key