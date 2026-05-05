# Incident Readiness Scoring Cookbook

Source spec: `docs/specs/cookbook-11-incident-readiness-scoring.md`

The `incident_readiness` queue audits services for operational readiness and produces a scorecard answering: if this service breaks tonight, are we ready?

Stages:
1. `inventory_services` inventories web, worker, cron, and infrastructure-backed services.
2. `score_readiness` scores health checks, alerting, runbooks, dashboards, logging, error handling, resilience, and documentation.
3. `identify_gaps` ranks service and platform gaps by risk and effort.
4. `draft_improvements` drafts quick wins and recommends cross-queue work for larger fixes.
5. `human_review` stops for review.
6. `done` is terminal.

Artifacts:
- `service_inventory`
- `readiness_scores`
- `gap_analysis`
- `improvement_drafts`

Infrastructure notes:
- The queue uses `inline_claude` and `fake` stages only.
- Docker-friendly fixture files live under `spec/fixtures/incident_readiness`.
- Shared Docker Compose adapter behavior belongs to the shared cookbook infrastructure plan and is not duplicated here.

The scorecard report should use the standalone table format from the source spec so it can be shared directly with an operations or product team.
