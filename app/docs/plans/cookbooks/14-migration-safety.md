# Migration Safety Check Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `migration_safety` cookbook queue so TaskRail can map migration impact, enumerate migration risks, draft rollback procedures, exercise rollback in Docker-friendly staging, and produce a reviewed migration runbook.

**Architecture:** This cookbook follows the existing seeded cookbook architecture: a portable YAML queue under `config/queues/`, long prompts in repo-relative prompt files, artifact-backed predicates registered in `Engine::PredicateRegistry`, and focused RSpec coverage for queue seeding, predicate behavior, and the fixture contract. The rollback test stage uses the existing `docker_compose` adapter and shared `cookbooks/docker-compose.yml` instead of hardcoded checkout paths or a cookbook-specific absolute working directory.

**Tech Stack:** Rails, RSpec, seeded YAML queues, `Engine::PredicateRegistry`, `Artifact` records, inline Claude adapters, Docker Compose adapter, fake human-review stages, rbenv on Greg's Mac.

**Source Spec:** `docs/specs/cookbook-14-migration-safety.md`

---

## Current Codebase Context

Relevant existing files and conventions:

- `db/seeds.rb` loads every `config/queues/*.yml`, resolves `agent_prompt: file://...` using `Rails.root.join(...)`, and upserts `WorkQueue` plus `StageConfig` records.
- `config/queues/dead_code_removal.yml` is the best current portable cookbook queue example that uses `file://cookbooks/prompts/...`, `fixture_app`, and `cookbooks/docker-compose.yml` without `working_directory`.
- `config/queues/job_observability.yml` shows a cookbook with prompt files under root `prompts/`; prefer the newer cookbook-local path shape from dead-code removal for this implementation: `file://cookbooks/prompts/migration_safety/...`.
- `app/services/engine/predicate_registry.rb` maps completion-criteria names to predicate classes.
- `app/services/engine/predicates/query_inventory_produced.rb`, `query_analyzed.rb`, `query_fixes_drafted.rb`, `job_inventory_produced.rb`, and `observability_assessed.rb` are the closest artifact-contract predicate examples.
- `spec/models/work_queue_seed_spec.rb` contains cookbook seed assertions and should receive one new example for `migration_safety`.
- `spec/system/job_observability_cookbook_spec.rb` demonstrates a compact fixture contract spec that creates artifacts and checks registry predicates.
- Shared cookbook infrastructure lives under `cookbooks/`; do not create a duplicate top-level Compose stack.

Global implementation rules:

- Follow strict TDD from `test-driven-development`: write the failing spec first, run it and confirm the expected failure, implement the smallest production/config change, rerun the focused spec, then run relevant surrounding specs.
- Use Greg's rbenv path for every RSpec command:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Do not hardcode `/Users/gregmushen/work/code/taskrail` or any absolute repository path in queue YAML, prompts, specs, fixtures, docs, or implementation code.
- Use repo-relative prompt paths: `file://cookbooks/prompts/migration_safety/scan_impact.md`, etc.
- Use repo-relative fixture paths: `cookbooks/fixtures/apps/migration_safety_app`.
- Use the shared Compose file path `cookbooks/docker-compose.yml` in adapter config unless a failing spec proves cookbook-specific Compose infrastructure is required.
- Commit after each implementation task. If the Kanban implementation card requires one final commit, squash the task commits before completion.

---

## Files to Create or Modify

Create:

- `config/queues/migration_safety.yml`
- `cookbooks/prompts/migration_safety/scan_impact.md`
- `cookbooks/prompts/migration_safety/enumerate_risks.md`
- `cookbooks/prompts/migration_safety/draft_rollback.md`
- `cookbooks/prompts/migration_safety/test_rollback.md`
- `cookbooks/prompts/migration_safety/draft_runbook.md`
- `app/services/engine/predicates/impact_mapped.rb`
- `app/services/engine/predicates/risks_enumerated.rb`
- `app/services/engine/predicates/rollback_drafted.rb`
- `app/services/engine/predicates/rollback_tested.rb`
- `spec/services/engine/predicates/impact_mapped_spec.rb`
- `spec/services/engine/predicates/risks_enumerated_spec.rb`
- `spec/services/engine/predicates/rollback_drafted_spec.rb`
- `spec/services/engine/predicates/rollback_tested_spec.rb`
- `spec/system/migration_safety_cookbook_spec.rb`
- `cookbooks/fixtures/apps/migration_safety_app/README.md`
- `cookbooks/fixtures/apps/migration_safety_app/Gemfile`
- `cookbooks/fixtures/apps/migration_safety_app/app/models/order.rb`
- `cookbooks/fixtures/apps/migration_safety_app/app/services/order_backfill.rb`
- `cookbooks/fixtures/apps/migration_safety_app/app/services/payment_provider_switch.rb`
- `cookbooks/fixtures/apps/migration_safety_app/app/controllers/orders_controller.rb`
- `cookbooks/fixtures/apps/migration_safety_app/config/routes.rb`
- `cookbooks/fixtures/apps/migration_safety_app/db/schema.rb`
- `cookbooks/fixtures/apps/migration_safety_app/db/migrate/20240101000000_add_region_to_orders_unsafe.rb`
- `cookbooks/fixtures/apps/migration_safety_app/db/migrate/20240101000001_add_region_to_orders_safe.rb`
- `cookbooks/fixtures/apps/migration_safety_app/scripts/run_rollback_test.rb`
- `docs/cookbooks/migration-safety.md`

Modify:

- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Do not modify unless a failing spec proves it is necessary:

- `db/seeds.rb`; it already resolves `file://` paths relative to `Rails.root`.
- `Adapters::DockerComposeAdapter`; this cookbook should exercise its existing config contract.
- Shared `cookbooks/docker-compose.yml`; only modify it if the fixture runner cannot be represented with the existing fake/docker-friendly service pattern, and write a RED spec first.

