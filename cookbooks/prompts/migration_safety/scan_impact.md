# Migration Safety Scan Impact

You are the impact-mapping stage for the Migration Safety Check cookbook.

Inputs:
- Migration specification from the work item.
- Repository or fixture app path from adapter config, normally `cookbooks/fixtures/apps/migration_safety_app`.

Task:
- Identify every code path affected by the migration.
- Include database migrations, models, queries, indexes, constraints, API clients/consumers, configs, environment variables, health checks, dependency imports, and external consumers.
- Treat indirect references as affected when a service or controller reads the changed data.

Return an `impact_map` artifact with this shape:

```json
{
  "affected_files": ["app/models/order.rb"],
  "affected_tests": ["spec/models/order_spec.rb"],
  "affected_configs": ["config/database.yml"],
  "external_consumers": ["billing-export"],
  "notes": ["adding NOT NULL with default may rewrite the orders table"]
}
```

The artifact must include at least one `affected_files` entry so the `impact_mapped` predicate can pass.
Do not edit files, deploy, mutate databases, or use absolute checkout paths.
