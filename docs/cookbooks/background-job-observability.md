# Background Job Observability Cookbook

The `job_observability` cookbook audits workers and background jobs for retries, timeouts, idempotency, error capture, logging, metrics, and operational visibility.

## Problem Statement

Background jobs often fail quietly. Retry behavior, timeouts, idempotency, logging, and metrics differ across workers, which makes incidents harder to diagnose.

Taskrail turns job observability into a repeatable review queue.

## Stages

```text
scan_job_classes -> assess_observability -> draft_fixes -> run_tests -> human_review -> done
```

## Artifacts

- `job_inventory`: job classes, schedules, queues, retry behavior, dependencies, and owners.
- `observability_scorecard`: logging, metrics, error handling, idempotency, and timeout assessment.
- `fix_patches`: proposed instrumentation or behavior changes.
- `test_results`: validation output for drafted changes.

## Human Gate

Humans review patches and scorecards before accepting instrumentation or retry behavior changes.

## Configurability

Teams can change scoring rules, job frameworks, required metrics, test commands, artifact schemas, and review policy.

## Focused Tests

Run focused cookbook tests after changing predicates, fixtures, or queue config.