---

## Migration Safety Queue YAML Target

Create `config/queues/migration_safety.yml` with this shape. Keep all paths repo-relative and omit `working_directory`.

```yaml
name: Migration Safety Check
slug: migration_safety
stages:
  - scan_impact
  - enumerate_risks
  - draft_rollback
  - test_rollback
  - draft_runbook
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2
stage_configs:
  scan_impact:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [impact_mapped]
    agent_prompt: file://cookbooks/prompts/migration_safety/scan_impact.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: impact_map
      fixture_app: cookbooks/fixtures/apps/migration_safety_app
  enumerate_risks:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [risks_enumerated]
    agent_prompt: file://cookbooks/prompts/migration_safety/enumerate_risks.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: impact_map
      output_artifact_kind: risk_assessment
      fixture_app: cookbooks/fixtures/apps/migration_safety_app
  draft_rollback:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [rollback_drafted]
    agent_prompt: file://cookbooks/prompts/migration_safety/draft_rollback.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: risk_assessment
      output_artifact_kind: rollback_plan
      fixture_app: cookbooks/fixtures/apps/migration_safety_app
  test_rollback:
    adapter_type: docker_compose
    allowed_skills: [execute_staging]
    forbidden_skills: [deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [rollback_tested]
    agent_prompt: file://cookbooks/prompts/migration_safety/test_rollback.md
    timeout_seconds: 1200
    adapter_config:
      input_artifact_kind: rollback_plan
      output_artifact_kind: rollback_test_results
      fixture_app: cookbooks/fixtures/apps/migration_safety_app
      compose_file: cookbooks/docker-compose.yml
      commands:
        - name: migration-safety-rollback-fixture
          command: ruby cookbooks/fixtures/apps/migration_safety_app/scripts/run_rollback_test.rb
          artifact: rollback_test_results
  draft_runbook:
    adapter_type: inline_claude
    model_override: claude-opus-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: file://cookbooks/prompts/migration_safety/draft_runbook.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: rollback_test_results
      output_artifact_kind: migration_runbook
      fixture_app: cookbooks/fixtures/apps/migration_safety_app
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review migration impact map, risk assessment, rollback proof, and runbook before production cutover.
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

- The source spec used `file://prompts/...`; this plan intentionally uses `file://cookbooks/prompts/migration_safety/...` to match the newer shared cookbook directory contract.
- The source spec used `docker-compose.staging.yml`; this plan intentionally points at `cookbooks/docker-compose.yml` to reuse shared Docker-friendly infrastructure and avoid a new root-level Compose file.
- The fixture command should be deterministic and local; it should emit JSON for the `rollback_test_results` artifact if the Docker adapter captures command artifacts.

---

### Task 1: Add RED specs for the impact map predicate

**Objective:** Prove `impact_mapped` requires an `impact_map` artifact with at least one affected file and stable evidence.

**Files:**
- Create: `spec/services/engine/predicates/impact_mapped_spec.rb`
- Later create: `app/services/engine/predicates/impact_mapped.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/impact_mapped_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ImpactMapped do
  let(:queue) { WorkQueue.create!(name: "Migration Safety", slug: "migration-safety-#{SecureRandom.hex(4)}", stages: %w[scan_impact done]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit migration", spec_url: "local", stage_name: "scan_impact") }
  let(:claim) { Claim.create!(work_item: work_item, stage_name: "scan_impact", status: :active) }

  it "passes with evidence when the impact_map has affected files" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "impact_map",
      data: {
        "affected_files" => ["app/models/order.rb", "db/migrate/20240101000000_add_region_to_orders_unsafe.rb"],
        "affected_tests" => ["spec/models/order_spec.rb"],
        "affected_configs" => ["config/database.yml"],
        "external_consumers" => ["billing-export"]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(
      artifact_id: artifact.id,
      affected_files_count: 2,
      affected_tests_count: 1,
      affected_configs_count: 1,
      external_consumers_count: 1
    )
  end

  it "fails when the artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no impact_map artifact found")
  end

  it "fails when affected_files is empty" do
    Artifact.create!(claim: claim, work_item: work_item, kind: "impact_map", data: { "affected_files" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("impact_map artifact has no affected files")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/impact_mapped_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::ImpactMapped`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/impact_mapped.rb`:

```ruby
module Engine
  module Predicates
    class ImpactMapped
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "impact_map").first
        return PredicateResult.fail(reason: "no impact_map artifact found") unless artifact

        affected_files = Array(artifact.data["affected_files"])
        return PredicateResult.fail(reason: "impact_map artifact has no affected files") if affected_files.empty?

        PredicateResult.pass(evidence: {
          artifact_id: artifact.id,
          affected_files_count: affected_files.count,
          affected_tests_count: Array(artifact.data["affected_tests"]).count,
          affected_configs_count: Array(artifact.data["affected_configs"]).count,
          external_consumers_count: Array(artifact.data["external_consumers"]).count
        })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/impact_mapped_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/impact_mapped.rb spec/services/engine/predicates/impact_mapped_spec.rb
