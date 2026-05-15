# TaskRail

A workflow control plane for agent-assisted engineering work.

The core idea: the agent does not own the workflow — the queue does. TaskRail keeps stages, retries, review regressions, child decomposition, traces, reports, and transitions in explicit Postgres records. Agents are replaceable workers behind narrow adapters.

---

## Requirements

- Ruby (rbenv)
- Rails 8
- Docker / Docker Compose
- Node.js (for the TUI)

## Setup

```bash
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
bundle install
docker compose up -d
bin/rails db:prepare
bin/rails db:seed
```

This starts Postgres on port `5435` and loads all queue definitions from `config/queues/*.yml`.

To run fully containerized:

```bash
docker compose up --build
```

## Running

**API server:**

```bash
bin/rails server
# → http://localhost:3000
```

**Web UI:**

Browse to `http://localhost:3000` — queues are grouped by category in the left sidebar.

**Engine (one tick):**

```bash
bin/rails runner 'Engine::Runner.new.call'
```

Each tick picks the oldest pending unclaimed work item, runs it through the current stage adapter, persists results, and applies queue-owned transition rules.

---

## Key Concepts

**WorkQueue** — defines a pipeline of stages, each with an adapter type and config. Loaded from `config/queues/*.yml`.

**WorkItem** — a unit of work moving through a queue's stages. Has status (`pending`, `claimed`, `completed`, `blocked`, `cancelled`) and a `stage_name`.

**Claim** — a record of one adapter execution attempt on a work item. Stores the assignment, report, artifacts, and trace.

**Pipe** — routes completed work items from one queue into another, copying selected artifacts as input.

**Adapter types:**
- `fake` — deterministic, no external calls (default for development)
- `shell_script` — runs local shell commands, converts exit status to artifacts
- `inline_claude` — calls a local Claude CLI synchronously
- `codex` — submits async build/fix work to Codex CLI, polls for completion

Adapters return a normalized `AgentResult`. Transition logic lives in engine services, not adapters.

---

## API

```
GET    /api/v1/queues
GET    /api/v1/queues/:slug/stages
POST   /api/v1/work_items
GET    /api/v1/work_items/:id
GET    /api/v1/work_items
POST   /api/v1/work_items/:id/retry
POST   /api/v1/work_items/:id/cancel
POST   /api/v1/work_items/:id/answer
GET    /api/v1/costs
GET    /api/v1/costs?period=today
GET    /api/v1/costs/work_items/:id
```

**Create a work item:**

```bash
curl -s -X POST http://localhost:3000/api/v1/work_items \
  -H 'Content-Type: application/json' \
  -d '{"queue":"development","title":"Smoke test","spec_url":"./README.md"}'
```

---

## CLI

```bash
bin/taskrail queues
bin/taskrail stages development
bin/taskrail submit --queue development --title "My task" --spec ./README.md
bin/taskrail list --queue development
bin/taskrail list --queue development --stage build --status blocked
bin/taskrail status WORK_ITEM_ID
bin/taskrail status WORK_ITEM_ID --traces
bin/taskrail retry WORK_ITEM_ID
bin/taskrail cancel WORK_ITEM_ID
bin/taskrail answer WORK_ITEM_ID "Use bearer tokens"
bin/taskrail costs
bin/taskrail costs --today
bin/taskrail costs --work-item WORK_ITEM_ID
```

Default API base: `http://localhost:3000`. Override with `TASKRAIL_API_URL`.

---

## TUI Dashboard

Read-only terminal dashboard over the same API:

```bash
bin/taskrail dashboard --queue development
bin/taskrail dashboard --queue development --watch --refresh 5
bin/taskrail dashboard --queue development --status pending --limit 20
```

Build the TUI:

```bash
cd tui && npm install && npm run build
```

---

## Tests

```bash
bundle exec rspec
```

End-to-end fake workflow integration test:

```bash
bundle exec rspec spec/services/engine/fake_workflow_integration_spec.rb
```

TUI tests:

```bash
cd tui && npm test
```

---

## CI (Woodpecker)

Stages: `lint` (RuboCop) → `security_scan` (Brakeman) → `test_ruby` → `test_tui` → `docker_build`
