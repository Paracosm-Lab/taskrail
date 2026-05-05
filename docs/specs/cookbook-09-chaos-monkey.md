# Cookbook Spec: Chaos Monkey (Adversarial Runbook Testing)

## Use Case

You have runbooks. You think they work. But nobody's tested them since they were written — and the infrastructure has changed twice since then. The only way to know if a runbook works is to break something and try to fix it.

This cookbook uses two queues that are blind to each other. The **chaos queue** invents failure scenarios and breaks things in the staging environment. The **response queue** receives the resulting alerts and has to diagnose and fix the problem using only the runbooks. Neither queue knows what the other is doing.

If the response queue can't fix it, the runbooks are inadequate. If the alerts don't provide enough context to diagnose it, the instrumentation is inadequate. Either way, you found out on a Tuesday instead of at 3am.

## Architecture: Two Blind Queues

```
┌─────────────────────────────┐     ┌─────────────────────────────┐
│       CHAOS QUEUE           │     │      RESPONSE QUEUE         │
│                             │     │                             │
│  plan_disruption            │     │  detect_alerts              │
│       ↓                     │     │       ↓                     │
│  execute_disruption ────────┼──→  │  diagnose_failure           │
│       ↓                     │  ↑  │       ↓                     │
│  monitor_impact       alerts│  │  │  select_runbook             │
│       ↓                     │  │  │       ↓                     │
│  hold_for_response    ──────┼──┘  │  execute_runbook            │
│       ↓                     │     │       ↓                     │
│  evaluate_recovery ←────────┼──── │  verify_recovery            │
│       ↓                     │     │       ↓                     │
│  score_and_report           │     │  report_outcome             │
│                             │     │                             │
└─────────────────────────────┘     └─────────────────────────────┘
```

**Key constraint:** The response queue does NOT know what the chaos queue broke. It only sees the alerts that fire. This simulates a real incident — the on-call engineer doesn't know the root cause when they get paged.

## Queue 1: `chaos_monkey`

### Stages

```
plan_disruption → execute_disruption → monitor_impact → hold_for_response → evaluate_recovery → score_and_report → done
```

### Stage Details

**plan_disruption** (Sonnet)
- Adapter: `inline_claude`
- Input: staging environment inventory (services, databases, queues, external dependencies), past disruption history
- Task: Choose a realistic failure scenario to simulate. Categories:
  - **Infrastructure**: kill a database, stop a service, fill a disk, saturate a connection pool
  - **Dependency**: block an external API, introduce latency, return errors from a third-party service
  - **Data**: corrupt a config, rotate a credential without updating consumers, introduce a schema mismatch
  - **Load**: spike traffic to a single endpoint, flood a queue, trigger rate limits
  - Must be reversible. Must be scoped to staging. Must not affect production.
  - Must not repeat the last N disruptions (check history).
- Artifact: `disruption_plan` — `{ scenario, category, target_service, action, expected_symptoms, reversal_steps, safety_checks }`
- Predicate: `disruption_planned` — artifact exists with scenario and reversal_steps
- Why Sonnet: needs to reason about realistic failure modes and safety

**execute_disruption** (shell_script or docker_compose)
- Adapter: `docker_compose` or `shell_script`
- Input: disruption_plan artifact
- Task: Execute the planned disruption in the staging environment:
  - `docker compose stop crm-postgres` (kill a database)
  - `iptables -A OUTPUT -d api.stripe.com -j DROP` (block an external API)
  - `docker compose exec billing-service env RATE_LIMIT_OVERRIDE=0` (trigger rate limits)
  - Record the exact commands executed and timestamps
- Artifact: `disruption_executed` — `{ commands_run: [], start_time, target_service, expected_alert_lag_seconds }`
- Predicate: `disruption_executed` — artifact exists with commands_run
- Safety: reversal_steps from the plan are stored as metadata — if anything goes wrong, the engine has the undo commands

**monitor_impact** (shell_script)
- Adapter: `shell_script`
- Input: disruption_executed artifact
- Task: Wait for alerts to fire. Poll Sentry/alerting for new events matching the disrupted service. Timeout after expected_alert_lag + buffer.
- Artifact: `impact_observed` — `{ alerts_fired: count, alert_delay_seconds, services_affected: [], sentry_event_ids: [] }`
- Predicate: `impact_observed` — at least one alert fired
- If no alerts fire: that's a finding too — your monitoring has a gap

**hold_for_response** (fake — waiting gate)
- Adapter: `fake`
- Task: Wait for the response queue to complete its work. The chaos queue pauses here while the response queue detects, diagnoses, and attempts recovery.
- This stage uses the `waiting` status — it transitions when the response queue's work item reaches `report_outcome`.
- Timeout: 30 minutes. If the response queue can't fix it in 30 minutes, that's a finding.

