# Taskrail Documentation

Taskrail is an open-source queue layer for AI workflows. It keeps the workflow outside the agent by storing queues, stages, claims, artifacts, traces, reports, retries, regressions, pipes, and human escalations in explicit Rails/Postgres records.

The shortest description is:

> The agent does not own the workflow. The queue does.

Product loop:

```text
Define stages. Run agents. Observe execution. Reuse the queue.
```

## Start Here

- [Quickstart](./quickstart.md) - run Taskrail locally and process your first work item.
- [Installation](./installation.md) - prerequisites and local setup.
- [Overview](./overview.md) - what Taskrail is and when to use it.
- [Core Concepts](./concepts.md) - queues, stages, work items, claims, reports, artifacts, traces, predicates, and transitions.
- [Create a Queue](./create-a-queue.md) - build your own queue from scratch.
- [Adapters](./adapters.md) - run agents, models, scripts, CI, and containers behind one lifecycle.
- [Predicates](./predicates.md) - define what done means.
- [Artifacts and Reports](./artifacts-and-reports.md) - reviewable evidence from each stage.
- [Architecture](./architecture.md) - Rails app, engine loop, adapters, queues, pipes, API, UI, CLI, and TUI.
- [API Reference](./api.md) - HTTP endpoints for queues, work items, costs, digests, streams, pipes, and GitHub webhooks.
- [Configuration](./configuration.md) - queue YAML, stage configs, adapters, predicates, prompts, pipes, and runtime settings.
- [Operations](./operations.md) - running the engine, async claims, diagnostics, testing, and operational notes.
- [Test Plan](./test-plan.md) - automated gates for auth, PATs, adapters, streams, CI, and release readiness.
- [Troubleshooting](./troubleshooting.md) - common local and execution failures.
- [Deployment](./deployment.md) - production deployment concerns.
- [Comparison](./comparison.md) - why Taskrail exists alongside generic runners.
- [Cookbook Catalog](./cookbooks/index.md) - included development, testing, DevOps, security, and data workflows.

## What Taskrail Controls

Taskrail gives teams a repeatable way to run AI work with:

- Explicit stage transitions.
- Queue-owned completion criteria.
- Adapter-driven execution.
- Reviewable artifacts and reports.
- Cost and trace visibility.
- Retry and regression budgets.
- Human escalation when work is blocked.
- Cross-queue routing through pipes.
- Reusable cookbooks for recurring engineering operations.

## Main Interfaces

- Web UI: queue boards, work item views, pipes, retries, and cancellations.
- API: JSON endpoints under `/api/v1`.
- CLI: `bin/taskrail` for queue inspection, submission, status, costs, digests, and doctor checks.
- TUI: terminal dashboard backed by the same API.
- Engine: `Engine::Runner` and recurring jobs that execute pending work.

## Repository Map

```text
app/                    Rails app code
app/adapters/           Adapter implementations for fake, shell, Claude, Codex, Docker Compose
app/controllers/        Web, API, health, and admin endpoints
app/models/             WorkQueue, WorkItem, Claim, Artifact, Report, Trace, Pipe, transition records
app/services/engine/    Runner, transition manager, predicates, pipes, assignment building, async checks
bin/taskrail            CLI entrypoint
config/queues/          Cookbook and workflow definitions
config/pipes/           Cross-queue routing definitions
cookbooks/              Cookbook fixtures, prompts, runbooks, and fake services
docs/                   Product, architecture, cookbook, and operational documentation
prompts/                Prompt files referenced by queue configs
spec/                   RSpec coverage for engine, adapters, API, cookbooks, and UI
tui/                    Node/React terminal dashboard
```
