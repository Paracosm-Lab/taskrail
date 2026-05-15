# CRM Postgres Unavailable

## Scope

Use this runbook when the CRM service cannot connect to its PostgreSQL database or when database saturation causes request failures. Human review required before destructive database operations.

## Observe

- Confirm database reachability:

```sh
pg_isready -h crm-postgres.internal -p 5432
```

- Check active sessions and long transactions:

```sql
SELECT pid, state, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE datname = 'crm_production'
ORDER BY state, query_start;
```

- Look for `idle_in_transaction` sessions, lock waits, and connection pool exhaustion in application logs and metrics.

## Mitigate

- Scale down nonessential background workers that are consuming CRM database connections.
- Restart the CRM web process if connection pools are wedged after the database is reachable.
- Terminate only clearly stale `idle_in_transaction` sessions after confirming ownership and impact.

## Verify

- `pg_isready` returns accepting connections.
- CRM health checks pass for at least five minutes.
- Error rate and database connection counts return to normal ranges.

## Escalate

Human review required if database storage is full, replication is unhealthy, lock waits continue after mitigation, or any data repair is needed.
