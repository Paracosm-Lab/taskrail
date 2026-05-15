# Cookbook Spec: Credential Rotation Audit

**Category: Live DevOps**

## Use Case

Somewhere in your infrastructure there's an API key that was created 18 months ago by someone who no longer works here. It has admin access to your payment provider. It's hardcoded in a config file that three services read. Nobody knows which services would break if you rotated it, so nobody rotates it. Meanwhile, the key appears in a Docker image layer that was pushed to a registry that five people have access to.

TaskRail finds every secret in your codebase and infrastructure, maps which services depend on each one, checks when they were last rotated, assesses the blast radius of a compromise, and drafts a rotation plan that won't take anything down.

## Queue: `credential_rotation`

### Stages

```
scan_secrets → map_dependencies → assess_risk → draft_rotation_plan → human_review → done
```

### Stage Details

**scan_secrets** (Haiku)
- Adapter: `inline_claude`
- Input: repository path, infrastructure config, environment files
- Task: Find every secret, credential, and sensitive value:
  - **Source code**: API keys, tokens, passwords in config files, `.env` files, YAML, JSON
  - **Environment variables**: referenced but not committed secrets (grep for `ENV['']`, `os.environ`, `process.env`)
  - **Docker/CI**: secrets in Dockerfiles, docker-compose, GitHub Actions, CI configs
  - **Secrets managers**: references to Vault, AWS SSM, Doppler, etc. (note: can't read the values, just the references)
  - **Git history**: secrets that were committed and then removed (they're still in history)
  - For each: name/identifier, type (API key, DB password, OAuth token, etc.), location, whether it's hardcoded or referenced from a secrets manager
- Artifact: `secret_inventory` — `{ secrets: [{ name, type, locations: [{ file, line, how: "hardcoded"|"env_var"|"secrets_manager" }], in_git_history: bool }], total_count, hardcoded_count }`
- Predicate: `secrets_scanned`
- Why Haiku: pattern matching across files, not reasoning

**map_dependencies** (Sonnet)
- Adapter: `inline_claude`
- Input: secret_inventory, source code, infrastructure config
- Task: For each secret, trace every service that uses it:
  - Which services read this secret at startup?
  - Which services read it at runtime (hot-reloadable vs. restart required)?
  - Are there multiple services sharing the same credential? (a rotation would need to update all of them simultaneously)
  - Is there a fallback if this credential is invalid? (graceful degradation vs. hard crash)
  - What's the scope of the credential? (read-only vs. admin, single-service vs. org-wide)
- Artifact: `dependency_map` — `{ credentials: [{ name, type, scope, services: [{ name, reads_at: "startup"|"runtime", fallback: bool }], shared_across: count, rotation_requires_restart: bool }] }`
- Predicate: `dependencies_mapped`
- Why Sonnet: needs to trace usage across services and understand the blast radius

**assess_risk** (Sonnet)
- Adapter: `inline_claude`
- Input: dependency_map, secret_inventory
- Task: Risk-score each credential:
  - **Exposure risk**: hardcoded in source > env var in CI > secrets manager. In git history = exposed.
  - **Blast radius**: admin key to payment provider > read-only key to analytics > internal service token
  - **Staleness**: how long since last rotation? (check git blame on the value, or metadata if from a secrets manager)
  - **Sharing risk**: credentials shared across services are harder to rotate and more dangerous if leaked
  - Classify: `critical` (rotate immediately) / `high` (rotate this sprint) / `medium` (rotate this quarter) / `low` (acceptable risk)
  - Flag any credential that appears in git history as at minimum `high` — it's effectively public
- Artifact: `risk_assessment` — `{ credentials: [{ name, exposure_risk, blast_radius, estimated_age_days, sharing_risk, overall_risk: "critical"|"high"|"medium"|"low", rationale }], critical_count, summary }`
- Predicate: `risk_assessed`

**draft_rotation_plan** (Sonnet)
- Adapter: `inline_claude`
- Input: risk_assessment, dependency_map, source code
- Task: For each critical and high-risk credential, draft a rotation procedure:
  - **Step 1**: Generate new credential in the provider (Stripe dashboard, AWS IAM, etc.)
  - **Step 2**: Update the credential in the secrets manager / env config
  - **Step 3**: Deploy/restart affected services (list them, in order if there are dependencies)
  - **Step 4**: Verify each service is healthy with the new credential
  - **Step 5**: Revoke the old credential
  - **Step 6**: If the old credential is in git history, note that rotating alone isn't enough — the history is still exposed
  - For shared credentials: coordinate the rotation across all dependent services
  - For hardcoded credentials: draft the code change to move them to a secrets manager, then rotate
  - Estimate downtime risk for each rotation
- Artifact: `rotation_plan` — `{ rotations: [{ credential_name, risk_level, steps: [{ action, target, verification, rollback }], services_affected, estimated_downtime, requires_code_change: bool, code_change_description }], rotation_order: [] }`
- Predicate: `rotation_planned`

**human_review** (gate)
- Credential rotation can cause outages. Human must review the plan, verify the order of operations, and execute rotations one at a time with verification between each.

### Queue Config

```yaml
name: Credential Rotation Audit
slug: credential_rotation
stages:
  - scan_secrets
  - map_dependencies
  - assess_risk
  - draft_rotation_plan
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
stage_configs:
  scan_secrets:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [secrets_scanned]
    agent_prompt: file://prompts/credential_scan.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: secret_inventory
  map_dependencies:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [dependencies_mapped]
    agent_prompt: file://prompts/credential_dependencies.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: dependency_map
  assess_risk:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [risk_assessed]
    agent_prompt: file://prompts/credential_risk.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: risk_assessment
  draft_rotation_plan:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [rotation_planned]
    agent_prompt: file://prompts/credential_rotation_plan.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: rotation_plan
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review rotation plan. Execute rotations one at a time with verification.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates

- `secrets_scanned` — secret_inventory artifact with results
- `dependencies_mapped` — dependency_map artifact with service mappings
- `risk_assessed` — risk_assessment artifact with risk levels
- `rotation_planned` — rotation_plan artifact with at least one rotation procedure

### Cross-Queue Spawn

- Hardcoded credentials needing code changes → spawn into `development` queue
- Credentials in git history → spawn into `security_scan` queue for broader audit
- Missing secrets manager → spawn into `incident_readiness` queue

### Safety

This pipeline is strictly READ-ONLY and ADVISORY. It does NOT rotate credentials, generate new keys, or modify any external service. The rotation plan is a document for humans to execute manually, one credential at a time, with verification between each step.

### Recurring Use

Run quarterly. Track credential age over time. The goal is: zero hardcoded secrets, zero credentials older than 90 days, every credential in a secrets manager. Each run should find fewer issues as the rotation discipline takes hold.
