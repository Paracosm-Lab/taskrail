# Runbook Draft: CRM Postgres Unavailable

Human review required before production use.

## Scope

Failure Readiness cookbook fixture for `crm-service` staging alerts involving `ActiveRecord::ConnectionTimeoutError` and `PG::ConnectionBad` against `crm-postgres.internal`.

## Observe

```bash
pg_isready -h crm-postgres.internal -p 5432
psql "$CRM_DATABASE_URL" -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"
psql "$CRM_DATABASE_URL" -c "SELECT pid, now() - xact_start AS age, query FROM pg_stat_activity WHERE state = 'idle in transaction' ORDER BY age DESC LIMIT 10;"
```

Check alert context for `pool_size`, `checked_out`, `waiting`, `active_connections`, `max_connections`, and `idle_in_transaction`.

## Mitigate

1. If Postgres is down, page the database owner and restart only through the approved staging/prod database control plane.
2. If `idle_in_transaction` is above the reviewed threshold, terminate sessions older than five minutes after confirming they are safe.
3. If app pools do not drain after database recovery, perform a rolling app restart.

## Verify

```bash
curl -fsS https://crm.staging.scribbl.test/health
curl -fsS -X POST https://crm.staging.scribbl.test/sessions -d '{"token":"fixture"}'
```

Monitor Sentry for 15 minutes and confirm pool stats return to idle capacity.

## Escalate

Escalate to DBA for unavailable Postgres, connection saturation by active queries, or unsafe session termination. Escalate to incident commander if customer-facing outage lasts more than 30 minutes.
