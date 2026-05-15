# Taskrail MVP-0 Runbook

## Purpose

MVP-0 proves the Taskrail control-plane idea with deterministic fake agents before real model integrations.

Core principle:

```text
The agent does not own the workflow. The queue owns the workflow.
```

## Local start

```bash
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
docker compose up -d postgres
bin/rails db:prepare
bin/rails db:seed
bin/rails server
```

Postgres uses host port `5433` in this project.

## One-tick processing

```bash
bin/rails runner 'Engine::Runner.new.call'
```

Run repeatedly to drain pending work:

```bash
bin/rails runner '20.times { Engine::Runner.new.call }'
```

## CLI examples

```bash
bin/taskrail queues
bin/taskrail stages development
bin/taskrail submit --queue development --spec ./README.md --title "Smoke test"
bin/taskrail list --queue development
bin/taskrail list --queue development --stage build --status blocked --tag risk=high
bin/taskrail status WORK_ITEM_ID
bin/taskrail status WORK_ITEM_ID --traces
bin/taskrail costs
bin/taskrail costs --today
bin/taskrail costs --work-item WORK_ITEM_ID
bin/taskrail answer WORK_ITEM_ID "Use bearer tokens"
bin/taskrail retry WORK_ITEM_ID
bin/taskrail cancel WORK_ITEM_ID
```

Set a different API URL:

```bash
TASKRAIL_API_URL=http://localhost:3001 bin/taskrail queues
```

## Test commands

```bash
bundle exec rspec
bundle exec rspec spec/services/engine/fake_workflow_integration_spec.rb
bundle exec rspec spec/requests/api/v1
bundle exec rspec spec/cli/taskrail_spec.rb
bundle exec rspec spec/services/cli
```

## Dashboard TUI

The TUI skin is available through the existing API-backed CLI:

```bash
bin/taskrail dashboard --queue development
bin/taskrail dashboard --queue development-codex --status pending --limit 20
bin/taskrail dashboard --queue development --watch --refresh 5
```

The dashboard is a read-only terminal skin over the Rails API. It uses `TASKRAIL_API_URL` like the rest of `bin/taskrail`, renders queue stages/work items/costs, and shows safe active-claim summaries for async Codex work without exposing prompts, full assignments, or credentials. Blocked items with human escalations show a `HUMAN:` marker plus an action hint to run `bin/taskrail answer WORK_ITEM_ID "your guidance"`. It does not own workflow transitions; queue-owned transitions remain authoritative. Use the existing `submit`, `answer`, `retry`, and `cancel` commands for writes.

## Human escalation and observability

When retry or review-regression budgets are exhausted, Taskrail blocks the work item and stores a safe escalation summary. Operators resolve it with:

```bash
bin/taskrail answer WORK_ITEM_ID "your guidance"
```

Useful inspection commands:

```bash
bin/taskrail status WORK_ITEM_ID --traces
bin/taskrail costs
bin/taskrail costs --today
bin/taskrail costs --work-item WORK_ITEM_ID
bin/taskrail list --queue development --status blocked --tag risk=high
```

`status --traces` returns sanitized trace summaries only. Prompt-derived input summaries and prompt/assignment/credential/token metadata are redacted.

## What to inspect when debugging

Rails console:

```ruby
WorkItem.order(:created_at).pluck(:title, :stage_name, :status, :retry_count, :regression_count)
TransitionLog.order(:created_at).pluck(:from_stage, :to_stage, :trigger)
Claim.order(:created_at).pluck(:agent_type, :status, :async_execution)
Trace.sum(:total_cost_cents)
```

## Completed stages

The next-phase adapter and TUI milestones are now implemented on top of MVP-0 while preserving the fake-backed default `development` queue:

1. ShellScriptAdapter for deterministic test/lint stages
2. InlineClaudeAdapter for intake/decompose/review
3. CodexAdapter for async build/fix claims
4. TUI skin on top of the same API
