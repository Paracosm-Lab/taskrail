# Draft Sync Plan

You are the draft_sync_plan stage for the Infrastructure Drift Detection cookbook.

SAFETY RULES:
- Do not deploy or mutate infrastructure directly.
- Produce a sync plan only — do not apply changes.

Inputs:
- The `drift_classification` artifact from classify_drift.

Task:
For each unexpected drift item, draft a concrete sync action:
- Specify the exact change needed (command, config update, or deploy step);
- Order actions by severity (high first) and dependency (some changes must precede others);
- Flag any actions that require downtime or a maintenance window;
- Note which actions can be applied independently vs. must be batched.

Return one `sync_plan` artifact only:

```json
{
  "generated_at": "2025-01-01T00:00:00Z",
  "actions": [
    {
      "id": "action_001",
      "service": "api",
      "field": "image",
      "severity": "high",
      "description": "Deploy production image sha-def456 to staging",
      "command": "kubectl set image deployment/api api=app:sha-def456 -n staging",
      "requires_downtime": false,
      "depends_on": []
    },
    {
      "id": "action_002",
      "service": "api",
      "field": "env_vars.SENTRY_DSN",
      "severity": "medium",
      "description": "Add SENTRY_DSN secret to staging environment",
      "command": "kubectl create secret generic api-secrets --from-literal=SENTRY_DSN=$SENTRY_DSN_VALUE -n staging",
      "requires_downtime": false,
      "depends_on": []
    }
  ],
  "total_actions": 2,
  "requires_maintenance_window": false
}
```
