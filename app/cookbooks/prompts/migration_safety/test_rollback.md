# Migration Safety Test Rollback

You are the Docker-friendly staging validation stage for the Migration Safety Check cookbook.

Inputs:
- The upstream `rollback_plan` artifact.
- Fixture app path: `cookbooks/fixtures/apps/migration_safety_app`.
- Shared Compose file: `cookbooks/docker-compose.yml`.

Execute the fixture migration scenario, execute rollback, and verify:
- migration succeeded
- rollback succeeded
- data stayed intact
- health checks passed

Return a `rollback_test_results` artifact:

```json
{
  "migration_succeeded": true,
  "rollback_succeeded": true,
  "data_intact": true,
  "health_checks_passed": true,
  "issues": []
}
```

If anything fails, set the relevant boolean to false and include actionable issue strings. The `rollback_tested` predicate requires all four booleans to be true.
