# Background Job Observability Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `job_observability` cookbook queue so StupidClaw can scan async job classes, score their observability, draft missing instrumentation fixes, and gate the results through tests and human review.

**Architecture:** This follows the existing seeded queue architecture: add a portable YAML queue under `config/queues/`, keep long prompts in `prompts/` via `file://` indirection, add independent predicates under `Engine::Predicates`, and cover the seed/predicate behavior with focused RSpec examples. The cookbook uses fake/docker-friendly fixture app files under `test/fixtures/apps/uninstrumented_jobs/` for end-to-end cookbook exercising, while shared infrastructure such as Docker Compose adapters and base shell execution remains owned by the shared cookbook infrastructure plan.

**Tech Stack:** Rails, RSpec, seeded YAML queues, `Engine::PredicateRegistry`, `Artifact` records, inline Claude adapters, shell_script adapters, fake human-review stages, rbenv on Greg's Mac.

**Source Spec:** `docs/specs/cookbook-12-background-job-observability.md`

---

## Implementation principles

- Use strict TDD for every production behavior change: write the failing spec, run it and confirm the expected failure, implement the smallest change, rerun the focused spec, then run the relevant broader spec.
- Do not hardcode `/Users/gregmushen/...` or any absolute checkout path in queue YAML, prompts, specs, fixtures, or docs. Queue prompts must use relative `file://prompts/...` paths resolved by `Rails.root` through `db/seeds.rb`.
- Commit after each completed implementation task. If the Kanban assignment wants one final commit instead, squash the task commits before completion.
- Use Greg's Mac rbenv command shape for all focused test commands:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Keep fake/docker-friendly fixture infrastructure minimal: include a fixture Rails-style app tree and a local fake test command in queue config, but do not introduce or duplicate shared Docker Compose services here.

## Files to create or modify

Create:
- `config/queues/job_observability.yml`
- `prompts/jobs_scan_classes.md`
- `prompts/jobs_assess_observability.md`
- `prompts/jobs_draft_fixes.md`
- `app/services/engine/predicates/job_inventory_produced.rb`
- `app/services/engine/predicates/observability_assessed.rb`
- `spec/services/engine/predicates/job_inventory_produced_spec.rb`
- `spec/services/engine/predicates/observability_assessed_spec.rb`
- `test/fixtures/apps/uninstrumented_jobs/Gemfile`
- `test/fixtures/apps/uninstrumented_jobs/README.md`
- `test/fixtures/apps/uninstrumented_jobs/app/jobs/application_job.rb`
- `test/fixtures/apps/uninstrumented_jobs/app/jobs/export_job.rb`
- `test/fixtures/apps/uninstrumented_jobs/app/jobs/billing_job.rb`
- `test/fixtures/apps/uninstrumented_jobs/app/jobs/sync_job.rb`
- `test/fixtures/apps/uninstrumented_jobs/app/jobs/cleanup_job.rb`
- `test/fixtures/apps/uninstrumented_jobs/app/models/user.rb`
- `test/fixtures/apps/uninstrumented_jobs/app/services/s3.rb`
- `test/fixtures/apps/uninstrumented_jobs/app/services/external_api.rb`
- `docs/cookbooks/background-job-observability.md`

Modify:
- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Do not modify unless a failing spec proves it is necessary:
- `db/seeds.rb` because it already resolves `file://` relative to `Rails.root`.
- shared adapter classes such as `Adapters::DockerComposeAdapter`, `Adapters::ShellScriptAdapter`, or `Adapters::InlineClaudeAdapter`.

---

### Task 1: Add RED specs for the job inventory predicate

**Objective:** Prove the new `job_inventory_produced` predicate must pass only when a claim has a non-empty `job_inventory` artifact.