**evaluate_recovery** (Sonnet)
- Adapter: `inline_claude`
- Input: response queue's outcome report, disruption_plan, monitoring data
- Task: Score the recovery:
  - **Detection time**: how long from disruption to first alert?
  - **Diagnosis accuracy**: did the response queue identify the right root cause?
  - **Runbook applicability**: did an existing runbook cover this scenario?
  - **Recovery time**: how long from first alert to verified recovery?
  - **Recovery completeness**: is the service fully restored, or just partially?
  - **Alert quality**: did the alerts provide enough context to diagnose without guessing?
- Artifact: `recovery_evaluation` — `{ scores: { detection, diagnosis, runbook_coverage, recovery_time, recovery_completeness, alert_quality }, overall_grade, gaps: [], recommendations: [] }`
- Predicate: `recovery_evaluated`

**score_and_report** (Sonnet)
- Adapter: `inline_claude`
- Task: Produce a final chaos exercise report:
  - What was broken
  - What alerts fired (and what didn't)
  - How the response queue handled it
  - What worked, what failed
  - Specific improvements needed (alert gaps, runbook gaps, missing monitoring)
  - Spawn work items for the improvements
- Artifact: `chaos_report`
- Cross-queue spawn: creates work items in `operations` (runbook updates) and `development` (instrumentation/monitoring fixes)

## Queue 2: `chaos_response`

### Stages

```
detect_alerts → diagnose_failure → select_runbook → execute_runbook → verify_recovery → report_outcome → done
```

### Stage Details

**detect_alerts** (shell_script)
- Adapter: `shell_script`
- Input: Sentry API credentials, monitoring endpoints
- Task: Poll Sentry for new alerts. Collect all events from the last N minutes. This stage has NO knowledge of what was broken — it only sees what the monitoring sees.
- Artifact: `detected_alerts` — `{ events: [...], detection_time }`
- Predicate: `alerts_detected` — at least one event captured

**diagnose_failure** (Sonnet)
- Adapter: `inline_claude`
- Input: detected_alerts artifact ONLY — no access to disruption plan
- Task: From the alerts alone, determine:
  - What services are affected?
  - What's the likely root cause?
  - What's the severity?
  - Are these related or independent failures?
  - Cluster the alerts (same pattern as ops queue)
- Artifact: `diagnosis` — `{ root_cause_hypothesis, affected_services, severity, clusters: [], confidence }`
- Predicate: `diagnosis_produced`
- Why this matters: if the diagnosis is wrong, the runbook won't help. Alert quality directly determines diagnosis accuracy.

**select_runbook** (Sonnet)
- Adapter: `inline_claude`
- Input: diagnosis artifact, available runbooks in repo
- Task: Find the runbook that matches the diagnosed failure. If no runbook exists, report the gap.
- Artifact: `runbook_selection` — `{ selected_runbook: path|null, match_confidence, gaps: [] }`
- Predicate: `runbook_selected` — artifact exists (null selection is valid — that's a finding)

**execute_runbook** (docker_compose)
- Adapter: `docker_compose`
- Input: runbook_selection artifact, staging environment
- Task: Follow the runbook's observe → mitigate → verify steps against the staging environment. Execute each command. Record results.
- Artifact: `runbook_execution` — `{ steps_executed: [{ step, command, output, success }], overall_success: bool }`
- Predicate: `runbook_executed` — artifact exists
- If no runbook was found: skip to report_outcome with "no applicable runbook"

**verify_recovery** (shell_script)
- Adapter: `shell_script`
- Input: runbook_execution artifact
- Task: Check if the service actually recovered:
  - Health check endpoints responding?
  - Sentry alert rate dropped to zero?
  - Key operations succeeding?
- Artifact: `recovery_verification` — `{ service_healthy: bool, alert_rate: number, verification_checks: [] }`
- Predicate: `recovery_verified` — `service_healthy: true`

**report_outcome** (Sonnet)
- Adapter: `inline_claude`
- Task: Summarize what happened from the response queue's perspective:
  - What alerts were seen
  - What was diagnosed
  - What runbook was used (or not)
  - Whether recovery succeeded
  - Time from detection to recovery
- Artifact: `response_outcome` — `{ detected, diagnosed, runbook_used, recovered, timeline: {} }`
- This artifact is read by the chaos queue's `evaluate_recovery` stage

### Queue Configs

```yaml
# chaos_monkey.yml
name: Chaos Monkey
slug: chaos_monkey
stages:
  - plan_disruption
  - execute_disruption
  - monitor_impact
  - hold_for_response
  - evaluate_recovery
  - score_and_report
  - done
config:
  default_max_retries: 1
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
stage_configs:
  plan_disruption:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo, read_environment_inventory]
    forbidden_skills: [deploy, mutate_database, execute_staging]
    max_retries: 1
    completion_criteria: [disruption_planned]
    agent_prompt: file://prompts/chaos_plan_disruption.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: disruption_plan
  execute_disruption:
    adapter_type: docker_compose
    allowed_skills: [execute_staging]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 0
    completion_criteria: [disruption_executed]
    agent_prompt: file://prompts/chaos_execute_disruption.md
    timeout_seconds: 300
    adapter_config:
      compose_file: docker-compose.staging.yml
      output_artifact_kind: disruption_record
  monitor_impact:
    adapter_type: shell_script
    allowed_skills: [read_sentry]
    forbidden_skills: [deploy, mutate_database, execute_staging]
    max_retries: 1
    completion_criteria: [impact_observed]
    agent_prompt: file://prompts/chaos_monitor_impact.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: impact_report
  hold_for_response:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Waiting for chaos_response queue to complete recovery attempt.
    timeout_seconds: 1800
  evaluate_recovery:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 1
    completion_criteria: [recovery_evaluated]
    agent_prompt: file://prompts/chaos_evaluate_recovery.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: recovery_evaluation
  score_and_report:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 1
    completion_criteria: [report_present]
    agent_prompt: file://prompts/chaos_score_report.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: chaos_report
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

```yaml
# chaos_response.yml
name: Chaos Response
slug: chaos_response
stages:
  - detect_alerts
  - diagnose_failure
  - select_runbook
  - execute_runbook
  - verify_recovery
  - report_outcome
  - done
config:
  default_max_retries: 1
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
stage_configs:
  detect_alerts:
    adapter_type: shell_script
    allowed_skills: [read_sentry]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 2
    completion_criteria: [alerts_detected]
    agent_prompt: file://prompts/response_detect_alerts.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: detected_alerts
  diagnose_failure:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_sentry]
    forbidden_skills: [deploy, mutate_database, execute_staging, read_disruption_plan]
    max_retries: 1
    completion_criteria: [diagnosis_produced]
    agent_prompt: file://prompts/response_diagnose.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: diagnosis
  select_runbook:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database, execute_staging]
    max_retries: 1
    completion_criteria: [runbook_selected]
    agent_prompt: file://prompts/response_select_runbook.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: runbook_selection
  execute_runbook:
    adapter_type: docker_compose
    allowed_skills: [execute_staging, read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 1
    completion_criteria: [runbook_executed]
    agent_prompt: file://prompts/response_execute_runbook.md
    timeout_seconds: 1200
    adapter_config:
      compose_file: docker-compose.staging.yml
      output_artifact_kind: runbook_execution
  verify_recovery:
    adapter_type: shell_script
    allowed_skills: [read_sentry, execute_staging]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 2
    completion_criteria: [recovery_verified]
    agent_prompt: file://prompts/response_verify_recovery.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: recovery_verification
  report_outcome:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 1
    completion_criteria: [report_present]
    agent_prompt: file://prompts/response_report_outcome.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: response_outcome
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates Needed

- `disruption_planned` — artifact has scenario + reversal_steps
- `disruption_executed` — artifact has commands_run
- `impact_observed` — artifact exists (zero alerts is a valid finding)
- `recovery_evaluated` — artifact has scores
- `alerts_detected` — artifact has events
- `diagnosis_produced` — artifact has root_cause_hypothesis
- `runbook_selected` — artifact exists (null selection valid)
- `runbook_executed` — artifact has steps_executed
- `recovery_verified` — artifact has service_healthy

### Cross-Queue Communication

The two queues communicate through:

1. **Sentry** — the chaos queue breaks something, alerts fire in Sentry, the response queue reads Sentry. No direct data sharing.
2. **Work item linkage** — the chaos queue's `execute_disruption` stage spawns the response queue's work item. The chaos queue's `hold_for_response` waits for the response work item to complete.
3. **Artifact reading** — `evaluate_recovery` reads the response queue's `response_outcome` artifact to score the recovery.

The response queue's `forbidden_skills` includes `read_disruption_plan` — it is explicitly prevented from knowing what was broken. It must diagnose from alerts alone.

### E2E Test Setup

Requires a Docker Compose staging environment with:
- At least 2 services (e.g., the StupidClaw API + Postgres)
- Sentry DSN configured to capture events
- Health check endpoints
- A set of "safe disruption" scripts (stop a container, block a port, etc.)

For a lightweight first test, the chaos queue can plan but not execute — have it output the plan and score a human-executed disruption instead.

### Safety

- All disruptions MUST have reversal steps
- Chaos queue MUST NOT touch production
- `execute_disruption` has `max_retries: 0` — if it fails, don't retry breaking things
- `hold_for_response` has a 30-minute timeout — if recovery fails, the chaos queue must still run `evaluate_recovery` and undo the disruption via reversal steps
- The engine should run reversal steps on any chaos queue failure/timeout as a safety net
