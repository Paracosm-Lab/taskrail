# Chaos Monkey / Chaos Response Cookbook Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Implement the cookbook described in `docs/specs/cookbook-09-chaos-monkey.md`: two blind queues where a chaos queue safely creates staging disruptions and a response queue diagnoses and recovers from alerts without seeing the disruption plan.

**Architecture:** Add two portable queue seed YAML files, prompt files, artifact predicates, and minimal fake Docker-friendly staging fixtures. The chaos queue spawns/links a response work item after disruption execution, waits while the response queue works, then reads only the response outcome artifact to evaluate recovery. The response queue is intentionally blind to `disruption_plan` and must diagnose from alerts/runbooks only.

**Tech Stack:** Rails, ActiveRecord, RSpec, seeded `config/queues/*.yml`, `inline_claude`, `shell_script`, `docker_compose`, `fake` adapters, `Engine::Predicates`, Docker Compose fixture files.

**Source spec:** `docs/specs/cookbook-09-chaos-monkey.md`

---

## Implementation Notes and Constraints

- Use strict TDD for every production behavior change: write a failing spec, run it and confirm the expected failure, implement minimal code, run the focused spec, then run the relevant broader spec set.
- All commands below assume Greg's Mac/Rails setup and must be run from the repository root:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Queue YAML must remain portable. Do not add `working_directory: /Users/gregmushen/...` or any other absolute checkout path. The existing adapters default to `Rails.root.to_s`; use relative `compose_file` values and relative `file://prompts/...` prompts.
- Keep infrastructure fake/docker-friendly and cookbook-local. Do not duplicate shared cookbook infrastructure; depend on the shared cookbook infrastructure plan for common Sentry fake API, shared app service, common Postgres, and base Docker Compose conventions.
- The response queue must not have direct access to the chaos queue's `disruption_plan`. Preserve `forbidden_skills: [deploy, mutate_database, execute_staging, read_disruption_plan]` for `chaos_response.diagnose_failure`.
- `impact_observed` should pass when the artifact exists even when `alerts_fired` is zero, because missing alerts are a valid monitoring-gap finding.
- `runbook_selected` should pass when the artifact exists even when `selected_runbook` is null, because no matching runbook is a valid finding.

---

## Files to Create or Modify

### Queue YAML

- Create: `config/queues/chaos_monkey.yml`
- Create: `config/queues/chaos_response.yml`

### Prompt files

- Create: `prompts/chaos_plan_disruption.md`
- Create: `prompts/chaos_execute_disruption.md`
- Create: `prompts/chaos_monitor_impact.md`
- Create: `prompts/chaos_evaluate_recovery.md`
- Create: `prompts/chaos_score_report.md`
- Create: `prompts/response_detect_alerts.md`
- Create: `prompts/response_diagnose.md`
- Create: `prompts/response_select_runbook.md`
- Create: `prompts/response_execute_runbook.md`
- Create: `prompts/response_verify_recovery.md`
- Create: `prompts/response_report_outcome.md`

### Predicates

- Modify: `app/services/engine/predicate_registry.rb`
- Create: `app/services/engine/predicates/disruption_planned.rb`
- Create: `app/services/engine/predicates/disruption_executed.rb`
- Create: `app/services/engine/predicates/impact_observed.rb`
- Create: `app/services/engine/predicates/recovery_evaluated.rb`
- Create: `app/services/engine/predicates/alerts_detected.rb`
- Create: `app/services/engine/predicates/diagnosis_produced.rb`
- Create: `app/services/engine/predicates/runbook_selected.rb`
- Create: `app/services/engine/predicates/runbook_executed.rb`
- Create: `app/services/engine/predicates/recovery_verified.rb`

### Specs

- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Create: `spec/services/engine/predicates/chaos_cookbook_predicates_spec.rb`
- Create: `spec/db/seeds/chaos_cookbook_queues_spec.rb`
- Create: `spec/services/engine/chaos_cross_queue_wait_spec.rb` if current waiting semantics do not fully cover chaos parent/response child behavior.

### Fixture app and fake infrastructure

- Create: `spec/fixtures/chaos_staging/docker-compose.staging.yml`
- Create: `spec/fixtures/chaos_staging/api/Dockerfile`
- Create: `spec/fixtures/chaos_staging/api/config.ru`
- Create: `spec/fixtures/chaos_staging/api/Gemfile`
- Create: `spec/fixtures/chaos_staging/scripts/execute_safe_disruption.sh`
- Create: `spec/fixtures/chaos_staging/scripts/monitor_fake_sentry.sh`
- Create: `spec/fixtures/chaos_staging/scripts/detect_fake_alerts.sh`
- Create: `spec/fixtures/chaos_staging/scripts/verify_fake_recovery.sh`
- Create: `docs/runbooks/chaos/postgres-unavailable.md`
- Create: `docs/cookbooks/09-chaos-monkey.md`

---

## Artifact Predicate Contract

Use one small predicate class per criterion. Each class should query artifacts on the current claim first, with a fallback to the work item if that matches existing adapter persistence behavior in the repository.

Recommended helper shape inside each predicate class:

```ruby
def artifact(kind)
  @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
    @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
end
```

