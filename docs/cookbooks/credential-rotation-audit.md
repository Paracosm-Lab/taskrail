# Credential Rotation Audit

The `credential_rotation` cookbook is a read-only advisory queue for finding credentials, mapping dependencies, scoring rotation risk, and drafting human-executed rotation plans.

It never rotates, revokes, deploys, restarts, or contacts credential providers automatically. The `human_review` stage is the handoff point for humans to execute one credential at a time with health checks and rollback ready.

## Problem Statement

Credential rotation is risky because secrets are rarely isolated. A database password, API token, webhook secret, or OAuth credential may be referenced by services, background jobs, CI, local scripts, and deployment configuration.

Teams need a dependency map and safe sequence before changing anything.

## Stages

```text
scan_secrets -> map_dependencies -> assess_risk -> draft_rotation_plan -> human_review -> done
```

## Artifacts

- `secret_inventory`: discovered credentials and references.
- `dependency_map`: services, jobs, and configs that use each credential.
- `rotation_risk`: blast radius, staleness, exposure, and operational risk.
- `rotation_plan`: human-executed steps, health checks, rollback notes, and sequencing.

## Human Gate

The queue stops before any credential is changed. Humans review the plan, execute rotation through approved systems, and verify service health.

## Configurability

Teams can change scan scope, risk scoring, credential classes, required artifacts, review gates, and follow-up queues.