**Files:**
- Create: `spec/services/engine/predicates/job_inventory_produced_spec.rb`
- Later create: `app/services/engine/predicates/job_inventory_produced.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/job_inventory_produced_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::JobInventoryProduced do
  let(:queue) { WorkQueue.create!(name: "Job Observability", slug: "job-observability", stages: %w[scan_job_classes done]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit jobs", spec_url: "local", stage_name: "scan_job_classes") }
  let(:claim) { Claim.create!(work_item: work_item, stage_name: "scan_job_classes", status: "claimed") }

  it "passes with evidence when a job_inventory artifact has at least one job" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "job_inventory",
      data: {
        "framework" => "active_job",
        "jobs" => [
          {
            "class_name" => "ExportJob",
            "file" => "app/jobs/export_job.rb",
            "queue" => "default",
            "args" => ["user_id"]
          }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, jobs_count: 1 })
  end

  it "fails when the job_inventory artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no job_inventory artifact found")
  end

  it "fails when the job_inventory artifact has no jobs" do
    Artifact.create!(claim: claim, work_item: work_item, kind: "job_inventory", data: { "framework" => "active_job", "jobs" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("job_inventory artifact has no jobs")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/job_inventory_produced_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::JobInventoryProduced`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/job_inventory_produced.rb`:

```ruby
module Engine
  module Predicates
    class JobInventoryProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "job_inventory").first
        return PredicateResult.fail(reason: "no job_inventory artifact found") unless artifact

        jobs = artifact.data["jobs"]
        return PredicateResult.fail(reason: "job_inventory artifact has no jobs") unless jobs.is_a?(Array) && jobs.any?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, jobs_count: jobs.count })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/job_inventory_produced_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/job_inventory_produced.rb spec/services/engine/predicates/job_inventory_produced_spec.rb
git commit -m "feat: add job inventory predicate"
```

---

### Task 2: Add RED specs for the observability assessment predicate

**Objective:** Prove the new `observability_assessed` predicate validates an `observability_assessment` artifact and requires assessments for all jobs found in the latest job inventory.

**Files:**
- Create: `spec/services/engine/predicates/observability_assessed_spec.rb`
- Later create: `app/services/engine/predicates/observability_assessed.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/observability_assessed_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ObservabilityAssessed do
  let(:queue) { WorkQueue.create!(name: "Job Observability", slug: "job-observability", stages: %w[scan_job_classes assess_observability done]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit jobs", spec_url: "local", stage_name: "assess_observability") }
  let(:claim) { Claim.create!(work_item: work_item, stage_name: "assess_observability", status: "claimed") }

  before do
    Artifact.create!(
      work_item: work_item,
      kind: "job_inventory",
      data: {
        "framework" => "active_job",
        "jobs" => [
          { "class_name" => "ExportJob", "file" => "app/jobs/export_job.rb" },
          { "class_name" => "BillingJob", "file" => "app/jobs/billing_job.rb" }
        ]
      }
    )
  end

  it "passes with evidence when every inventoried job has an assessment" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "observability_assessment",
      data: {
        "jobs" => [
          { "class_name" => "ExportJob", "scores" => { "error_capture" => 0 }, "total_score" => 0.0, "classification" => "blind", "critical_gaps" => ["no logging"] },
          { "class_name" => "BillingJob", "scores" => { "error_capture" => 3 }, "total_score" => 2.1, "classification" => "well_instrumented", "critical_gaps" => [] }
        ],
        "summary" => { "total_jobs" => 2, "well_instrumented" => 1, "under_instrumented" => 0, "blind" => 1, "worst_job" => "ExportJob" }
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, assessed_jobs_count: 2 })
  end

  it "fails when the assessment artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no observability_assessment artifact found")
  end

  it "fails when the assessment has no job entries" do
    Artifact.create!(claim: claim, work_item: work_item, kind: "observability_assessment", data: { "jobs" => [], "summary" => { "total_jobs" => 0 } })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("observability_assessment artifact has no assessments")
  end

  it "fails when any inventoried job is missing from the assessment" do
    Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "observability_assessment",
      data: {
        "jobs" => [{ "class_name" => "ExportJob", "scores" => {}, "total_score" => 0.0, "classification" => "blind", "critical_gaps" => [] }],
        "summary" => { "total_jobs" => 1 }
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("observability_assessment missing jobs: BillingJob")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/observability_assessed_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::ObservabilityAssessed`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/observability_assessed.rb`:

```ruby
module Engine
  module Predicates
    class ObservabilityAssessed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "observability_assessment").first
        return PredicateResult.fail(reason: "no observability_assessment artifact found") unless artifact

        assessed_jobs = artifact.data["jobs"]
        return PredicateResult.fail(reason: "observability_assessment artifact has no assessments") unless assessed_jobs.is_a?(Array) && assessed_jobs.any?

        inventory = @claim.work_item.artifacts.where(kind: "job_inventory").order(created_at: :desc).first
        inventory_jobs = Array(inventory&.data&.fetch("jobs", []))
        expected_names = inventory_jobs.filter_map { |job| job["class_name"] }
        assessed_names = assessed_jobs.filter_map { |job| job["class_name"] }
        missing_names = expected_names - assessed_names
        return PredicateResult.fail(reason: "observability_assessment missing jobs: #{missing_names.join(', ')}") if missing_names.any?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, assessed_jobs_count: assessed_jobs.count })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/observability_assessed_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/observability_assessed.rb spec/services/engine/predicates/observability_assessed_spec.rb
git commit -m "feat: add observability assessment predicate"
```

---

### Task 3: Register both predicates

**Objective:** Make `PredicateRegistry.resolve` return both new predicate classes.

**Files:**
- Modify: `app/services/engine/predicate_registry.rb`
- Modify: `spec/services/engine/predicate_registry_spec.rb`

**Step 1: Write failing test**

Modify `spec/services/engine/predicate_registry_spec.rb` to include:

```ruby
it "resolves background job observability predicates" do
  expect(described_class.resolve("job_inventory_produced")).to eq(Engine::Predicates::JobInventoryProduced)
  expect(described_class.resolve("observability_assessed")).to eq(Engine::Predicates::ObservabilityAssessed)
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate: job_inventory_produced`.

**Step 3: Register predicates**

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
  "job_inventory_produced" => Predicates::JobInventoryProduced,
  "observability_assessed" => Predicates::ObservabilityAssessed
}.freeze
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register job observability predicates"
```

---

### Task 4: Add RED seed spec for the job observability queue

**Objective:** Prove seeds create a portable `job_observability` queue with all stage configs, resolved prompt files, and no hardcoded checkout path.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/job_observability.yml`
- Later create: `prompts/jobs_scan_classes.md`
- Later create: `prompts/jobs_assess_observability.md`
- Later create: `prompts/jobs_draft_fixes.md`

