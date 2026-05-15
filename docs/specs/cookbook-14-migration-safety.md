# Cookbook Spec: Migration Safety Check

**Category: Development**

## Use Case

You're about to do something scary: upgrade the database schema on a 50M-row table, swap out a payment provider, migrate from REST to GraphQL, or move from Heroku to Kubernetes. You've planned it out in a doc. You think it'll work. But you haven't tested the rollback, you haven't enumerated every code path that touches the old thing, and you're not sure staging actually matches production.

TaskRail scans for everything affected, simulates the failure modes, drafts rollback procedures, and tests them against staging before you cut over. Measure twice, cut once.

## Queue: `migration_safety`

### Stages

```
scan_impact → enumerate_risks → draft_rollback → test_rollback → draft_runbook → human_review → done
```

### Stage Details

**scan_impact** (Sonnet)
- Adapter: `inline_claude`
- Input: migration spec (what's changing), repository
- Task: Find every code path affected by the migration:
  - Database migration: every model, query, index, constraint that references the changing table/column
  - API migration: every consumer, client, integration that calls the changing endpoint
  - Infrastructure migration: every config, env var, connection string, health check that references the old system
  - Dependency migration: every import, require, API call that uses the old version
  - Map: `{ affected_files: [], affected_tests: [], affected_configs: [], external_consumers: [] }`
- Artifact: `impact_map` — full list of everything that touches the migrating component
- Predicate: `impact_mapped`
- Why Sonnet: needs to trace references across the codebase and understand indirect dependencies

**enumerate_risks** (Sonnet)
- Adapter: `inline_claude`
- Input: impact_map artifact, migration spec
- Task: For each affected path, identify what can go wrong:
  - **Data loss**: can the migration lose or corrupt data?
  - **Downtime**: will there be a period where the system is unavailable?
  - **Partial failure**: what happens if the migration succeeds on one service but fails on another?
  - **Backwards compatibility**: can old code talk to new schema/API? Can new code talk to old?
  - **Rollback blockers**: what makes rollback impossible? (e.g., destructive column drops, one-way data transforms)
  - Rate each risk as `blocking` / `high` / `medium` / `low`
- Artifact: `risk_assessment` — `{ risks: [{ category, description, severity, affected_paths, mitigation }], blocking_risks: [] }`
- Predicate: `risks_enumerated`

**draft_rollback** (Sonnet)
- Adapter: `inline_claude`
- Input: risk_assessment, migration spec, source code
- Task: Write a concrete rollback procedure for every blocking and high risk:
  - Database: reverse migration file, data restore commands, verification queries
  - API: feature flag to switch back, DNS/routing rollback, client notification plan
  - Infrastructure: previous config restore, deployment rollback commands
  - Each step must be testable in staging
- Artifact: `rollback_plan` — `{ procedures: [{ risk_ref, steps: [{ action, command, verification }], estimated_time, data_loss_potential }] }`
- Predicate: `rollback_drafted`

**test_rollback** (docker_compose)
- Adapter: `docker_compose`
- Input: rollback_plan, staging environment
- Task: Execute the migration in staging, then execute the rollback, then verify:
  - Did the rollback complete without errors?
  - Is the system functional after rollback?
  - Was any data lost?
  - Do the health checks pass?
- Artifact: `rollback_test_results` — `{ migration_succeeded, rollback_succeeded, data_intact, health_checks_passed, issues: [] }`
- Predicate: `rollback_tested` — migration and rollback both succeeded
- On failure: regress to `draft_rollback` with test output

**draft_runbook** (Opus)
- Adapter: `inline_claude`
- Input: all upstream artifacts
- Task: Produce a complete migration runbook:
  - Pre-migration checklist (backups, communication, maintenance windows)
  - Step-by-step migration procedure with verification after each step
  - Rollback procedure (tested and proven)
  - Post-migration verification
  - Escalation contacts
  - Go/no-go decision criteria
- Artifact: `migration_runbook`
- Predicate: `report_present` (existing)

**human_review** (gate)

### Queue Config

```yaml
name: Migration Safety Check
slug: migration_safety
stages:
  - scan_impact
  - enumerate_risks
  - draft_rollback
  - test_rollback
  - draft_runbook
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2
stage_configs:
  scan_impact:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    completion_criteria: [impact_mapped]
    agent_prompt: file://prompts/migration_scan_impact.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: impact_map
  enumerate_risks:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    completion_criteria: [risks_enumerated]
    agent_prompt: file://prompts/migration_enumerate_risks.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: risk_assessment
  draft_rollback:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 2
    completion_criteria: [rollback_drafted]
    agent_prompt: file://prompts/migration_draft_rollback.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: rollback_plan
  test_rollback:
    adapter_type: docker_compose
    allowed_skills: [execute_staging]
    forbidden_skills: [deploy]
    max_retries: 1
    completion_criteria: [rollback_tested]
    agent_prompt: file://prompts/migration_test_rollback.md
    timeout_seconds: 1200
    adapter_config:
      compose_file: docker-compose.staging.yml
      output_artifact_kind: rollback_test_results
  draft_runbook:
    adapter_type: inline_claude
    model_override: claude-opus-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 1
    completion_criteria: [report_present]
    agent_prompt: file://prompts/migration_draft_runbook.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: migration_runbook
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review migration plan, rollback procedures, and runbook.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates

- `impact_mapped` — impact_map artifact with affected files
- `risks_enumerated` — risk_assessment artifact with risks
- `rollback_drafted` — rollback_plan artifact with procedures
- `rollback_tested` — rollback_test_results with both migration and rollback succeeded

### E2E Test Fixtures

Use a simple database migration as the test case: add a NOT NULL column with a default to an existing table. The pipeline should identify that this can lock the table on large datasets, draft a concurrent migration approach, test the rollback, and produce a runbook.
