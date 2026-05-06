Execute the selected runbook's observe, mitigate, and verify steps against the staging Docker Compose fixture. If no runbook was selected, record that no applicable runbook exists.

Return artifact kind `runbook_execution` with JSON data:
- steps_executed
- overall_success
- skipped_reason