Use `Engine::PredicateResult.pass(evidence: { artifact_id: artifact.id })` for successes and actionable failure reasons for failures.

Predicate requirements:

- `disruption_planned`: artifact kind `disruption_plan`, data has nonblank `scenario` and `reversal_steps` array/string.
- `disruption_executed`: artifact kind `disruption_record`, data has nonempty `commands_run`.
- `impact_observed`: artifact kind `impact_report` exists. Do not require `alerts_fired > 0`.
- `recovery_evaluated`: artifact kind `recovery_evaluation`, data has `scores`.
- `alerts_detected`: artifact kind `detected_alerts`, data has nonempty `events`.
- `diagnosis_produced`: artifact kind `diagnosis`, data has nonblank `root_cause_hypothesis`.
- `runbook_selected`: artifact kind `runbook_selection` exists. `selected_runbook: nil` is valid.
- `runbook_executed`: artifact kind `runbook_execution`, data has `steps_executed` array.
- `recovery_verified`: artifact kind `recovery_verification`, data has `service_healthy: true`.

---

## Task 1: Add RED specs for chaos artifact predicates

**Objective:** Specify all nine new predicate behaviors before adding predicate implementation.

**Files:**
- Create: `spec/services/engine/predicates/chaos_cookbook_predicates_spec.rb`
- Test references: existing predicate specs under `spec/services/engine/`

**Step 1: Write failing specs**

Create `spec/services/engine/predicates/chaos_cookbook_predicates_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Chaos cookbook predicates" do
  let(:queue) { WorkQueue.create!(name: "Chaos", slug: "chaos-predicate-#{SecureRandom.hex(4)}", stages: ["stage", "done"]) }
  let(:work_item) { WorkItem.create!(title: "Chaos exercise", spec_url: "inline", work_queue: queue, stage_name: "stage") }
  let(:claim) { Claim.create!(work_item: work_item, agent_type: "fake", status: "completed", started_at: Time.current) }

  def create_artifact(kind, data)
    Artifact.create!(work_item: work_item, claim: claim, kind: kind, data: data)
  end

  it "passes disruption_planned when scenario and reversal_steps are present" do
    create_artifact("disruption_plan", {
      "scenario" => "stop postgres in staging",
      "reversal_steps" => ["docker compose start postgres"]
    })

    result = Engine::Predicates::DisruptionPlanned.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to include(:artifact_id)
  end

  it "fails disruption_planned without reversal steps" do
    create_artifact("disruption_plan", { "scenario" => "stop postgres in staging" })

    result = Engine::Predicates::DisruptionPlanned.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("disruption_plan missing scenario or reversal_steps")
  end

  it "passes disruption_executed when commands_run is nonempty" do
    create_artifact("disruption_record", { "commands_run" => ["docker compose stop postgres"] })

    result = Engine::Predicates::DisruptionExecuted.new(claim: claim).call

    expect(result).to be_passed
  end

  it "passes impact_observed when an impact_report exists even with zero alerts" do
    create_artifact("impact_report", { "alerts_fired" => 0, "services_affected" => [] })

    result = Engine::Predicates::ImpactObserved.new(claim: claim).call

    expect(result).to be_passed
  end

  it "passes recovery_evaluated when scores are present" do
    create_artifact("recovery_evaluation", { "scores" => { "detection" => 4 } })

    result = Engine::Predicates::RecoveryEvaluated.new(claim: claim).call

    expect(result).to be_passed
  end

  it "passes alerts_detected when events are nonempty" do
    create_artifact("detected_alerts", { "events" => [{ "id" => "evt-1" }] })

    result = Engine::Predicates::AlertsDetected.new(claim: claim).call

    expect(result).to be_passed
  end

  it "fails alerts_detected when no events are present" do
    create_artifact("detected_alerts", { "events" => [] })

    result = Engine::Predicates::AlertsDetected.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("detected_alerts missing events")
  end

  it "passes diagnosis_produced when root_cause_hypothesis is present" do
    create_artifact("diagnosis", { "root_cause_hypothesis" => "postgres unavailable" })

    result = Engine::Predicates::DiagnosisProduced.new(claim: claim).call

    expect(result).to be_passed
  end

  it "passes runbook_selected when artifact exists even with null selection" do
    create_artifact("runbook_selection", { "selected_runbook" => nil, "gaps" => ["no matching runbook"] })

    result = Engine::Predicates::RunbookSelected.new(claim: claim).call

    expect(result).to be_passed
  end

  it "passes runbook_executed when steps_executed is present" do
    create_artifact("runbook_execution", { "steps_executed" => [], "overall_success" => false })

    result = Engine::Predicates::RunbookExecuted.new(claim: claim).call

    expect(result).to be_passed
  end

  it "passes recovery_verified only when service_healthy is true" do
    create_artifact("recovery_verification", { "service_healthy" => true, "verification_checks" => [] })

    result = Engine::Predicates::RecoveryVerified.new(claim: claim).call

    expect(result).to be_passed
  end

  it "fails recovery_verified when service_healthy is false" do
    create_artifact("recovery_verification", { "service_healthy" => false, "verification_checks" => [] })

    result = Engine::Predicates::RecoveryVerified.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("recovery_verification service_healthy is not true")
  end
end
```

