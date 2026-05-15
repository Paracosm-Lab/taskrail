# Backfill Identify Gaps

You are the gap analysis stage for the Test Coverage Backfill cookbook.

Inputs:
- The latest `coverage_map` artifact.
- Repository source code and existing tests.

Rules:
- Read only. Do not edit files.
- Classify uncovered code into testable units.
- Prioritize public APIs and risky behavior over internal helpers.
- Prefer small units that can each become one focused spec example.

Artifact schema:

```json
{
  "units": [
    {
      "file": "relative/source/path.rb",
      "method": "method_or_action_name",
      "gap_type": "model validation | controller action | service method | error path | edge case",
      "risk": "high | medium | low",
      "description": "Specific behavior that needs a spec"
    }
  ]
}
```

Success criteria:
- The artifact kind is `test_plan`.
- `units` is non-empty.
