# Post-Incident Replay Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `post_incident_replay` cookbook queue so TaskRail can ingest incident evidence, reconstruct a timeline, separate root cause from symptoms, grade the response, draft runbook/alert/code/process improvements, and stop at human review.

**Architecture:** This cookbook follows the existing seeded Rails queue pattern: a portable YAML queue under `config/queues/`, repo-relative prompt files loaded through `file://`, artifact-backed predicates under `Engine::Predicates`, registry/seed specs, and an integration spec that advances through synthetic incident artifacts. The fixture is Docker-friendly source/data under `cookbooks/fixtures/incidents/ops_pipeline_p1/` and reuses existing fake-service conventions; it must not require real Slack, Sentry, metrics, or deploy-log credentials.

**Tech Stack:** Rails, RSpec, seeded YAML queues, `WorkQueue`/`StageConfig`/`WorkItem`/`Claim`/`Artifact`, `Engine::PredicateRegistry`, inline Claude adapters, fake human-review stages, repo-relative cookbook fixtures, rbenv on Greg's Mac.

**Source Spec:** `docs/specs/cookbook-19-post-incident-replay.md`

---

## Source Requirements Summary

Implement cookbook-19, `Post-Incident Replay`, category `Live DevOps`.

Queue stages:

`ingest_artifacts -> reconstruct_timeline -> analyze_root_cause -> evaluate_response -> draft_updates -> human_review -> done`

Required predicates:

- `artifacts_ingested`: passes when the current claim has an `incident_artifacts` artifact with a time window and at least one event source (`sentry_events`, `slack_messages`, `deploys`, or `metrics`).
- `timeline_reconstructed`: passes when the current claim has an `incident_timeline` artifact with phases and a positive total duration.
- `root_cause_analyzed`: passes when the current claim has a `root_cause_analysis` artifact with a root cause and causal chain.
- `response_evaluated`: passes when the current claim has a `response_evaluation` artifact with scores and improvements.
- `updates_drafted`: passes when the current claim has an `incident_updates` artifact with at least one runbook update or alert.

Artifacts:

- `incident_artifacts`: `{ time_window: { start, end }, sentry_events: [{ timestamp, error, stack_trace, count, users_affected }], slack_messages: [{ timestamp, author, text, is_decision }], deploys: [{ timestamp, commit, action }], metrics: [] }`
- `incident_timeline`: `{ phases: [{ name, start, end, duration_minutes, events: [{ timestamp, description, actor, type }] }], total_duration_minutes, detection_delay_minutes, time_to_mitigate_minutes, time_to_resolve_minutes, impact: { users_affected, error_count } }`
- `root_cause_analysis`: `{ root_cause: { description, code_path, trigger }, contributing_factors: [{ factor, category }], causal_chain: [{ event, type }], why_not_caught: [] }`
- `response_evaluation`: `{ scores: { detection, diagnosis, runbook_coverage, communication, resolution }, grade, improvements: [{ dimension, current_state, recommended_change, time_saved_estimate }] }`
- `incident_updates`: `{ runbook_updates: [{ path, content, failure_mode, references_phase }], new_alerts: [{ metric, threshold, rationale, would_have_detected_at }], code_fixes: [{ file, description, spawn_to_queue }], process_changes: [{ change, rationale }] }`

Safety and sensitivity:

- This queue analyzes real incident evidence and response quality; prompts must be factual, fair, and non-blaming.
- The queue must not contact real Slack, Sentry, deploy, or metrics systems in tests. Fixture data is local JSON/text.
- `human_review` is mandatory before outputs are treated as accepted postmortem/runbook updates.
- Cross-queue follow-up targets are advisory artifact fields only for this slice: code fixes to `development`, missing monitoring to `incident_readiness`, thin alerts to `operations`.

---

## Current Codebase Context

Relevant existing files and conventions discovered during planning:

- `db/seeds.rb` loads every `config/queues/*.yml`, resolves `agent_prompt: file://...` using `Rails.root.join(relative_path).read`, and upserts `WorkQueue` plus `StageConfig` rows.
- `config/queues/incident_readiness.yml` is a close root-prompt example with inline Claude stages, `adapter_config.output_artifact_kind`, fake review stages, and `max_regression_loops: 0`.
- `config/queues/chaos_response.yml` is the closest incident-response queue example and already uses local fake alert scripts under `spec/fixtures/chaos_staging`; do not reuse its real stage names because this cookbook is retrospective replay, not live response.
- `config/queues/dead_code_removal.yml` and `docs/plans/cookbooks/14-migration-safety.md` show the newer shared cookbook fixture/prompt shape under `cookbooks/`; use that shape here rather than adding more root prompt files.
- Existing predicates live in `app/services/engine/predicates/` and return `PredicateResult.pass(evidence: { artifact_id: artifact.id, ... })` or `PredicateResult.fail(reason: "...")`.
- `app/services/engine/predicate_registry.rb` maps completion-criteria names to predicate classes; `spec/services/engine/predicate_registry_spec.rb` verifies registered names.
- `spec/models/work_queue_seed_spec.rb` has queue seed examples that assert resolved prompts, adapter config, stage order, and no absolute checkout paths in serialized YAML.
- `spec/services/engine/dead_code_removal_workflow_integration_spec.rb` demonstrates a compact artifact-driven workflow integration spec.
- `spec/system/job_observability_cookbook_spec.rb` demonstrates fixture-contract assertions plus predicate-registry checks.
- Shared cookbook infrastructure lives under `cookbooks/`, including `cookbooks/docker-compose.yml`, `cookbooks/fake_services/fake_service.rb`, `cookbooks/prompts/`, and `cookbooks/fixtures/`.

