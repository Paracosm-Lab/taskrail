# Uninstrumented Jobs Fixture

This fixture app is intentionally small and non-runnable. It gives the Background Job Observability cookbook representative job files to scan:

- `ExportJob`: no instrumentation
- `BillingJob`: good instrumentation example
- `SyncJob`: infinite retries with no timeout or dead letter strategy
- `CleanupJob`: silently swallows errors

Do not add shared Docker Compose or external service infrastructure here; use the shared cookbook infrastructure plan for that.
