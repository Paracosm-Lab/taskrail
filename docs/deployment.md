# Deployment

This page describes deployment concerns for Taskrail without assuming a specific host, registry, or deployment tool.

## Production Requirements

- Rails application runtime.
- Postgres database.
- Persistent secret management.
- Background or recurring job execution for engine ticks and async claim checks.
- Health checks.
- Logs and metrics.

## Required Configuration

At minimum, configure:

- Rails environment.
- Database URL or database credentials.
- Rails secret key base / credentials.
- Public app host.
- Adapter-specific credentials only for adapters you enable.

## Database

Taskrail stores queue state, work items, claims, reports, artifacts, traces, transition logs, pipes, and runtime state in Postgres.

Back up Postgres regularly. Treat it as operational state, not cache.

## Background Execution

Production deployment must run:

- web process for the Rails app
- recurring engine ticks
- async claim polling

Important jobs:

- `EngineTickJob`
- `CheckAsyncClaimsJob`

## Health Checks

Expose and monitor:

```text
/health
/up
```

## Secrets

Do not commit credentials.

Use your platform's secret manager or environment variable system for:

- database credentials
- Rails credentials
- webhook secrets
- model or agent provider credentials

Trace serialization should redact sensitive prompt, token, authorization, secret, password, credential, and API-key-like fields.

## Adapter Safety

Only enable adapters that are appropriate for the environment.

For production-adjacent work, prefer queues with explicit human review gates and conservative retry limits.

## Rollback

Use your deployment platform's normal rollback mechanism for application code.

Work item state lives in the database. Do not drop or reset the database as part of rollback.

## Public Hosting Rule

Keep machine names, private IPs, personal infrastructure names, and registry credentials out of public docs.
