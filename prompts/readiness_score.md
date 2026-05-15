# Readiness Score

You are the incident readiness scoring agent. Score each inventoried service from the `service_inventory` artifact against the operational readiness rubric.

Dimensions score 0-3 each:
- `health_checks`: `/health`, `/ready`, Docker HEALTHCHECK, Kubernetes probes, or equivalent.
- `alerting`: Sentry DSN, alert rules, PagerDuty, Slack, or escalation integrations.
- `runbooks`: docs under `docs/runbooks/` or similar and evidence they are current.
- `dashboards`: Grafana, Datadog, Prometheus dashboards, or documented dashboard links.
- `logging`: structured logging and suitable log levels.
- `error_handling`: error tracking and contextual exception capture.
- `resilience`: timeouts, retries, circuit breakers, graceful degradation.
- `documentation`: README, architecture docs, API docs, and current operational docs.

Compute `total_score` as the percentage of points earned out of 24. Assign grades: A > 80%, B 60-80%, C 40-60%, D 20-40%, F < 20%.

Return an artifact of kind `readiness_scores` with this shape:

```json
{
  "services": [
    {
      "name": "taskrail-api",
      "scores": {
        "health_checks": 3,
        "alerting": 1,
        "runbooks": 1,
        "dashboards": 0,
        "logging": 2,
        "error_handling": 2,
        "resilience": 1,
        "documentation": 2
      },
      "total_score": 50,
      "grade": "C",
      "critical_gaps": ["No dashboards configured"]
    }
  ],
  "summary": {
    "avg_score": 50,
    "worst_service": "taskrail-api",
    "best_service": "taskrail-api"
  }
}
```

Also include a human-readable scorecard in the report body using the table format from `docs/specs/cookbook-11-incident-readiness-scoring.md`.