Global implementation rules:

- Follow strict TDD from `test-driven-development`: write each failing spec first, run it and confirm the expected RED failure, implement the smallest production/config change, rerun focused specs, then run relevant surrounding specs.
- Use Greg's rbenv path for every RSpec command:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Do not hardcode `/Users/gregmushen/work/code/taskrail` or any absolute repository path in queue YAML, prompts, specs, fixtures, docs, or implementation code.
- Use repo-relative prompt paths: `file://cookbooks/prompts/post_incident_replay/ingest_artifacts.md`, etc.
- Use repo-relative fixture paths: `cookbooks/fixtures/incidents/ops_pipeline_p1`.
- Queue YAML should omit `working_directory`; adapters already default to `Rails.root` where needed.
- Commit after each task when implementing from this plan. If the Kanban implementation card requires one final commit, squash task commits before completion.

---

## Files to Create or Modify

Create:

- `config/queues/post_incident_replay.yml`
- `cookbooks/prompts/post_incident_replay/ingest_artifacts.md`
- `cookbooks/prompts/post_incident_replay/reconstruct_timeline.md`
- `cookbooks/prompts/post_incident_replay/analyze_root_cause.md`
- `cookbooks/prompts/post_incident_replay/evaluate_response.md`
- `cookbooks/prompts/post_incident_replay/draft_updates.md`
- `app/services/engine/predicates/artifacts_ingested.rb`
- `app/services/engine/predicates/timeline_reconstructed.rb`
- `app/services/engine/predicates/root_cause_analyzed.rb`
- `app/services/engine/predicates/response_evaluated.rb`
- `app/services/engine/predicates/updates_drafted.rb`
- `spec/services/engine/predicates/artifacts_ingested_spec.rb`
- `spec/services/engine/predicates/timeline_reconstructed_spec.rb`
- `spec/services/engine/predicates/root_cause_analyzed_spec.rb`
- `spec/services/engine/predicates/response_evaluated_spec.rb`
- `spec/services/engine/predicates/updates_drafted_spec.rb`
- `spec/services/engine/post_incident_replay_workflow_integration_spec.rb`
- `spec/system/post_incident_replay_cookbook_spec.rb`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/README.md`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/incident_reference.json`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/sentry_events.json`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/slack_thread.json`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/deploy_log.json`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/metrics.json`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/runbooks/ops-pipeline-latency.md`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/alerting/rules.yml`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/source/app/jobs/ops_pipeline_refresh_job.rb`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/source/app/services/ops_pipeline/query_runner.rb`
- `cookbooks/fixtures/incidents/ops_pipeline_p1/bin/replay-fixture-smoke`
- `docs/cookbooks/post-incident-replay.md`

Modify:

- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Do not modify unless a failing spec proves it is necessary:

- `db/seeds.rb`; it already resolves `file://` paths relative to `Rails.root`.
- Adapter classes; this cookbook is inline-Claude plus fake gate only.
- Shared `cookbooks/docker-compose.yml`; local fixture files and a smoke script are sufficient for deterministic tests.

---

## Queue YAML Target

Create `config/queues/post_incident_replay.yml` with this shape. Keep all paths repo-relative and omit `working_directory`.

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
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [artifacts_ingested]
    agent_prompt: file://cookbooks/prompts/post_incident_replay/ingest_artifacts.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: incident_artifacts
      fixture_incident: cookbooks/fixtures/incidents/ops_pipeline_p1
      read_only: true
  reconstruct_timeline:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [timeline_reconstructed]
    agent_prompt: file://cookbooks/prompts/post_incident_replay/reconstruct_timeline.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: incident_artifacts
      output_artifact_kind: incident_timeline
      fixture_incident: cookbooks/fixtures/incidents/ops_pipeline_p1
      read_only: true
  analyze_root_cause:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [root_cause_analyzed]
    agent_prompt: file://cookbooks/prompts/post_incident_replay/analyze_root_cause.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: incident_timeline
      secondary_input_artifact_kind: incident_artifacts
      output_artifact_kind: root_cause_analysis
      fixture_incident: cookbooks/fixtures/incidents/ops_pipeline_p1
      read_only: true
  evaluate_response:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [response_evaluated]
    agent_prompt: file://cookbooks/prompts/post_incident_replay/evaluate_response.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: root_cause_analysis
      secondary_input_artifact_kind: incident_timeline
      output_artifact_kind: response_evaluation
      fixture_incident: cookbooks/fixtures/incidents/ops_pipeline_p1
      read_only: true
  draft_updates:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [updates_drafted]
    agent_prompt: file://cookbooks/prompts/post_incident_replay/draft_updates.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: root_cause_analysis
      secondary_input_artifact_kind: response_evaluation
      tertiary_input_artifact_kind: incident_timeline
      output_artifact_kind: incident_updates
      fixture_incident: cookbooks/fixtures/incidents/ops_pipeline_p1
      read_only: true
      spawn_targets:
        code_fixes: development
        missing_monitoring: incident_readiness
        thin_alerts: operations
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: [deploy, mutate_database]
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review incident replay, root cause analysis, response scores, and proposed runbook/alerting/process updates for fairness and actionability.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

