# Predicates

Predicates are named completion checks. They decide whether a stage can advance.

A stage can produce output, but output alone is not done. Predicates turn output into an explicit definition of done.

## Where Predicates Are Configured

Predicates are referenced by name in queue YAML:

```yaml
completion_criteria:
  - report_present
  - tests_passed
  - review_verdict
```

All required predicates must pass before the stage advances.

## What Predicates Check

Predicates can inspect:

- reports
- artifacts
- trace metadata
- work item fields
- claim results
- upstream outputs
- human review answers

Examples:

- `report_present`
- `branch_created`
- `tests_passed`
- `lint_clean`
- `coverage_not_decreased`
- `severity_classified`
- `rollback_tested`
- `review_verdict`

## Predicate Outcomes

A predicate can cause the transition manager to:

- advance to the next stage
- retry the same stage with feedback
- regress to an earlier stage
- block for human review
- complete the work item

## Why Predicates Matter

Predicates keep agents from deciding for themselves whether work is complete.

The queue owns advancement. The agent produces evidence.

## Adding a Predicate

To add a predicate:

1. Create a predicate class under the engine predicates namespace.
2. Return a structured predicate result.
3. Register the predicate name.
4. Add the predicate to queue YAML.
5. Add focused tests.
6. Add a fixture where possible.

## Design Rule

If a human would ask "how do we know this is done?", the answer probably belongs in a predicate.
