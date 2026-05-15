---
name: read_sentry
description: Interpret Sentry issue data for failure analysis
requires_env:
  - SENTRY_API_TOKEN
  - SENTRY_ORG
---

# Read Sentry

## Purpose

Interpret pre-fetched Sentry issue data to understand failure patterns across Scribbl services.

## Input

Your assignment context includes `sentry_issues` — an array of Sentry issue objects from the past 24 hours. Each issue has id, title, culprit, count, userCount, firstSeen, lastSeen, project.slug, metadata.type, metadata.value, level, and status.

## Instructions

1. Parse each issue and extract error type, message, service, frequency, affected users, and time window.
2. Assess severity from count, userCount, level, and service criticality.
3. Note temporal patterns and multiple issues beginning in the same window.
4. Identify obvious correlations between issues without assigning root cause.

## Output Format

Produce an artifact with `kind: "signal_summary"` and include report body JSON:

```json
{
  "status": "success",
  "issues": [
    {
      "sentry_id": "12345",
      "service": "crm-service",
      "error_type": "ActiveRecord::ConnectionTimeoutError",
      "message": "could not obtain connection from pool",
      "count": 143,
      "user_count": 12,
      "severity": "high",
      "first_seen": "2026-05-04T14:03:00Z",
      "last_seen": "2026-05-04T14:45:00Z"
    }
  ],
  "patterns_observed": ["description of temporal or service correlations"]
}
```

## Constraints

- Do NOT guess root causes. That is for clustering.
- Do NOT suggest fixes. You are an ingestion agent.
- If no issues are found, return an empty issues array with status "success".

## Examples

Input: 2 issues in crm-service within the same 30-minute window.
Output: Both issues listed, pattern noted: "Two errors in crm-service correlate temporally; root cause not determined".
