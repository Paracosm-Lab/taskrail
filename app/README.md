# TaskRail

TaskRail is a Rails-native workflow control plane for agent work.

The thesis is simple: the agent does not own the workflow; the queue owns the workflow. TaskRail keeps stages, retries, review regressions, child decomposition, traces, reports, and transitions in explicit Rails records. Agents are replaceable workers behind narrow adapters.

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
- Thin `bin/taskrail` CLI
- End-to-end fake workflow coverage
- Deterministic shell validation adapter for local test/lint/coverage evidence
- Optional inline Claude CLI adapter for local intake/decompose/review experiments
- Optional async Codex CLI adapter for local build/fix experiments

MVP-0 still keeps the default `development` queue fake-backed. Real model adapters are opt-in queue fixtures; queue-owned transitions remain the source of truth for stage movement.

## Requirements

- Ruby managed by rbenv
- Rails 8.0.5
- Docker / Docker Compose
- PostgreSQL via the included `docker-compose.yml`

The local Compose file maps PostgreSQL to host port `5433` and Rails to host port `3333`.

## Setup

From this directory:

```bash
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
bundle install
docker compose up -d
bin/rails db:prepare
bin/rails db:seed
```

To run fully containerized:

```bash
docker compose up --build
```

The API is then available at:

```text
http://localhost:3333
```

The seed task loads every queue YAML file from:

```text
config/queues/*.yml
```

### Dead Code Removal Cookbook

The `dead_code_removal` queue scans for unused dependencies, unreferenced files, dead methods, orphan routes, no-op migrations, and abandoned feature flags.

Pipeline:

`scan_references -> verify_unused -> draft_removals -> run_tests -> human_review -> done`

Safety:
- `verify_unused` is intentionally conservative.
- Dynamic Ruby references such as `send`, `public_send`, `const_get`, `constantize`, and `eval` should force `needs_investigation` unless the agent can prove the candidate is safe.
- Only `safe_to_remove` items may become removal patches.
- Human review remains mandatory before done.

The default `development` queue remains fully fake-backed. The optional `development-shell` queue uses `ShellScriptAdapter` for the `test` stage, `development-claude` uses `InlineClaudeAdapter` for intake/decompose/review, and `development-codex` adds async Codex build/fix submission plus shell validation.

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

If using Docker Compose, set:

```bash
export TASKRAIL_API_URL=http://localhost:3333
```

## CI/CD (Woodpecker)

This repository now includes `.woodpecker.yml` with these stages:

- `lint` (`rubocop`)
- `security_scan` (`brakeman`)
- `test_ruby` (`bin/rails db:test:prepare test`) with Postgres service
- `test_tui` (`npm test` in `tui/`)
- `docker_build` (dry-run image build via Buildx plugin)

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
GET    /api/v1/work_items/:id?traces=true
GET    /api/v1/work_items
GET    /api/v1/work_items?queue=:slug&stage=:stage&status=:status&tags[risk]=high
POST   /api/v1/work_items/:id/answer
POST   /api/v1/work_items/:id/retry
POST   /api/v1/work_items/:id/cancel
GET    /api/v1/costs
GET    /api/v1/costs?period=today
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

The CLI talks to the Rails API. The default API base URL is `http://localhost:3000`; override it with `TASKRAIL_API_URL`.

```bash
bin/taskrail queues
bin/taskrail stages development
bin/taskrail submit --queue development --spec ./README.md --title "Smoke test"
bin/taskrail list --queue development
bin/taskrail list --queue development --stage build
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

## Human escalation and observability

When retry budgets or review regression budgets are exhausted, queue-owned transition rules block the work item and store a safe human escalation summary. The API exposes only the safe escalation fields needed by operators; it does not expose prompts, full assignments, credentials, or raw trace metadata. Future Slack/Telegram/email notification integrations are not part of this slice yet.

Humans unblock work through the existing answer flow:

```bash
bin/taskrail answer WORK_ITEM_ID "Use bearer tokens"
```

For investigation and cost visibility:

```bash
bin/taskrail status WORK_ITEM_ID --traces
bin/taskrail costs
bin/taskrail costs --today
bin/taskrail costs --work-item WORK_ITEM_ID
```

`status --traces` includes sanitized trace summaries. Prompt-derived input summaries are redacted, and trace metadata is recursively sanitized for prompt, assignment, token, secret, API-key, password, authorization, and credential fields.

## Dashboard TUI

The dashboard is a read-only terminal skin over the same Rails API used by the JSON CLI commands. It does not read Rails models directly and it does not own workflow transitions; queue-owned transition rules remain authoritative. Use the existing `submit`, `answer`, `retry`, and `cancel` commands for writes.

The default API base URL is `http://localhost:3000`; override it with `TASKRAIL_API_URL` when the server runs elsewhere.

Render a one-shot dashboard:

```bash
bin/taskrail dashboard --queue development
```

Show a filtered queue view:

```bash
bin/taskrail dashboard --queue development-codex --status pending --limit 20
```

Watch the dashboard refresh periodically:

```bash
bin/taskrail dashboard --queue development --watch --refresh 5
```

Dashboard rows show work item id, status, stage, title, and any safe active-claim summary returned by the API. Async Codex work appears as a compact claim marker such as:

```text
codex:active async run-123
```

The dashboard rows intentionally display only safe active-claim fields: agent type, status, async flag, and external id. The underlying API summary also includes the claim id for clients that need it. The dashboard does not display full assignment payloads, prompts, or credentials.

