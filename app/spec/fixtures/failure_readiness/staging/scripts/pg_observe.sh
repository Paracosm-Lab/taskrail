#!/usr/bin/env bash
set -euo pipefail
pg_isready -h "${FAILURE_READINESS_POSTGRES_HOST:-127.0.0.1}" -p "${FAILURE_READINESS_POSTGRES_PORT:-55438}" || true
cat <<'JSON'
{"active_connections":3,"max_connections":100,"idle_in_transaction":0,"pool_waiting":0}
JSON
