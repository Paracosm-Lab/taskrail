Evaluate the response queue's recovery using the disruption plan, impact report, and response_outcome artifact.

Return artifact kind `recovery_evaluation` with JSON data:
- scores: detection, diagnosis, runbook_coverage, recovery_time, recovery_completeness, alert_quality
- overall_grade
- gaps
- recommendations

Judge alert and runbook quality, not just whether the service recovered.
