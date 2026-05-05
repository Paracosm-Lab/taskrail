Execute only the approved staging disruption plan. Record the exact safe commands and timestamps.

Return artifact kind `disruption_record` with JSON data:
- commands_run
- start_time
- target_service
- expected_alert_lag_seconds
- reversal_steps
- response_spawn: a suggested chaos_response work item payload

If the target is not clearly staging or reversal steps are missing, fail closed.