**Step 1: Write failing test**

Append to `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the background job observability queue with resolved portable prompts" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "job_observability")
  expect(queue.name).to eq("Background Job Observability")
  expect(queue.stages).to eq(%w[scan_job_classes assess_observability draft_fixes run_tests human_review done])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_max_retries" => 2,
    "default_timeout_seconds" => 600,
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 2
  )

  scan = queue.stage_configs.find_by!(stage_name: "scan_job_classes")
  expect(scan.adapter_type).to eq("inline_claude")
  expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
  expect(scan.allowed_skills).to eq(%w[read_repo])
  expect(scan.forbidden_skills).to include("edit_files", "deploy")
  expect(scan.completion_criteria).to eq(%w[job_inventory_produced])
  expect(scan.agent_prompt).to include("# Job Observability: Scan Job Classes")
  expect(scan.agent_prompt).to include("job_inventory")
  expect(scan.agent_prompt).not_to start_with("file://")
  expect(scan.agent_prompt).not_to include(Rails.root.to_s)
  expect(scan.adapter_config).to eq("output_artifact_kind" => "job_inventory")

  assess = queue.stage_configs.find_by!(stage_name: "assess_observability")
  expect(assess.adapter_type).to eq("inline_claude")
  expect(assess.model_override).to eq("claude-sonnet-4-20250514")
  expect(assess.completion_criteria).to eq(%w[observability_assessed])
  expect(assess.agent_prompt).to include("# Job Observability: Assess Observability")
  expect(assess.agent_prompt).to include("scorecard")
  expect(assess.adapter_config).to eq("output_artifact_kind" => "observability_assessment")

  draft = queue.stage_configs.find_by!(stage_name: "draft_fixes")
  expect(draft.adapter_type).to eq("inline_claude")
  expect(draft.allowed_skills).to eq(%w[read_repo])
  expect(draft.forbidden_skills).to eq(%w[deploy])
  expect(draft.max_retries).to eq(2)
  expect(draft.completion_criteria).to eq(%w[fixes_drafted])
  expect(draft.agent_prompt).to include("# Job Observability: Draft Fixes")
  expect(draft.adapter_config).to eq("output_artifact_kind" => "job_patches")

  run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
  expect(run_tests.adapter_type).to eq("shell_script")
  expect(run_tests.allowed_skills).to eq(%w[run_tests])
  expect(run_tests.forbidden_skills).to include("edit_files", "deploy")
  expect(run_tests.completion_criteria).to eq(%w[tests_passed])
  expect(run_tests.timeout_seconds).to eq(600)
  expect(run_tests.adapter_config.fetch("commands").first.fetch("command")).to include("bundle exec rspec")

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.completion_criteria).to eq(%w[report_present])
  expect(human_review.timeout_seconds).to eq(86_400)
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL with `Couldn't find WorkQueue` for slug `job_observability`.

