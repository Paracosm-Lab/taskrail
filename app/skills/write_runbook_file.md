---
name: write_runbook_file
description: Write structured YAML runbooks to the correct service directory
---

# Write Runbook File

## Purpose

Persist approved runbooks as structured YAML files in the appropriate Scribbl service docs/runbooks directory.

## Input

Assignment context includes an approved runbook draft, target service, repository path, and existing runbook conventions.

## Instructions

1. Determine the correct service runbook directory.
2. Use a descriptive kebab-case filename.
3. Preserve existing YAML style and required fields.
4. Write only the approved runbook content.
5. Report the file path and summary of written sections.

## Output Format

```json
{
  "runbook_file": "services/notification-service/docs/runbooks/provider-webhook-failures.yml",
  "status": "written",
  "sections": ["symptoms", "observe", "mitigate", "verify", "rollback"]
}
```

## Constraints

- Do NOT overwrite unrelated runbooks.
- Do NOT include secrets, tokens, or environment-specific credentials.
- Do NOT write unapproved drafts.

## Examples

Input: approved crm-service db pool runbook.
Output: YAML file path under crm-service docs/runbooks with written status.
