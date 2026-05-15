# Artifacts and Reports

Reports and artifacts are the reviewable evidence produced by stage execution.

They make agent work inspectable, reusable, and safe to hand off.

## Report

A report is the structured outcome of a claim for one stage.

Reports answer:

- What did the adapter do?
- What did it find?
- What changed?
- What should happen next?
- Did it ask a human question?

## Artifact

An artifact is a typed output that later stages, humans, or pipes can consume.

Common artifact kinds:

- `branch`
- `test_results`
- `coverage_map`
- `vulnerability_scan`
- `severity_report`
- `rollback_plan`
- `migration_runbook`
- `dependency_audit`
- `upgrade_plan`

## Reports vs Artifacts

Use a report for the stage summary.

Use artifacts for outputs that need to be validated, displayed, copied, routed, or consumed by later stages.

## How Later Stages Use Artifacts

A later stage assignment can include upstream reports and artifacts. This lets a queue build context over time without requiring the agent to remember the workflow.

Example:

```text
scan_coverage -> coverage_map
identify_gaps -> prioritized_gaps
generate_tests -> test_patch
run_tests -> test_results
human_review -> accepted/rejected
```

## Pipes

Pipes can copy artifacts from one queue to another. This lets one workflow spawn or route follow-up work without losing context.

Example:

```text
security_scan severity_report -> development input_findings
```

## Human Review

Humans should review artifacts, reports, traces, and predicate outcomes before accepting risky work.

## Design Rule

If the next stage or a human needs to inspect it, make it an artifact.