**Step 3: Commit only if RED is established?**

Do not commit the failing spec alone unless your workflow intentionally captures red commits. Continue to Task 5 to make it pass, then commit the queue/prompt/seed spec together.

---

### Task 5: Add the portable queue YAML and prompt files

**Objective:** Seed the full `job_observability` queue exactly from the cookbook spec using portable prompt file references.

**Files:**
- Create: `config/queues/job_observability.yml`
- Create: `prompts/jobs_scan_classes.md`
- Create: `prompts/jobs_assess_observability.md`
- Create: `prompts/jobs_draft_fixes.md`
- Modify: `spec/models/work_queue_seed_spec.rb` from Task 4

**Step 1: Create queue YAML**

Create `config/queues/job_observability.yml`:

```yaml
name: Background Job Observability
slug: job_observability
stages:
  - scan_job_classes
  - assess_observability
  - draft_fixes
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2
stage_configs:
  scan_job_classes:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [job_inventory_produced]
    agent_prompt: file://prompts/jobs_scan_classes.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: job_inventory
  assess_observability:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [observability_assessed]
    agent_prompt: file://prompts/jobs_assess_observability.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: observability_assessment
  draft_fixes:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [fixes_drafted]
    agent_prompt: file://prompts/jobs_draft_fixes.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: job_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [tests_passed]
    agent_prompt: Apply generated job instrumentation patches, run the focused fixture specs, then run the relevant application test suite. Report pass/fail with command output.
    timeout_seconds: 600
    adapter_config:
      commands:
        - name: job_observability_fixture_specs
          command: PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/job_observability_cookbook_spec.rb
          artifact: test_results
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review job observability inventory, scorecard, and drafted patches before applying them to production code.
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
- The `run_tests` command is fake/docker-friendly and local to this cookbook. It does not add shared Docker Compose infrastructure.
- If `spec/system/job_observability_cookbook_spec.rb` does not exist yet, add it in a later implementation task before expecting this queue to run end-to-end.
- Do not add `working_directory` unless an adapter spec requires it. Existing runners should default to `Rails.root`.

**Step 2: Create scan prompt**

Create `prompts/jobs_scan_classes.md`:

```markdown
# Job Observability: Scan Job Classes

You are the scan stage for the `job_observability` queue.

Read the assignment context and repository files. Find every async job or worker class for frameworks including ActiveJob, Sidekiq, GoodJob, SQS workers, and Celery-style workers when present.

For each job, catalog:
- class_name
- file
- queue
- args from the perform/call method signature
- retry_config including max retries, backoff, and dead letter behavior
- timeout or deadline configuration
- error_handling such as rescue blocks, Sentry capture, or logger error calls
- logging statements and whether they are structured/contextual
- idempotent evidence or missing idempotency handling
- dependencies such as databases, external APIs, storage, mailers, or other services
- schedule such as cron, on-demand, event-driven, or unknown

Return only JSON that StupidClaw can parse:

```json
{
  "status": "success",
  "summary": "Cataloged background jobs and their observability-relevant configuration.",
  "reports": [{ "status": "success", "body": "Found N job classes." }],
  "artifacts": [
    {
      "kind": "job_inventory",
      "data": {
        "framework": "active_job",
        "jobs": [
          {
            "class_name": "ExportJob",
            "file": "app/jobs/export_job.rb",
            "queue": "default",
            "args": ["user_id"],
            "retry_config": "unknown",
            "timeout": null,
            "error_handling": "none",
            "logging": "none",
            "idempotent": false,
            "dependencies": ["User", "S3"],
            "schedule": "on_demand"
          }
        ]
      }
    }
  ]
}
```

Do not edit files in this stage.
```

**Step 3: Create assessment prompt**

Create `prompts/jobs_assess_observability.md`:

```markdown
# Job Observability: Assess Observability

You are the assessment stage for the `job_observability` queue.

Read the upstream `job_inventory` artifact and relevant source code. Score each job on a 0-3 scale for:
- error_capture
- structured_logging
- timeout_protection
- retry_strategy
- idempotency
- context_propagation
- metrics

