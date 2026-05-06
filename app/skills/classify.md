---
name: classify
description: Classify a work item by cost, risk, and complexity
---

# Classify

## Purpose

Tag a work item with cost, risk, and complexity assessments.

## Input

You receive the work item's title and spec content.

## Instructions

1. Read the title and spec
2. Assess cost: low (< 1 hour), medium (1-4 hours), high (> 4 hours)
3. Assess risk: low (no prod impact), medium (may affect prod), high (direct prod impact)
4. Assess complexity: low (single file), medium (multiple files), high (cross-service)

## Output Format

Include in your report body:

```json
{
  "tags": {
    "cost": "medium",
    "risk": "low",
    "complexity": "medium"
  }
}
```

## Constraints

- Do NOT guess if you lack information. Return status "blocked" with a question.
- Do NOT assess the work item's priority. That is a human decision.

## Examples

Input: "Add health check endpoint to user-service"
Output tags: { "cost": "low", "risk": "low", "complexity": "low" }

Input: "Migrate auth from session tokens to JWTs across all services"
Output tags: { "cost": "high", "risk": "high", "complexity": "high" }