Notes:

- The source spec uses `file://prompts/...`; this plan intentionally uses `file://cookbooks/prompts/post_incident_replay/...` to match newer shared cookbook organization and avoid crowding root prompts.
- `query_sentry` and `query_slack` are allowed skill labels for live usage, but tests must rely only on fixture files.
- `read_only: true` is advisory metadata for agents/prompts; do not implement new enforcement unless a separate task asks for it.

---

## Prompt File Requirements

All prompt files must be concrete, non-blaming, and explicit about artifact JSON contracts.

### `cookbooks/prompts/post_incident_replay/ingest_artifacts.md`

Include:

- Header `# Post-Incident Replay: Ingest Artifacts`.
- Instructions to read `incident_reference.json`, `sentry_events.json`, `slack_thread.json`, `deploy_log.json`, and `metrics.json` from `adapter_config.fixture_incident` when present.
- Normalize timestamps to UTC ISO-8601 strings.
- Preserve source paths/IDs in fields where available.
- Output exactly one `incident_artifacts` artifact with `time_window`, `sentry_events`, `slack_messages`, `deploys`, and `metrics`.
- Do not call live Sentry/Slack APIs when fixture files are supplied.

### `cookbooks/prompts/post_incident_replay/reconstruct_timeline.md`

Include:

- Header `# Post-Incident Replay: Reconstruct Timeline`.
- Build detection, investigation, mitigation, resolution, and gap phases from artifact timestamps.
- Calculate `total_duration_minutes`, `detection_delay_minutes`, `time_to_mitigate_minutes`, and `time_to_resolve_minutes`.
- Mark dead ends and waiting periods as `type: "gap"` where supported by Slack/deploy evidence.
- Output exactly one `incident_timeline` artifact.

### `cookbooks/prompts/post_incident_replay/analyze_root_cause.md`

Include:

- Header `# Post-Incident Replay: Analyze Root Cause`.
- Distinguish trigger, root cause, symptoms, detection, and response.
- For the fixture, the intended root cause is the ops pipeline refresh job issuing unbounded read queries after a deploy, causing lock contention/latency; the plan should leave room for the agent to infer this from fixture files.
- Use repo-relative `code_path` values such as `source/app/jobs/ops_pipeline_refresh_job.rb`.
- Output exactly one `root_cause_analysis` artifact.

### `cookbooks/prompts/post_incident_replay/evaluate_response.md`

Include:

- Header `# Post-Incident Replay: Evaluate Response`.
- Grade detection, diagnosis, runbook coverage, communication, and resolution on a 0-5 scale.
- Avoid blame; focus on systems, runbooks, ownership, alerts, and access.
- Tie each improvement to timeline evidence.
- Output exactly one `response_evaluation` artifact.

### `cookbooks/prompts/post_incident_replay/draft_updates.md`

Include:

- Header `# Post-Incident Replay: Draft Updates`.
- Draft at least one runbook update or alert.
- Advisory cross-queue rules: code fixes include `spawn_to_queue: development`, missing monitoring includes rationale for `incident_readiness`, thin alerts include rationale for `operations`.
- Do not edit runbook files or alerting config directly; draft content only in the artifact.
- Output exactly one `incident_updates` artifact.

---

## Fixture Requirements

Create `cookbooks/fixtures/incidents/ops_pipeline_p1/` as a local replay of the TaskRail ops pipeline E2E incident.

Required fixture intent:

- The incident starts shortly after a deploy of an ops pipeline refresh change.
- Sentry events show repeated API timeouts/lock-wait errors with counts and affected users.
- Slack messages show detection, hypotheses, a dead-end metrics investigation, mitigation by pausing the refresh job, final fix by adding query limits/timeouts, and incident end.
- Deploy log shows the triggering deploy, mitigation deploy/rollback, and final fix deploy.
- Metrics show error-rate and latency spikes plus a lock-wait or DB saturation signal.
- Existing runbook is too generic and misses lock-wait diagnosis.
- Existing alerting catches high error rate late but not DB lock waits.
- Source files represent the problematic code path without needing a full Rails app.

Required files:

- `README.md`: describes the synthetic P1 and states that all paths are repo-relative and all data is fake.
- `incident_reference.json`: includes `incident_id`, `severity`, `time_window`, `sentry_issue_ids`, `slack_thread_url` as a fake URL, `deploy_log_range`, and source data filenames.
- `sentry_events.json`: array of at least two events; include `timestamp`, `issue_id`, `error`, `stack_trace`, `count`, `users_affected`, `first_seen`, and `last_seen`.
- `slack_thread.json`: array of at least six messages; include `timestamp`, `author`, `text`, and `is_decision`; at least one decision should pause a job.
- `deploy_log.json`: array of at least three deploy events; include triggering deploy, mitigation, and final fix.
- `metrics.json`: object or array with latency, error-rate, and DB-lock-wait samples.
- `runbooks/ops-pipeline-latency.md`: intentionally incomplete runbook.
- `alerting/rules.yml`: includes late high-error alert and missing lock-wait alert.
- `source/app/jobs/ops_pipeline_refresh_job.rb`: problematic unbounded job.
- `source/app/services/ops_pipeline/query_runner.rb`: query code path with missing timeout before final fix.
- `bin/replay-fixture-smoke`: executable Ruby or Bash script that reads all fixture files and prints deterministic JSON with counts; no network, Docker, or database.

Smoke script expected output shape:

