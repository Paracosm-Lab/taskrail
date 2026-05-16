# Installation

Taskrail is a Rails application backed by Postgres. It can run locally with Docker Compose and deterministic fake adapters before any external model or agent integration is configured.

## Requirements

- Ruby compatible with `.ruby-version`.
- Bundler.
- Docker and Docker Compose.
- Node.js for the terminal UI.
- Postgres, usually through the provided compose setup.

## Install Ruby Dependencies

```bash
bundle install
```

If your Ruby manager does not activate automatically, use the Ruby version declared by the repository before installing gems.

## Start Services

```bash
docker compose up -d postgres
```

## Prepare Database

```bash
bin/rails db:prepare
bin/rails db:seed
```

`db:seed` loads queue and cookbook definitions into Postgres.

## Run the App

```bash
bin/rails server
```

Default local URL:

```text
http://localhost:3000
```

## Verify

```bash
curl http://localhost:3000/health
curl http://localhost:3000/up
bin/taskrail doctor
```

## Optional Environment Variables

```bash
TASKRAIL_API_URL=http://localhost:3000
TASKRAIL_SERVICE_TOKEN=<legacy-service-token>
TASKRAIL_ADMIN_TOKEN=<admin-token>
GITHUB_WEBHOOK_SECRET=<webhook-secret>
```

Production API requests require either a personal access token or `TASKRAIL_SERVICE_TOKEN`. GitHub webhooks fail closed unless `GITHUB_WEBHOOK_SECRET` is configured. Adapter-specific variables depend on the adapters you enable. The fake adapter requires no external secrets.

## Next Step

Continue with [Quickstart](./quickstart.md) to submit and process your first work item.
