# Cookbook Spec: Incident Readiness Scoring

## Use Case

You have eight services. Some have health checks, alerting, runbooks, dashboards, and on-call coverage. Some have none of the above. You don't know which ones because nobody's audited it. When service X breaks at 3am, you find out the hard way that it has no runbook, no dashboard, and the last person who understood it left the company.

StupidClaw audits every service against a readiness rubric, scores them, ranks by risk, and drafts the missing pieces for the worst ones. The output is a readiness scorecard — a single view of "if this breaks tonight, are we ready?"

## Queue: `incident_readiness`

### Stages

```
inventory_services → score_readiness → identify_gaps → draft_improvements → human_review → done
```

### Stage Details

**inventory_services** (Haiku)
- Adapter: `inline_claude`
- Input: repository path(s), infrastructure config (docker-compose, k8s manifests, etc.)
- Task: Build a service inventory by scanning:
  - Docker Compose / Kubernetes manifests for service definitions
  - Application directories for independent services/apps
  - Database dependencies, external API dependencies, queue dependencies
  - For each service: name, type (web, worker, cron), dependencies, deployment method, team owner (if discoverable from CODEOWNERS or similar)
- Artifact: `service_inventory` — `{ services: [{ name, type, dependencies: [], deployment, owner, repo_path }] }`
- Predicate: `service_inventory_produced` — artifact exists with at least one service
- Why Haiku: parsing config files, not reasoning

**score_readiness** (Sonnet)
- Adapter: `inline_claude`
- Input: service_inventory artifact, repository contents
- Task: For each service, check and score (0-3 per dimension):
  - **Health checks**: does it expose `/health`, `/ready`, or equivalent? (check routes, Docker HEALTHCHECK, k8s probes)
  - **Alerting**: are there Sentry DSN configs, alert rules, PagerDuty/Slack integrations?
  - **Runbooks**: do runbooks exist in `docs/runbooks/` or similar? Are they recent (check git blame)?
  - **Dashboards**: are there Grafana/Datadog dashboard configs or references?
  - **Logging**: structured logging configured? Log level appropriate?
  - **Error handling**: does it use Sentry/error tracking? Are errors captured with context?
  - **Dependency resilience**: circuit breakers, timeouts, retries on external calls?
  - **Documentation**: README, architecture docs, API docs exist and are current?
  - Overall score: sum of dimensions / max possible. Grade: A (>80%), B (60-80%), C (40-60%), D (20-40%), F (<20%)
- Artifact: `readiness_scores` — `{ services: [{ name, scores: { health_checks, alerting, runbooks, dashboards, logging, error_handling, resilience, documentation }, total_score, grade, critical_gaps: [] }], summary: { avg_score, worst_service, best_service } }`
- Predicate: `readiness_scored` — artifact exists with scores for every inventoried service
- Why Sonnet: needs to understand what constitutes good monitoring, logging, and operational readiness

**identify_gaps** (Sonnet)
- Adapter: `inline_claude`
- Input: readiness_scores artifact
- Task: Prioritize the gaps across all services:
  - Rank by risk: a user-facing web service with no health checks is worse than a weekly cron with no dashboard
  - Group related gaps (e.g., if no service has structured logging, that's a platform-wide gap, not N individual gaps)
  - Estimate effort for each fix: quick (add a health check endpoint), medium (set up alerting), large (write runbooks from scratch)
  - Produce a prioritized improvement plan
- Artifact: `gap_analysis` — `{ platform_gaps: [], service_gaps: [{ service, gap, risk, effort, recommendation }], priority_order: [] }`
- Predicate: `gaps_identified` — artifact exists
- Why Sonnet: needs to make risk/effort tradeoff judgments

**draft_improvements** (Sonnet)
- Adapter: `inline_claude`
- Input: gap_analysis artifact, source code
- Task: For the top-priority gaps, draft the actual improvements:
  - **Health check**: add a `/health` endpoint that checks DB connectivity, queue health, and returns structured status
  - **Alerting**: draft Sentry alert rules or PagerDuty config
  - **Runbooks**: draft runbooks for the most likely failure modes (same format as ops queue runbooks)
  - **Logging**: add structured logging to critical paths
  - Start with quick wins — the health checks and alert configs that take 30 minutes to implement
- Artifact: `improvement_drafts` — `{ improvements: [{ service, gap_type, files: [{ path, content }], description }] }`
- Predicate: `improvements_drafted` — artifact has at least one improvement
- Cross-queue spawn: for large improvements (full runbook suite, monitoring overhaul), spawn into `development` or `operations` queue
- Why Sonnet: writing code and config that matches project patterns

**human_review** (gate)
- Adapter: `fake`
- The readiness scorecard itself is valuable even without applying fixes — share it with the team

### Queue Config

```yaml
name: Incident Readiness Scoring
slug: incident_readiness
stages:
  - inventory_services
  - score_readiness
  - identify_gaps
  - draft_improvements
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
stage_configs:
  inventory_services:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [service_inventory_produced]
    agent_prompt: file://prompts/readiness_inventory.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: service_inventory
  score_readiness:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [readiness_scored]
    agent_prompt: file://prompts/readiness_score.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: readiness_scores
  identify_gaps:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [gaps_identified]
    agent_prompt: file://prompts/readiness_gaps.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: gap_analysis
  draft_improvements:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [improvements_drafted]
    agent_prompt: file://prompts/readiness_draft_improvements.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: improvement_drafts
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review readiness scorecard and improvement drafts.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates Needed

- `service_inventory_produced` — artifact with at least one service
- `readiness_scored` — artifact with scores for all inventoried services
- `gaps_identified` — artifact with gap analysis
- `improvements_drafted` — artifact with at least one improvement

### E2E Test Fixtures

Use StupidClaw's own codebase as the target. It has:
- A Rails API (web service) with some health check infrastructure
- Docker Compose for staging
- Runbooks (from the ops queue E2E test)
- Sentry fixtures but maybe no DSN config
- Some structured logging, some not

This makes a realistic test — the readiness scorer will find real gaps in StupidClaw itself.

### Recurring Use

Run quarterly. Compare scores against the previous run. Track improvement over time. The readiness scorecard becomes a living document — not a one-time audit that gets stale in a drawer.

### Output Format

The readiness scorecard should be human-readable as a standalone document:

```
SERVICE READINESS SCORECARD — 2026-05-05

Service             Health  Alert  Runbook  Dash  Log  Error  Resil  Docs  GRADE
crm-service           2      1      0       1     1     1      0      1     D (29%)
notification-service  1      1      0       0     0     1      0      0     F (13%)
billing-service       2      1      0       0     1     0      0      1     D (21%)
stupidclaw-api        3      2      1       0     2     2      1      2     B (65%)

Platform gaps: No service has runbooks. No dashboards configured. No circuit breakers.
Worst service: notification-service (F, 13%)
Quick wins: Add /health to notification-service. Add Sentry DSN to billing-service.
```
