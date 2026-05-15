# Cookbook Spec: Database Query Health Check

## Use Case

N+1 queries, missing indexes, full table scans hiding behind ActiveRecord. Performance degrades gradually until someone notices a page takes 8 seconds. The fix is always obvious in hindsight — add an `includes`, add an index, rewrite the query. But nobody audits proactively.

TaskRail analyzes your queries, identifies the worst offenders, drafts index migrations and query optimizations, tests them, and queues for review.

## Queue: `query_health`

### Stages

```
collect_queries → analyze_performance → draft_fixes → run_tests → human_review → done
```

### Stage Details

**collect_queries** (shell_script + Haiku)
- Adapter: `shell_script`
- Input: repository path, database config
- Task: Collect query data from multiple sources:
  - Run the test suite with query logging enabled, capture all SQL
  - Parse `log/development.log` for queries if available
  - Extract ActiveRecord/ORM queries from source code (`.where`, `.find`, `.joins`, etc.)
  - Parse slow query log from Postgres if accessible (`pg_stat_statements`)
  - For each query: SQL, origin (file:line), frequency hint, table(s) touched
- Artifact: `query_inventory` — `{ queries: [{ sql, origin, tables, frequency, has_index_hint: bool }], table_stats: { row_counts: {} } }`
- Predicate: `query_inventory_produced` — artifact exists with at least one query
- Why shell: needs to run the test suite and parse logs

**analyze_performance** (Sonnet)
- Adapter: `inline_claude`
- Input: query_inventory artifact, database schema (`db/schema.rb` or equivalent), existing indexes
- Task: For each query, assess:
  - **N+1 detection**: loops that produce one query per iteration
  - **Missing indexes**: WHERE/JOIN columns without indexes
  - **Full table scans**: queries on large tables without indexed filters
  - **Unnecessary loads**: `SELECT *` when only specific columns are needed
  - **Redundant queries**: same data fetched multiple times in one request
  - Score each as `critical` / `high` / `medium` / `low` based on table size and frequency
  - Recommend: add index, add eager loading, rewrite query, add counter cache, etc.
- Artifact: `query_analysis` — `{ findings: [{ query, origin, issue_type, severity, tables, recommendation, estimated_impact }] }`
- Predicate: `query_analyzed` — artifact exists with findings
- Why Sonnet: needs to understand schema, indexes, and query plans

**draft_fixes** (Sonnet)
- Adapter: `inline_claude`
- Input: query_analysis artifact, source code, schema
- Task: Draft fixes for critical and high findings:
  - **Missing indexes**: generate migration files (`add_index :table, :column`)
  - **N+1 queries**: add `includes`/`preload`/`eager_load` to the query chain
  - **Full table scans**: rewrite with proper WHERE clauses or pagination
  - **SELECT ***: switch to `.select(:id, :name, ...)` or use a presenter
  - Group related fixes (e.g., all N+1s in the same controller)
- Artifact: `query_patches` — `{ migrations: [{ filename, content }], code_patches: [{ file, original, replacement }] }`
- Predicate: `query_fixes_drafted` — artifact has at least one migration or patch
- Why Sonnet: needs to write correct migrations and query optimizations

**run_tests** (shell_script)
- Adapter: `shell_script`
- Input: query_patches artifact
- Task: Apply migrations, apply code patches, run test suite, verify:
  - All tests pass
  - No new query-related warnings
  - Optionally: re-run query collection and compare counts (did we actually reduce queries?)
- Artifact: `test_results`
- Predicate: `tests_passed` (existing)
- On failure: regress to `draft_fixes`

**human_review** (gate)
- Adapter: `fake`
- Important: DBA should review index additions on large tables — adding an index on a 50M-row table in production needs a concurrent migration strategy

### Queue Config

```yaml
name: Database Query Health Check
slug: query_health
stages:
  - collect_queries
  - analyze_performance
  - draft_fixes
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2
stage_configs:
  collect_queries:
    adapter_type: shell_script
    allowed_skills: [run_tests, read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    completion_criteria: [query_inventory_produced]
    agent_prompt: file://prompts/query_collect.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: query_inventory
  analyze_performance:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    completion_criteria: [query_analyzed]
    agent_prompt: file://prompts/query_analyze.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: query_analysis
  draft_fixes:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 2
    completion_criteria: [query_fixes_drafted]
    agent_prompt: file://prompts/query_draft_fixes.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: query_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [tests_passed]
    agent_prompt: Apply migrations and code patches, run the test suite. Report pass/fail.
    timeout_seconds: 600
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review query optimizations and index migrations. Flag large-table indexes for concurrent migration.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates Needed

- `query_inventory_produced` — checks for `query_inventory` artifact with at least one query
- `query_analyzed` — checks for `query_analysis` artifact with findings
- `query_fixes_drafted` — checks for `query_patches` artifact with at least one migration or patch

### E2E Test Fixtures

Create a fixture app in `test/fixtures/apps/slow_queries/` with:
- A model with an N+1 in a controller (`@posts = Post.all` then `post.author.name` in the view)
- A WHERE clause on an unindexed column
- A `SELECT *` on a wide table when only 2 columns are needed
- A counter that queries `COUNT(*)` instead of using a counter cache

### Cross-Queue Spawn

When `analyze_performance` finds queries that need architectural changes (e.g., denormalization, caching layer, read replica routing), it can spawn work items into the `development` queue rather than trying to fix them with index additions.
