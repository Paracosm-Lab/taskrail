# StupidClaw

StupidClaw is a Rails-native workflow control plane for agent work.

The thesis is simple: the agent does not own the workflow; the queue owns the workflow. StupidClaw keeps stages, retries, review regressions, child decomposition, traces, reports, and transitions in explicit Rails records. Agents are replaceable workers behind narrow adapters.

## MVP-0

MVP-0 includes:

- Rails API app backed by PostgreSQL
- Explicit `WorkQueue` and stage configuration records
- `WorkItem`, `Claim`, `Report`, `Artifact`, `Trace`, `TraceEvent`, and `TransitionLog` records
- Deterministic fake adapter for intake, decompose, build, test, and review stages
- Queue-owned transition manager
- Retry/blocking behavior
- Review regression from `review` back to `build`
- Decomposition into child work items
- One-tick engine runner
- ActiveJob wrappers
- JSON API endpoints
- Thin `bin/stupidclaw` CLI
- End-to-end fake workflow coverage

MVP-0 intentionally excludes real Claude/Codex/model adapters. Those come after the fake workflow is boring and reliable.

## Requirements

- Ruby managed by rbenv
- Rails 8.0.5
- Docker / Docker Compose
- PostgreSQL via the included `docker-compose.yml`

The local Compose file maps PostgreSQL to host port `5433` to avoid conflicts with other local Postgres instances.

## Setup

From this directory:

```bash
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
bundle install
docker compose up -d postgres
bin/rails db:prepare
bin/rails db:seed
```

The seed task loads every queue YAML file from:

```text
config/queues/*.yml
```

The default `development` queue remains fully fake-backed. The optional `development-shell` queue uses `ShellScriptAdapter` for the `test` stage so shell-produced evidence can satisfy queue-owned transition predicates.

Seeds are intended to be idempotent.

## Run the API server

```bash
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
bin/rails server
```

The API defaults to:

```text
http://localhost:3000
```

## Run one engine tick

```bash
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
bin/rails runner 'Engine::Runner.new.call'
```

A tick does this:

1. Advances waiting parents whose children are completed.
2. Finds the first pending work item without an active claim.
3. Matches it to the current stage adapter.
4. Creates a claim.
5. Executes the adapter inline for MVP-0.
6. Persists report/artifacts/trace data.
7. Applies queue-owned transition rules.

## API

Implemented endpoints:

```text
GET    /api/v1/queues
GET    /api/v1/queues/:slug/stages
POST   /api/v1/work_items
GET    /api/v1/work_items/:id
GET    /api/v1/work_items
POST   /api/v1/work_items/:id/answer
POST   /api/v1/work_items/:id/retry
POST   /api/v1/work_items/:id/cancel
GET    /api/v1/costs
GET    /api/v1/costs/work_items/:id
```

Create a work item:

```bash
curl -s -X POST http://localhost:3000/api/v1/work_items \
  -H 'Content-Type: application/json' \
  -d '{"queue":"development","title":"Smoke test","spec_url":"./README.md"}'
```

List work items:

```bash
curl -s 'http://localhost:3000/api/v1/work_items?queue=development'
```

## CLI

The CLI talks to the Rails API. The default API base URL is `http://localhost:3000`; override it with `STUPIDCLAW_API_URL`.

```bash
bin/stupidclaw queues
bin/stupidclaw stages development
bin/stupidclaw submit --queue development --spec ./README.md --title "Smoke test"
bin/stupidclaw list --queue development
bin/stupidclaw list --queue development --stage build
bin/stupidclaw status WORK_ITEM_ID
bin/stupidclaw answer WORK_ITEM_ID "Use bearer tokens"
bin/stupidclaw retry WORK_ITEM_ID
bin/stupidclaw cancel WORK_ITEM_ID
```

## Fake workflow smoke test

With the database prepared and seeded:
```bash
bin/rails runner 'queue = WorkQueue.find_by!(slug: "development"); item = WorkItem.create!(work_queue: queue, title: "Smoke test", spec_url: "opaque spec", stage_name: queue.stages.first); 40.times { Engine::Runner.new.call; break if item.reload.completed? }; puts({ id: item.id, status: item.status, stage: item.stage_name }.to_json)'
```

Expected output includes:

```json
{"status":"completed","stage":"done"}
```

## ShellScriptAdapter

`ShellScriptAdapter` is the first real, non-fake adapter. It is intended for deterministic validation stages where the queue should execute local shell commands and convert their results into normal StupidClaw artifacts.

The seeded `development-shell` queue keeps intake, decompose, build, review, and done fake-backed, but uses `shell_script` for the `test` stage:

```bash
bin/stupidclaw stages development-shell
```

A shell-backed stage config looks like:

```yaml
adapter_type: shell_script
adapter_config:
  working_directory: /path/to/project
  commands:
    - name: rspec
      command: bundle exec rspec
      artifact: test_results
    - name: rubocop
      command: bundle exec rubocop
      artifact: lint
    - name: coverage
      command: ruby -e 'exit 0'
      artifact: coverage
      previous_coverage: 90.0
      current_coverage: 91.0
```

Supported artifact mappings:

- `artifact: test_results` stores `kind: test_results` with `data.passed` based on command exit status.
- `artifact: lint` stores `kind: lint` with `data.clean` based on command exit status.
- `artifact: coverage` stores `kind: coverage` with `data.current` and `data.previous` from the command config.
- Commands without an `artifact` are collected into an aggregate `test_results` artifact.

Each configured command also writes a `shell_command` trace event with command name, command text, output summary, duration, and exit status. The work item advances only after the adapter result satisfies queue-owned transition rules; the adapter does not choose the next stage.

Smoke-test only the shell-backed test stage:

```bash
bin/rails runner 'queue = WorkQueue.find_by!(slug: "development-shell"); item = WorkItem.create!(work_queue: queue, title: "Shell smoke", spec_url: "opaque spec", stage_name: "test"); Engine::Runner.new.call; puts({ id: item.id, status: item.reload.status, stage: item.stage_name, artifacts: item.artifacts.pluck(:kind) }.to_json)'
```

Expected output includes `"stage":"review"` and artifact kinds `test_results`, `lint`, and `coverage`.

## Tests

Run the full suite:

```bash
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
bundle exec rspec
```

The MVP-0 end-to-end fake workflow test is:

```bash
bundle exec rspec spec/services/engine/fake_workflow_integration_spec.rb
```

## Development notes

- Keep adapters narrow: adapters return normalized `AgentResult`; transition logic belongs in engine services.
- Use strict TDD for behavior changes.
- Commit after each green slice.
- Do not add real model adapters until fake workflow remains reliable.
