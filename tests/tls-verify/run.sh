#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"

./gen-certs.sh
python3 gen-routes.py

docker compose down -v >/dev/null 2>&1
docker compose up -d --build
trap 'docker compose down -v >/dev/null 2>&1' EXIT

# wacht tot de gateway en de routes echt klaar zijn
ready=0
for i in $(seq 1 40); do
  [ "$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' localhost:9080/valid)" = "200" ] && ready=1 && break
  sleep 1
done
if [ "$ready" != 1 ]; then
  echo "FAIL: gateway niet klaar (/valid geeft geen 200)"; docker compose logs gateway | tail -40; exit 1
fi

fail=0
check() { # pad, verwachte status
  code=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "localhost:9080/$1" || true)
  if [ "$code" = "$2" ]; then echo "OK   /$1 -> $code"
  else echo "FAIL /$1 -> $code (verwacht $2)"; fail=1; fi
}
reason() { # route, patroon
  if docker compose logs gateway 2>&1 | grep "GET /$1 " | grep -q "$2"; then
    echo "OK   /$1 reden: $2"
  else echo "FAIL /$1 geen reden '$2' in log"; fail=1; fi
}

check valid      200
check noverify   200
check selfsigned 502
check untrusted  502
check wronghost  502

reason selfsigned "(18:self-signed certificate)"
reason untrusted  "(20:unable to get local issuer certificate)"
reason wronghost  "does not match"

[ "$fail" = 0 ] && echo "ALLE CHECKS OK" || { docker compose logs gateway | tail -40; }
exit $fail