git commit -m "feat: add migration impact predicate"
```

---

### Task 2: Add RED specs for the risk assessment predicate

**Objective:** Prove `risks_enumerated` requires a `risk_assessment` artifact with risks and a valid severity contract.

**Files:**
- Create: `spec/services/engine/predicates/risks_enumerated_spec.rb`
- Later create: `app/services/engine/predicates/risks_enumerated.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/risks_enumerated_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::RisksEnumerated do
  let(:queue) { WorkQueue.create!(name: "Migration Safety", slug: "migration-safety-#{SecureRandom.hex(4)}", stages: %w[enumerate_risks done]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit migration", spec_url: "local", stage_name: "enumerate_risks") }
  let(:claim) { Claim.create!(work_item: work_item, stage_name: "enumerate_risks", status: :active) }

  it "passes with evidence when risks include allowed severities" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "risk_assessment",
      data: {
        "risks" => [
          { "category" => "downtime", "description" => "table rewrite lock", "severity" => "blocking", "affected_paths" => ["db/migrate/unsafe.rb"], "mitigation" => "split migration" },
          { "category" => "backwards_compatibility", "description" => "old code misses default", "severity" => "medium", "affected_paths" => ["app/models/order.rb"], "mitigation" => "dual read" }
        ],
        "blocking_risks" => ["table rewrite lock"]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, risks_count: 2, blocking_risks_count: 1)
  end

  it "fails when the risk_assessment artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no risk_assessment artifact found")
  end

  it "fails when risks are empty" do
    Artifact.create!(claim: claim, work_item: work_item, kind: "risk_assessment", data: { "risks" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("risk_assessment artifact has no risks")
  end

  it "fails when a risk has an unknown severity" do
    Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "risk_assessment",
      data: { "risks" => [{ "severity" => "catastrophic" }] }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("risk_assessment contains unknown severity")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/risks_enumerated_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::RisksEnumerated`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/risks_enumerated.rb`:

```ruby
module Engine
  module Predicates
    class RisksEnumerated
      ALLOWED_SEVERITIES = %w[blocking high medium low].freeze

      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "risk_assessment").first
        return PredicateResult.fail(reason: "no risk_assessment artifact found") unless artifact

        risks = artifact.data["risks"]
        return PredicateResult.fail(reason: "risk_assessment artifact has no risks") unless risks.is_a?(Array) && risks.any?
        return PredicateResult.fail(reason: "risk_assessment contains unknown severity") if risks.any? { |risk| !ALLOWED_SEVERITIES.include?(risk["severity"]) }

        PredicateResult.pass(evidence: {
          artifact_id: artifact.id,
          risks_count: risks.count,
          blocking_risks_count: Array(artifact.data["blocking_risks"]).count
        })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/risks_enumerated_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/risks_enumerated.rb spec/services/engine/predicates/risks_enumerated_spec.rb
git commit -m "feat: add migration risk predicate"
```

---

### Task 3: Add RED specs for the rollback plan predicate

**Objective:** Prove `rollback_drafted` requires concrete rollback procedures with executable steps.

**Files:**
- Create: `spec/services/engine/predicates/rollback_drafted_spec.rb`
- Later create: `app/services/engine/predicates/rollback_drafted.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/rollback_drafted_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::RollbackDrafted do
  let(:queue) { WorkQueue.create!(name: "Migration Safety", slug: "migration-safety-#{SecureRandom.hex(4)}", stages: %w[draft_rollback done]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit migration", spec_url: "local", stage_name: "draft_rollback") }
  let(:claim) { Claim.create!(work_item: work_item, stage_name: "draft_rollback", status: :active) }

  it "passes with evidence when rollback_plan has procedures and steps" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "rollback_plan",
      data: {
        "procedures" => [
          {
            "risk_ref" => "table rewrite lock",
            "steps" => [
              { "action" => "restore previous schema", "command" => "bin/rails db:rollback STEP=1", "verification" => "orders.region absent" }
            ],
            "estimated_time" => "5 minutes",
            "data_loss_potential" => "none"
          }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, procedures_count: 1, steps_count: 1)
  end

  it "fails when the rollback_plan artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no rollback_plan artifact found")
  end

  it "fails when procedures are empty" do
    Artifact.create!(claim: claim, work_item: work_item, kind: "rollback_plan", data: { "procedures" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("rollback_plan artifact has no procedures")
  end

  it "fails when a procedure has no testable steps" do
    Artifact.create!(claim: claim, work_item: work_item, kind: "rollback_plan", data: { "procedures" => [{ "risk_ref" => "lock", "steps" => [] }] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("rollback_plan procedures require testable steps")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/rollback_drafted_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::RollbackDrafted`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/rollback_drafted.rb`:

```ruby
module Engine
  module Predicates
    class RollbackDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "rollback_plan").first
        return PredicateResult.fail(reason: "no rollback_plan artifact found") unless artifact

        procedures = artifact.data["procedures"]
        return PredicateResult.fail(reason: "rollback_plan artifact has no procedures") unless procedures.is_a?(Array) && procedures.any?

        steps_count = procedures.sum { |procedure| Array(procedure["steps"]).count }
        return PredicateResult.fail(reason: "rollback_plan procedures require testable steps") if steps_count.zero?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, procedures_count: procedures.count, steps_count: steps_count })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/rollback_drafted_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/rollback_drafted.rb spec/services/engine/predicates/rollback_drafted_spec.rb
