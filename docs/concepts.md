# Core Concepts

## WorkQueue

A `WorkQueue` defines a reusable workflow. It has a name, slug, category, ordered stages, and queue-level config.

Queues are loaded from `config/queues/*.yml` and persisted in Postgres.

Example stages:

```text
intake -> decompose -> build -> test -> review -> done
```

## StageConfig

A `StageConfig` defines how one stage runs.

Important fields:

- `stage_name`: stage identifier.
- `adapter_type`: execution adapter, such as `fake`, `shell_script`, `inline_claude`, `codex`, or `docker_compose`.
- `adapter_config`: adapter-specific options.
- `allowed_skills`: capabilities the assignment may use.
- `forbidden_skills`: capabilities the assignment must not use.
- `completion_criteria`: predicate names required to advance.
- `agent_prompt`: inline prompt text or `file://` prompt path.
- `model_override`: optional model identifier.
- `max_retries`: retry budget for the stage.
- `timeout_seconds`: execution timeout.
- `escalation_target`: where blocked work should route.

## WorkItem

A `WorkItem` is one unit of work moving through a queue.

Key fields:

- `title`
- `spec_url`
- `work_queue_id`
- `stage_name`
- `status`
- `tags`
- `metadata`
- `retry_count`
- `regression_count`
- `parent_id`
- `pipe_id`

Statuses:

- `pending`
- `claimed`
- `blocked`
- `waiting`
- `completed`
- `cancelled`

## Claim

A `Claim` records one adapter execution attempt for a work item stage.

Claims store:

- Adapter type as `agent_type`.
- Assignment payload.
- Status.
- Async execution state.
- Start and completion timestamps.
- Heartbeat timestamps and messages.

## Assignment

`Engine::AssignmentBuilder` constructs the payload sent to adapters. It includes:

- Claim ID and callback URL.
- Work item title, spec URL, tags, and parent ID.
- Stage name, adapter type, adapter config, skills, and completion criteria.
- Prompt and model override.
- Resolved spec content.
- Upstream reports and artifacts.
- Human answer and feedback from prior retries or regressions.
- Limits such as timeout, max tokens, and max cost.

## AgentResult

Adapters return normalized results so the engine does not care whether the work came from a script, fake adapter, Claude, Codex, or Docker Compose.

A result contains:

- Status.
- Report body.
- Artifacts.
- Trace events.
- Optional blocked question.

## Report

A `Report` is the structured outcome of a claim for a stage. Reports are evaluated by predicates and surfaced to humans.

## Artifact

An `Artifact` is a typed output from a stage, such as:

- `branch`
- `test_results`
- `coverage_map`
- `vulnerability_scan`
- `severity_report`
- `rollback_plan`
- `migration_runbook`

Artifacts can be consumed by later stages or copied across queues through pipes.

## Trace and TraceEvent

Traces record execution cost and observability metadata.

A `Trace` totals:

- Tokens in.
- Tokens out.
- Cost cents.
- Duration milliseconds.

`TraceEvent` rows capture ordered events inside the claim. API serialization redacts sensitive prompt, token, secret, password, credential, and authorization-like fields.

## Predicate

Predicates are named completion checks. Stage configs reference them by name in `completion_criteria`. Predicate classes live under `app/services/engine/predicates` and return `Engine::PredicateResult`.

Examples:

- `report_present`
- `branch_created`
- `tests_passed`
- `lint_clean`
- `review_verdict`
- `scan_completed`
- `severity_classified`
- `rollback_tested`

## TransitionLog

A `TransitionLog` records why a work item moved or stopped.

Common triggers:

- `rule_satisfied`
- `retry`
- `blocked`
- `regression`
- `decompose`
- `children_completed`
- `spawn`
- `pipe`
- `pipe_received`
- `manual_retry`
- `cancelled`
- `human_answer`

## Pipe

A `Pipe` connects queues. It observes completed stages, checks artifact conditions, creates downstream work items, copies artifacts, and logs both sides of the handoff.