**Step 2: Run RED verification**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/chaos_cookbook_predicates_spec.rb -v
```

Expected: FAIL with missing constants such as `Engine::Predicates::DisruptionPlanned`.

**Step 3: Commit?**

Do not commit yet; this is the RED half of the predicate task.

---

## Task 2: Implement chaos artifact predicates and registry entries

**Objective:** Add minimal predicate classes and register them.

**Files:**
- Create: all predicate files listed in the predicate section above
- Modify: `app/services/engine/predicate_registry.rb`
- Modify: `spec/services/engine/predicate_registry_spec.rb`

**Step 1: Implement `DisruptionPlanned`**

Create `app/services/engine/predicates/disruption_planned.rb`:

```ruby
module Engine
  module Predicates
    class DisruptionPlanned
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = latest_artifact("disruption_plan")
        data = artifact&.data || {}

        if artifact && data["scenario"].present? && data["reversal_steps"].present?
          return PredicateResult.pass(evidence: { artifact_id: artifact.id })
        end

        PredicateResult.fail(reason: "disruption_plan missing scenario or reversal_steps")
      end

      private

      def latest_artifact(kind)
        @claim.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first ||
          @claim.work_item.artifacts.where(kind: kind).order(created_at: :desc, id: :desc).first
      end
    end
  end
end
```

**Step 2: Implement the remaining predicates**

Use the same class pattern, changing the validation logic:

```ruby
# app/services/engine/predicates/disruption_executed.rb
# pass if latest_artifact("disruption_record") data["commands_run"].present?
# failure reason: "disruption_record missing commands_run"

# app/services/engine/predicates/impact_observed.rb
# pass if latest_artifact("impact_report") exists
# failure reason: "missing impact_report artifact"

# app/services/engine/predicates/recovery_evaluated.rb
# pass if latest_artifact("recovery_evaluation") data["scores"].present?
# failure reason: "recovery_evaluation missing scores"

# app/services/engine/predicates/alerts_detected.rb
# pass if latest_artifact("detected_alerts") data["events"].present?
# failure reason: "detected_alerts missing events"

# app/services/engine/predicates/diagnosis_produced.rb
# pass if latest_artifact("diagnosis") data["root_cause_hypothesis"].present?
# failure reason: "diagnosis missing root_cause_hypothesis"

# app/services/engine/predicates/runbook_selected.rb
# pass if latest_artifact("runbook_selection") exists
# failure reason: "missing runbook_selection artifact"

# app/services/engine/predicates/runbook_executed.rb
# pass if latest_artifact("runbook_execution") data.key?("steps_executed")
# failure reason: "runbook_execution missing steps_executed"

# app/services/engine/predicates/recovery_verified.rb
# pass if latest_artifact("recovery_verification") data["service_healthy"] == true
# failure reason: "recovery_verification service_healthy is not true"
```

YAGNI note: It is OK to duplicate the small `latest_artifact` helper in each predicate for now, matching existing predicate style. Extract a shared base only after duplication becomes painful.

**Step 3: Register the predicates**

Modify `app/services/engine/predicate_registry.rb`:

```ruby
PREDICATES = {
  "report_present" => Predicates::ReportPresent,
  "branch_created" => Predicates::BranchCreated,
  "tests_passed" => Predicates::TestsPassed,
  "lint_clean" => Predicates::LintClean,
  "coverage_not_decreased" => Predicates::CoverageNotDecreased,
  "review_verdict" => Predicates::ReviewVerdict,
  "clusters_created" => Predicates::ClustersCreated,
  "assessment_complete" => Predicates::AssessmentComplete,
  "runbook_mapped" => Predicates::RunbookMapped,
  "runbook_drafted" => Predicates::RunbookDrafted,
  "validation_passed" => Predicates::ValidationPassed,
  "disruption_planned" => Predicates::DisruptionPlanned,
  "disruption_executed" => Predicates::DisruptionExecuted,
  "impact_observed" => Predicates::ImpactObserved,
  "recovery_evaluated" => Predicates::RecoveryEvaluated,
  "alerts_detected" => Predicates::AlertsDetected,
  "diagnosis_produced" => Predicates::DiagnosisProduced,
  "runbook_selected" => Predicates::RunbookSelected,
  "runbook_executed" => Predicates::RunbookExecuted,
  "recovery_verified" => Predicates::RecoveryVerified
}.freeze
```

**Step 4: Add registry spec expectations**

Modify `spec/services/engine/predicate_registry_spec.rb` inside `resolves known predicate names`:

```ruby
expect(described_class.resolve("disruption_planned")).to eq(Engine::Predicates::DisruptionPlanned)
expect(described_class.resolve("disruption_executed")).to eq(Engine::Predicates::DisruptionExecuted)
expect(described_class.resolve("impact_observed")).to eq(Engine::Predicates::ImpactObserved)
expect(described_class.resolve("recovery_evaluated")).to eq(Engine::Predicates::RecoveryEvaluated)
expect(described_class.resolve("alerts_detected")).to eq(Engine::Predicates::AlertsDetected)
expect(described_class.resolve("diagnosis_produced")).to eq(Engine::Predicates::DiagnosisProduced)
expect(described_class.resolve("runbook_selected")).to eq(Engine::Predicates::RunbookSelected)
expect(described_class.resolve("runbook_executed")).to eq(Engine::Predicates::RunbookExecuted)
expect(described_class.resolve("recovery_verified")).to eq(Engine::Predicates::RecoveryVerified)
```

**Step 5: Run GREEN verification**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/chaos_cookbook_predicates_spec.rb spec/services/engine/predicate_registry_spec.rb -v
```