Blocked items that require human input show a compact `HUMAN:` marker and an `Actions` section:

```text
Run: bin/taskrail answer WORK_ITEM_ID "your guidance"
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

`ShellScriptAdapter` is the first real, non-fake adapter. It is intended for deterministic validation stages where the queue should execute local shell commands and convert their results into normal TaskRail artifacts.

The seeded `development-shell` queue keeps intake, decompose, build, review, and done fake-backed, but uses `shell_script` for the `test` stage:

```bash
bin/taskrail stages development-shell
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

## InlineClaudeAdapter

`InlineClaudeAdapter` runs a configured local Claude CLI command synchronously for stages such as intake, decompose, and review. It sends a deterministic assignment prompt on stdin and converts stdout/stderr/exit status into normal TaskRail reports, artifacts, and trace events.

The default `development` queue remains fake-backed. The optional `development-claude` queue uses `inline_claude` for intake, decompose, and review; keeps build and done fake-backed; and uses `shell_script` for test validation.

Configure Claude CLI authentication outside TaskRail. Do not commit API keys, tokens, or credentials into queue YAML.

```bash
bin/taskrail stages development-claude
```

An inline Claude stage config looks like:

```yaml
adapter_type: inline_claude
model_override: claude-3-5-sonnet-latest
adapter_config:
  command: claude
  args:
    - --print
  working_directory: /path/to/project
  output_artifact_kind: agent_report
```

Runtime behavior:

- TaskRail builds a prompt from the assignment payload: work item, stage prompt, allowed/forbidden skills, completion criteria, and context.
- The configured command receives that prompt on stdin.
- Exit status `0` stores a successful report plus an `agent_report` artifact by default.
- Non-zero exit status stores a failed report with stdout/stderr/exit status.
- Each run writes a `claude_cli` trace event with prompt/output summaries, duration, exit status metadata, and placeholder token/cost fields.
- The adapter never chooses the next stage; queue-owned transition rules decide whether the item advances.

Smoke-test only the Claude-backed intake stage with a real local Claude CLI. This assumes the development database has no older pending items because `Engine::Runner` processes the oldest runnable pending item:

```bash
bin/rails runner 'queue = WorkQueue.find_by!(slug: "development-claude"); WorkItem.pending.update_all(status: WorkItem.statuses[:blocked]); item = WorkItem.create!(work_queue: queue, title: "Claude smoke", spec_url: "opaque spec", stage_name: "intake"); Engine::Runner.new.call; puts({ id: item.id, status: item.reload.status, stage: item.stage_name, report: item.reports.last&.body&.fetch("summary", nil) }.to_json)'
```

Expected output includes `"stage":"decompose"` after the intake report satisfies the queue-owned `report_present` transition rule.

## CodexAdapter

`CodexAdapter` starts build/fix work asynchronously through a configured local Codex CLI command. It is intended for longer-running implementation stages where TaskRail should submit work, keep the claim active, and poll for completion later.

The default `development` queue remains fake-backed. The optional `development-codex` queue uses:

- `inline_claude` for intake, decompose, and review
- `codex` for build
- `shell_script` for test validation
- `fake` for done

Configure Codex CLI authentication outside TaskRail. Do not commit API keys, tokens, or credentials into queue YAML.

```bash
bin/taskrail stages development-codex
```

A Codex build stage config looks like:

```yaml
adapter_type: codex
model_override: codex-cli
completion_criteria:
  - branch_created
  - report_present
adapter_config:
  command: codex
  args:
    - exec
    - --json
  poll_command: codex
  poll_args:
    - status
    - --json
```

Runtime behavior:

1. `Engine::Runner` creates a claim and calls `CodexAdapter`.
2. `CodexAdapter` builds a deterministic build/fix prompt from the assignment and submits it to the configured Codex command on stdin.
3. A successful submit returns an external id and stores async metadata on the claim.
4. The claim remains `active` with `async_execution: true`; the work item does not transition yet.
5. `CheckAsyncClaimsJob` runs `Engine::AsyncClaimChecker`, which polls Codex with the configured poll command and external id.
6. A running poll result leaves the claim active.
7. A completed poll result is normalized into reports, artifacts, and `codex_complete` trace events.
8. Only after completion does TaskRail mark the claim complete and run queue-owned transition rules.

Smoke-test only the Codex-backed build stage with a real local Codex CLI. This blocks older pending items first because `Engine::Runner` processes the oldest runnable pending item:

```bash
bin/rails runner 'queue = WorkQueue.find_by!(slug: "development-codex"); WorkItem.pending.update_all(status: WorkItem.statuses[:blocked]); item = WorkItem.create!(work_queue: queue, title: "Codex smoke", spec_url: "opaque spec", stage_name: "build"); Engine::Runner.new.call; claim = item.claims.order(:created_at).last; puts({ id: item.id, status: item.reload.status, stage: item.stage_name, claim_status: claim.status, async_execution: claim.async_execution, external_id: claim.assignment.dig("async", "external_id") }.to_json)'
```

Expected output after submission includes `"stage":"build"`, `"claim_status":"active"`, and `"async_execution":true`. Run the async checker after Codex completes:

```bash
bin/rails runner 'CheckAsyncClaimsJob.perform_now'
```

If Codex polling returns a completed result with a branch artifact and report evidence, queue-owned transition rules can then advance the work item from `build` to `test`.

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
