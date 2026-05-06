---
name: read_repo
description: Read Scribbl repository files for service structure, runbooks, and deployment configuration
---

# Read Repo

## Purpose

Use repository context to understand services, existing runbooks, code paths, observability instrumentation, and deployment topology.

## Input

Assignment context may include repository path, file excerpts, service names, Sentry culprits, Docker Compose files, Kamal config, and existing runbook paths.

## Instructions

1. Identify the relevant service and likely files from Sentry culprit and metadata.
2. Inspect existing runbooks, README files, deploy config, health checks, and observability setup.
3. Summarize exact files and line references used as evidence.
4. Report gaps between observed code/config and required operational context.

## Output Format

```json
{
  "repo_findings": [
    {
      "service": "notification-service",
      "files_read": ["services/notification/docs/runbooks/retry.yml"],
      "observations": ["existing runbook covers queue retries"],
      "gaps": ["no runbook for provider webhook failures"]
    }
  ]
}
```

## Constraints

- Do NOT modify repository files unless paired with write_runbook_file.
- Do NOT infer file contents you did not inspect.
- Prefer exact file paths over prose references.

## Examples

Input: Sentry culprit references SessionsController.
Output: repo findings list controller, Sentry instrumentation, and absence/presence of auth runbook.
