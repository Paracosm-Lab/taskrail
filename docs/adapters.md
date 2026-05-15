# Adapters

Adapters run work for a stage and return normalized execution results. They let Taskrail use different models, CLIs, scripts, containers, and future agents behind the same queue lifecycle.

## What an Adapter Does

An adapter receives an assignment and returns either:

- a synchronous result, or
- an async submission that will be polled later.

The engine stores reports, artifacts, traces, trace events, and transition logs regardless of which adapter ran.

## Built-In Adapter Types

### `fake`

Deterministic in-process adapter for local development and tests. Use it for quickstarts, fixtures, and workflow validation without model calls.

### `shell_script`

Runs configured shell commands and captures output as artifacts. Useful for tests, lint, audits, fixture scripts, and deterministic validation steps.

### `inline_claude`

Runs a local Claude CLI synchronously and parses the response into normalized reports and artifacts.

### `codex`

Submits work to Codex CLI asynchronously and polls later. Useful for long-running implementation stages.

### `docker_compose`

Starts Docker Compose work and tracks it as an async execution with heartbeat state.

## Sync vs Async

Synchronous adapters finish during the engine tick. The transition manager can evaluate predicates immediately.

Async adapters submit work, keep the claim active, and rely on async polling to complete later.

## Normalized Result Shape

Adapters should produce:

- status
- report body
- artifacts
- trace events
- optional blocked question
- optional async metadata

This lets the queue reason about work without caring which model or tool ran it.

## Model Flexibility

Model choice is stage policy. Routine stages can use cheaper models or scripts. Judgment-heavy stages can use stronger models. The queue lifecycle stays the same.

## Adding an Adapter

A new adapter should:

1. Accept an assignment.
2. Execute or submit work.
3. Return normalized result data.
4. Emit safe trace events.
5. Avoid leaking secrets in reports or traces.
6. Support tests with deterministic fixtures.

## Safety

Adapters should not own workflow advancement. They produce evidence. Predicates and transition rules decide what happens next.
