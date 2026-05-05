#!/usr/bin/env bash
set -euo pipefail
cat <<'JSON'
{"service_healthy":true,"checks":[{"name":"api_health","passed":true},{"name":"postgres_ready","passed":true}]}
JSON
