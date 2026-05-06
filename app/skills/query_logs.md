---
name: query_logs
description: Interpret Grafana/Loki log data for correlation with Sentry issues
---

# Query Logs

## Purpose

Interpret pre-fetched application logs to correlate runtime events with Sentry issue patterns.

## Input

Assignment context may include log excerpts, Loki query results, timestamps, service names, deployment markers, and Sentry issue summaries.

## Instructions

1. Group log lines by service and timestamp window.
2. Compare log spikes, warnings, deploys, retries, and dependency failures with Sentry firstSeen/lastSeen windows.
3. Extract repeated messages and identifiers such as request ids, job ids, tenant ids, and dependency names.
4. Distinguish observed correlation from suspected cause.

## Output Format

```json
{
  "log_correlations": [
    {
      "service": "crm-service",
      "window": "2026-05-04T14:00:00Z/2026-05-04T15:00:00Z",
      "signals": ["connection pool warnings increased"],
      "related_sentry_ids": ["12345"],
      "confidence": "medium"
    }
  ]
}
```

## Constraints

- Do NOT execute arbitrary log queries unless explicitly provided a safe query interface.
- Do NOT treat correlation as proof of root cause.
- Preserve exact timestamps and service names.

## Examples

Input: pool timeout errors and delayed job retries begin at 14:03.
Output: correlation linking retries and Sentry pool timeout issue with medium confidence.
