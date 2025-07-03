#!/bin/bash
set -e

echo "Waiting for APISIX to be ready..."

until curl --silent http://apisix:9080 >/dev/null 2>&1; do
  printf '.'
  sleep 2
done
echo "APISIX is up!"

# Now call EntryPoint.sh
exec ./EntryPoint.sh