```json
{
  "incident_id": "ops-pipeline-p1-2026-04-18",
  "sentry_events": 2,
  "slack_messages": 6,
  "deploys": 3,
  "metrics_series": 3,
  "has_runbook": true,
  "has_alerting_rules": true
}
```

---

### Task 1: Add RED specs for the `artifacts_ingested` predicate

**Objective:** Prove `artifacts_ingested` requires an `incident_artifacts` artifact with a time window and at least one populated evidence source.

**Files:**
- Create: `spec/services/engine/predicates/artifacts_ingested_spec.rb`
- Later create: `app/services/engine/predicates/artifacts_ingested.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/artifacts_ingested_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ArtifactsIngested do
  let(:queue) { WorkQueue.create!(name: "Post-Incident Replay", slug: "post-incident-replay", stages: %w[ingest]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Replay P1", spec_url: "fixture", stage_name: "ingest") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active) }

  it "passes with evidence when incident artifacts include a time window and source events" do
    artifact = claim.artifacts.create!(
      work_item: work_item,
      kind: "incident_artifacts",
      data: {
        "time_window" => { "start" => "2026-04-18T02:00:00Z", "end" => "2026-04-18T03:30:00Z" },
        "sentry_events" => [{ "timestamp" => "2026-04-18T02:14:00Z", "error" => "ActiveRecord::QueryCanceled", "count" => 47 }],
        "slack_messages" => [],
        "deploys" => [],
        "metrics" => []
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, source_count: 1)
  end

  it "fails when the artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing incident_artifacts artifact with time_window and at least one event source")
  end

  it "fails when all event sources are empty" do
    claim.artifacts.create!(
      work_item: work_item,
      kind: "incident_artifacts",
      data: {
        "time_window" => { "start" => "2026-04-18T02:00:00Z", "end" => "2026-04-18T03:30:00Z" },
        "sentry_events" => [],
        "slack_messages" => [],
        "deploys" => [],
        "metrics" => []
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing incident_artifacts artifact with time_window and at least one event source")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/artifacts_ingested_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::ArtifactsIngested`.

**Step 3: Write minimal implementation**

Create `app/services/engine/predicates/artifacts_ingested.rb`:

```ruby
module Engine
  module Predicates
    class ArtifactsIngested
      SOURCE_KEYS = %w[sentry_events slack_messages deploys metrics].freeze
      FAILURE = "missing incident_artifacts artifact with time_window and at least one event source".freeze

      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "incident_artifacts").order(created_at: :desc).first
        return PredicateResult.fail(reason: FAILURE) unless artifact
        return PredicateResult.fail(reason: FAILURE) unless artifact.data["time_window"].present?

        source_count = SOURCE_KEYS.count { |key| artifact.data[key].present? }
        return PredicateResult.fail(reason: FAILURE) if source_count.zero?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, source_count: source_count })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run the same RSpec command. Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/predicates/artifacts_ingested_spec.rb app/services/engine/predicates/artifacts_ingested.rb
git commit -m "feat: add incident artifacts predicate"
```

---

### Task 2: Add RED specs for timeline/root-cause/response/update predicates

**Objective:** Add focused artifact-contract specs for the remaining four predicates before implementing them.

**Files:**
- Create: `spec/services/engine/predicates/timeline_reconstructed_spec.rb`
- Create: `spec/services/engine/predicates/root_cause_analyzed_spec.rb`
- Create: `spec/services/engine/predicates/response_evaluated_spec.rb`
- Create: `spec/services/engine/predicates/updates_drafted_spec.rb`
- Later create matching implementation files under `app/services/engine/predicates/`

**Step 1: Write failing tests**

Follow the exact style from Task 1. Required pass/fail contracts:

- `TimelineReconstructed` looks for latest `incident_timeline`, requires non-empty `phases` and `total_duration_minutes.to_i > 0`, passes with `{ artifact_id:, phase_count: }`, fails with `"missing incident_timeline artifact with phases and duration"`.
- `RootCauseAnalyzed` looks for latest `root_cause_analysis`, requires `root_cause.description` and non-empty `causal_chain`, passes with `{ artifact_id:, causal_chain_count: }`, fails with `"missing root_cause_analysis artifact with root_cause and causal_chain"`.
- `ResponseEvaluated` looks for latest `response_evaluation`, requires non-empty `scores` and non-empty `improvements`, passes with `{ artifact_id:, improvement_count: }`, fails with `"missing response_evaluation artifact with scores and improvements"`.
- `UpdatesDrafted` looks for latest `incident_updates`, requires at least one item in `runbook_updates` or `new_alerts`, passes with `{ artifact_id:, runbook_update_count:, alert_count: }`, fails with `"missing incident_updates artifact with runbook updates or alerts"`.

Example positive artifact payloads:

```ruby
# incident_timeline
{
  "phases" => [{ "name" => "detection", "duration_minutes" => 12, "events" => [{ "type" => "detection" }] }],
  "total_duration_minutes" => 90
}

# root_cause_analysis
{
  "root_cause" => { "description" => "Unbounded refresh query held locks", "code_path" => "source/app/jobs/ops_pipeline_refresh_job.rb" },
  "causal_chain" => [{ "event" => "deploy", "type" => "trigger" }]
}

# response_evaluation
{
  "scores" => { "detection" => 2, "diagnosis" => 3, "runbook_coverage" => 1, "communication" => 4, "resolution" => 3 },
  "grade" => "C",
  "improvements" => [{ "dimension" => "detection", "recommended_change" => "Add lock wait alert" }]
}

# incident_updates
{
  "runbook_updates" => [{ "path" => "runbooks/ops-pipeline-latency.md", "content" => "Add lock wait diagnosis", "failure_mode" => "DB lock contention" }],
  "new_alerts" => []
}
```