Classification rules:
- `well_instrumented`: average score >= 2.0
- `under_instrumented`: average score >= 1.0 and < 2.0
- `blind`: average score < 1.0

Flag critical jobs involving payments, billing, invoices, data sync, customer notifications, exports, or irreversible data changes when they are blind or under-instrumented.

Include a human-readable scorecard in the success report body. Use this shape:

```text
BACKGROUND JOB OBSERVABILITY — YYYY-MM-DD

Job                Queue      Error  Log  Timeout  Retry  Idemp  Context  Metrics  CLASS
ExportJob          default      0     0     0        0      0      0        0        BLIND

Summary: N jobs total, W well-instrumented, U under-instrumented, B blind
Worst: ExportJob
Critical risk: SyncJob retries infinitely with no timeout or dead letter
```

Return only JSON that StupidClaw can parse:

```json
{
  "status": "success",
  "summary": "Scored background job observability.",
  "reports": [{ "status": "success", "body": "BACKGROUND JOB OBSERVABILITY ..." }],
  "artifacts": [
    {
      "kind": "observability_assessment",
      "data": {
        "jobs": [
          {
            "class_name": "ExportJob",
            "scores": {
              "error_capture": 0,
              "structured_logging": 0,
              "timeout_protection": 0,
              "retry_strategy": 0,
              "idempotency": 0,
              "context_propagation": 0,
              "metrics": 0
            },
            "total_score": 0.0,
            "classification": "blind",
            "critical_gaps": ["no error capture", "no structured logging", "no timeout"]
          }
        ],
        "summary": {
          "total_jobs": 1,
          "well_instrumented": 0,
          "under_instrumented": 0,
          "blind": 1,
          "worst_job": "ExportJob"
        }
      }
    }
  ]
}
```

Do not edit files in this stage.
```

**Step 4: Create draft fixes prompt**

Create `prompts/jobs_draft_fixes.md`:

```markdown
# Job Observability: Draft Fixes

You are the fix-drafting stage for the `job_observability` queue.

Read the upstream `observability_assessment` artifact and source code. For jobs classified as `blind` or `under_instrumented`, draft minimal patches that match the repository's existing job patterns.

Prioritize fixes by risk:
1. Prevent silent failure: Sentry/error capture with job context.
2. Make execution visible: structured start/success/failure logging with sanitized args.
3. Prevent stuck jobs: timeout/deadline configuration appropriate to the framework.
4. Bound retries: retry count, backoff, and exhausted/dead-letter handling.
5. Make retries safe: idempotency key or duplicate-work guard where applicable.
6. Preserve correlation: request_id, tenant_id, customer/account IDs, and job IDs.
7. Add metrics when a local metrics pattern exists.

For architectural changes such as splitting a monolithic job or adding a real dead letter queue, do not implement directly. Include a `spawn_recommendations` entry targeting the `development` queue.

Return only JSON that StupidClaw can parse:

```json
{
  "status": "success",
  "summary": "Drafted job observability patches.",
  "reports": [{ "status": "success", "body": "Drafted patches for blind and under-instrumented jobs." }],
  "artifacts": [
    {
      "kind": "job_patches",
      "data": {
        "patches": [
          {
            "file": "app/jobs/export_job.rb",
            "class_name": "ExportJob",
            "original": "def perform(user_id)\n  ...\nend",
            "replacement": "def perform(user_id)\n  Sentry.with_scope do |scope|\n    ...\n  end\nend",
            "fix_type": "error_capture_structured_logging_timeout_retry",
            "priority": "high"
          }
        ],
        "spawn_recommendations": [
          {
            "queue": "development",
            "reason": "SyncJob needs a real dead letter queue design before implementation."
          }
        ]
      }
    }
  ]
}
```

Do not deploy. Do not mutate production data. Keep proposed code minimal and testable.
```

**Step 5: Run seed spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git add config/queues/job_observability.yml prompts/jobs_scan_classes.md prompts/jobs_assess_observability.md prompts/jobs_draft_fixes.md spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed job observability queue"
```

---

### Task 6: Add fixture app files for uninstrumented jobs

**Objective:** Provide a small Rails-style fixture app that demonstrates blind, partially instrumented, infinite-retry, and silent-failure jobs for future cookbook E2E specs.

**Files:**
- Create fixture files under `test/fixtures/apps/uninstrumented_jobs/`

