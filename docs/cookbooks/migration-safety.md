# Migration Safety Check Cookbook

Source spec: `docs/specs/cookbook-14-migration-safety.md`
Queue slug: `migration_safety`
Category: Development

## What it does

This cookbook checks scary migrations before cutover. It maps affected code paths, enumerates risks, drafts rollback procedures, tests rollback in a staging-like Docker-friendly fixture, and produces a migration runbook for human review.

## Stages

1. `scan_impact` -> `impact_map`
2. `enumerate_risks` -> `risk_assessment`
3. `draft_rollback` -> `rollback_plan`
4. `test_rollback` -> `rollback_test_results`
5. `draft_runbook` -> `migration_runbook` / success report
6. `human_review`
7. `done`

## Fixture

The fixture app at `cookbooks/fixtures/apps/migration_safety_app` models an unsafe large-table database migration: adding a `NOT NULL` column with a default to `orders`.

The safe path uses expand/backfill/contract:

- add nullable column
- backfill in batches
- enforce `NOT NULL`

## Verification

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/impact_mapped_spec.rb \
  spec/services/engine/predicates/risks_enumerated_spec.rb \
  spec/services/engine/predicates/rollback_drafted_spec.rb \
  spec/services/engine/predicates/rollback_tested_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/system/migration_safety_cookbook_spec.rb
```
