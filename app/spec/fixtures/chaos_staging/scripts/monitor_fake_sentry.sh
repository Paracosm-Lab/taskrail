#!/usr/bin/env bash
set -euo pipefail
mkdir -p tmp/chaos_staging
cat > tmp/chaos_staging/monitor_sentry.json <<'JSON'
{"alerts_fired":1,"alert_delay_seconds":5,"services_affected":["chaos-api"],"sentry_event_ids":["evt-1"],"monitoring_gaps":[]}
JSON
cat tmp/chaos_staging/monitor_sentry.json