**Step 2: Run tests to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/timeline_reconstructed_spec.rb \
  spec/services/engine/predicates/root_cause_analyzed_spec.rb \
  spec/services/engine/predicates/response_evaluated_spec.rb \
  spec/services/engine/predicates/updates_drafted_spec.rb
```

Expected: FAIL with uninitialized constants for the four predicate classes.

**Step 3: Write minimal implementations**

Create each predicate with the same shape as Task 1:

- `app/services/engine/predicates/timeline_reconstructed.rb`
- `app/services/engine/predicates/root_cause_analyzed.rb`
- `app/services/engine/predicates/response_evaluated.rb`
- `app/services/engine/predicates/updates_drafted.rb`

Implementation details:

- Use `@claim.artifacts.where(kind: KIND).order(created_at: :desc).first`, not unordered `.last`.
- Use `PredicateResult.pass(evidence: ...)` and `PredicateResult.fail(reason: ...)`.
- Keep validation shallow and artifact-contract oriented; do not implement full schema validation.
- Treat missing arrays, empty arrays, and empty hashes as failures with the exact reasons above.

**Step 4: Run tests to verify GREEN**

Run the same multi-file RSpec command. Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/predicates/timeline_reconstructed_spec.rb \
  spec/services/engine/predicates/root_cause_analyzed_spec.rb \
  spec/services/engine/predicates/response_evaluated_spec.rb \
  spec/services/engine/predicates/updates_drafted_spec.rb \
  app/services/engine/predicates/timeline_reconstructed.rb \
  app/services/engine/predicates/root_cause_analyzed.rb \
  app/services/engine/predicates/response_evaluated.rb \
  app/services/engine/predicates/updates_drafted.rb
git commit -m "feat: add post incident replay predicates"
```

---

### Task 3: Register post-incident replay predicates

**Objective:** Make the new completion criteria resolvable by the engine.

**Files:**
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing test**

Append expectations to `spec/services/engine/predicate_registry_spec.rb` inside `it "resolves known predicate names"`:

```ruby
expect(described_class.resolve("artifacts_ingested")).to eq(Engine::Predicates::ArtifactsIngested)
expect(described_class.resolve("timeline_reconstructed")).to eq(Engine::Predicates::TimelineReconstructed)
expect(described_class.resolve("root_cause_analyzed")).to eq(Engine::Predicates::RootCauseAnalyzed)
expect(described_class.resolve("response_evaluated")).to eq(Engine::Predicates::ResponseEvaluated)
expect(described_class.resolve("updates_drafted")).to eq(Engine::Predicates::UpdatesDrafted)
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `Engine::PredicateRegistry::UnknownPredicate` for `artifacts_ingested` or equivalent first missing mapping.

**Step 3: Implement registry mappings**

Add to `PREDICATES` in `app/services/engine/predicate_registry.rb`:

```ruby
"artifacts_ingested" => Predicates::ArtifactsIngested,
"timeline_reconstructed" => Predicates::TimelineReconstructed,
"root_cause_analyzed" => Predicates::RootCauseAnalyzed,
"response_evaluated" => Predicates::ResponseEvaluated,
"updates_drafted" => Predicates::UpdatesDrafted
```

Keep ordering near the incident readiness / response predicates if possible.

**Step 4: Run test to verify GREEN**

Run the same RSpec command. Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/predicate_registry_spec.rb app/services/engine/predicate_registry.rb
git commit -m "feat: register post incident replay predicates"
```

---

### Task 4: Add RED seed spec for the queue YAML and prompts