Expected: PASS.

**Step 6: Commit**

```bash
git add app/services/engine/predicate_registry.rb app/services/engine/predicates/disruption_planned.rb app/services/engine/predicates/disruption_executed.rb app/services/engine/predicates/impact_observed.rb app/services/engine/predicates/recovery_evaluated.rb app/services/engine/predicates/alerts_detected.rb app/services/engine/predicates/diagnosis_produced.rb app/services/engine/predicates/runbook_selected.rb app/services/engine/predicates/runbook_executed.rb app/services/engine/predicates/recovery_verified.rb spec/services/engine/predicate_registry_spec.rb spec/services/engine/predicates/chaos_cookbook_predicates_spec.rb
git commit -m "feat: add chaos cookbook artifact predicates"
```

---

## Task 3: Add RED specs for seeded chaos queue configuration

**Objective:** Prove the two queue YAML files seed correctly, resolve relative prompts, contain all stage configs, and preserve blind-queue constraints.

**Files:**
- Create: `spec/db/seeds/chaos_cookbook_queues_spec.rb`
- Later create: `config/queues/chaos_monkey.yml`, `config/queues/chaos_response.yml`, prompt files

**Step 1: Write failing spec**

Create `spec/db/seeds/chaos_cookbook_queues_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "chaos cookbook queue seeds" do
  before do
    Rails.application.load_seed
  end

  it "seeds the chaos_monkey queue with every configured stage" do
    queue = WorkQueue.find_by!(slug: "chaos_monkey")

    expect(queue.name).to eq("Chaos Monkey")
    expect(queue.stages).to eq(%w[
      plan_disruption execute_disruption monitor_impact hold_for_response
      evaluate_recovery score_and_report done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to match_array(queue.stages)
  end

  it "seeds the chaos_response queue with every configured stage" do
    queue = WorkQueue.find_by!(slug: "chaos_response")

    expect(queue.name).to eq("Chaos Response")
    expect(queue.stages).to eq(%w[
      detect_alerts diagnose_failure select_runbook execute_runbook
      verify_recovery report_outcome done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to match_array(queue.stages)
  end

  it "resolves file prompts instead of persisting file URI literals" do
    queue = WorkQueue.find_by!(slug: "chaos_monkey")
    stage = queue.stage_configs.find_by!(stage_name: "plan_disruption")

    expect(stage.agent_prompt).to include("You are planning a safe staging-only chaos exercise")
    expect(stage.agent_prompt).not_to include("file://")
  end

  it "keeps docker compose adapter paths portable" do
    chaos_queue = WorkQueue.find_by!(slug: "chaos_monkey")
    response_queue = WorkQueue.find_by!(slug: "chaos_response")

    compose_configs = [
      chaos_queue.stage_configs.find_by!(stage_name: "execute_disruption"),
      response_queue.stage_configs.find_by!(stage_name: "execute_runbook")
    ].map(&:adapter_config)

    expect(compose_configs).to all(include("compose_file" => "spec/fixtures/chaos_staging/docker-compose.staging.yml"))
    expect(compose_configs).to all(satisfy { |config| config["working_directory"].blank? })
  end

  it "prevents the response diagnosis stage from reading the disruption plan" do
    queue = WorkQueue.find_by!(slug: "chaos_response")
    stage = queue.stage_configs.find_by!(stage_name: "diagnose_failure")

    expect(stage.allowed_skills).to include("read_sentry")
    expect(stage.forbidden_skills).to include("read_disruption_plan")
    expect(stage.forbidden_skills).to include("execute_staging")
  end

  it "uses cookbook-specific predicates from the source spec" do
    chaos_queue = WorkQueue.find_by!(slug: "chaos_monkey")
    response_queue = WorkQueue.find_by!(slug: "chaos_response")

    expect(chaos_queue.stage_configs.find_by!(stage_name: "plan_disruption").completion_criteria).to eq(["disruption_planned"])
    expect(chaos_queue.stage_configs.find_by!(stage_name: "execute_disruption").completion_criteria).to eq(["disruption_executed"])
    expect(chaos_queue.stage_configs.find_by!(stage_name: "monitor_impact").completion_criteria).to eq(["impact_observed"])
    expect(chaos_queue.stage_configs.find_by!(stage_name: "evaluate_recovery").completion_criteria).to eq(["recovery_evaluated"])
    expect(response_queue.stage_configs.find_by!(stage_name: "detect_alerts").completion_criteria).to eq(["alerts_detected"])
    expect(response_queue.stage_configs.find_by!(stage_name: "diagnose_failure").completion_criteria).to eq(["diagnosis_produced"])
    expect(response_queue.stage_configs.find_by!(stage_name: "select_runbook").completion_criteria).to eq(["runbook_selected"])
    expect(response_queue.stage_configs.find_by!(stage_name: "execute_runbook").completion_criteria).to eq(["runbook_executed"])
    expect(response_queue.stage_configs.find_by!(stage_name: "verify_recovery").completion_criteria).to eq(["recovery_verified"])
  end
end
```