**Step 1: Write a failing fixture existence spec**

If no cookbook fixture spec exists yet, create or extend `spec/system/job_observability_cookbook_spec.rb` with this first failing example:

```ruby
require "rails_helper"

RSpec.describe "job observability cookbook fixture" do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/uninstrumented_jobs") }

  it "contains representative background jobs for observability scoring" do
    expect(fixture_root.join("app/jobs/export_job.rb")).to exist
    expect(fixture_root.join("app/jobs/billing_job.rb")).to exist
    expect(fixture_root.join("app/jobs/sync_job.rb")).to exist
    expect(fixture_root.join("app/jobs/cleanup_job.rb")).to exist

    expect(fixture_root.join("app/jobs/export_job.rb").read).to include("class ExportJob < ApplicationJob")
    expect(fixture_root.join("app/jobs/billing_job.rb").read).to include("sidekiq_options retry: 5, queue: :critical, deadline: 300")
    expect(fixture_root.join("app/jobs/sync_job.rb").read).to include("sidekiq_options retry: true")
    expect(fixture_root.join("app/jobs/cleanup_job.rb").read).to include("rescue => e")
  end
end
```

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/job_observability_cookbook_spec.rb
```

Expected: FAIL because fixture files do not exist.

**Step 2: Create fixture support files**

Create `test/fixtures/apps/uninstrumented_jobs/Gemfile`:

```ruby
source "https://rubygems.org"

gem "rails"
gem "sidekiq"
gem "sentry-ruby"
```

Create `test/fixtures/apps/uninstrumented_jobs/README.md`:

```markdown
# Uninstrumented Jobs Fixture

This fixture app is intentionally small and non-runnable. It gives the Background Job Observability cookbook representative job files to scan:

- `ExportJob`: no instrumentation
- `BillingJob`: good instrumentation example
- `SyncJob`: infinite retries with no timeout or dead letter strategy
- `CleanupJob`: silently swallows errors

Do not add shared Docker Compose or external service infrastructure here; use the shared cookbook infrastructure plan for that.
```

Create `test/fixtures/apps/uninstrumented_jobs/app/jobs/application_job.rb`:

```ruby
class ApplicationJob
  def self.sidekiq_options(*) = nil
  def self.sidekiq_retries_exhausted(&) = nil
end
```

Create `test/fixtures/apps/uninstrumented_jobs/app/jobs/export_job.rb`:

```ruby
class ExportJob < ApplicationJob
  def perform(user_id)
    user = User.find(user_id)
    csv = generate_csv(user.orders)
    S3.upload("exports/#{user_id}.csv", csv)
  end

  private

  def generate_csv(orders)
    orders.map(&:to_s).join("\n")
  end
end
```

Create `test/fixtures/apps/uninstrumented_jobs/app/jobs/billing_job.rb`:

```ruby
class BillingJob < ApplicationJob
  sidekiq_options retry: 5, queue: :critical, deadline: 300

  def perform(invoice_id)
    Sentry.with_scope do |scope|
      scope.set_context("billing", { invoice_id: invoice_id })
      Rails.logger.info({ event: "billing.start", invoice_id: invoice_id }.to_json)
      # Billing implementation omitted in fixture.
    end
  end

  sidekiq_retries_exhausted do |msg, ex|
    Sentry.capture_exception(ex, extra: { job: msg })
    Rails.logger.error({ event: "billing.exhausted", msg: msg }.to_json)
  end
end
```

Create `test/fixtures/apps/uninstrumented_jobs/app/jobs/sync_job.rb`:

```ruby
class SyncJob < ApplicationJob
  sidekiq_options retry: true # infinite retries, no dead letter

  def perform(record_id)
    ExternalApi.sync(record_id) # no timeout, no error handling
  end
end
```

Create `test/fixtures/apps/uninstrumented_jobs/app/jobs/cleanup_job.rb`:

```ruby
class CleanupJob < ApplicationJob
  def perform
    User.inactive.find_each do |user|
      user.anonymize!
    rescue => e
      # silently continue
    end
  end
end
```

Create `test/fixtures/apps/uninstrumented_jobs/app/models/user.rb`:

```ruby
class User
  def self.find(id) = new(id)
  def self.inactive = []

  attr_reader :id

  def initialize(id = nil)
    @id = id
  end

  def orders = []
  def anonymize! = true