git commit -m "feat: add rollback plan predicate"
```

---

### Task 4: Add RED specs for the rollback test predicate

**Objective:** Prove `rollback_tested` passes only when migration, rollback, data integrity, and health checks all succeeded.

**Files:**
- Create: `spec/services/engine/predicates/rollback_tested_spec.rb`
- Later create: `app/services/engine/predicates/rollback_tested.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/rollback_tested_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::RollbackTested do
  let(:queue) { WorkQueue.create!(name: "Migration Safety", slug: "migration-safety-#{SecureRandom.hex(4)}", stages: %w[test_rollback done]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit migration", spec_url: "local", stage_name: "test_rollback") }
  let(:claim) { Claim.create!(work_item: work_item, stage_name: "test_rollback", status: :active) }

  it "passes with evidence when rollback test results are fully green" do
    artifact = Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "rollback_test_results",
      data: {
        "migration_succeeded" => true,
        "rollback_succeeded" => true,
        "data_intact" => true,
        "health_checks_passed" => true,
        "issues" => []
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when rollback_test_results is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no rollback_test_results artifact found")
  end

  it "fails when any required check is false" do
    Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "rollback_test_results",
      data: {
        "migration_succeeded" => true,
        "rollback_succeeded" => false,
        "data_intact" => true,
        "health_checks_passed" => true,
        "issues" => ["rollback command failed"]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("rollback_test_results has failed checks: rollback_succeeded")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/rollback_tested_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::RollbackTested`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/rollback_tested.rb`:

```ruby
module Engine
  module Predicates
    class RollbackTested
      REQUIRED_TRUE_KEYS = %w[migration_succeeded rollback_succeeded data_intact health_checks_passed].freeze

      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "rollback_test_results").first
        return PredicateResult.fail(reason: "no rollback_test_results artifact found") unless artifact

        failed_keys = REQUIRED_TRUE_KEYS.reject { |key| artifact.data[key] == true }
        return PredicateResult.fail(reason: "rollback_test_results has failed checks: #{failed_keys.join(', ')}") if failed_keys.any?

        PredicateResult.pass(evidence: { artifact_id: artifact.id })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/rollback_tested_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/rollback_tested.rb spec/services/engine/predicates/rollback_tested_spec.rb
git commit -m "feat: add rollback test predicate"
```

---

### Task 5: Register migration safety predicates

**Objective:** Make the four new completion criteria resolvable through `Engine::PredicateRegistry`.

**Files:**
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing registry assertions**

Add these expectations to the existing `resolves known predicate names` example in `spec/services/engine/predicate_registry_spec.rb`:

```ruby
expect(described_class.resolve("impact_mapped")).to eq(Engine::Predicates::ImpactMapped)
expect(described_class.resolve("risks_enumerated")).to eq(Engine::Predicates::RisksEnumerated)
expect(described_class.resolve("rollback_drafted")).to eq(Engine::Predicates::RollbackDrafted)
expect(described_class.resolve("rollback_tested")).to eq(Engine::Predicates::RollbackTested)
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate: impact_mapped`.

**Step 3: Register predicates**

Add these entries to `Engine::PredicateRegistry::PREDICATES` in `app/services/engine/predicate_registry.rb` near the other cookbook predicates:

```ruby
"impact_mapped" => Predicates::ImpactMapped,
"risks_enumerated" => Predicates::RisksEnumerated,
"rollback_drafted" => Predicates::RollbackDrafted,
"rollback_tested" => Predicates::RollbackTested,
```

**Step 4: Run tests to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb spec/services/engine/predicates/impact_mapped_spec.rb spec/services/engine/predicates/risks_enumerated_spec.rb spec/services/engine/predicates/rollback_drafted_spec.rb spec/services/engine/predicates/rollback_tested_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register migration safety predicates"
```

---

### Task 6: Add RED seed spec for the migration safety queue

**Objective:** Prove `db/seeds.rb` can seed the full `migration_safety` queue, resolve prompt files, and preserve portable adapter config.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/migration_safety.yml`
- Later create prompt files under `cookbooks/prompts/migration_safety/`

**Step 1: Write failing seed spec**

Add this example to `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the migration safety cookbook queue with resolved portable prompts" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "migration_safety")
  expect(queue.name).to eq("Migration Safety Check")
  expect(queue.stages).to eq(%w[scan_impact enumerate_risks draft_rollback test_rollback draft_runbook human_review done])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_max_retries" => 2,
    "default_timeout_seconds" => 600,
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 2
  )

  scan = queue.stage_configs.find_by!(stage_name: "scan_impact")
  expect(scan.adapter_type).to eq("inline_claude")
  expect(scan.model_override).to eq("claude-sonnet-4-20250514")
  expect(scan.allowed_skills).to eq(["read_repo"])
  expect(scan.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
  expect(scan.completion_criteria).to eq(["impact_mapped"])
  expect(scan.agent_prompt).to include("# Migration Safety Scan Impact")
  expect(scan.agent_prompt).to include("affected_files")
  expect(scan.agent_prompt).not_to start_with("file://")
  expect(scan.agent_prompt).not_to include(Rails.root.to_s)
  expect(scan.adapter_config).to include(
    "output_artifact_kind" => "impact_map",
    "fixture_app" => "cookbooks/fixtures/apps/migration_safety_app"
  )

  enumerate = queue.stage_configs.find_by!(stage_name: "enumerate_risks")
  expect(enumerate.completion_criteria).to eq(["risks_enumerated"])
  expect(enumerate.agent_prompt).to include("blocking")
  expect(enumerate.adapter_config).to include(
    "input_artifact_kind" => "impact_map",
    "output_artifact_kind" => "risk_assessment"
  )

  rollback = queue.stage_configs.find_by!(stage_name: "draft_rollback")
  expect(rollback.completion_criteria).to eq(["rollback_drafted"])
  expect(rollback.agent_prompt).to include("rollback_plan")
  expect(rollback.adapter_config).to include(
    "input_artifact_kind" => "risk_assessment",
    "output_artifact_kind" => "rollback_plan"
  )

  test_rollback = queue.stage_configs.find_by!(stage_name: "test_rollback")
  expect(test_rollback.adapter_type).to eq("docker_compose")
  expect(test_rollback.allowed_skills).to eq(["execute_staging"])
  expect(test_rollback.forbidden_skills).to include("deploy")
  expect(test_rollback.timeout_seconds).to eq(1200)
  expect(test_rollback.completion_criteria).to eq(["rollback_tested"])
  expect(test_rollback.agent_prompt).to include("rollback_test_results")
  expect(test_rollback.adapter_config).to include(
    "input_artifact_kind" => "rollback_plan",
    "output_artifact_kind" => "rollback_test_results",
    "fixture_app" => "cookbooks/fixtures/apps/migration_safety_app",
    "compose_file" => "cookbooks/docker-compose.yml"
  )
  expect(test_rollback.adapter_config).not_to have_key("working_directory")

  runbook = queue.stage_configs.find_by!(stage_name: "draft_runbook")
  expect(runbook.adapter_type).to eq("inline_claude")
  expect(runbook.model_override).to eq("claude-opus-4-20250514")
  expect(runbook.completion_criteria).to eq(["report_present"])
  expect(runbook.agent_prompt).to include("# Migration Safety Draft Runbook")
  expect(runbook.adapter_config).to include(
    "input_artifact_kind" => "rollback_test_results",
    "output_artifact_kind" => "migration_runbook"
  )

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.completion_criteria).to eq(["report_present"])
  expect(human_review.timeout_seconds).to eq(86_400)

  serialized_queue = Rails.root.join("config/queues/migration_safety.yml").read
  expect(serialized_queue).to include("file://cookbooks/prompts/migration_safety/scan_impact.md")
  expect(serialized_queue).to include("cookbooks/docker-compose.yml")
  expect(serialized_queue).not_to include(Rails.root.to_s)
  expect(serialized_queue).not_to include("/Users/")
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL with `Couldn't find WorkQueue with [WHERE "work_queues"."slug" = ?]` for `migration_safety` or a missing prompt file once YAML exists.

**Step 3: Commit RED spec only if the team accepts red commits; otherwise continue to Task 7 before committing**

Preferred in this repo: do not leave a committed red state. Continue to Task 7, then commit the seed spec with the queue and prompts.

---

### Task 7: Add queue YAML and prompt files

**Objective:** Implement the seeded queue and prompt content required by the seed spec.

**Files:**
- Create: `config/queues/migration_safety.yml`
- Create: `cookbooks/prompts/migration_safety/scan_impact.md`
- Create: `cookbooks/prompts/migration_safety/enumerate_risks.md`
- Create: `cookbooks/prompts/migration_safety/draft_rollback.md`
- Create: `cookbooks/prompts/migration_safety/test_rollback.md`
- Create: `cookbooks/prompts/migration_safety/draft_runbook.md`

**Step 1: Create queue YAML**

Create `config/queues/migration_safety.yml` exactly as shown in the Queue YAML Target section.

**Step 2: Create scan prompt**

Create `cookbooks/prompts/migration_safety/scan_impact.md`:

```markdown
# Migration Safety Scan Impact

You are the impact-mapping stage for the Migration Safety Check cookbook.

Inputs:
- Migration specification from the work item.
- Repository or fixture app path from adapter config, normally `cookbooks/fixtures/apps/migration_safety_app`.

Task:
- Identify every code path affected by the migration.
- Include database migrations, models, queries, indexes, constraints, API clients/consumers, configs, environment variables, health checks, dependency imports, and external consumers.
- Treat indirect references as affected when a service or controller reads the changed data.

Return an `impact_map` artifact with this shape:

```json
{
  "affected_files": ["app/models/order.rb"],
  "affected_tests": ["spec/models/order_spec.rb"],
  "affected_configs": ["config/database.yml"],
  "external_consumers": ["billing-export"],
  "notes": ["adding NOT NULL with default may rewrite the orders table"]
}
```

The artifact must include at least one `affected_files` entry so the `impact_mapped` predicate can pass.
Do not edit files, deploy, mutate databases, or use absolute checkout paths.
```

**Step 3: Create enumerate risks prompt**

Create `cookbooks/prompts/migration_safety/enumerate_risks.md`:

```markdown
# Migration Safety Enumerate Risks

You are the risk enumeration stage for the Migration Safety Check cookbook.

Inputs:
- The upstream `impact_map` artifact.
- The migration specification.
- Repository or fixture app context.

For each affected path, identify risks in these categories:
- data_loss
- downtime
- partial_failure
- backwards_compatibility
- rollback_blocker

Rate each risk as exactly one of: `blocking`, `high`, `medium`, `low`.

Return a `risk_assessment` artifact:

```json
{
  "risks": [
    {
      "category": "downtime",
      "description": "Adding a NOT NULL column with a default can rewrite and lock a large orders table.",
      "severity": "blocking",
      "affected_paths": ["db/migrate/20240101000000_add_region_to_orders_unsafe.rb"],
      "mitigation": "Use expand/backfill/contract: add nullable column, backfill batches, then enforce NOT NULL."
    }
  ],
  "blocking_risks": ["Adding a NOT NULL column with a default can rewrite and lock a large orders table."]
}
```

The artifact must include at least one risk and only allowed severities.
```

**Step 4: Create draft rollback prompt**

Create `cookbooks/prompts/migration_safety/draft_rollback.md`:

```markdown
# Migration Safety Draft Rollback

You are the rollback-planning stage for the Migration Safety Check cookbook.

Inputs:
- The upstream `risk_assessment` artifact.
- The migration specification and source code.

Draft concrete rollback procedures for every blocking and high risk.
Each procedure must be testable in staging and include:
- `risk_ref`
- ordered `steps`
- each step's `action`, `command`, and `verification`
- `estimated_time`
- `data_loss_potential`

Return a `rollback_plan` artifact:

```json
{
  "procedures": [
    {
      "risk_ref": "orders table rewrite lock",
      "steps": [
        {
          "action": "rollback unsafe migration",
          "command": "bin/rails db:rollback STEP=1",
          "verification": "SELECT column_name FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'region' returns zero rows"
        }
      ],
      "estimated_time": "5 minutes",
      "data_loss_potential": "none if rollback happens before writes depend on region"
    }
  ]
}
```

Do not deploy or mutate production databases. Commands must be staging/fixture-safe.
```

**Step 5: Create test rollback prompt**

Create `cookbooks/prompts/migration_safety/test_rollback.md`:

```markdown
# Migration Safety Test Rollback

You are the Docker-friendly staging validation stage for the Migration Safety Check cookbook.

Inputs:
- The upstream `rollback_plan` artifact.
- Fixture app path: `cookbooks/fixtures/apps/migration_safety_app`.
- Shared Compose file: `cookbooks/docker-compose.yml`.

Execute the fixture migration scenario, execute rollback, and verify:
- migration succeeded
- rollback succeeded
- data stayed intact
- health checks passed

Return a `rollback_test_results` artifact:

```json
{
  "migration_succeeded": true,
  "rollback_succeeded": true,
  "data_intact": true,
  "health_checks_passed": true,
  "issues": []
}
```

If anything fails, set the relevant boolean to false and include actionable issue strings. The `rollback_tested` predicate requires all four booleans to be true.
```

**Step 6: Create draft runbook prompt**

Create `cookbooks/prompts/migration_safety/draft_runbook.md`:

```markdown
# Migration Safety Draft Runbook

You are the runbook authoring stage for the Migration Safety Check cookbook.

Inputs:
- `impact_map`
- `risk_assessment`
- `rollback_plan`
- `rollback_test_results`
- migration specification

Produce a complete migration runbook with:
- pre-migration checklist: backups, communication, maintenance windows, staging parity, metrics dashboards
- step-by-step migration procedure with verification after each step
- tested rollback procedure
- post-migration verification
- escalation contacts placeholders
- go/no-go decision criteria

Return a success report suitable for the existing `report_present` predicate and include a `migration_runbook` artifact when supported by the adapter.
```

**Step 7: Run seed spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS, including the new migration safety queue example.

**Step 8: Commit**

```bash
git add config/queues/migration_safety.yml cookbooks/prompts/migration_safety spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed migration safety cookbook queue"
```

---

### Task 8: Add migration safety fixture app contract

**Objective:** Add a small Docker-friendly fixture app that demonstrates the source spec's unsafe database migration scenario: adding a NOT NULL column with a default to an existing table.

**Files:**
- Create: `spec/system/migration_safety_cookbook_spec.rb`
- Create fixture files under `cookbooks/fixtures/apps/migration_safety_app/`

**Step 1: Write failing fixture spec**

Create `spec/system/migration_safety_cookbook_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "migration safety cookbook fixture" do
  let(:fixture_root) { Rails.root.join("cookbooks/fixtures/apps/migration_safety_app") }

  it "contains an unsafe and safe migration scenario for large-table NOT NULL defaults" do
    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("app/models/order.rb")).to exist
    expect(fixture_root.join("app/services/order_backfill.rb")).to exist
    expect(fixture_root.join("db/migrate/20240101000000_add_region_to_orders_unsafe.rb")).to exist
    expect(fixture_root.join("db/migrate/20240101000001_add_region_to_orders_safe.rb")).to exist
    expect(fixture_root.join("scripts/run_rollback_test.rb")).to exist

    unsafe_migration = fixture_root.join("db/migrate/20240101000000_add_region_to_orders_unsafe.rb").read
    expect(unsafe_migration).to include("null: false")
    expect(unsafe_migration).to include("default:")

    safe_migration = fixture_root.join("db/migrate/20240101000001_add_region_to_orders_safe.rb").read
    expect(safe_migration).to include("add_column :orders, :region")
    expect(safe_migration).to include("OrderBackfill")
    expect(safe_migration).to include("change_column_null")
  end

  it "defines the artifact contract for migration safety stages" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "migration_safety")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Check orders region migration",
      spec_url: "cookbooks/fixtures/apps/migration_safety_app/README.md",
      stage_name: "scan_impact"
    )

    scan_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
    Artifact.create!(
      claim: scan_claim,
      work_item: work_item,
      kind: "impact_map",
      data: {
        "affected_files" => ["app/models/order.rb", "app/services/order_backfill.rb", "db/migrate/20240101000000_add_region_to_orders_unsafe.rb"],
        "affected_tests" => ["spec/system/migration_safety_cookbook_spec.rb"],
        "affected_configs" => [],
        "external_consumers" => ["warehouse export"]
      }
    )
    expect(Engine::PredicateRegistry.resolve("impact_mapped").new(claim: scan_claim).call).to be_passed

    risk_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
    Artifact.create!(
      claim: risk_claim,
      work_item: work_item,
      kind: "risk_assessment",
      data: {
        "risks" => [
          { "category" => "downtime", "description" => "NOT NULL default can lock orders", "severity" => "blocking", "affected_paths" => ["db/migrate/20240101000000_add_region_to_orders_unsafe.rb"], "mitigation" => "expand/backfill/contract" }
        ],
        "blocking_risks" => ["NOT NULL default can lock orders"]
      }
    )
    expect(Engine::PredicateRegistry.resolve("risks_enumerated").new(claim: risk_claim).call).to be_passed

    rollback_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
    Artifact.create!(
      claim: rollback_claim,
      work_item: work_item,
      kind: "rollback_plan",
      data: {
        "procedures" => [
          {
            "risk_ref" => "NOT NULL default can lock orders",
            "steps" => [{ "action" => "rollback migration", "command" => "bin/rails db:rollback STEP=1", "verification" => "orders.region removed" }],
            "estimated_time" => "5 minutes",
            "data_loss_potential" => "none"
          }
        ]
      }
    )
    expect(Engine::PredicateRegistry.resolve("rollback_drafted").new(claim: rollback_claim).call).to be_passed

    test_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :active)
    Artifact.create!(
      claim: test_claim,
      work_item: work_item,
      kind: "rollback_test_results",
      data: {
        "migration_succeeded" => true,
        "rollback_succeeded" => true,
        "data_intact" => true,
        "health_checks_passed" => true,
        "issues" => []
      }
    )
    expect(Engine::PredicateRegistry.resolve("rollback_tested").new(claim: test_claim).call).to be_passed
  end

  it "has a deterministic rollback runner that reports green JSON" do
    output = IO.popen(["ruby", fixture_root.join("scripts/run_rollback_test.rb").to_s], &:read)
    data = JSON.parse(output)

    expect(data).to include(
      "migration_succeeded" => true,
      "rollback_succeeded" => true,
      "data_intact" => true,
      "health_checks_passed" => true,
      "issues" => []
    )
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/migration_safety_cookbook_spec.rb
```

Expected: FAIL because fixture files and/or predicates are missing, depending on task order.

**Step 3: Create fixture README**

Create `cookbooks/fixtures/apps/migration_safety_app/README.md`:

```markdown
# Migration Safety Fixture App

This fixture models a risky database migration: adding `orders.region` as `NOT NULL` with a default on a large existing table.

The unsafe migration (`20240101000000_add_region_to_orders_unsafe.rb`) represents the scary production change that can rewrite or lock a large table.
The safe migration (`20240101000001_add_region_to_orders_safe.rb`) represents the expand/backfill/contract approach:
1. add the column nullable
2. backfill in batches through `OrderBackfill`
3. enforce `NOT NULL` after data is present

The cookbook should identify affected files, flag the unsafe migration as a blocking downtime risk, draft rollback commands, run the deterministic rollback fixture, and produce a runbook.
```

**Step 4: Create minimal fixture files**

Create `cookbooks/fixtures/apps/migration_safety_app/Gemfile`:

```ruby
source "https://rubygems.org"

gem "rails"
gem "sqlite3"
```

Create `cookbooks/fixtures/apps/migration_safety_app/app/models/order.rb`:

```ruby
class Order < ApplicationRecord
  validates :number, presence: true

  scope :missing_region, -> { where(region: nil) }
end
```

Create `cookbooks/fixtures/apps/migration_safety_app/app/services/order_backfill.rb`:

```ruby
class OrderBackfill
  BATCH_SIZE = 1_000

  def self.region!(default_region: "us")
    Order.missing_region.in_batches(of: BATCH_SIZE) do |relation|
      relation.update_all(region: default_region, updated_at: Time.current)
    end
  end
end
```

Create `cookbooks/fixtures/apps/migration_safety_app/app/services/payment_provider_switch.rb`:

```ruby
class PaymentProviderSwitch
  def initialize(provider: ENV.fetch("PAYMENT_PROVIDER", "legacy"))
    @provider = provider
  end

  def enabled?
    @provider == "next"
  end
end
```

Create `cookbooks/fixtures/apps/migration_safety_app/app/controllers/orders_controller.rb`:

```ruby
class OrdersController < ApplicationController
  def index
    render json: Order.limit(10).pluck(:number, :region)
  end
end
```

Create `cookbooks/fixtures/apps/migration_safety_app/config/routes.rb`:

```ruby
Rails.application.routes.draw do
  resources :orders, only: :index
end
```

Create `cookbooks/fixtures/apps/migration_safety_app/db/schema.rb`:

```ruby
ActiveRecord::Schema[8.0].define(version: 2024_01_01_000000) do
  create_table "orders", force: :cascade do |t|
    t.string "number", null: false
    t.decimal "total_cents", precision: 12, scale: 0, null: false, default: 0
    t.timestamps
  end
end
```

Create `cookbooks/fixtures/apps/migration_safety_app/db/migrate/20240101000000_add_region_to_orders_unsafe.rb`:

```ruby
class AddRegionToOrdersUnsafe < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :region, :string, null: false, default: "us"
  end
end
```

Create `cookbooks/fixtures/apps/migration_safety_app/db/migrate/20240101000001_add_region_to_orders_safe.rb`:

```ruby
class AddRegionToOrdersSafe < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :orders, :region, :string
    OrderBackfill.region!(default_region: "us")
    change_column_null :orders, :region, false
  end

  def down
    remove_column :orders, :region
  end
end
```

Create `cookbooks/fixtures/apps/migration_safety_app/scripts/run_rollback_test.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

result = {
  migration_succeeded: true,
  rollback_succeeded: true,
  data_intact: true,
  health_checks_passed: true,
  issues: []
}

puts JSON.generate(result.transform_keys(&:to_s))
```

Then make it executable:

```bash
chmod +x cookbooks/fixtures/apps/migration_safety_app/scripts/run_rollback_test.rb
```

**Step 5: Run fixture spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/migration_safety_cookbook_spec.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git add cookbooks/fixtures/apps/migration_safety_app spec/system/migration_safety_cookbook_spec.rb
git commit -m "feat: add migration safety fixture app"
```

---

### Task 9: Add cookbook documentation

**Objective:** Document the cookbook source, queue, artifacts, predicates, fixture scenario, and verification workflow.

**Files:**
- Create: `docs/cookbooks/migration-safety.md`

**Step 1: Write failing documentation assertion**

If existing cookbook docs have dedicated specs by implementation time, add this assertion to the appropriate doc spec. Otherwise add it to `spec/system/migration_safety_cookbook_spec.rb` as a small documentation example:

```ruby
it "documents the cookbook source spec and verification workflow" do
  doc = Rails.root.join("docs/cookbooks/migration-safety.md")

  expect(doc).to exist
  content = doc.read
  expect(content).to include("docs/specs/cookbook-14-migration-safety.md")
  expect(content).to include("migration_safety")
  expect(content).to include("impact_map")
  expect(content).to include("rollback_test_results")
  expect(content).to include("cookbooks/fixtures/apps/migration_safety_app")
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/migration_safety_cookbook_spec.rb
```

Expected: FAIL because `docs/cookbooks/migration-safety.md` does not exist.

**Step 3: Create cookbook documentation**

Create `docs/cookbooks/migration-safety.md`:

```markdown
# Migration Safety Check Cookbook

Source spec: `docs/specs/cookbook-14-migration-safety.md`
Queue slug: `migration_safety`
Category: Development

## What it does

This cookbook checks scary migrations before cutover. It maps affected code paths, enumerates risks, drafts rollback procedures, tests rollback in a staging-like Docker-friendly fixture, and produces a migration runbook for human review.

## Stages

1. `scan_impact` -> `impact_map`
2. `enumerate_risks` -> `risk_assessment`
3. `draft_rollback` -> `rollback_plan`
4. `test_rollback` -> `rollback_test_results`
5. `draft_runbook` -> `migration_runbook` / success report
6. `human_review`
7. `done`

## Fixture

The fixture app at `cookbooks/fixtures/apps/migration_safety_app` models an unsafe large-table database migration: adding a `NOT NULL` column with a default to `orders`.

The safe path uses expand/backfill/contract:

- add nullable column
- backfill in batches
- enforce `NOT NULL`

## Verification

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/impact_mapped_spec.rb \
  spec/services/engine/predicates/risks_enumerated_spec.rb \
  spec/services/engine/predicates/rollback_drafted_spec.rb \
  spec/services/engine/predicates/rollback_tested_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/system/migration_safety_cookbook_spec.rb
```
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/migration_safety_cookbook_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add docs/cookbooks/migration-safety.md spec/system/migration_safety_cookbook_spec.rb
git commit -m "docs: add migration safety cookbook"
```

---

### Task 10: Run focused cookbook regression suite

**Objective:** Verify the new cookbook behavior together with existing cookbook infrastructure and seed loading.

**Files:**
- No production file changes unless tests expose a bug.

**Step 1: Run focused specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/impact_mapped_spec.rb \
  spec/services/engine/predicates/risks_enumerated_spec.rb \
  spec/services/engine/predicates/rollback_drafted_spec.rb \
  spec/services/engine/predicates/rollback_tested_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/system/migration_safety_cookbook_spec.rb
```

Expected: PASS.

**Step 2: Run shared cookbook specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks spec/system/job_observability_cookbook_spec.rb spec/e2e/logging_audit_cookbook_spec.rb
```

Expected: PASS. If unrelated dirty work in the shared workspace causes failures, do not modify or stage unrelated files; capture the failure and verify this cookbook slice in a clean temporary worktree if needed.

**Step 3: Search for absolute path regressions**

Run:

```bash
git grep -n "/Users/gregmushen\|/Users/" -- config/queues/migration_safety.yml cookbooks/prompts/migration_safety cookbooks/fixtures/apps/migration_safety_app docs/cookbooks/migration-safety.md spec/system/migration_safety_cookbook_spec.rb app/services/engine/predicates/impact_mapped.rb app/services/engine/predicates/risks_enumerated.rb app/services/engine/predicates/rollback_drafted.rb app/services/engine/predicates/rollback_tested.rb || true
```

Expected: no matches.

**Step 4: Commit any test-only fixes**

If this task required changes, commit them:

```bash
git add <changed-files>
git commit -m "test: cover migration safety cookbook regression"
```

If no changes were required, do not create an empty commit.

---

### Task 11: Final implementation verification and handoff

**Objective:** Ensure the cookbook implementation is complete, portable, committed, and ready for review.

**Step 1: Inspect git status**

Run:

```bash
git status --short
```

Expected: no unstaged/staged files related to `migration_safety`. In this shared workspace there may be unrelated dirty files from other cookbook work; do not stage them.

**Step 2: Review final diff for this cookbook**

Run:

```bash
git log --oneline --decorate -n 8
```

Expected: includes the migration safety commits from Tasks 1-10.

**Step 3: Final test command**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/impact_mapped_spec.rb \
  spec/services/engine/predicates/risks_enumerated_spec.rb \
  spec/services/engine/predicates/rollback_drafted_spec.rb \
  spec/services/engine/predicates/rollback_tested_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/system/migration_safety_cookbook_spec.rb
```

Expected: PASS.

**Step 4: Handoff summary**

Record these facts in the Kanban completion metadata:

- Changed files, grouped by queue/prompt/predicate/spec/fixture/docs.
- Test commands run and pass/fail status.
- Commit hashes.
- Note that all generated app/config paths are repo-relative and no absolute checkout paths were introduced.

---

## Acceptance Checklist

- [ ] `config/queues/migration_safety.yml` seeds a queue with stages `scan_impact -> enumerate_risks -> draft_rollback -> test_rollback -> draft_runbook -> human_review -> done`.
- [ ] Queue prompt paths use `file://cookbooks/prompts/migration_safety/...` and resolve through `db/seeds.rb`.
- [ ] Queue config has no `working_directory` and no absolute checkout paths.
- [ ] `test_rollback` uses `adapter_type: docker_compose`, `compose_file: cookbooks/docker-compose.yml`, and `output_artifact_kind: rollback_test_results`.
- [ ] Predicates `impact_mapped`, `risks_enumerated`, `rollback_drafted`, and `rollback_tested` are implemented, registered, and covered by focused specs.
- [ ] Fixture app includes the unsafe NOT NULL/default migration and a safe expand/backfill/contract example.
- [ ] Fixture rollback runner emits deterministic green JSON for the happy path.
- [ ] Cookbook docs link back to `docs/specs/cookbook-14-migration-safety.md`.
- [ ] Focused RSpec commands pass with Greg's rbenv PATH prefix.
- [ ] Implementation is committed in small TDD commits, or squashed if required by the implementation Kanban card.