**Step 2: Run RED verification**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/db/seeds/chaos_cookbook_queues_spec.rb -v
```

Expected: FAIL because `chaos_monkey` and `chaos_response` queues do not exist yet.

---

## Task 4: Add chaos queue YAML and prompt files

**Objective:** Seed both queue definitions with portable prompts and docker-friendly fixture paths.

**Files:**
- Create: `config/queues/chaos_monkey.yml`
- Create: `config/queues/chaos_response.yml`
- Create: all prompt files listed above

**Step 1: Create `config/queues/chaos_monkey.yml`**

```yaml
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
    escalation_target: block_and_notify
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
    escalation_target: block_and_notify
    completion_criteria: [disruption_executed]
    agent_prompt: file://prompts/chaos_execute_disruption.md
    timeout_seconds: 300
    adapter_config:
      compose_file: spec/fixtures/chaos_staging/docker-compose.staging.yml
      output_artifact_kind: disruption_record
  monitor_impact:
    adapter_type: shell_script
    allowed_skills: [read_sentry]
    forbidden_skills: [deploy, mutate_database, execute_staging]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [impact_observed]
    agent_prompt: file://prompts/chaos_monitor_impact.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: impact_report
      commands:
        - name: monitor fake sentry impact
          command: bash spec/fixtures/chaos_staging/scripts/monitor_fake_sentry.sh
          artifact: impact_report
  hold_for_response:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Waiting for the linked chaos_response work item to complete recovery attempt.
    timeout_seconds: 1800
  evaluate_recovery:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
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
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: file://prompts/chaos_score_report.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: chaos_report
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

**Step 2: Create `config/queues/chaos_response.yml`**

```yaml
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
    escalation_target: block_and_notify
    completion_criteria: [alerts_detected]
    agent_prompt: file://prompts/response_detect_alerts.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: detected_alerts
      commands:
        - name: detect fake sentry alerts
          command: bash spec/fixtures/chaos_staging/scripts/detect_fake_alerts.sh
          artifact: detected_alerts
  diagnose_failure:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_sentry]
    forbidden_skills: [deploy, mutate_database, execute_staging, read_disruption_plan]
    max_retries: 1
    escalation_target: block_and_notify
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
    escalation_target: block_and_notify
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
    escalation_target: block_and_notify
    completion_criteria: [runbook_executed]
    agent_prompt: file://prompts/response_execute_runbook.md
    timeout_seconds: 1200
    adapter_config:
      compose_file: spec/fixtures/chaos_staging/docker-compose.staging.yml
      output_artifact_kind: runbook_execution
  verify_recovery:
    adapter_type: shell_script
    allowed_skills: [read_sentry, execute_staging]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [recovery_verified]
    agent_prompt: file://prompts/response_verify_recovery.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: recovery_verification
      commands:
        - name: verify fake recovery
          command: bash spec/fixtures/chaos_staging/scripts/verify_fake_recovery.sh
          artifact: recovery_verification
  report_outcome:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: file://prompts/response_report_outcome.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: response_outcome
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

**Step 3: Create prompt files**

Each prompt must name its required artifact kind and JSON shape. Keep them self-contained and safety-focused.

`prompts/chaos_plan_disruption.md`:

```markdown
You are planning a safe staging-only chaos exercise.

Read the staging inventory, recent disruption history, and available runbooks. Choose one realistic, reversible failure scenario that is scoped to staging and does not repeat recent scenarios.

Return an artifact of kind `disruption_plan` with JSON data:
- scenario
- category: infrastructure, dependency, data, or load
- target_service
- action
- expected_symptoms
- reversal_steps
- safety_checks
- expected_alert_lag_seconds

Never choose production. Never choose a disruption without reversal steps.
```

`prompts/chaos_execute_disruption.md`:

```markdown
Execute only the approved staging disruption plan. Record the exact safe commands and timestamps.

Return artifact kind `disruption_record` with JSON data:
- commands_run
- start_time
- target_service
- expected_alert_lag_seconds
- reversal_steps
- response_spawn: a suggested chaos_response work item payload

If the target is not clearly staging or reversal steps are missing, fail closed.
```

`prompts/chaos_monitor_impact.md`:

```markdown
Monitor fake or staging alerting for the expected impact window. Zero alerts is a valid result and should be reported as an instrumentation gap.

Return artifact kind `impact_report` with JSON data:
- alerts_fired
- alert_delay_seconds
- services_affected
- sentry_event_ids
- monitoring_gaps
```

`prompts/chaos_evaluate_recovery.md`:

```markdown
Evaluate the response queue's recovery using the disruption plan, impact report, and response_outcome artifact.

Return artifact kind `recovery_evaluation` with JSON data:
- scores: detection, diagnosis, runbook_coverage, recovery_time, recovery_completeness, alert_quality
- overall_grade
- gaps
- recommendations

