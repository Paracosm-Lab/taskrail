# StupidClaw MVP-0 Runbook

## Purpose

MVP-0 proves the StupidClaw control-plane idea with deterministic fake agents before real model integrations.

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
bin/stupidclaw queues
bin/stupidclaw stages development
bin/stupidclaw submit --queue development --spec ./README.md --title "Smoke test"
bin/stupidclaw list --queue development
bin/stupidclaw status WORK_ITEM_ID
bin/stupidclaw retry WORK_ITEM_ID
bin/stupidclaw cancel WORK_ITEM_ID
```

Set a different API URL:

```bash
STUPIDCLAW_API_URL=http://localhost:3001 bin/stupidclaw queues
```

## Test commands

```bash
bundle exec rspec
bundle exec rspec spec/services/engine/fake_workflow_integration_spec.rb
bundle exec rspec spec/requests/api/v1
bundle exec rspec spec/cli/stupidclaw_spec.rb
```

## What to inspect when debugging

Rails console:

```ruby
WorkItem.order(:created_at).pluck(:title, :stage_name, :status, :retry_count, :regression_count)
TransitionLog.order(:created_at).pluck(:from_stage, :to_stage, :trigger)
Claim.order(:created_at).pluck(:agent_type, :status, :async_execution)
Trace.sum(:total_cost_cents)
```

## Next phase

Add real adapters only after MVP-0 stays green:

1. ShellScriptAdapter for deterministic test/lint stages
2. InlineClaudeAdapter for intake/decompose/review
3. CodexAdapter for async build/fix claims
4. TUI skin on top of the same API
