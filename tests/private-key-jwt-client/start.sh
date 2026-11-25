#!/bin/sh
set -eu

export TEST_PRIVATE_KEY="$(cat /usr/local/apisix/conf/test/signing-key.pem)"
export TEST_PUBLIC_KEY="$(cat /usr/local/apisix/conf/test/signing-public.pem)"
export TEST_WRONG_PRIVATE_KEY="$(cat /usr/local/apisix/conf/test/wrong-signing-key.pem)"
exec /docker-entrypoint.sh docker-start
