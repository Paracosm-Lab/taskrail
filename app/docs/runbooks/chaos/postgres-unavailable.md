# Runbook: Staging Postgres Unavailable

## Scope

Staging-only chaos fixture. Never run these commands against production.

## Symptoms

- API health checks fail or return elevated errors.
- Fake Sentry events mention database connection failures or unavailable Postgres.
- The `chaos-postgres` service is stopped or unhealthy in the fixture Compose project.

## Observe

```bash
docker compose -f spec/fixtures/chaos_staging/docker-compose.staging.yml ps
curl -fsS http://127.0.0.1:${CHAOS_STAGING_API_PORT:-3929}/health
```

## Mitigate

```bash
docker compose -f spec/fixtures/chaos_staging/docker-compose.staging.yml start chaos-postgres
```

## Verify

```bash
curl -fsS http://127.0.0.1:${CHAOS_STAGING_API_PORT:-3929}/health
bash spec/fixtures/chaos_staging/scripts/verify_fake_recovery.sh
```

## Safety notes

- Confirm the Compose file path is `spec/fixtures/chaos_staging/docker-compose.staging.yml` before running mitigation.
- Do not use production credentials or production hostnames.
- If verification fails, stop and escalate rather than repeatedly mutating the fixture.