Judge alert and runbook quality, not just whether the service recovered.
```

`prompts/chaos_score_report.md`:

```markdown
Produce the final chaos exercise report. Include what was broken, what alerts fired or failed to fire, how the response queue handled it, what worked, what failed, and specific follow-up work.

Return a success report body with:
- summary
- chaos_report
- spawn_work_items: operations runbook updates and development instrumentation fixes when gaps are found
```

`prompts/response_detect_alerts.md`:

```markdown
Detect recent alerts from Sentry or the fake alert fixture. You do not know what chaos broke.

Return artifact kind `detected_alerts` with JSON data:
- events
- detection_time
- time_window_minutes
```

`prompts/response_diagnose.md`:

```markdown
Diagnose the incident using detected_alerts only. Do not read or request the disruption plan.

Return artifact kind `diagnosis` with JSON data:
- root_cause_hypothesis
- affected_services
- severity
- clusters
- confidence
- evidence_from_alerts
```

`prompts/response_select_runbook.md`:

```markdown
Select the best matching runbook from the repository for the diagnosis. A null selected_runbook is valid when no runbook applies.

Return artifact kind `runbook_selection` with JSON data:
- selected_runbook
- match_confidence
- gaps
```

`prompts/response_execute_runbook.md`:

```markdown
Execute the selected runbook's observe, mitigate, and verify steps against the staging Docker Compose fixture. If no runbook was selected, record that no applicable runbook exists.

Return artifact kind `runbook_execution` with JSON data:
- steps_executed
- overall_success
- skipped_reason
```

`prompts/response_verify_recovery.md`:

```markdown
Verify whether the affected service has recovered using health checks, fake Sentry alert rate, and key operation checks.

Return artifact kind `recovery_verification` with JSON data:
- service_healthy
- alert_rate
- verification_checks
```

`prompts/response_report_outcome.md`:

```markdown
Report the incident from the response queue's perspective only.

Return artifact kind `response_outcome` with JSON data:
- detected
- diagnosed
- runbook_used
- recovered
- timeline
- gaps
```

**Step 4: Run GREEN verification for queue seeds**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/db/seeds/chaos_cookbook_queues_spec.rb -v
```

Expected: PASS.

**Step 5: Commit**

```bash
git add config/queues/chaos_monkey.yml config/queues/chaos_response.yml prompts/chaos_plan_disruption.md prompts/chaos_execute_disruption.md prompts/chaos_monitor_impact.md prompts/chaos_evaluate_recovery.md prompts/chaos_score_report.md prompts/response_detect_alerts.md prompts/response_diagnose.md prompts/response_select_runbook.md prompts/response_execute_runbook.md prompts/response_verify_recovery.md prompts/response_report_outcome.md spec/db/seeds/chaos_cookbook_queues_spec.rb
git commit -m "feat: seed chaos monkey and response queues"
```

---

## Task 5: Add RED spec for chaos cross-queue waiting behavior

**Objective:** Prove the existing parent/child waiting mechanism can model `hold_for_response`, and add only the minimum missing behavior if current engine semantics are insufficient.

**Files:**
- Create: `spec/services/engine/chaos_cross_queue_wait_spec.rb`
- Possibly modify: `app/services/engine/transition_manager.rb`

**Step 1: Write failing or characterization spec**

Create `spec/services/engine/chaos_cross_queue_wait_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Chaos cross-queue response waiting" do
  it "advances a waiting chaos parent when the response child is completed" do
    chaos_queue = WorkQueue.create!(name: "Chaos Monkey", slug: "chaos-wait-#{SecureRandom.hex(4)}", stages: %w[hold_for_response evaluate_recovery done])
    response_queue = WorkQueue.create!(name: "Chaos Response", slug: "chaos-response-wait-#{SecureRandom.hex(4)}", stages: %w[detect_alerts report_outcome done])

    parent = WorkItem.create!(
      title: "Chaos exercise",
      spec_url: "inline",
      work_queue: chaos_queue,
      stage_name: "hold_for_response",
      status: :waiting
    )
    WorkItem.create!(
      title: "Response attempt",
      spec_url: "spawned://chaos-response",
      work_queue: response_queue,
      stage_name: "done",
      status: :completed,
      parent: parent,
      metadata: { "response_outcome_artifact_id" => "artifact-1" }
    )

    Engine::TransitionManager.advance_waiting_parent(parent)

    expect(parent.reload.stage_name).to eq("evaluate_recovery")
    expect(parent).to be_pending
    expect(parent.transition_logs.last.details["children_count"]).to eq(1)
  end
end
```

**Step 2: Run verification**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/chaos_cross_queue_wait_spec.rb -v
```

Expected: PASS if the existing `advance_waiting_parent` behavior already covers this. If it fails, implement the minimal fix in `app/services/engine/transition_manager.rb` and re-run.

**Step 3: Run broader transition specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/transition_manager_spec.rb spec/services/engine/cross_queue_spawn_spec.rb spec/services/engine/chaos_cross_queue_wait_spec.rb -v
```

Expected: PASS.

**Step 4: Commit**

If only the spec was added:

```bash
git add spec/services/engine/chaos_cross_queue_wait_spec.rb
git commit -m "test: cover chaos response waiting flow"
```

