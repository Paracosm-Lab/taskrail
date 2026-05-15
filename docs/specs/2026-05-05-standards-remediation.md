# Spec: Standards Remediation Plan (2026-05-05)

## Use Case

Bring TaskRail into compliance with the Scribbl service standards baseline for:
- API conventions
- security/authentication
- service lifecycle scripts
- runbook structure and enforcement
- logging
- CI security gates

This spec defines the minimum implementation slice needed to close the critical and high-severity gaps found in the standards audit.

## Scope

In scope:
- Add required health and admin endpoints with auth.
- Add request authentication and webhook signature verification.
- Add required lifecycle scripts in `bin/`.
- Add runbook validation script and standardize runbook file format.
- Add structured JSON logging configuration.
- Add missing CI security gates (secret scanning + SBOM artifact generation).

Out of scope:
- Full observability stack rollout (Grafana/Alloy/Terraform provisioning).
- Production infrastructure migration.
- Feature-level cookbook changes not required for standards compliance.

## Requirements

### 1) API Conventions

1. Add `GET /health` returning JSON payload and HTTP 200 when healthy.
2. Keep existing `/up` behavior for Rails/Kamal compatibility, but `/health` becomes the standards endpoint.
3. Add admin endpoints:
- `PUT /admin/log-level`
- `PUT /admin/trace-sample-rate`
- `GET /admin/circuit-breaker`
- `PUT /admin/circuit-breaker`
- `PUT /admin/maintenance`

### 2) Authentication and Authorization

1. Introduce request authentication in `ApplicationController` for protected endpoints.
2. Support service token auth via `Authorization: Bearer <token>`.
3. Allow unauthenticated access only to `GET /health` and `GET /up`.
4. Enforce admin-scope authorization on `/admin/*` routes.
5. Ensure unauthorized responses follow JSON error format.

### 3) Webhook Security

1. Verify GitHub webhook signatures (`X-Hub-Signature-256`) using a configured shared secret.
2. Reject missing/invalid signatures with `401`.
3. Preserve existing accepted event-action behavior.

### 4) Lifecycle Scripts

Add required scripts:
- `bin/check-runbooks`
- `bin/monitor-prod`
- `bin/smoke-prod`
- `bin/check-error-budget-burn`
- `bin/load-test`

Each script must:
- be executable,
- be safe/idempotent where applicable,
- return non-zero exit on failure,
- include usage/help comments.

### 5) Runbooks

1. Add canonical service runbook file: `docs/runbooks/taskrail.md`.
2. Use required alert-section schema:
- `## <alert-slug>`
- `Alert`, `Severity`, `Fires when`, `Meaning`
- `Investigate`, `Diagnosis`, `Fix A/B`, `Escalate if`
3. Implement `bin/check-runbooks` to validate required fields and section anchors.

### 6) Logging

1. Emit structured JSON logs in production.
2. Ensure request logs include `request_id`.
3. Keep sensitive parameter filtering in place.
4. Keep health endpoint log suppression.

### 7) CI/CD Security Gates

1. Keep existing Brakeman + RuboCop + tests.
2. Add secret scanning gate (e.g., gitleaks) in CI.
3. Add SBOM generation and upload artifact step in CI.
4. Keep Dependabot config as-is.

## Implementation Plan

### Phase 1: Security + API Baseline

- Add auth layer to controllers.
- Add GitHub webhook signature verification.
- Add `/health` and `/admin/*` routes/controllers.
- Add request/response JSON error helpers.

### Phase 2: Operations Baseline

- Add required `bin/` scripts.
- Add `docs/runbooks/taskrail.md`.
- Add `bin/check-runbooks` validation logic.

### Phase 3: Logging + CI Hardening

- Configure JSON logging in production.
- Add CI gitleaks job.
- Add CI SBOM generation artifact.

## Acceptance Criteria

1. `curl /health` returns HTTP 200 with JSON response.
2. Protected API endpoints reject missing/invalid bearer token.
3. `/admin/*` rejects non-admin credentials.
4. GitHub webhook endpoint rejects invalid signature and accepts valid signature.
5. All required lifecycle scripts exist and execute with predictable exit codes.
6. `bin/check-runbooks` passes against `docs/runbooks/taskrail.md`.
7. Production logs are JSON and include request correlation fields.
8. CI includes Brakeman, lint, tests, secret scan, and SBOM artifact generation.

## Test Plan

- Request specs for auth gates, admin gates, and webhook signature verification.
- Request spec for `GET /health` schema/status.
- Script specs for `bin/check-runbooks` positive/negative paths.
- CI dry-run validation via workflow syntax check.

## Risks

- New auth layer could break existing CLI flows if token handling is not wired.
- Runbook validator may be brittle if markdown parsing is too strict.
- JSON logging transition could impact local log tooling expectations.

## Rollout

1. Land Phase 1 behind a short-lived feature branch.
2. Run full test suite and manual smoke checks.
3. Land Phase 2 and Phase 3 incrementally.
4. Update README with auth/env/script usage changes.

## Required Environment Variables

- `TASKRAIL_SERVICE_TOKEN` (service-to-service auth)
- `TASKRAIL_ADMIN_TOKEN` (admin endpoint auth)
- `GITHUB_WEBHOOK_SECRET` (webhook signature verification)
- `LOG_LEVEL` (runtime log level)

## Follow-ups

- Add OpenTelemetry trace/log correlation (`trace_id`, `span_id`).
- Add Terraform-managed alert/runbook URL mapping once `ops/terraform` is introduced.
- Add deploy workflow gating on `bin/check-runbooks` and `bin/check-error-budget-burn`.
