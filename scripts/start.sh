#!/bin/sh
set -e

echo "[Frank Gateway] Starting gateway..."

if [ "${MERGE_CONFIGURATIONS:-false}" = "true" ]; then
    echo "[Frank Gateway] Starting merge script..."
    lua /usr/local/bin/scripts/merge.lua &
else
    echo "[Frank Gateway] Merge script disabled"
fi

echo "[Frank Gateway] Starting APISIX..."

exec /docker-entrypoint.sh "$@"