**Objective:** Prove the `post_incident_replay` queue seeds with the right stages, resolved prompts, portable config, review gate, and artifact kinds.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/post_incident_replay.yml`
- Later create: prompt files under `cookbooks/prompts/post_incident_replay/`

**Step 1: Write failing test**

Add an example to `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the post incident replay cookbook queue with resolved portable prompts" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "post_incident_replay")
  expect(queue.name).to eq("Post-Incident Replay")
  expect(queue.stages).to eq(%w[
    ingest_artifacts
    reconstruct_timeline
    analyze_root_cause
    evaluate_response
    draft_updates
    human_review
    done
  ])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 0
  )

  ingest = queue.stage_configs.find_by!(stage_name: "ingest_artifacts")
  expect(ingest.adapter_type).to eq("inline_claude")
  expect(ingest.model_override).to eq("claude-haiku-4-5-20251001")
  expect(ingest.allowed_skills).to include("read_repo", "query_sentry", "query_slack")
  expect(ingest.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
  expect(ingest.completion_criteria).to eq(["artifacts_ingested"])
  expect(ingest.agent_prompt).to include("# Post-Incident Replay: Ingest Artifacts")
  expect(ingest.agent_prompt).not_to start_with("file://")
  expect(ingest.agent_prompt).not_to include(Rails.root.to_s)
  expect(ingest.adapter_config).to include(
    "output_artifact_kind" => "incident_artifacts",
    "fixture_incident" => "cookbooks/fixtures/incidents/ops_pipeline_p1",
    "read_only" => true
  )

  timeline = queue.stage_configs.find_by!(stage_name: "reconstruct_timeline")
  expect(timeline.completion_criteria).to eq(["timeline_reconstructed"])
  expect(timeline.agent_prompt).to include("# Post-Incident Replay: Reconstruct Timeline")
  expect(timeline.adapter_config).to include(
    "input_artifact_kind" => "incident_artifacts",
    "output_artifact_kind" => "incident_timeline"
  )

  root_cause = queue.stage_configs.find_by!(stage_name: "analyze_root_cause")
  expect(root_cause.completion_criteria).to eq(["root_cause_analyzed"])
  expect(root_cause.agent_prompt).to include("# Post-Incident Replay: Analyze Root Cause")
  expect(root_cause.adapter_config).to include("output_artifact_kind" => "root_cause_analysis")

  evaluation = queue.stage_configs.find_by!(stage_name: "evaluate_response")
  expect(evaluation.completion_criteria).to eq(["response_evaluated"])
  expect(evaluation.agent_prompt).to include("# Post-Incident Replay: Evaluate Response")
  expect(evaluation.adapter_config).to include("output_artifact_kind" => "response_evaluation")

  draft = queue.stage_configs.find_by!(stage_name: "draft_updates")
  expect(draft.completion_criteria).to eq(["updates_drafted"])
  expect(draft.agent_prompt).to include("# Post-Incident Replay: Draft Updates")
  expect(draft.forbidden_skills).to include("deploy")
  expect(draft.adapter_config).to include("output_artifact_kind" => "incident_updates")
  expect(draft.adapter_config["spawn_targets"]).to include(
    "code_fixes" => "development",
    "missing_monitoring" => "incident_readiness",
    "thin_alerts" => "operations"
  )

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.timeout_seconds).to eq(86_400)
  expect(human_review.agent_prompt).to include("fairness and actionability")

  serialized_queue = Rails.root.join("config/queues/post_incident_replay.yml").read
  expect(serialized_queue).not_to include(Rails.root.to_s)
  expect(serialized_queue).not_to include("/Users/")
  expect(serialized_queue).not_to include("working_directory:")
  expect(serialized_queue).to include("file://cookbooks/prompts/post_incident_replay/ingest_artifacts.md")
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL with `Couldn't find WorkQueue` for slug `post_incident_replay`.

**Step 3: Implement YAML and prompt files**

Create `config/queues/post_incident_replay.yml` using the Queue YAML Target above.

Create the five prompt files from Prompt File Requirements. Keep prompts concise but explicit enough that seed specs can assert headers and key contract strings.

**Step 4: Run test to verify GREEN**

Run the same RSpec command. Expected: PASS.

**Step 5: Commit**

```bash
git add spec/models/work_queue_seed_spec.rb config/queues/post_incident_replay.yml cookbooks/prompts/post_incident_replay
git commit -m "feat: seed post incident replay queue"
```

---

### Task 5: Add the Docker-friendly incident fixture and smoke spec

**Objective:** Provide deterministic local incident data that the cookbook can replay without network credentials.

**Files:**
- Create fixture files listed in Fixture Requirements
- Create: `spec/system/post_incident_replay_cookbook_spec.rb`

**Step 1: Write failing fixture spec**

Create `spec/system/post_incident_replay_cookbook_spec.rb`:

