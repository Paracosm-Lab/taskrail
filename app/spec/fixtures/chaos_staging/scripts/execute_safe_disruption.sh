#!/usr/bin/env bash
set -euo pipefail
mkdir -p tmp/chaos_staging
cat > tmp/chaos_staging/execute_disruption.json <<'JSON'
{"commands_run":["docker compose stop chaos-postgres"],"target_service":"chaos-postgres","expected_alert_lag_seconds":5}
JSON
cat tmp/chaos_staging/execute_disruption.json
