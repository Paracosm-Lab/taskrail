# Cookbook Spec: Post-Incident Replay

**Category: Live DevOps**

## Use Case

An incident happened. The Slack thread is 200 messages long. The Sentry project has 47 events from a 90-minute window. Someone wrote a hasty postmortem at 2am that says "database was slow" and lists "add more monitoring" as the action item. Three months later, the same thing happens again because nobody actually understood what went wrong or updated the runbooks.

TaskRail ingests the actual incident artifacts — Sentry events, Slack threads, deploy logs, metrics — reconstructs a timeline, identifies root cause vs. symptoms, evaluates whether existing runbooks would have caught it faster, and drafts updates to the runbooks and alerting so the next incident is shorter.

## Queue: `post_incident_replay`

### Stages

```
ingest_artifacts → reconstruct_timeline → analyze_root_cause → evaluate_response → draft_updates → human_review → done
```

### Stage Details

**ingest_artifacts** (Haiku)
- Adapter: `inline_claude`
- Input: incident reference (Sentry issue IDs, Slack thread URL, deploy log range, time window)
- Task: Collect and normalize all incident artifacts:
  - **Sentry events**: error messages, stack traces, frequency, affected users, first/last seen
  - **Slack thread**: who said what, when decisions were made, when the fix was deployed
  - **Deploy logs**: what was deployed before/during the incident, rollback timestamps
  - **Metrics**: if available, latency spikes, error rate changes, resource utilization
  - Normalize everything to a common timeline with UTC timestamps
- Artifact: `incident_artifacts` — `{ time_window: { start, end }, sentry_events: [{ timestamp, error, stack_trace, count, users_affected }], slack_messages: [{ timestamp, author, text, is_decision }], deploys: [{ timestamp, commit, action }], metrics: [] }`
- Predicate: `artifacts_ingested`
- Why Haiku: parsing and normalizing structured data, not reasoning

**reconstruct_timeline** (Sonnet)
- Adapter: `inline_claude`
- Input: incident_artifacts
- Task: Build a chronological narrative of the incident:
  - **Detection**: when was the problem first noticed? By whom/what? How long after it started?
  - **Investigation**: what hypotheses were explored? Which were dead ends?
  - **Mitigation**: what temporary fix was applied? When? Did it work?
  - **Resolution**: what was the actual fix? When was it deployed? When was the incident declared over?
  - **Impact**: total duration, users affected, revenue impact if estimable
  - Identify the gaps: periods where nothing happened (people sleeping, waiting for access, unclear ownership)
- Artifact: `incident_timeline` — `{ phases: [{ name, start, end, duration_minutes, events: [{ timestamp, description, actor, type: "detection"|"investigation"|"mitigation"|"resolution"|"gap" }] }], total_duration_minutes, detection_delay_minutes, time_to_mitigate_minutes, time_to_resolve_minutes, impact: { users_affected, error_count } }`
- Predicate: `timeline_reconstructed`
- Why Sonnet: needs to understand the narrative arc of an incident from fragmented artifacts

**analyze_root_cause** (Sonnet)
- Adapter: `inline_claude`
- Input: incident_timeline, incident_artifacts, source code
- Task: Distinguish root cause from symptoms:
  - What actually broke? (not "the database was slow" but "the batch job at 2am acquired a table lock that blocked the API's read queries for 12 minutes")
  - Why did it break? (the batch job was added without considering lock contention)
  - Why wasn't it caught earlier? (no alerting on lock wait times, no query timeout on the API)
  - Contributing factors: missing tests, missing monitoring, unclear ownership, deployment timing
  - Map the causal chain: trigger → root cause → symptoms → detection → response
- Artifact: `root_cause_analysis` — `{ root_cause: { description, code_path, trigger }, contributing_factors: [{ factor, category: "code"|"monitoring"|"process"|"knowledge" }], causal_chain: [{ event, type: "trigger"|"cause"|"symptom"|"detection"|"response" }], why_not_caught: [] }`
- Predicate: `root_cause_analyzed`