```ruby
require "rails_helper"
require "json"

RSpec.describe "post incident replay cookbook fixture" do
  let(:fixture_root) { Rails.root.join("cookbooks/fixtures/incidents/ops_pipeline_p1") }

  it "contains local incident artifacts and no absolute checkout paths" do
    expect(fixture_root.join("incident_reference.json")).to exist
    expect(fixture_root.join("sentry_events.json")).to exist
    expect(fixture_root.join("slack_thread.json")).to exist
    expect(fixture_root.join("deploy_log.json")).to exist
    expect(fixture_root.join("metrics.json")).to exist
    expect(fixture_root.join("runbooks/ops-pipeline-latency.md")).to exist
    expect(fixture_root.join("alerting/rules.yml")).to exist
    expect(fixture_root.join("source/app/jobs/ops_pipeline_refresh_job.rb")).to exist
    expect(fixture_root.join("source/app/services/ops_pipeline/query_runner.rb")).to exist

    contents = fixture_root.glob("**/*").select(&:file?).map(&:read).join("\n")
    expect(contents).not_to include(Rails.root.to_s)
    expect(contents).not_to include("/Users/")
  end

  it "smoke-checks fixture counts without network services" do
    output = `#{fixture_root.join("bin/replay-fixture-smoke")}`
    expect($CHILD_STATUS).to be_success

    summary = JSON.parse(output)
    expect(summary).to include(
      "incident_id" => "ops-pipeline-p1-2026-04-18",
      "has_runbook" => true,
      "has_alerting_rules" => true
    )
    expect(summary["sentry_events"]).to be >= 2
    expect(summary["slack_messages"]).to be >= 6
    expect(summary["deploys"]).to be >= 3
  end

  it "defines the artifact contract for replay predicates" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "post_incident_replay")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Replay ops pipeline P1",
      spec_url: "cookbooks/fixtures/incidents/ops_pipeline_p1/incident_reference.json",
      stage_name: "ingest_artifacts"
    )

    ingest_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: ingest_claim,
      work_item: work_item,
      kind: "incident_artifacts",
      data: {
        "time_window" => { "start" => "2026-04-18T02:00:00Z", "end" => "2026-04-18T03:30:00Z" },
        "sentry_events" => [{ "timestamp" => "2026-04-18T02:14:00Z", "error" => "ActiveRecord::QueryCanceled", "count" => 47 }],
        "slack_messages" => [{ "timestamp" => "2026-04-18T02:18:00Z", "author" => "oncall", "text" => "Seeing API timeouts", "is_decision" => false }],
        "deploys" => [{ "timestamp" => "2026-04-18T02:02:00Z", "commit" => "abc123", "action" => "deploy" }],
        "metrics" => [{ "timestamp" => "2026-04-18T02:15:00Z", "metric" => "db.lock_wait_ms", "value" => 12000 }]
      }
    )
    expect(Engine::PredicateRegistry.resolve("artifacts_ingested").new(claim: ingest_claim).call).to be_passed

    timeline_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: timeline_claim,
      work_item: work_item,
      kind: "incident_timeline",
      data: {
        "phases" => [{ "name" => "detection", "start" => "2026-04-18T02:14:00Z", "end" => "2026-04-18T02:26:00Z", "duration_minutes" => 12, "events" => [{ "type" => "detection", "description" => "Alert fired late" }] }],
        "total_duration_minutes" => 90,
        "impact" => { "users_affected" => 128, "error_count" => 47 }
      }
    )
    expect(Engine::PredicateRegistry.resolve("timeline_reconstructed").new(claim: timeline_claim).call).to be_passed
  end
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/post_incident_replay_cookbook_spec.rb
```

Expected: FAIL because fixture files and smoke script do not exist.

**Step 3: Create fixture files**

Implement all files listed in Fixture Requirements. Keep JSON valid and small. Make `bin/replay-fixture-smoke` executable with `chmod +x`.

Suggested smoke implementation shape:

```ruby
#!/usr/bin/env ruby
require "json"
require "pathname"
root = Pathname.new(__dir__).parent
reference = JSON.parse(root.join("incident_reference.json").read)
summary = {
  incident_id: reference.fetch("incident_id"),
  sentry_events: JSON.parse(root.join("sentry_events.json").read).length,
  slack_messages: JSON.parse(root.join("slack_thread.json").read).length,
  deploys: JSON.parse(root.join("deploy_log.json").read).length,
  metrics_series: JSON.parse(root.join("metrics.json").read).fetch("series").length,
  has_runbook: root.join("runbooks/ops-pipeline-latency.md").file?,
  has_alerting_rules: root.join("alerting/rules.yml").file?
}
puts JSON.generate(summary)
```

**Step 4: Run test to verify GREEN**

Run the same spec. Expected: PASS.

**Step 5: Commit**

```bash
git add spec/system/post_incident_replay_cookbook_spec.rb cookbooks/fixtures/incidents/ops_pipeline_p1
git commit -m "test: add post incident replay fixture"
```

---

### Task 6: Add workflow integration spec for all replay artifacts

**Objective:** Prove the queue's artifact-backed predicates form a coherent replay workflow through `draft_updates`.

**Files:**
- Create: `spec/services/engine/post_incident_replay_workflow_integration_spec.rb`

**Step 1: Write failing integration spec**

Create `spec/services/engine/post_incident_replay_workflow_integration_spec.rb` that mirrors `spec/services/engine/dead_code_removal_workflow_integration_spec.rb` and creates:

1. Queue from seeds.
2. Work item at `ingest_artifacts`.
3. Claim/artifact for `incident_artifacts`, assert `ArtifactsIngested` passes and `source_count` is at least 3.
4. Claim/artifact for `incident_timeline`, assert `TimelineReconstructed` passes and `phase_count` is at least 4.
5. Claim/artifact for `root_cause_analysis`, assert `RootCauseAnalyzed` passes and `causal_chain_count` is at least 4.
6. Claim/artifact for `response_evaluation`, assert `ResponseEvaluated` passes and `improvement_count` is at least 2.
7. Claim/artifact for `incident_updates`, assert `UpdatesDrafted` passes and evidence reports at least one runbook update or alert.

Use this payload shape for final updates:

```ruby
{
  "runbook_updates" => [
    {
      "path" => "runbooks/ops-pipeline-latency.md",
      "content" => "Add lock-wait diagnosis and pause refresh job mitigation.",
      "failure_mode" => "DB lock contention from ops pipeline refresh",
      "references_phase" => "investigation"
    }
  ],
  "new_alerts" => [
    {
      "metric" => "db.lock_wait_ms",
      "threshold" => "> 5000 for 5 minutes",
      "rationale" => "Would have detected contention before customer-visible timeouts.",
      "would_have_detected_at" => "2026-04-18T02:08:00Z"
    }
  ],
  "code_fixes" => [{ "file" => "source/app/jobs/ops_pipeline_refresh_job.rb", "description" => "Add query timeout and batch limit", "spawn_to_queue" => "development" }],
  "process_changes" => [{ "change" => "Ensure ops pipeline owner is paged for DB lock alerts", "rationale" => "Reduced waiting for ownership" }]
}
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/post_incident_replay_workflow_integration_spec.rb
```

Expected: Initially FAIL if any predicate, registry mapping, or seed fixture contract is incomplete.

**Step 3: Fix only proven gaps**

Likely fixes should be confined to predicate evidence counts, registry mappings, seed YAML, or the spec payload. Do not add new transition-engine behavior.

**Step 4: Run test to verify GREEN**

Run the same spec. Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/post_incident_replay_workflow_integration_spec.rb
git commit -m "test: cover post incident replay workflow artifacts"
```

