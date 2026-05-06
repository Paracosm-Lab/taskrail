---
name: execute_staging
description: Interpret Docker Compose staging validation results
---

# Execute Staging

## Purpose

Evaluate whether a drafted runbook can be safely executed and verified in a Docker Compose staging environment.

## Input

Assignment context includes runbook draft data, Docker Compose output, command output, service health checks, and validation report details.

## Instructions

1. Confirm Docker Compose services started successfully.
2. Match each runbook observe/action/verify step to command output.
3. Identify failed, skipped, or unsafe steps.
4. Report whether staging validation passed and why.

## Output Format

```json
{
  "validation_passed": true,
  "steps": [
    { "name": "check queue depth", "status": "passed", "evidence": "queue depth returned 0" }
  ],
  "failures": []
}
```

## Constraints

- Do NOT deploy to production.
- Do NOT mutate production data or credentials.
- Mark validation_passed false when any required verification step is missing.

## Examples

Input: docker compose up succeeds, health endpoint returns 200, verification command succeeds.
Output: validation_passed true with evidence for each step.
