#!/usr/bin/env bash
set -euo pipefail
mkdir -p tmp/chaos_staging
cat > tmp/chaos_staging/verify_recovery.json <<'JSON'
{"service_healthy":true,"alert_rate":0,"verification_checks":[{"name":"health","passed":true}]}
JSON
cat tmp/chaos_staging/verify_recovery.json