---

### Task 7: Add cookbook documentation

**Objective:** Document how to use the cookbook and what artifacts/human review mean.

**Files:**
- Create: `docs/cookbooks/post-incident-replay.md`

**Step 1: Write documentation**

Create `docs/cookbooks/post-incident-replay.md` with:

- Title `# Post-Incident Replay`.
- Use case summary.
- Queue slug and stages.
- Fixture incident path.
- Artifact outputs and predicates.
- Safety note: analysis is non-blaming and requires human review before publication.
- Cross-queue follow-up note for `development`, `incident_readiness`, and `operations`.
- Example work item spec URL: `cookbooks/fixtures/incidents/ops_pipeline_p1/incident_reference.json`.

**Step 2: Verify docs are portable**

Run:

```bash
ruby -e 'abort "absolute path found" if File.read("docs/cookbooks/post-incident-replay.md").include?(Dir.pwd) || File.read("docs/cookbooks/post-incident-replay.md").include?("/Users/")'
```

Expected: exits 0.

**Step 3: Commit**

```bash
git add docs/cookbooks/post-incident-replay.md
git commit -m "docs: add post incident replay cookbook"
```

---

### Task 8: Run focused and broader verification

**Objective:** Verify the complete cookbook slice without relying on live external systems.

**Files:**
- No intended file changes.

**Step 1: Run predicate specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/artifacts_ingested_spec.rb \
  spec/services/engine/predicates/timeline_reconstructed_spec.rb \
  spec/services/engine/predicates/root_cause_analyzed_spec.rb \
  spec/services/engine/predicates/response_evaluated_spec.rb \
  spec/services/engine/predicates/updates_drafted_spec.rb \
  spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 2: Run seed and workflow specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/system/post_incident_replay_cookbook_spec.rb \
  spec/services/engine/post_incident_replay_workflow_integration_spec.rb
```

Expected: PASS.

**Step 3: Run nearby cookbook regression specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/system/job_observability_cookbook_spec.rb \
  spec/fixtures/incident_readiness_fixture_spec.rb \
  spec/services/engine/dead_code_removal_workflow_integration_spec.rb
```

Expected: PASS.

**Step 4: Check portability**

```bash
ruby -e 'paths = Dir["config/queues/post_incident_replay.yml", "cookbooks/prompts/post_incident_replay/**/*.md", "cookbooks/fixtures/incidents/ops_pipeline_p1/**/*", "docs/cookbooks/post-incident-replay.md"].select { |p| File.file?(p) }; bad = paths.select { |p| File.read(p).include?(Dir.pwd) || File.read(p).include?("/Users/") }; abort("absolute paths: #{bad.join(", ")}") unless bad.empty?'
```

Expected: exits 0.

**Step 5: Run final status check**

```bash
git status --short
```

Expected: only intended files are modified/untracked before the final commit; do not stage unrelated existing workspace files.

**Step 6: Commit if verification produced final changes**

If Task 8 required fixes, commit them:

```bash
git add [only files touched for cookbook 19]
git commit -m "test: verify post incident replay cookbook"
```

If no changes were made, do not create an empty commit.

---

## Final Acceptance Criteria

The implementation is complete when:

- `config/queues/post_incident_replay.yml` seeds a `post_incident_replay` queue with the exact seven stages.
- All five prompt files resolve through `db/seeds.rb` and persisted `StageConfig#agent_prompt` values do not start with `file://`.
- Queue YAML, prompts, fixtures, docs, and tests contain no hardcoded absolute checkout paths and no `/Users/` paths.
- Five artifact-backed predicates exist, are registered, and use latest-artifact ordering with actionable evidence.
- `spec/models/work_queue_seed_spec.rb` covers stage order, adapter config, resolved prompts, human review, spawn target metadata, and portability.
- `spec/system/post_incident_replay_cookbook_spec.rb` proves local fixture availability and smoke script behavior.
- `spec/services/engine/post_incident_replay_workflow_integration_spec.rb` proves artifact contracts from ingestion through update drafting.
- Documentation exists at `docs/cookbooks/post-incident-replay.md`.
- All focused verification commands in Task 8 pass.
- The implementation commits only cookbook-19 files and leaves unrelated workspace files unstaged.

## Suggested Implementation Commit Sequence

1. `feat: add incident artifacts predicate`
2. `feat: add post incident replay predicates`
3. `feat: register post incident replay predicates`
4. `feat: seed post incident replay queue`
5. `test: add post incident replay fixture`
6. `test: cover post incident replay workflow artifacts`
7. `docs: add post incident replay cookbook`
8. Optional if fixes were needed: `test: verify post incident replay cookbook`

If a Kanban implementation card requires one final commit, squash these into:

`feat: add post incident replay cookbook`

## Handoff Notes for Implementers

- Do not contact real Sentry, Slack, deploy, or metrics services during tests.
- Do not implement automatic cross-queue spawning unless a separate spec and card request it; this plan only records intended spawn targets in artifact/config metadata.
- Keep the analysis language fair and system-focused. Avoid prompts that assign personal blame.
- Use `order(created_at: :desc).first` for latest artifacts because IDs may be UUIDs and unordered `.last` is unsafe.
- Use `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...` for all Rails/RSpec commands on Greg's Mac.
