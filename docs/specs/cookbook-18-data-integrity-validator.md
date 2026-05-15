# Cookbook Spec: Data Integrity Validator

**Category: Testing**

## Use Case

Your database has orphaned records from a migration that didn't clean up properly. Foreign keys that point to deleted rows. A `status` column with values that don't match any enum. Timestamps in the future. Duplicate records that should be unique. Caches that disagree with the database.

You don't know about any of this until a customer reports something weird, or a query returns unexpected results, or a background job crashes on bad data. Data integrity problems are silent and cumulative — they get worse over time until something breaks visibly.

TaskRail scans your schema for integrity rules, queries the database for violations, categorizes the damage, and drafts repair scripts. Human review before any data is touched.

## Queue: `data_integrity`

### Stages

```
define_rules → scan_violations → assess_damage → draft_repairs → human_review → done
```

### Stage Details

**define_rules** (Sonnet)
- Adapter: `inline_claude`
- Input: database schema (`db/schema.rb`, migrations), model validations, source code
- Task: Build a comprehensive integrity ruleset from the code:
  - **Referential integrity**: every `belongs_to` should have a corresponding record. Every foreign key should point to an existing row.
  - **Constraint violations**: NOT NULL columns with nulls (possible if constraints were added after data existed), unique constraints with duplicates
  - **Enum consistency**: status/type/role columns should only contain known values
  - **Temporal sanity**: `created_at` should be before `updated_at`, timestamps shouldn't be in the future, `deleted_at` should be after `created_at`
  - **Business rules**: amounts should be non-negative, email format, phone format, required associations (e.g., every order must have a customer)
  - **Staleness**: cached counters vs actual counts, denormalized fields vs source of truth
  - Extract rules from model validations, database constraints, and business logic
- Artifact: `integrity_rules` — `{ rules: [{ name, table, type, sql_check, description, severity }] }`
- Predicate: `rules_defined`
- Why Sonnet: needs to understand the data model and business logic to derive meaningful rules

**scan_violations** (shell_script)
- Adapter: `shell_script`
- Input: integrity_rules artifact, database connection
- Task: Run each rule as a SQL query against the database. Count violations.
  - `SELECT COUNT(*) FROM orders WHERE customer_id NOT IN (SELECT id FROM customers)` — orphaned orders
  - `SELECT COUNT(*) FROM users WHERE status NOT IN ('active', 'inactive', 'suspended')` — invalid enums
  - `SELECT COUNT(*) FROM invoices WHERE amount_cents < 0` — negative amounts
  - For each rule: pass/fail, violation count, sample violating rows (limit 10)
- Artifact: `violation_report` — `{ results: [{ rule_name, table, passed: bool, violation_count, sample_rows: [] }], total_violations, tables_affected }`
- Predicate: `violations_scanned`
- Safety: READ-ONLY queries only. This stage must NOT modify data.

**assess_damage** (Sonnet)
- Adapter: `inline_claude`
- Input: violation_report artifact
- Task: For each violation:
  - **Impact**: is this causing user-visible bugs? Silent data corruption? Just cosmetic?
  - **Root cause**: how did this data get here? Missing validation? Failed migration? Race condition? Deleted parent without cascade?
  - **Scope**: how many records? Growing or stable?
  - **Urgency**: fix now (active data corruption) vs. fix eventually (cosmetic) vs. monitor (stable, low impact)
  - Prioritize repairs
- Artifact: `damage_assessment` — `{ findings: [{ rule_name, impact, root_cause_hypothesis, scope, urgency, repair_strategy }], priority_order: [] }`
- Predicate: `damage_assessed`

**draft_repairs** (Sonnet)
- Adapter: `inline_claude`
- Input: damage_assessment, schema, source code
- Task: Draft repair scripts for urgent and high-priority violations:
  - **Orphaned records**: delete or reassign to a default parent
  - **Invalid enums**: map to the closest valid value or set a default
  - **Constraint violations**: backfill nulls, deduplicate
  - **Stale caches**: reset counter caches, refresh materialized views
  - Each repair script must:
    - Be idempotent (safe to run twice)
    - Include a dry-run mode (report what would change without changing it)
    - Include a count before and after
    - Be wrapped in a transaction where appropriate
  - Also draft a migration to prevent recurrence (add the missing constraint, add the missing validation)
- Artifact: `repair_scripts` — `{ repairs: [{ violation_ref, script, dry_run_script, prevention_migration, estimated_rows_affected }] }`
- Predicate: `repairs_drafted`

**human_review** (gate)
- DATA REPAIRS ARE DESTRUCTIVE. Human must review every script, run dry-run first, verify the counts, then approve execution.
- The prevention migrations (constraints, validations) can be reviewed separately from the data repairs.

### Queue Config

```yaml
name: Data Integrity Validator
slug: data_integrity
stages:
  - define_rules
  - scan_violations
  - assess_damage
  - draft_repairs
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
stage_configs:
  define_rules:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    completion_criteria: [rules_defined]
    agent_prompt: file://prompts/integrity_define_rules.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: integrity_rules
  scan_violations:
    adapter_type: shell_script
    allowed_skills: [query_database_readonly]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    completion_criteria: [violations_scanned]
    agent_prompt: file://prompts/integrity_scan.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: violation_report
  assess_damage:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    completion_criteria: [damage_assessed]
    agent_prompt: file://prompts/integrity_assess_damage.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: damage_assessment
  draft_repairs:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 2
    completion_criteria: [repairs_drafted]
    agent_prompt: file://prompts/integrity_draft_repairs.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: repair_scripts
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: DATA REPAIRS — run dry-run scripts first, verify counts, then approve.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates

- `rules_defined` — integrity_rules artifact with at least one rule
- `violations_scanned` — violation_report artifact with results for all rules
- `damage_assessed` — damage_assessment artifact with findings
- `repairs_drafted` — repair_scripts artifact with at least one script

### Safety

This pipeline is READ-ONLY until human review. The `mutate_database` skill is forbidden on every stage. Repair scripts are drafted as artifacts — they are NOT executed automatically. The human reviewer runs the dry-run, checks the output, and manually executes the repair.

### Recurring Use

Run monthly. Track violation counts over time. The prevention migrations (constraints, validations) should reduce violations on subsequent runs. If a violation type keeps reappearing, the root cause hasn't been fixed — spawn into `development` to fix the code path that creates bad data.
