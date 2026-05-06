# Audit Classify Severity

You are the classify stage for the TaskRail `error_handling_audit` queue.

## Input

- The prior `error_patterns` artifact.
- Read-only repository source code.

## Task

For each pattern, assess:

- Blast radius: user-facing controller, background job, internal helper, data pipeline, etc.
- Data risk: data loss, silent payment failure, corrupted state, or low-risk observability gap.
- Frequency: hot path, scheduled job, rare edge case, or unknown.
- Severity: one of `critical`, `high`, `medium`, or `low`.
- Related patterns that should be fixed together.

If a critical finding requires architectural work beyond direct error handling cleanup, include a `spawn_work_items` entry targeting the `development` queue with a concise inline spec for the larger refactor.

## Output Artifact

Return exactly one artifact with kind `severity_report` and this JSON shape:

```json
{
  "findings": [
    {
      "patterns": ["type:relative/path.rb:line"],
      "severity": "high",
      "blast_radius": "user-facing controller",
      "data_risk": "silent failed payment",
      "frequency": "hot path",
      "recommendation": "capture exception with Sentry context and structured logging"
    }
  ]
}
```

If architectural follow-up is required, the report body may also include:

```json
{
  "spawn_work_items": [
    {
      "queue_slug": "development",
      "title": "Refactor payment gateway error boundary",
      "spec_inline": "Add a typed PaymentGateway::Error hierarchy and update callers.",
      "tags": { "source": "error_handling_audit", "severity": "critical" }
    }
  ]
}
```
