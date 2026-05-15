# Overview

Taskrail is an open-source queue layer for AI workflows. It is built for work that is too important to hand to an agent as an open-ended prompt, but repeatable enough to encode as stages, predicates, artifacts, adapters, and review gates.

## Problem

AI agents can generate patches, tests, analysis, runbooks, dependency upgrades, and security findings. The hard part is not only getting output. The hard part is controlling the lifecycle around that output:

- What stage is the work in?
- What is the definition of done?
- What evidence did the agent produce?
- What did it cost?
- What retries happened?
- When should work regress, block, or escalate?
- Can the same workflow run across many repos, services, and teams?

Taskrail answers those questions by making the workflow explicit.

## Thesis

Agents should be replaceable workers behind narrow adapters. The queue owns the lifecycle.

That means:

- Stage order is configured in YAML.
- Each stage has allowed skills, forbidden skills, prompts, adapter settings, retry limits, and predicates.
- Adapters run the work and return normalized results.
- The engine persists reports, artifacts, traces, costs, and transition logs.
- Predicates decide whether a stage advances.
- Failed criteria trigger retries, regressions, blocks, or human escalation.

## Why It Is Flexible

The queue abstraction is the product. A queue can coordinate agents, scripts, CI, model calls, containerized checks, or human review as long as each stage produces evidence and predicates decide advancement.

The cookbook is included, but teams can define their own stages, adapters, prompts, predicates, artifacts, retry rules, gates, and execution targets.

## When To Use Taskrail

Taskrail is a fit for recurring workflows where auditability and control matter:

- Feature development with decomposition, build, test, and review gates.
- Test coverage backfill and integration test generation.
- Dependency upgrades with audit, prioritization, patching, test, and review.
- Security scans that classify findings and spawn follow-up work.
- Migration safety checks with rollback planning and proof.
- Incident readiness, chaos response, runbook generation, and post-incident replay.
- Credential rotation, data integrity checks, query health, logging audits, and infrastructure drift.

## What Taskrail Is Not

Taskrail is not a general chat UI. It is not a single-agent task runner. It is not a replacement for CI, issue trackers, workflow engines, or human review.

It is a queue layer that can call local scripts, CI commands, Claude, Codex, Docker Compose, fake deterministic adapters, and future adapters through the same lifecycle.

See [Comparison](./comparison.md) for how Taskrail relates to generic runners.