end
```

Create `test/fixtures/apps/uninstrumented_jobs/app/services/s3.rb`:

```ruby
class S3
  def self.upload(path, body)
    true
  end
end
```

Create `test/fixtures/apps/uninstrumented_jobs/app/services/external_api.rb`:

```ruby
class ExternalApi
  def self.sync(record_id)
    true
  end
end
```

**Step 3: Run fixture spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/job_observability_cookbook_spec.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add spec/system/job_observability_cookbook_spec.rb test/fixtures/apps/uninstrumented_jobs
git commit -m "test: add job observability fixture app"
```

---

### Task 7: Add E2E cookbook spec for inventory, assessment, and patches

**Objective:** Exercise the cookbook stages against the fixture app with deterministic fake/inline outputs so the queue contract stays stable.

**Files:**
- Modify: `spec/system/job_observability_cookbook_spec.rb`

**Step 1: Write failing end-to-end contract spec**

Extend `spec/system/job_observability_cookbook_spec.rb` with examples that seed the queue and verify the expected artifact contract. Keep this deterministic: do not call a real Claude CLI in this spec.

```ruby
it "defines the artifact contract for the background job observability stages" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "job_observability")
  work_item = WorkItem.create!(
    work_queue: queue,
    title: "Audit fixture jobs",
    spec_url: "test/fixtures/apps/uninstrumented_jobs",
    stage_name: "scan_job_classes"
  )

  scan_claim = Claim.create!(work_item: work_item, stage_name: "scan_job_classes", status: "claimed")
  Artifact.create!(
    claim: scan_claim,
    work_item: work_item,
    kind: "job_inventory",
    data: {
      "framework" => "active_job",
      "jobs" => [
        { "class_name" => "ExportJob", "file" => "app/jobs/export_job.rb", "queue" => "default", "args" => ["user_id"] },
        { "class_name" => "BillingJob", "file" => "app/jobs/billing_job.rb", "queue" => "critical", "args" => ["invoice_id"] },
        { "class_name" => "SyncJob", "file" => "app/jobs/sync_job.rb", "queue" => "default", "args" => ["record_id"] },
        { "class_name" => "CleanupJob", "file" => "app/jobs/cleanup_job.rb", "queue" => "default", "args" => [] }
      ]
    }
  )

  expect(Engine::PredicateRegistry.resolve("job_inventory_produced").new(claim: scan_claim).call).to be_passed

  assess_claim = Claim.create!(work_item: work_item, stage_name: "assess_observability", status: "claimed")
  Artifact.create!(
    claim: assess_claim,
    work_item: work_item,
    kind: "observability_assessment",
    data: {
      "jobs" => [
        { "class_name" => "ExportJob", "scores" => {}, "total_score" => 0.0, "classification" => "blind", "critical_gaps" => ["no instrumentation"] },
        { "class_name" => "BillingJob", "scores" => {}, "total_score" => 2.0, "classification" => "well_instrumented", "critical_gaps" => [] },
        { "class_name" => "SyncJob", "scores" => {}, "total_score" => 0.0, "classification" => "blind", "critical_gaps" => ["infinite retries"] },
        { "class_name" => "CleanupJob", "scores" => {}, "total_score" => 0.0, "classification" => "blind", "critical_gaps" => ["swallows errors"] }
      ],
      "summary" => { "total_jobs" => 4, "well_instrumented" => 1, "under_instrumented" => 0, "blind" => 3, "worst_job" => "ExportJob" }
    }
  )

  result = Engine::PredicateRegistry.resolve("observability_assessed").new(claim: assess_claim).call

  expect(result).to be_passed
  expect(result.evidence[:assessed_jobs_count]).to eq(4)
end
```

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/job_observability_cookbook_spec.rb
```

Expected: PASS if Tasks 1-6 are complete. If it fails, fix only the missing contract behavior.

**Step 2: Commit**

```bash
git add spec/system/job_observability_cookbook_spec.rb
git commit -m "test: cover job observability cookbook contract"
```

---

### Task 8: Add user-facing cookbook docs

**Objective:** Document how to run and interpret the Background Job Observability cookbook without duplicating shared infrastructure setup.

**Files:**
- Create: `docs/cookbooks/background-job-observability.md`

**Step 1: Write docs**

Create `docs/cookbooks/background-job-observability.md`:

```markdown
# Background Job Observability Cookbook

Source spec: `docs/specs/cookbook-12-background-job-observability.md`

