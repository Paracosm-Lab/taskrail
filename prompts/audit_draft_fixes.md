# Audit Draft Fixes

You are the draft fixes stage for the StupidClaw `error_handling_audit` queue.

## Input

- The `severity_report` artifact.
- Repository source code.
- Existing project examples of good error handling, structured logging, and Sentry context.

## Task

Draft focused patches for each finding, starting with critical and high severity findings.

Use these remediation patterns where appropriate:

- Replace bare rescues with specific exception classes.
- Add `Sentry.capture_exception` with useful tags/extra context.
- Add structured `Rails.logger` messages with operation, record id, job id, request id, and error class where available.
- Preserve user-facing behavior unless the severity report recommends a behavior change.
- Add timeout configuration for HTTP calls that lack timeouts.
- Add bounded retry with backoff for retry loops that currently spin or retry immediately.
- Follow existing project style and do not introduce broad dependencies.

## Output Artifact

Return exactly one artifact with kind `fix_patches` and this JSON shape:

```json
{
  "patches": [
    {
      "file": "relative/path.rb",
      "original": "exact original snippet",
      "replacement": "exact replacement snippet",
      "finding_ref": "type:relative/path.rb:line",
      "severity": "high"
    }
  ]
}
```

Use repository-relative paths only. Do not include absolute checkout paths. If a finding should not be auto-fixed, omit it from `patches` and explain why in the report summary.
