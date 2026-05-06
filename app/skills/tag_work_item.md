---
name: tag_work_item
description: Add operational metadata tags to work items
---

# Tag Work Item

## Purpose

Attach useful metadata tags for triage, routing, reporting, and prioritization support.

## Input

Assignment context includes work item title, spec, service, Sentry/log evidence, and current tags.

## Instructions

1. Preserve existing tags unless replacing an explicitly incorrect value.
2. Assess cost, risk, complexity, and domain from evidence.
3. Add service and source identifiers when known.
4. Explain uncertain tags rather than guessing.

## Output Format

```json
{
  "tags": {
    "cost": "medium",
    "risk": "low",
    "complexity": "medium",
    "domain": "instrumentation",
    "service": "crm-service"
  }
}
```

## Constraints

- Do NOT decide human priority.
- Do NOT invent service names or domains.
- Use low/medium/high for cost, risk, and complexity.

## Examples

Input: add Sentry context to one controller.
Output: cost low, risk low, complexity low, domain instrumentation.