**evaluate_response** (Sonnet)
- Adapter: `inline_claude`
- Input: root_cause_analysis, incident_timeline, existing runbooks (if any)
- Task: Grade the incident response:
  - **Detection**: was there an alert, or did a customer report it? Could an alert have caught it earlier?
  - **Diagnosis**: how long did it take to identify the root cause? What slowed it down?
  - **Runbook coverage**: did a runbook exist for this failure mode? Was it followed? Was it helpful?
  - **Communication**: was the right team notified? Were stakeholders updated?
  - **Resolution**: was the fix appropriate? Was it tested? Could it have been faster?
  - Score each dimension and identify specific improvements
- Artifact: `response_evaluation` — `{ scores: { detection, diagnosis, runbook_coverage, communication, resolution }, grade, improvements: [{ dimension, current_state, recommended_change, time_saved_estimate }] }`
- Predicate: `response_evaluated`

**draft_updates** (Sonnet)
- Adapter: `inline_claude`
- Input: root_cause_analysis, response_evaluation, existing runbooks, alerting config
- Task: Draft concrete improvements:
  - **New/updated runbook**: for this specific failure mode, with the actual diagnosis steps that worked
  - **New alerts**: monitoring that would have caught this incident earlier (with thresholds based on actual incident data)
  - **Code fixes**: if the root cause is a code issue, draft the fix or spawn to `development`
  - **Process changes**: if the response was slow due to unclear ownership or missing access, document what needs to change
  - Each update references the specific incident phase it would have improved
- Artifact: `incident_updates` — `{ runbook_updates: [{ path, content, failure_mode, references_phase }], new_alerts: [{ metric, threshold, rationale, would_have_detected_at }], code_fixes: [{ file, description, spawn_to_queue }], process_changes: [{ change, rationale }] }`
- Predicate: `updates_drafted`

**human_review** (gate)
- The postmortem is sensitive — it involves real incidents, real people's response times, and real gaps. Human review ensures the analysis is fair and the recommendations are actionable.

### Queue Config

```yaml
name: Post-Incident Replay
slug: post_incident_replay
stages:
  - ingest_artifacts
  - reconstruct_timeline
  - analyze_root_cause
  - evaluate_response
  - draft_updates
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
stage_configs:
  ingest_artifacts:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo, query_sentry, query_slack]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [artifacts_ingested]
    agent_prompt: file://prompts/incident_ingest.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: incident_artifacts
  reconstruct_timeline:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [timeline_reconstructed]
    agent_prompt: file://prompts/incident_timeline.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: incident_timeline
  analyze_root_cause:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [root_cause_analyzed]
    agent_prompt: file://prompts/incident_root_cause.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: root_cause_analysis
  evaluate_response:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [response_evaluated]
    agent_prompt: file://prompts/incident_evaluate.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: response_evaluation
  draft_updates:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [updates_drafted]
    agent_prompt: file://prompts/incident_draft_updates.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: incident_updates
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review incident analysis, root cause, and proposed improvements.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates

- `artifacts_ingested` — incident_artifacts with at least one event source
- `timeline_reconstructed` — incident_timeline with phases and duration
- `root_cause_analyzed` — root_cause_analysis with causal chain
- `response_evaluated` — response_evaluation with scores
- `updates_drafted` — incident_updates with at least one runbook update or alert

### Cross-Queue Spawn

- Code fixes → spawn into `development` queue
- Missing monitoring → spawn into `incident_readiness` queue
- Thin alerts → spawn into `operations` queue (the self-improving loop)

### Recurring Use

Run after every P1/P2 incident. The output replaces the hasty 2am postmortem with a structured analysis. Over time, the runbook library grows from actual incidents — not hypothetical scenarios — and the alerting gets tuned to real failure modes.

### E2E Test Fixture

Use the TaskRail ops pipeline E2E test as the incident. The fixture includes Sentry-format events, simulated Slack messages, and deploy timestamps. The replay pipeline should reconstruct what happened and identify improvements to the ops pipeline's own alerting.