The `job_observability` queue audits async jobs and workers for missing error capture, structured logging, timeout protection, retry strategy, idempotency, context propagation, and metrics.

## Stages

1. `scan_job_classes`: catalogs job classes into a `job_inventory` artifact.
2. `assess_observability`: scores each job and writes an `observability_assessment` artifact plus a human-readable scorecard.
3. `draft_fixes`: drafts `job_patches` for blind and under-instrumented jobs.
4. `run_tests`: applies or validates patches through the configured shell test command.
5. `human_review`: blocks for review before work is considered complete.
6. `done`: terminal state.

## Fixture app

The fixture app at `test/fixtures/apps/uninstrumented_jobs/` includes:

- `ExportJob`: no instrumentation.
- `BillingJob`: good instrumentation example.
- `SyncJob`: infinite retries with no timeout or dead letter strategy.
- `CleanupJob`: silently swallows errors.

## Infrastructure expectations

This cookbook assumes the shared StupidClaw development/test infrastructure is already available. It does not define new Docker Compose services. External services in the fixture app are fake Ruby classes so the cookbook can run in local and Docker-friendly test environments.

## Focused tests

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/job_inventory_produced_spec.rb \
  spec/services/engine/predicates/observability_assessed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/system/job_observability_cookbook_spec.rb
```
```

**Step 2: Verify docs mention the source spec**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/job_observability_cookbook_spec.rb spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add docs/cookbooks/background-job-observability.md
git commit -m "docs: document job observability cookbook"
```

---

### Task 9: Run final focused verification

**Objective:** Verify all cookbook behavior is green before handing off.

**Files:**
- No new files.

**Step 1: Run focused specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/job_inventory_produced_spec.rb \
  spec/services/engine/predicates/observability_assessed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/system/job_observability_cookbook_spec.rb
```

Expected: PASS.

**Step 2: Run a broader safety check if time allows**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine spec/models/work_queue_seed_spec.rb spec/system/job_observability_cookbook_spec.rb
```

Expected: PASS. If the broader check fails because of unrelated existing failures, record the failures and keep the focused cookbook specs green.

**Step 3: Verify portability and source references**

Run:

```bash
! grep -R "/Users/gregmushen/work/code/stupidclaw" config/queues/job_observability.yml prompts/jobs_*.md test/fixtures/apps/uninstrumented_jobs docs/cookbooks/background-job-observability.md

grep -R "docs/specs/cookbook-12-background-job-observability.md" docs/cookbooks/background-job-observability.md
```

Expected: first command exits 0 with no output; second command prints the source spec reference.

---

## Implementation task checklist

- [ ] Add `Engine::Predicates::JobInventoryProduced` with RED-GREEN specs.
- [ ] Add `Engine::Predicates::ObservabilityAssessed` with RED-GREEN specs.
- [ ] Register both predicates in `Engine::PredicateRegistry` with a failing registry spec first.
- [ ] Add `config/queues/job_observability.yml` with portable `file://prompts/...` references and no hardcoded checkout paths.
- [ ] Add `prompts/jobs_scan_classes.md`, `prompts/jobs_assess_observability.md`, and `prompts/jobs_draft_fixes.md` with parseable artifact contracts.
- [ ] Add seed coverage proving the queue stages, adapters, predicates, prompt resolution, and fake/docker-friendly test command.
- [ ] Add `test/fixtures/apps/uninstrumented_jobs/` with ExportJob, BillingJob, SyncJob, CleanupJob, and fake dependencies.
- [ ] Add deterministic cookbook contract specs for inventory and assessment artifacts.
- [ ] Add user-facing docs under `docs/cookbooks/background-job-observability.md`.
- [ ] Run focused RSpec verification with rbenv command prefixes.
- [ ] Verify no hardcoded repo path appears in new queue/prompt/fixture/docs files.

## Expected final commit message

```bash
git commit -m "feat: add background job observability cookbook"
```

## Implementation dependencies

- Existing `db/seeds.rb` must continue resolving `file://` prompts relative to `Rails.root`.
- Existing shell_script adapter behavior should support `adapter_config.commands` and default command execution from `Rails.root`.
- Existing `fixes_drafted`, `tests_passed`, and `report_present` predicates remain reused.
- Shared Docker Compose/development infrastructure is intentionally out of scope for this cookbook; do not duplicate it here.
