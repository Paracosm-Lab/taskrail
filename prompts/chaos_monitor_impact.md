Monitor fake or staging alerting for the expected impact window. Zero alerts is a valid result and should be reported as an instrumentation gap.

Return artifact kind `impact_report` with JSON data:
- alerts_fired
- alert_delay_seconds
- services_affected
- sentry_event_ids
- monitoring_gaps
