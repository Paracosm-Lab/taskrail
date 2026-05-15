---
name: request_changes
description: Request specific actionable changes during review
---

# Request Changes

## Purpose

Return actionable review feedback when a runbook, assessment, or draft does not satisfy requirements.

## Input

Assignment context includes draft content, validation results, review rubric, and observed gaps.

## Instructions

1. Identify blocking issues first.
2. Tie each requested change to evidence or a missing requirement.
3. Provide concrete replacement/addition guidance.
4. Separate blocking changes from optional improvements.

## Output Format

```json
{
  "verdict": "request_changes",
  "blocking_changes": [
    { "issue": "Missing verification step", "requested_change": "Add a command that proves queue depth is recovering." }
  ],
  "optional_changes": []
}
```

## Constraints

- Do NOT provide vague feedback such as "improve clarity" without specifics.
- Do NOT request changes outside the stage scope.
- Do NOT approve and request blocking changes in the same verdict.

## Examples

Input: runbook has mitigation but no rollback.
Output: request_changes with a blocking rollback-step request.
