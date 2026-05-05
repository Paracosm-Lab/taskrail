# Chaos Monkey / Chaos Response Cookbook

Source spec: `docs/specs/cookbook-09-chaos-monkey.md`
Implementation plan: `docs/plans/cookbooks/09-chaos-monkey.md`

## Purpose

This cookbook exercises incident response by letting one queue create a safe, reversible staging disruption while a second queue diagnoses and recovers from the alerts without seeing the disruption plan.

The result is a staged chaos exercise that identifies runbook gaps, alerting gaps, and recovery workflow weaknesses before they matter in production.

## Queue architecture

Two seeded queues are involved:

- `chaos_monkey`: plans a staging-only disruption, executes the disruption, observes impact, waits for a response work item, evaluates recovery, and writes the final report.
- `chaos_response`: detects alerts, diagnoses the incident from alert evidence only, selects a runbook, executes it against the fixture, verifies recovery, and reports the outcome.

The response queue is intentionally blind. Its `diagnose_failure` stage has `forbidden_skills` including `read_disruption_plan` and `execute_staging`, so diagnosis must come from alerts and runbooks rather than direct knowledge of what the chaos queue broke.

## Safety checklist

Before running this cookbook:

- Confirm the target is staging or the local fixture only.
- Confirm every disruption has reversal steps.
- Do not provide production credentials, production hostnames, or production Compose contexts.
- Keep `execute_disruption.max_retries: 0`; failed attempts to break staging should not be retried automatically.
- Confirm the Compose path is the fixture path: `spec/fixtures/chaos_staging/docker-compose.staging.yml`.
- Use the runbook in `docs/runbooks/chaos/postgres-unavailable.md` for the fixture Postgres outage scenario.

## Seed the queues

From the repository root:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bin/rails db:seed
```

Inspect in Rails console:

```ruby
chaos = WorkQueue.find_by!(slug: "chaos_monkey")
response = WorkQueue.find_by!(slug: "chaos_response")
chaos.stages
response.stage_configs.find_by!(stage_name: "diagnose_failure").forbidden_skills
```

## Fixture notes

Shared cookbook infrastructure owns the common fake-service conventions. This cookbook adds only scenario-specific fixture files under `spec/fixtures/chaos_staging`:

- `docker-compose.staging.yml`
- a tiny Rack API fixture
- deterministic shell scripts for safe disruption, alert detection, impact monitoring, and recovery verification

Useful environment variables:

- `CHAOS_STAGING_API_PORT` defaults to `3929`.
- `CHAOS_STAGING_POSTGRES_PORT` defaults to `55432`.

The scripts emit deterministic JSON so shell-backed stages can persist artifacts such as `impact_report`, `detected_alerts`, and `recovery_verification` when the adapter supports the configured artifact mapping.

## Expected artifacts

Chaos queue artifacts:

- `disruption_plan`
- `disruption_record`
- `impact_report`
- `recovery_evaluation`
- `chaos_report`

Response queue artifacts:

- `detected_alerts`
- `diagnosis`
- `runbook_selection`
- `runbook_execution`
- `recovery_verification`
- `response_outcome`

Zero alerts and null runbook selection are valid findings when recorded explicitly; they should produce follow-up work for instrumentation or runbook coverage.
