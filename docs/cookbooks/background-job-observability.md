# Background Job Observability Cookbook

Source spec: `docs/specs/cookbook-12-background-job-observability.md`

The `job_observability` queue audits async jobs and workers for missing error capture, structured logging, timeout protection, retry strategy, idempotency, context propagation, and metrics.

## Stages

1. `scan_job_classes`: catalogs job classes into a `job_inventory` artifact.
2. `assess_observability`: scores each job and writes an `observability_assessment` artifact plus a human-readable scorecard.
3. `draft_fixes`: drafts `job_patches` for blind and under-instrumented jobs.
4. `run_tests`: applies or validates patches through the configured shell test command.
5. `human_review`: blocks for review before work is considered complete.
6. `done`: terminal state.

## Fixture app

The fixture app at `test/fixtures/apps/uninstrumented_jobs/` includes:

- `ExportJob`: no instrumentation.
- `BillingJob`: good instrumentation example.
- `SyncJob`: infinite retries with no timeout or dead letter strategy.
- `CleanupJob`: silently swallows errors.

## Infrastructure expectations

This cookbook assumes the shared StupidClaw development/test infrastructure is already available. It does not define new Docker Compose services. External services in the fixture app are fake Ruby classes so the cookbook can run in local and Docker-friendly test environments.

## Focused tests

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/job_inventory_produced_spec.rb \
  spec/services/engine/predicates/observability_assessed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/system/job_observability_cookbook_spec.rb
```
