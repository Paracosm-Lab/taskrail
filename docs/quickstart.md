# Quickstart

This guide gets Taskrail running locally with the deterministic fake adapter. It does not require a model API key or external agent provider.

Goal:

```text
clone -> install -> seed queues -> submit work -> run engine -> inspect result
```

## Prerequisites

- Ruby compatible with the app's `.ruby-version`.
- Bundler.
- Docker and Docker Compose.
- Node.js if you want to run the terminal UI.

## 1. Install dependencies

```bash
bundle install
```

## 2. Start Postgres

```bash
docker compose up -d postgres
```

The local compose setup exposes Postgres on port `5433`.

## 3. Prepare the database

```bash
bin/rails db:prepare
bin/rails db:seed
```

Seeding loads queue definitions from `config/queues/*.yml`.

## 4. Start the Rails app

```bash
bin/rails server
```

Open:

```text
http://localhost:3000
```

Health checks:

```bash
curl http://localhost:3000/health
curl http://localhost:3000/up
```

## 5. Submit a work item

In a second terminal:

```bash
bin/taskrail submit --queue development --title "Smoke test" --spec ./README.md
```

Then list queued work:

```bash
bin/taskrail list --queue development
```

Copy the work item ID from the output.

## 6. Run one engine tick

```bash
bin/rails runner 'Engine::Runner.new.call'
```

Run multiple ticks to drain a small workflow:

```bash
bin/rails runner '10.times { Engine::Runner.new.call }'
```

## 7. Inspect the result

```bash
bin/taskrail status WORK_ITEM_ID --traces
bin/taskrail costs --work-item WORK_ITEM_ID
```

Look for:

- Current stage.
- Status.
- Claims.
- Reports.
- Artifacts.
- Trace and cost summaries.
- Transition logs.

## What You Just Proved

You created a work item, moved it through queue-owned stages, executed adapter-backed work, stored artifacts and traces, and let predicates decide advancement.

The important idea:

> The agent does not own the workflow. The queue does.
