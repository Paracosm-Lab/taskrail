#!/usr/bin/env bash
set -euo pipefail
mkdir -p tmp/chaos_staging
cat > tmp/chaos_staging/detect_alerts.json <<'JSON'
{"events":[{"id":"evt-1","service":"chaos-api","message":"boom"}],"detection_time":"2026-05-05T00:00:00Z","time_window_minutes":10}
JSON
cat tmp/chaos_staging/detect_alerts.json