If production code was required, include it:

```bash
git add app/services/engine/transition_manager.rb spec/services/engine/chaos_cross_queue_wait_spec.rb
git commit -m "feat: support chaos response waiting flow"
```

---

## Task 6: Add fake Docker-friendly staging fixture

**Objective:** Provide a lightweight fixture environment for cookbook tests without duplicating shared infrastructure.

**Files:**
- Create: `spec/fixtures/chaos_staging/docker-compose.staging.yml`
- Create: `spec/fixtures/chaos_staging/api/Dockerfile`
- Create: `spec/fixtures/chaos_staging/api/config.ru`
- Create: `spec/fixtures/chaos_staging/api/Gemfile`
- Create: `spec/fixtures/chaos_staging/scripts/execute_safe_disruption.sh`
- Create: `spec/fixtures/chaos_staging/scripts/monitor_fake_sentry.sh`
- Create: `spec/fixtures/chaos_staging/scripts/detect_fake_alerts.sh`
- Create: `spec/fixtures/chaos_staging/scripts/verify_fake_recovery.sh`

**Step 1: Add fixture files**

`spec/fixtures/chaos_staging/docker-compose.staging.yml`:

```yaml
services:
  chaos-api:
    build: ./spec/fixtures/chaos_staging/api
    environment:
      RACK_ENV: staging
      FAKE_SENTRY_EVENTS_PATH: /tmp/fake_sentry/events.jsonl
    ports:
      - "127.0.0.1:${CHAOS_STAGING_API_PORT:-3929}:9292"
    volumes:
      - fake_sentry:/tmp/fake_sentry
    depends_on:
      - chaos-postgres
  chaos-postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: chaos_staging
    ports:
      - "127.0.0.1:${CHAOS_STAGING_POSTGRES_PORT:-55432}:5432"
  fake-sentry:
    image: alpine:3.20
    command: sh -c "mkdir -p /tmp/fake_sentry && touch /tmp/fake_sentry/events.jsonl && tail -f /tmp/fake_sentry/events.jsonl"
    volumes:
      - fake_sentry:/tmp/fake_sentry
volumes:
  fake_sentry:
```

`spec/fixtures/chaos_staging/api/Gemfile`:

```ruby
source "https://rubygems.org"
gem "rack", "~> 3.0"
puma_version = ENV.fetch("PUMA_VERSION", "6.4.0")
gem "puma", puma_version
```

`spec/fixtures/chaos_staging/api/Dockerfile`:

```dockerfile
FROM ruby:3.3-alpine
WORKDIR /app
COPY Gemfile /app/Gemfile
RUN bundle install
COPY config.ru /app/config.ru
CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0", "-p", "9292"]
```

`spec/fixtures/chaos_staging/api/config.ru`:

```ruby
run lambda { |env|
  case env["PATH_INFO"]
  when "/health"
    [200, { "content-type" => "application/json" }, ['{"ok":true}']]
  when "/boom"
    path = ENV.fetch("FAKE_SENTRY_EVENTS_PATH", "/tmp/fake_sentry/events.jsonl")
    File.open(path, "a") { |file| file.puts({ id: Time.now.to_i.to_s, service: "chaos-api", message: "boom" }.to_json) }
    [500, { "content-type" => "application/json" }, ['{"error":"boom"}']]
  else
    [404, { "content-type" => "application/json" }, ['{"error":"not_found"}']]
  end
}
```

Scripts should be executable and write deterministic JSON to stdout. Example `monitor_fake_sentry.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
mkdir -p tmp/chaos_staging
cat > tmp/chaos_staging/impact_report.json <<'JSON'
{"alerts_fired":1,"alert_delay_seconds":5,"services_affected":["chaos-api"],"sentry_event_ids":["evt-1"]}
JSON
cat tmp/chaos_staging/impact_report.json
```

Use analogous JSON for:

- `detect_fake_alerts.sh`: `{"events":[{"id":"evt-1","service":"chaos-api","message":"boom"}],"detection_time":"2026-05-05T00:00:00Z"}`
- `verify_fake_recovery.sh`: `{"service_healthy":true,"alert_rate":0,"verification_checks":[{"name":"health","passed":true}]}`
- `execute_safe_disruption.sh`: `{"commands_run":["docker compose stop chaos-postgres"],"target_service":"chaos-postgres","expected_alert_lag_seconds":5}`

**Step 2: Add a small fixture smoke spec only if needed**

If the shared infrastructure plan does not already include YAML syntax validation, add a lightweight spec to parse the compose YAML. Do not start Docker in unit specs.

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file("spec/fixtures/chaos_staging/docker-compose.staging.yml"); puts "compose yaml ok"'
```

Expected: `compose yaml ok`.

**Step 3: Commit**

```bash
git add spec/fixtures/chaos_staging
git commit -m "test: add chaos staging fixture"
```

---

## Task 7: Add docs and an example runbook

**Objective:** Document how to run the chaos cookbook safely and provide one response runbook for the fixture.

**Files:**
- Create: `docs/cookbooks/09-chaos-monkey.md`
- Create: `docs/runbooks/chaos/postgres-unavailable.md`

**Step 1: Create `docs/runbooks/chaos/postgres-unavailable.md`**

```markdown
# Runbook: Staging Postgres Unavailable

