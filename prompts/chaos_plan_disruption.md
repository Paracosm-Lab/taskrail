You are planning a safe staging-only chaos exercise.

Read the staging inventory, recent disruption history, and available runbooks. Choose one realistic, reversible failure scenario that is scoped to staging and does not repeat recent scenarios.

Return an artifact of kind `disruption_plan` with JSON data:
- scenario
- category: infrastructure, dependency, data, or load
- target_service
- action
- expected_symptoms
- reversal_steps
- safety_checks
- expected_alert_lag_seconds

Never choose production. Never choose a disruption without reversal steps.
