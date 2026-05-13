#!/bin/sh
set -e

echo "[Frank Gateway] Starting gateway..."

lua /usr/local/bin/scripts/merge.lua &

echo "[Frank Gateway] Starting APISIX..." &

exec apisix start