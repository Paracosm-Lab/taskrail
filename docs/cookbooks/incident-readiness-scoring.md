# Incident Readiness Scoring Cookbook

The `incident_readiness` queue audits services for operational readiness and produces a scorecard answering: if this service breaks tonight, are we ready?

## Problem Statement

Most incident readiness gaps are discovered during real incidents. Alerts are too thin, runbooks are stale, ownership is unclear, dashboards are incomplete, and recovery steps have not been tested.

Taskrail turns readiness review into a repeatable queue.

## Stages

```text
inventory_services -> score_readiness -> identify_gaps -> draft_improvements -> human_review -> done
```

## Artifacts

- `service_inventory`: services, jobs, schedules, dependencies, owners, and critical paths.
- `readiness_scores`: alerting, runbook, dashboard, logging, ownership, and recovery scores.
- `gap_analysis`: prioritized gaps by risk and effort.
- `improvement_drafts`: patches, docs, runbook updates, or follow-up work recommendations.

## Human Gate

The queue stops for human review before recommendations are accepted or spawned into follow-up work.

## Configurability

Teams can change score dimensions, required evidence, service sources, thresholds, follow-up queues, and review policy.

## Output Format

The scorecard should be shareable with engineering and operations teams. It should clearly show:

- service name
- owner
- readiness score
- highest-risk gaps
- recommended next steps
