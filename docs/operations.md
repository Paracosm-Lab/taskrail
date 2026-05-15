# Operations

This page covers local operation, engine execution, async claims, diagnostics, tests, and safety checks.

For first-time setup, start with [Installation](./installation.md) and [Quickstart](./quickstart.md).

## Run the Rails App

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

## Run the Engine

One engine tick:

```bash
bin/rails runner 'Engine::Runner.new.call'
```

The tick executes at most one pending item. It advances waiting parents first, then claims the oldest pending item without an active claim.

Recurring engine execution is configured through Rails jobs and recurring job configuration.

Important jobs:

- `EngineTickJob`: runs engine ticks.
- `CheckAsyncClaimsJob`: polls async claims such as Codex submissions.

## Async Claims

Async adapters return `Engine::AsyncAdapterResult`. The claim remains active with `async_execution: true` and stores provider metadata under `assignment["async"]`.

Current async flows include:

- `codex`: submit via Codex CLI, poll through `CodexCliPoller`.
- `docker_compose`: spawn Docker Compose process and heartbeat while the process is active.

Check async claims manually:

```bash
bin/rails runner 'Engine::AsyncClaimChecker.new.call'
```

## CLI Diagnostics

Run doctor:

```bash
bin/taskrail doctor
```

The doctor checks:

- `/api/v1/queues`
- `/api/v1/costs`
- `/health`
- `/up`

If an API endpoint returns `text/html`, the CLI is probably pointed at a frontend server instead of Rails.

Set API URL:

```bash
TASKRAIL_API_URL=http://localhost:3000 bin/taskrail queues
```

## Submitting Work

```bash
bin/taskrail submit --queue development --title "Smoke test" --spec ./README.md
bin/taskrail list --queue development
bin/taskrail status WORK_ITEM_ID --traces
```

Retry, cancel, or answer blocked work:

```bash
bin/taskrail retry WORK_ITEM_ID
bin/taskrail cancel WORK_ITEM_ID
bin/taskrail answer WORK_ITEM_ID "Use the existing credentials fixture only."
```

## Costs and Digests

```bash
bin/taskrail costs
bin/taskrail costs --today
bin/taskrail costs --work-item WORK_ITEM_ID
bin/taskrail digest --since 24h
bin/taskrail digest --since 7d --json
```

## TUI

Build the terminal UI:

```bash
cd tui
npm install
npm run build
```

Run it:

```bash
bin/taskrail
bin/taskrail --api http://localhost:3000
bin/taskrail dashboard --queue development --watch --refresh 5
```

## Tests

Ruby/Rails test suite:

```bash
bundle exec rspec
```

Focused examples:

```bash
bundle exec rspec spec/services/engine/fake_workflow_integration_spec.rb
bundle exec rspec spec/services/engine/transition_manager_spec.rb
bundle exec rspec spec/requests/api/v1/workflow_api_spec.rb
bundle exec rspec spec/cookbooks
bundle exec rspec spec/e2e
```

TUI tests:

```bash
cd tui
npm test
```

## Security and Secrets

GitHub PR webhook verification uses `GITHUB_WEBHOOK_SECRET` when set.

Trace serialization redacts sensitive-looking prompt, token, authorization, secret, password, credential, and API key fields.

Do not commit credentials. Use Rails credentials, local environment variables, or your deployment platform's secret manager.

## Deployment

See [Deployment](./deployment.md) for production deployment concerns.
