# Query Health Collect Queries

You are the collection stage for the `query_health` queue.

Inputs:
- Repository root from the runner working directory; do not assume an absolute path.
- Database config from the target app.
- Optional fixture path from adapter config: `test/fixtures/apps/slow_queries`.

Collect a query inventory from all available safe sources:

1. Run the test suite with SQL/query logging enabled when the runner provides a safe test command.
2. Parse `log/test.log` and `log/development.log` when present.
3. Scan Rails source files for ActiveRecord query calls such as `.where`, `.find`, `.joins`, `.includes`, `.preload`, `.eager_load`, `.select`, `.count`, `.pluck`, `.order`, and `.limit`.
4. If Postgres `pg_stat_statements` or a slow-query log is provided by the runner, parse it; otherwise record that it was unavailable.
5. For each query, record SQL or query expression, origin (`file:line` when known), touched tables, frequency hint, and whether an index hint exists.
6. Estimate table row counts from `db/schema.rb`, seed data, or database metadata if safely available.

Return exactly one `query_inventory` artifact as JSON:

```json
{
  "queries": [
    {
      "sql": "SELECT * FROM posts WHERE status = ?",
      "origin": "app/controllers/posts_controller.rb:8",
      "tables": ["posts"],
      "frequency": "per_request",
      "has_index_hint": false
    }
  ],
  "table_stats": {
    "row_counts": { "posts": 1000 }
  },
  "collection_notes": []
}
```

The artifact must include at least one query. Do not edit files, deploy, or mutate non-test databases.
