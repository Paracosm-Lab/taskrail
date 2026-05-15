# Cookbook Spec: Infrastructure Drift Detection

**Category: Live DevOps**

## Use Case

Staging and production were identical six months ago. Since then, someone added a Redis instance to production during an incident and forgot to add it to staging. Someone else bumped the Postgres version in staging to test a migration but never applied it to production. The Docker Compose files have diverged. The environment variables don't match. The nginx config has a rate limit in production that doesn't exist in staging.

You deploy to staging, everything works. You deploy to production, it breaks — because staging isn't production anymore. Nobody knows how far they've drifted because nobody's compared them recently.

TaskRail diffs your environments, categorizes every divergence, assesses which ones are intentional vs. accidental, and drafts the changes to bring them back in sync.

## Queue: `infrastructure_drift`

### Stages

```
collect_configs → diff_environments → classify_drift → draft_sync_plan → human_review → done
```

### Stage Details

**collect_configs** (shell_script)
- Adapter: `shell_script`
- Input: paths to environment configs (docker-compose files, k8s manifests, env files, nginx configs, Terraform state)
- Task: Collect and normalize configuration from each environment:
  - **Docker Compose**: services, images, versions, ports, volumes, environment variables, resource limits
  - **Environment variables**: `.env` files, `.env.production`, `.env.staging`, secrets references
  - **Web server**: nginx/Apache configs, rate limits, CORS settings, SSL config
  - **Database**: version, extensions, connection pool settings, replication config
  - **Infrastructure**: DNS records, CDN config, firewall rules, load balancer settings
  - Output a normalized representation of each environment that can be diffed
- Artifact: `environment_configs` — `{ environments: { production: { services: [], env_vars: [], web_config: {}, db_config: {} }, staging: { ... }, development: { ... } } }`
- Predicate: `configs_collected`
- Safety: READ-ONLY. Collect configs from files and APIs, do not modify anything.

**diff_environments** (Haiku)
- Adapter: `inline_claude`
- Input: environment_configs artifact
- Task: Produce a structured diff between environments (primarily staging vs. production):
  - **Services present in one but not the other** (e.g., Redis in production only)
  - **Version mismatches** (e.g., Postgres 15 in staging, 14 in production)
  - **Configuration differences** (e.g., different connection pool sizes, different rate limits)
  - **Environment variable differences** (missing, extra, or different values — mask actual secret values)
  - **Resource limit differences** (memory, CPU limits differ between environments)
  - For each diff: which environments, what specifically differs, the actual values (masked if sensitive)
- Artifact: `environment_diff` — `{ comparisons: [{ env_a, env_b, diffs: [{ category, key, value_a, value_b, type: "missing"|"extra"|"different" }] }], total_diffs }`
- Predicate: `diff_produced`
- Why Haiku: mechanical comparison, not reasoning

**classify_drift** (Sonnet)
- Adapter: `inline_claude`
- Input: environment_diff, source code, git history of config files
- Task: For each difference, classify it:
  - **Intentional**: production has higher resource limits, production has rate limiting, staging has debug mode on. These are expected and correct.
  - **Accidental**: someone added a service to production during an incident and forgot staging. A version was bumped in one environment but not the other. An env var was added to staging for testing and never cleaned up.
  - **Dangerous**: production is running an older version of a dependency with known CVEs. A security header exists in staging but not production. A database extension is missing in staging so migration testing is inaccurate.
  - **Stale**: config that references deprecated services, unused environment variables, ports that nothing listens on
  - Use git blame on config files to determine when each drift was introduced and by whom
- Artifact: `drift_classification` — `{ drifts: [{ diff_ref, classification: "intentional"|"accidental"|"dangerous"|"stale", confidence, rationale, introduced_by, introduced_at, risk_if_unresolved }], accidental_count, dangerous_count }`
- Predicate: `drift_classified`
- Why Sonnet: needs judgment about what's intentional vs. accidental, and understanding of infrastructure patterns

**draft_sync_plan** (Sonnet)
- Adapter: `inline_claude`
- Input: drift_classification, environment_configs, source code
- Task: Draft changes to resolve accidental and dangerous drift:
  - **Accidental drift**: which environment is correct? Update the other to match. If unclear, flag for human decision.
  - **Dangerous drift**: fix the risky environment immediately. Draft the config change.
  - **Stale drift**: draft removal of dead config. Verify nothing references it first.
  - **Intentional drift**: document it. Add a comment in the config explaining why the environments differ, so the next person who sees the diff doesn't "fix" it.
  - For each sync action: what changes, in which environment, the exact file and line, verification after applying
  - Order the sync plan: dangerous fixes first, then accidental, then stale cleanup
- Artifact: `sync_plan` — `{ actions: [{ drift_ref, classification, action: "sync"|"fix"|"remove"|"document", target_environment, file, change_description, verification, priority }], sync_order: [] }`
- Predicate: `sync_planned`

**human_review** (gate)
- Infrastructure changes can cause outages. Human reviews the sync plan, applies changes one at a time, verifies each environment after each change.

### Queue Config

```yaml
name: Infrastructure Drift Detection
slug: infrastructure_drift
stages:
  - collect_configs
  - diff_environments
  - classify_drift
  - draft_sync_plan
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
stage_configs:
  collect_configs:
    adapter_type: shell_script
    allowed_skills: [read_repo, query_infrastructure]
    forbidden_skills: [edit_files, deploy, mutate_infrastructure]
    max_retries: 1
    completion_criteria: [configs_collected]
    agent_prompt: file://prompts/drift_collect.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: environment_configs
  diff_environments:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [diff_produced]
    agent_prompt: file://prompts/drift_diff.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: environment_diff
  classify_drift:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [drift_classified]
    agent_prompt: file://prompts/drift_classify.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: drift_classification
  draft_sync_plan:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_infrastructure]
    max_retries: 2
    completion_criteria: [sync_planned]
    agent_prompt: file://prompts/drift_sync_plan.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: sync_plan
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review drift report and sync plan. Apply changes one environment at a time.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates

- `configs_collected` — environment_configs artifact with at least two environments
- `diff_produced` — environment_diff artifact with comparison results
- `drift_classified` — drift_classification artifact with classifications for all diffs
- `sync_planned` — sync_plan artifact with at least one action

### Cross-Queue Spawn

- Dangerous drift involving security → spawn into `security_scan` queue
- Drift caused by missing deployment automation → spawn into `development` queue
- Stale config referencing deprecated services → spawn into `dead_code` queue

### Safety

This pipeline is READ-ONLY. It collects and compares configs but does NOT modify any environment. The sync plan is a document for humans to execute. Infrastructure changes require manual application with verification between each step.

### Recurring Use

Run weekly or after every production deploy. Track drift count over time. The goal is: zero accidental drift, all intentional drift documented. If drift keeps reappearing in the same area, the deployment process has a gap — spawn into `development` to fix the deployment pipeline.

### E2E Test Fixture

Use TaskRail's own Docker Compose files as the test case. Create a `docker-compose.staging.yml` and `docker-compose.production.yml` with deliberate differences: a version mismatch on Postgres, a missing Redis service in staging, different environment variables. The pipeline should detect all three and classify them correctly.
