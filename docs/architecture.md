# Architecture

Taskrail is a Rails 8 application with Postgres-backed workflow state, a queue-driven execution engine, adapter abstractions, web/API interfaces, and a terminal dashboard.

## High-Level Flow

```text
WorkQueue YAML
  -> db seed / queue records
  -> WorkItem created
  -> Engine::Runner picks pending item
  -> Engine::AgentMatcher finds StageConfig
  -> Engine::ClaimExecutor builds assignment
  -> Adapter executes work
  -> Report, Artifact, Trace, TraceEvent records persisted
  -> Engine::TransitionManager evaluates predicates
  -> advance, retry, regress, block, spawn, pipe, or complete
```

## Main Components

### Rails App

The app provides API, web UI, admin settings, models, jobs, and services.

Key directories:

- `app/models`: persistent workflow records.
- `app/services/engine`: execution lifecycle, predicates, pipes, assignment building, async checks.
- `app/adapters`: concrete execution adapters.
- `app/controllers/api/v1`: JSON API.
- `app/controllers/web`: browser UI.
- `config/queues`: queue and stage definitions.
- `config/pipes`: cross-queue routing definitions.

### Engine Runner

`Engine::Runner` performs one engine tick:

1. Advance waiting parent work items whose children are complete.
2. Pick the oldest pending work item without an active claim.
3. Match the current stage to a `StageConfig`.
4. Create a `Claim` for the execution attempt.
5. Execute the stage via `Engine::ClaimExecutor`.
6. If the adapter is synchronous, transition the item immediately.
7. If the adapter is asynchronous, leave the claim active for polling.

Run one tick manually:

```bash
bin/rails runner 'Engine::Runner.new.call'
```

### Claims and Adapters

A `Claim` represents one execution attempt for one work item and stage. The claim stores the assignment sent to the adapter and tracks status, async execution, heartbeat, and completion timestamps.

Supported adapter types:

- `fake`: deterministic in-process adapter for local development and tests.
- `shell_script`: runs configured shell commands and captures output as artifacts.
- `inline_claude`: calls a local Claude CLI synchronously.
- `codex`: submits work to Codex CLI asynchronously and polls later.
- `docker_compose`: starts Docker Compose work and tracks it as async execution.

Adapters return either:

- `AgentResult`: synchronous normalized result with status, report, artifacts, trace events, and optional blocked question.
- `Engine::AsyncAdapterResult`: async submission metadata with provider, external ID, status, and trace events.

### Transition Manager

`Engine::TransitionManager` owns queue advancement logic. It evaluates each stage's `completion_criteria` through predicate classes.

Outcomes include:

- Advance to the next stage.
- Mark the item completed when the next stage is `done`.
- Retry the same stage with feedback.
- Regress to an earlier stage for review or test failures.
- Block with human escalation when retry or regression budgets are exhausted.
- Decompose work into child work items.
- Spawn cross-queue work from report payloads.
- Fire configured pipes into downstream queues.

### Pipes

Pipes route completed work from one queue and stage into another queue. A pipe can:

- Match artifact data with simple conditions.
- Copy selected artifacts to the downstream item.
- Add tags.
- Generate a downstream title from a template.
- Limit child creation to avoid runaway workflows.

Example: `config/pipes/security_to_development.yml` routes high-severity security findings into the development queue.

### Web UI

The web UI exposes queue boards, work item detail views, pipes, retries, cancellations, and new work item creation.

Core routes:

- `/`
- `/queues/:slug`
- `/queues/:slug/board`
- `/work_items/:id`
- `/work_items/new`
- `/pipes`

### CLI and TUI

`bin/taskrail` talks to the API. With no command, it starts the TUI dashboard.

Useful commands:

```bash
bin/taskrail doctor
bin/taskrail queues
bin/taskrail stages development
bin/taskrail submit --queue development --title "Smoke test" --spec ./README.md
bin/taskrail list --queue development --status pending
bin/taskrail status WORK_ITEM_ID --traces
bin/taskrail retry WORK_ITEM_ID
bin/taskrail cancel WORK_ITEM_ID
bin/taskrail answer WORK_ITEM_ID "Use bearer tokens"
bin/taskrail costs --today
bin/taskrail digest --since 24h
```
