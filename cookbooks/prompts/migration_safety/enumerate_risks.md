# Migration Safety Enumerate Risks

You are the risk enumeration stage for the Migration Safety Check cookbook.

Inputs:
- The upstream `impact_map` artifact.
- The migration specification.
- Repository or fixture app context.

For each affected path, identify risks in these categories:
- data_loss
- downtime
- partial_failure
- backwards_compatibility
- rollback_blocker

Rate each risk as exactly one of: `blocking`, `high`, `medium`, `low`.

Return a `risk_assessment` artifact:

```json
{
  "risks": [
    {
      "category": "downtime",
      "description": "Adding a NOT NULL column with a default can rewrite and lock a large orders table.",
      "severity": "blocking",
      "affected_paths": ["db/migrate/20240101000000_add_region_to_orders_unsafe.rb"],
      "mitigation": "Use expand/backfill/contract: add nullable column, backfill batches, then enforce NOT NULL."
    }
  ],
  "blocking_risks": ["Adding a NOT NULL column with a default can rewrite and lock a large orders table."]
}
```

The artifact must include at least one risk and only allowed severities.
