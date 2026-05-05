---
name: approve
description: Approve a runbook or review with structured verdict
---

# Approve

## Purpose

Produce a clear approval verdict when a runbook or operational artifact satisfies requirements.

## Input

Assignment context includes draft content, validation results, review checklist, and known constraints.

## Instructions

1. Verify all required checklist items are satisfied.
2. Confirm no blockers, unsafe actions, or missing verification steps remain.
3. State the approval reason and any non-blocking follow-ups.

## Output Format

```json
{
  "verdict": "approved",
  "reason": "All required observe, mitigate, verify, and rollback steps are present and validated.",
  "follow_ups": []
}
```

## Constraints

- Do NOT approve if validation evidence is missing.
- Do NOT approve production mutation without rollback/verification steps.
- Keep follow-ups non-blocking.

## Examples

Input: validated runbook with all required sections.
Output: verdict approved and concise reason.