## Scope

Staging-only chaos fixture. Never run these commands against production.

## Symptoms

- API health checks fail or return elevated errors.
- Fake Sentry events mention database connection failures or unavailable Postgres.

## Observe

```bash
docker compose -f spec/fixtures/chaos_staging/docker-compose.staging.yml ps
curl -fsS http://127.0.0.1:${CHAOS_STAGING_API_PORT:-3929}/health
```

## Mitigate

```bash
docker compose -f spec/fixtures/chaos_staging/docker-compose.staging.yml start chaos-postgres
```

## Verify

```bash
curl -fsS http://127.0.0.1:${CHAOS_STAGING_API_PORT:-3929}/health
bash spec/fixtures/chaos_staging/scripts/verify_fake_recovery.sh
```
```

**Step 2: Create `docs/cookbooks/09-chaos-monkey.md`**

Include:

- Link to `docs/specs/cookbook-09-chaos-monkey.md`.
- The two-queue architecture and blind-response invariant.
- Safety checklist: staging-only, reversible disruption, no production credentials, `execute_disruption.max_retries: 0`.
- How to seed:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bin/rails db:seed`
- How to inspect queues in Rails console.
- Fake fixture note: shared infrastructure plan owns common fake Sentry and app infrastructure; this cookbook only adds scenario-specific scripts and runbook.
- Example environment variables: `CHAOS_STAGING_API_PORT`, `CHAOS_STAGING_POSTGRES_PORT`.

**Step 3: Verification**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/db/seeds/chaos_cookbook_queues_spec.rb -v
```

Expected: PASS.

**Step 4: Commit**

```bash
git add docs/cookbooks/09-chaos-monkey.md docs/runbooks/chaos/postgres-unavailable.md
git commit -m "docs: add chaos monkey cookbook guide"
```

---

## Task 8: Final full verification

**Objective:** Prove cookbook predicates, queue seeds, waiting flow, and YAML parsing all work together.

**Files:**
- No new files expected.

**Step 1: Run focused RSpec suite**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/chaos_cookbook_predicates_spec.rb spec/services/engine/predicate_registry_spec.rb spec/db/seeds/chaos_cookbook_queues_spec.rb spec/services/engine/chaos_cross_queue_wait_spec.rb -v
```

Expected: all examples pass.

**Step 2: Run broader engine safety suite**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine spec/db/seeds/chaos_cookbook_queues_spec.rb -v
```

Expected: all examples pass. If unrelated pre-existing failures appear, record them with exact failure names and run the focused suite again before committing.

**Step 3: Verify no hardcoded repo paths in cookbook files**

Run:

```bash
ruby -e 'paths = Dir["config/queues/chaos_*.yml"] + Dir["prompts/{chaos,response}_*.md"] + Dir["docs/cookbooks/09-chaos-monkey.md"]; bad = paths.select { |p| File.read(p).include?("/Users/gregmushen/work/code/taskrail") }; abort("hardcoded paths: #{bad.join(", ")}") unless bad.empty?; puts "portable paths ok"'
```

Expected: `portable paths ok`.

**Step 4: Commit any final fixes**

```bash
git status --short
git add <only the files changed by the fix>
git commit -m "fix: finalize chaos cookbook wiring"
```

Skip this commit if there are no changes.

---

## Implementation Dependencies

- Shared cookbook infrastructure plan should provide common fake Sentry semantics, common staging service conventions, and any reusable Docker Compose base patterns.
- Current `DockerComposeAdapter` runs `docker compose -f <compose_file> up --abort-on-container-exit`. If future implementation needs one-shot disruption commands instead of `up`, add a separate adapter feature with its own RED spec before changing cookbook queue semantics.
- Current `ShellScriptAdapter` maps only selected artifact names (`test_results`, `lint`, `coverage`) into artifacts. If shell stages must persist `impact_report`, `detected_alerts`, or `recovery_verification` directly from script output, first add RED specs for generic `output_artifact_kind` support in `ShellScriptAdapter`, then implement it. Until then, inline/fake reports may be used for cookbook demonstration stages.
- Cross-queue response spawning can use existing `spawn_work_items` report behavior. If `execute_disruption` must spawn response work items from artifacts rather than reports, add a separate transition-manager spec before implementation.

---

## Implementation Task Checklist

- [ ] Add RED specs for nine chaos cookbook artifact predicates.
- [ ] Implement predicate classes and registry entries.
- [ ] Add RED seed specs for `chaos_monkey` and `chaos_response` queues.
- [ ] Add portable queue YAML and prompt files.
- [ ] Verify response queue blindness through seed specs.
- [ ] Add or characterize cross-queue waiting behavior for `hold_for_response`.
- [ ] Add fake Docker-friendly chaos staging fixture without duplicating shared infrastructure.
- [ ] Add fixture runbook and cookbook docs.
- [ ] Run focused RSpec suite with rbenv PATH.
- [ ] Verify no hardcoded absolute repo paths.
- [ ] Commit each completed slice before moving to the next.

Expected final commit message for the implementation worker:

```bash
git commit -m "feat: add chaos monkey cookbook"
```
