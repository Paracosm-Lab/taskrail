# Query Health Analyze Performance

You are the analysis stage for the `query_health` queue.

Inputs:
- `query_inventory` artifact.
- Rails schema from `db/schema.rb` or equivalent.
- Existing index definitions.
- Source files around query origins.

Analyze each query for:

- N+1 query risk from loops, views, serializers, or repeated association access.
- Missing indexes on WHERE, JOIN, ORDER, and foreign-key columns.
- Full table scans on large tables.
- Unnecessary loads such as `SELECT *` when only a few columns are used.
- Redundant queries that fetch the same data repeatedly.
- Counter queries that should use counter caches.

Score severity as `critical`, `high`, `medium`, or `low` using table size, frequency, and blast radius. Recommend one of: `add_index`, `eager_load`, `rewrite_query`, `add_counter_cache`, `add_pagination`, `use_select`, `architectural_change`, or `no_change`.

Return one `query_analysis` artifact as JSON:

```json
{
  "findings": [
    {
      "query": "SELECT * FROM posts WHERE status = ?",
      "origin": "app/controllers/posts_controller.rb:8",
      "issue_type": "missing_index",
      "severity": "high",
      "tables": ["posts"],
      "recommendation": "add_index",
      "estimated_impact": "Filters a high-frequency request on an unindexed status column."
    }
  ],
  "spawn_work_items": [
    {
      "queue_slug": "development",
      "title": "Design caching layer for expensive feed query",
      "spec_inline": "The query health analysis found an architectural_change finding that should be handled by the development queue instead of an index-only patch.",
      "tags": { "domain": "query_health", "issue_type": "architectural_change" }
    }
  ]
}
```

Only include `spawn_work_items` for architectural changes such as denormalization, caching layers, or read-replica routing. Do not spawn work for normal index/eager-loading fixes that `draft_fixes` can handle.
