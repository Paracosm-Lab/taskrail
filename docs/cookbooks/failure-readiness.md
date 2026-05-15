# Failure Readiness Cookbook

Source spec: `docs/cookbook-failure-readiness.md`

Failure Readiness runs a proactive incident drill before production breaks. It simulates realistic Sentry alerts, feeds them through the `operations` queue, clusters related failures, scores alert instrumentation, drafts runbooks, and spawns development work for thin alerts.

## Stages

1. `ingest_signals`: normalize Sentry events into operational signals.
2. `cluster_failures`: group related failures such as CRM Postgres connection refusal and pool exhaustion.
3. `assess_instrumentation`: score error specificity, context richness, breadcrumbs, reproducibility, and structured metadata. Thin alerts should emit `spawn_work_items` targeting the `development` queue.
4. `map_runbooks`: find matching runbooks or mark them missing/stale.
5. `draft_runbook`: draft observe, mitigate, verify, and escalation steps.
6. `human_review`: gate before staging validation or publishing.
7. `staging_validation`: execute approved runbooks against safe staging/fake infrastructure.
8. `publish_runbook`: write approved runbooks to the service docs convention.

## Fixtures

Sentry fixtures live in `test/fixtures/sentry/`:

- `db_pool_timeout.json`
- `db_connection_bad.json`
- `null_reference.json`
- `rate_limit_thin.json`

Dry-run fixture generation:

```bash
bin/generate-sentry-alerts --dry-run
bin/generate-sentry-alerts --alert all --dry-run
```

Use `--dsn` or `SENTRY_DSN` only when intentionally posting to a non-production Sentry project.

## Example runbooks

Draft example runbooks for this cookbook live in `docs/runbooks/failure-readiness/`. They are not production-approved; each includes `Human review required` until an operator validates commands, access, and escalation ownership.

## Focused verification

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/system/failure_readiness_cookbook_spec.rb \
  spec/system/generate_sentry_alerts_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/cross_queue_spawn_spec.rb \
  spec/adapters/adapters/response_parser_spec.rb
```

## Safety notes

- Never run generated runbooks against production without human review.
- Keep fixture paths repo-relative.
- Keep fake staging ports configurable with environment variables.
- Do not store real Sentry credentials in fixtures, docs, queue YAML, or tests.
