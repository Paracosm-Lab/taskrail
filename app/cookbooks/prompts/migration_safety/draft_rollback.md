# Migration Safety Draft Rollback

You are the rollback-planning stage for the Migration Safety Check cookbook.

Inputs:
- The upstream `risk_assessment` artifact.
- The migration specification and source code.

Draft concrete rollback procedures for every blocking and high risk.
Each procedure must be testable in staging and include:
- `risk_ref`
- ordered `steps`
- each step's `action`, `command`, and `verification`
- `estimated_time`
- `data_loss_potential`

Return a `rollback_plan` artifact:

```json
{
  "procedures": [
    {
      "risk_ref": "orders table rewrite lock",
      "steps": [
        {
          "action": "rollback unsafe migration",
          "command": "bin/rails db:rollback STEP=1",
          "verification": "SELECT column_name FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'region' returns zero rows"
        }
      ],
      "estimated_time": "5 minutes",
      "data_loss_potential": "none if rollback happens before writes depend on region"
    }
  ]
}
```

Do not deploy or mutate production databases. Commands must be staging/fixture-safe.
