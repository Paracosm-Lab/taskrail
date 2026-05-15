# Cookbook Catalog

Cookbooks are reusable workflow templates. Each cookbook is configured as a queue in `config/queues/*.yml`, usually backed by prompts, fixtures, predicates, and tests.

A cookbook is not a fixed process. Teams can change stages, adapters, prompts, predicates, artifacts, retry rules, review gates, and execution targets.

## Catalog

| Queue | Category | Slug | Stages |
| --- | --- | --- | --- |
| API Documentation Sync | Development | `api_docs_sync` | scan_endpoints -> diff_existing_docs -> draft_documentation -> validate_examples -> human_review -> done |
| Chaos Monkey | Operations | `chaos_monkey` | plan_disruption -> execute_disruption -> monitor_impact -> hold_for_response -> evaluate_recovery -> score_and_report -> done |
| Chaos Response | Operations | `chaos_response` | detect_alerts -> diagnose_failure -> select_runbook -> execute_runbook -> verify_recovery -> report_outcome -> done |
| Credential Rotation Audit | Security | `credential_rotation` | scan_secrets -> map_dependencies -> assess_risk -> draft_rotation_plan -> human_review -> done |
| Data Integrity Validator | Data | `data_integrity` | define_rules -> scan_violations -> assess_damage -> draft_repairs -> human_review -> done |
| Dead Code Removal | Development | `dead_code_removal` | scan_references -> verify_unused -> draft_removals -> run_tests -> human_review -> done |
| Dependency Upgrade | Development | `dependency_upgrade` | audit_dependencies -> prioritize_upgrades -> upgrade_one -> run_tests -> human_review -> done |
| Development | Development | `development` | intake -> decompose -> build -> test -> review -> done |
| Development Claude | Development | `development-claude` | intake -> decompose -> build -> test -> review -> done |
| Development Codex | Development | `development-codex` | intake -> decompose -> build -> test -> review -> done |
| Development Shell | Development | `development-shell` | intake -> decompose -> build -> test -> review -> done |
| Error Handling Audit | Development | `error_handling_audit` | scan_error_handling -> classify_severity -> draft_fixes -> run_tests -> human_review -> done |
| Incident Readiness Scoring | Operations | `incident_readiness` | inventory_services -> score_readiness -> identify_gaps -> draft_improvements -> human_review -> done |
| Infrastructure Drift Detection | Operations | `infrastructure_drift` | collect_configs -> diff_environments -> classify_drift -> draft_sync_plan -> human_review -> done |
| Integration Test Generator | Development | `integration_tests` | map_user_flows -> identify_boundaries -> generate_tests -> run_tests -> human_review -> done |
| Background Job Observability | Operations | `job_observability` | scan_job_classes -> assess_observability -> draft_fixes -> run_tests -> human_review -> done |
| Logging Consistency Audit | Operations | `logging_audit` | scan_log_statements -> assess_quality -> draft_standard -> draft_fixes -> run_tests -> human_review -> done |
| Migration Safety Check | Data | `migration_safety` | scan_impact -> enumerate_risks -> draft_rollback -> test_rollback -> draft_runbook -> human_review -> done |
| Operations | Operations | `operations` | ingest_signals -> cluster_failures -> assess_instrumentation -> map_runbooks -> draft_runbook -> human_review -> staging_validation -> publish_runbook -> done |
| Post-Incident Replay | Operations | `post_incident_replay` | ingest_artifacts -> reconstruct_timeline -> analyze_root_cause -> evaluate_response -> draft_updates -> human_review -> done |
| PR Review Pipeline | Development | `pr_review` | run_checks -> security_scan -> coverage_check -> architectural_review -> human_review -> done |
| Database Query Health Check | Data | `query_health` | collect_queries -> analyze_performance -> draft_fixes -> run_tests -> human_review -> done |
| Security Scan | Security | `security_scan` | scan_vulnerabilities -> classify_severity -> draft_fixes -> run_tests -> human_review -> done |
| Test Coverage Backfill | Development | `test_backfill` | scan_coverage -> identify_gaps -> generate_tests -> run_tests -> human_review -> done |

## Cookbook Shape

Most cookbooks follow the same pattern:

1. Collect or scan context.
2. Classify, map, prioritize, or assess risk.
3. Draft changes, fixes, tests, plans, or runbooks.
4. Validate through tests, checks, rollback proof, or staging execution.
5. Stop for human review before completion.

## Development Cookbooks

Use these when the output is code, tests, documentation, or reviewable engineering changes.

Representative queues:

- `development`
- `dependency_upgrade`
- `dead_code_removal`
- `api_docs_sync`
- `test_backfill`
- `integration_tests`
- `pr_review`
- `error_handling_audit`

## Operations and DevOps Cookbooks

Use these when production-adjacent reliability, visibility, runbooks, or recovery paths matter.

Representative queues:

- `operations`
- `incident_readiness`
- `chaos_response`
- `chaos_monkey`
- `job_observability`
- `logging_audit`
- `infrastructure_drift`
- `post_incident_replay`

## Security and Data Cookbooks

Use these when risk, impact, rollback, credential handling, data correctness, or exploitability require explicit gates.

Representative queues:

- `security_scan`
- `credential_rotation`
- `migration_safety`
- `data_integrity`
- `query_health`

## Existing Detailed Docs

Detailed cookbook docs already exist in this directory, including:

- [Feature Development](./04-feature-development.md)
- [Chaos Monkey](./09-chaos-monkey.md)
- [API Documentation Sync](./api-documentation-sync.md)
- [Background Job Observability](./background-job-observability.md)
- [Credential Rotation Audit](./credential-rotation-audit.md)
- [Dependency Upgrade](./dependency-upgrade.md)
- [Error Handling Audit](./error-handling-audit.md)
- [Failure Readiness](./failure-readiness.md)
- [Incident Readiness Scoring](./incident-readiness-scoring.md)
- [Integration Test Generator](./integration-test-generator.md)
- [Migration Safety](./migration-safety.md)
- [Security Scan](./security-scan.md)
- [Test Coverage Backfill](./test-coverage-backfill.md)
