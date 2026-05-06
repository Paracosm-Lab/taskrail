# Infrastructure Drift Detection Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `infrastructure_drift` cookbook queue so StupidClaw can collect read-only environment configuration snapshots, diff staging/production drift, classify intentional/accidental/dangerous/stale differences, draft a human-executed sync plan, and stop at a review gate.

**Architecture:** Follow the existing cookbook pattern: portable queue YAML under `config/queues/`, long prompts resolved from repo-relative `file://prompts/...` paths by `db/seeds.rb`, artifact-backed predicates under `Engine::Predicates`, registry and seed specs, and a deterministic fixture under `test/fixtures/apps/infrastructure_drift/`. The implementation is read-only/advisory: fixture files and shell smoke scripts prove collection/diff behavior without touching live infrastructure.

**Tech Stack:** Rails, RSpec, YAML queue seeds, `WorkQueue`/`StageConfig`/`Claim`/`Artifact`, `Engine::PredicateRegistry`, shell_script and inline Claude adapters, fake human-review stages, Docker Compose/YAML fixture files, rbenv on Greg's Mac.

**Source Spec:** `docs/specs/cookbook-21-infrastructure-drift.md`

---

## Source Requirements Summary

Implement cookbook-21, `Infrastructure Drift Detection`, category `Live DevOps`.

Queue stages:

`collect_configs -> diff_environments -> classify_drift -> draft_sync_plan -> human_review -> done`

Required artifact predicates:

- `configs_collected`: passes when an `environment_configs` artifact contains at least two named environments.
- `diff_produced`: passes when an `environment_diff` artifact contains comparisons and a numeric `total_diffs`.
- `drift_classified`: passes when a `drift_classification` artifact contains drift entries and count fields.
- `sync_planned`: passes when a `sync_plan` artifact contains one or more sync actions and an ordered list.

Safety requirements:

- Collection is read-only. It reads config files, manifests, env examples, nginx snippets, Docker Compose files, and optional API snapshots; it does not mutate infrastructure.
- Prompts and queue config must forbid deploys, config writes, database changes, secret disclosure, and live infrastructure mutation.
- Secret/environment values in artifacts must be masked when sensitive.
- Human review applies sync actions manually, one environment at a time, with verification between steps.

---

## Current Codebase Context

Relevant existing patterns inspected while writing this plan:

- `db/seeds.rb` already loads `config/queues/*.yml`, resolves `agent_prompt: file://...` with `Rails.root.join(relative_path).read`, and upserts queue/stage records. Do not modify it unless a RED spec proves a missing behavior.
- `config/queues/credential_rotation.yml`, `security_scan.yml`, `migration_safety.yml`, and `dependency_upgrade.yml` show recent cookbook queue style: portable prompt paths, no hardcoded checkout path, no `working_directory`, explicit `adapter_config.output_artifact_kind`, and fake review/done gates.
- `app/services/engine/predicates/*` predicates return actionable evidence such as `{ artifact_id: artifact.id, ... }` and precise failure reasons.
- `app/services/engine/predicate_registry.rb` maps predicate names to classes; `spec/services/engine/predicate_registry_spec.rb` asserts known mappings.
- `spec/models/work_queue_seed_spec.rb` is the place for seed/config/prompt/path-portability assertions.
- Recent workflow integration specs create real `WorkQueue`, `WorkItem`, `Claim`, and `Artifact` records and resolve predicates through `Engine::PredicateRegistry` without calling real LLMs or live services.
- Fixture apps are now commonly under `test/fixtures/apps/<cookbook_name>/`; use `test/fixtures/apps/infrastructure_drift/` for this cookbook.

Global implementation rules:

- Strict TDD: write each failing spec first, run it and verify the expected RED failure, implement the smallest change, rerun focused specs, then run broader relevant specs.
- Use Greg's rbenv command shape for every RSpec command:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Do not hardcode `/Users/gregmushen/work/code/stupidclaw`, `Rails.root.to_s`, or any user-local absolute path in queue YAML, prompts, fixtures, specs, or implementation code.
- Queue YAML should use repo-relative prompt/fixture paths and omit `working_directory`.
- Commit after each implementation task unless the Kanban implementation card explicitly requests one final commit. If it does, squash before completion.
- The planning task itself commits only this file with `git commit -m "docs: plan cookbook 21 infrastructure-drift"`.

---

## Files to Create or Modify During Implementation

Create:

- `config/queues/infrastructure_drift.yml`
- `prompts/drift_collect.md`
- `prompts/drift_diff.md`
- `prompts/drift_classify.md`
- `prompts/drift_sync_plan.md`
- `app/services/engine/predicates/configs_collected.rb`
- `app/services/engine/predicates/diff_produced.rb`
- `app/services/engine/predicates/drift_classified.rb`
- `app/services/engine/predicates/sync_planned.rb`
- `spec/services/engine/predicates/configs_collected_spec.rb`
- `spec/services/engine/predicates/diff_produced_spec.rb`
- `spec/services/engine/predicates/drift_classified_spec.rb`
- `spec/services/engine/predicates/sync_planned_spec.rb`
- `spec/fixtures/infrastructure_drift_fixture_spec.rb`
- `spec/services/engine/infrastructure_drift_workflow_integration_spec.rb`
- `test/fixtures/apps/infrastructure_drift/README.md`
- `test/fixtures/apps/infrastructure_drift/docker-compose.staging.yml`
- `test/fixtures/apps/infrastructure_drift/docker-compose.production.yml`
- `test/fixtures/apps/infrastructure_drift/env/.env.staging.example`
- `test/fixtures/apps/infrastructure_drift/env/.env.production.example`
- `test/fixtures/apps/infrastructure_drift/nginx/staging.conf`
- `test/fixtures/apps/infrastructure_drift/nginx/production.conf`
- `test/fixtures/apps/infrastructure_drift/terraform/staging.tfvars`
- `test/fixtures/apps/infrastructure_drift/terraform/production.tfvars`
- `test/fixtures/apps/infrastructure_drift/bin/collect-drift-fixture`
- `docs/cookbooks/infrastructure-drift.md`

Modify:

- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Do not modify unless a failing spec proves it is necessary:

- `db/seeds.rb`
- Shared adapters (`Adapters::ShellScriptAdapter`, `Adapters::InlineClaudeAdapter`)
- Shared pipe/cross-queue engine code; spawn/follow-up intent can be prompt/config metadata for this slice.
- Existing live project Docker Compose files outside the fixture.

---

## Queue YAML Target

Create `config/queues/infrastructure_drift.yml` with portable prompt paths and no `working_directory`:

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
    forbidden_skills: [edit_files, deploy, mutate_infrastructure, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [configs_collected]
    agent_prompt: file://prompts/drift_collect.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: environment_configs
      fixture_app: test/fixtures/apps/infrastructure_drift
      read_only: true
      commands:
        - name: infrastructure drift fixture collection
          artifact: environment_configs
          command: ruby test/fixtures/apps/infrastructure_drift/bin/collect-drift-fixture
  diff_environments:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_infrastructure, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [diff_produced]
    agent_prompt: file://prompts/drift_diff.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: environment_configs
      output_artifact_kind: environment_diff
      fixture_app: test/fixtures/apps/infrastructure_drift
      read_only: true
  classify_drift:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_infrastructure, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [drift_classified]
    agent_prompt: file://prompts/drift_classify.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: environment_diff
      secondary_input_artifact_kind: environment_configs
      output_artifact_kind: drift_classification
      read_only: true
  draft_sync_plan:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_infrastructure, mutate_database]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [sync_planned]
    agent_prompt: file://prompts/drift_sync_plan.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: drift_classification
      secondary_input_artifact_kind: environment_configs
      output_artifact_kind: sync_plan
      read_only: true
      spawn_targets:
        dangerous_security_drift: security_scan
        missing_deployment_automation: development
        stale_deprecated_service: dead_code_removal
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: [deploy, mutate_infrastructure, mutate_database]
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review drift report and sync plan. Apply changes manually one environment at a time, with verification and rollback between each change.
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

- `read_only: true` is an adapter/config safety hint and a seed-spec assertion; do not add adapter behavior unless a later failing spec requires it.
- The fixture collection command is a deterministic local Ruby script that prints a normalized JSON-like artifact shape for tests. It must not call Docker, Terraform, kubectl, cloud CLIs, or external APIs.
- `spawn_targets` documents follow-up intent only. Do not implement new cross-queue spawning in this slice unless separately specified.

---

### Task 1: Add RED specs for infrastructure drift predicates

**Objective:** Define artifact predicate behavior before production predicate classes exist.

**Files:**

- Create: `spec/services/engine/predicates/configs_collected_spec.rb`
- Create: `spec/services/engine/predicates/diff_produced_spec.rb`
- Create: `spec/services/engine/predicates/drift_classified_spec.rb`
- Create: `spec/services/engine/predicates/sync_planned_spec.rb`
- Later create predicate classes under `app/services/engine/predicates/`

**Step 1: Write failing tests**

Use this helper shape in each predicate spec with randomized slugs:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ConfigsCollected do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Infrastructure Drift #{SecureRandom.hex(4)}",
      slug: "infrastructure-drift-predicate-#{SecureRandom.hex(4)}",
      stages: %w[collect_configs done]
    )
    queue.stage_configs.create!(stage_name: "collect_configs", adapter_type: "fake")
    item = WorkItem.create!(title: "Collect config", spec_url: "fixture", work_queue: queue, stage_name: "collect_configs")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with environment count when environment_configs has at least two environments" do
    claim = build_claim(artifacts: [
      {
        kind: "environment_configs",
        data: {
          "environments" => {
            "staging" => { "services" => [{ "name" => "web" }] },
            "production" => { "services" => [{ "name" => "web" }, { "name" => "redis" }] }
          }
        }
      }
    ])
    artifact = claim.artifacts.find_by!(kind: "environment_configs")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, environment_count: 2 })
  end

  it "fails when no environment_configs artifact exists" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing environment_configs artifact")
  end

  it "fails when fewer than two environments are present" do
    claim = build_claim(artifacts: [
      { kind: "environment_configs", data: { "environments" => { "staging" => {} } } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("environment_configs artifact must include at least two environments")
  end
end
```

Add equivalent focused specs:

- `DiffProduced`: require `kind: "environment_diff"`, `comparisons` array present, and numeric `total_diffs`; evidence `{ artifact_id:, comparison_count:, total_diffs: }`; fail reasons `"missing environment_diff artifact"` and `"environment_diff artifact must include comparisons and total_diffs"`.
- `DriftClassified`: require `kind: "drift_classification"`, `drifts` array present, and numeric `accidental_count` and `dangerous_count`; evidence `{ artifact_id:, drift_count:, accidental_count:, dangerous_count: }`; fail reasons `"missing drift_classification artifact"` and `"drift_classification artifact must include drifts and count fields"`.
- `SyncPlanned`: require `kind: "sync_plan"`, non-empty `actions` array, and `sync_order` array; evidence `{ artifact_id:, action_count: }`; fail reasons `"missing sync_plan artifact"` and `"sync_plan artifact must include actions and sync_order"`.

**Step 2: Run RED specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/configs_collected_spec.rb \
  spec/services/engine/predicates/diff_produced_spec.rb \
  spec/services/engine/predicates/drift_classified_spec.rb \
  spec/services/engine/predicates/sync_planned_spec.rb
```

Expected: FAIL with uninitialized predicate constants.

**Step 3: Implement minimal predicates**

Create one class per predicate. Use `claim.artifacts.where(kind: ...).first` and return `PredicateResult.pass(evidence: ...)` or `PredicateResult.fail(reason: ...)`. Keep validation limited to the tested artifact shape.

Example for `configs_collected`:

```ruby
module Engine
  module Predicates
    class ConfigsCollected
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "environment_configs").first
        return PredicateResult.fail(reason: "missing environment_configs artifact") unless artifact

        environments = artifact.data.fetch("environments", {})
        if environments.keys.size < 2
          return PredicateResult.fail(reason: "environment_configs artifact must include at least two environments")
        end

        PredicateResult.pass(evidence: { artifact_id: artifact.id, environment_count: environments.keys.size })
      end
    end
  end
end
```

**Step 4: Run GREEN specs**

Run the same focused predicate command. Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/configs_collected.rb \
  app/services/engine/predicates/diff_produced.rb \
  app/services/engine/predicates/drift_classified.rb \
  app/services/engine/predicates/sync_planned.rb \
  spec/services/engine/predicates/configs_collected_spec.rb \
  spec/services/engine/predicates/diff_produced_spec.rb \
  spec/services/engine/predicates/drift_classified_spec.rb \
  spec/services/engine/predicates/sync_planned_spec.rb
git commit -m "feat: add infrastructure drift predicates"
```

---

### Task 2: Register infrastructure drift predicates

**Objective:** Make queue completion criteria resolvable by `Engine::PredicateRegistry`.

**Files:**

- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing registry expectations**

Add to the known predicate example:

```ruby
expect(described_class.resolve("configs_collected")).to eq(Engine::Predicates::ConfigsCollected)
expect(described_class.resolve("diff_produced")).to eq(Engine::Predicates::DiffProduced)
expect(described_class.resolve("drift_classified")).to eq(Engine::Predicates::DriftClassified)
expect(described_class.resolve("sync_planned")).to eq(Engine::Predicates::SyncPlanned)
```

**Step 2: Run RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with unknown predicate(s).

**Step 3: Add registry entries**

Add the four mappings to `PREDICATES` near the other cookbook artifact predicates.

**Step 4: Run GREEN**

Run the same registry spec. Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register infrastructure drift predicates"
```

---

### Task 3: Add RED seed spec for the infrastructure drift queue

**Objective:** Prove the queue seeds all stages, resolves prompts, keeps paths portable, uses read-only adapter config, and has the correct review gate.

**Files:**

- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/infrastructure_drift.yml`
- Later create: `prompts/drift_collect.md`
- Later create: `prompts/drift_diff.md`
- Later create: `prompts/drift_classify.md`
- Later create: `prompts/drift_sync_plan.md`

**Step 1: Write failing seed example**

Append an example to `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the infrastructure drift queue with resolved read-only prompts" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "infrastructure_drift")
  expect(queue.name).to eq("Infrastructure Drift Detection")
  expect(queue.stages).to eq(%w[collect_configs diff_environments classify_drift draft_sync_plan human_review done])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_max_retries" => 2,
    "default_timeout_seconds" => 600,
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 0
  )

  collect = queue.stage_configs.find_by!(stage_name: "collect_configs")
  expect(collect.adapter_type).to eq("shell_script")
  expect(collect.allowed_skills).to include("read_repo", "query_infrastructure")
  expect(collect.forbidden_skills).to include("edit_files", "deploy", "mutate_infrastructure", "mutate_database")
  expect(collect.completion_criteria).to eq(%w[configs_collected])
  expect(collect.agent_prompt).to include("# Infrastructure Drift: Collect Configs")
  expect(collect.agent_prompt).to include("READ-ONLY")
  expect(collect.agent_prompt).not_to start_with("file://")
  expect(collect.adapter_config).to include(
    "output_artifact_kind" => "environment_configs",
    "fixture_app" => "test/fixtures/apps/infrastructure_drift",
    "read_only" => true
  )
  expect(collect.adapter_config.fetch("commands")).to contain_exactly(
    include(
      "name" => "infrastructure drift fixture collection",
      "artifact" => "environment_configs",
      "command" => "ruby test/fixtures/apps/infrastructure_drift/bin/collect-drift-fixture"
    )
  )
  expect(collect.adapter_config).not_to have_key("working_directory")

  diff = queue.stage_configs.find_by!(stage_name: "diff_environments")
  expect(diff.adapter_type).to eq("inline_claude")
  expect(diff.model_override).to eq("claude-haiku-4-5-20251001")
  expect(diff.completion_criteria).to eq(%w[diff_produced])
  expect(diff.agent_prompt).to include("# Infrastructure Drift: Diff Environments")
  expect(diff.agent_prompt).to include("mask sensitive values")
  expect(diff.adapter_config).to include(
    "input_artifact_kind" => "environment_configs",
    "output_artifact_kind" => "environment_diff",
    "read_only" => true
  )

  classify = queue.stage_configs.find_by!(stage_name: "classify_drift")
  expect(classify.adapter_type).to eq("inline_claude")
  expect(classify.model_override).to eq("claude-sonnet-4-20250514")
  expect(classify.completion_criteria).to eq(%w[drift_classified])
  expect(classify.agent_prompt).to include("intentional")
  expect(classify.agent_prompt).to include("accidental")
  expect(classify.agent_prompt).to include("dangerous")
  expect(classify.agent_prompt).to include("stale")
  expect(classify.adapter_config).to include(
    "input_artifact_kind" => "environment_diff",
    "secondary_input_artifact_kind" => "environment_configs",
    "output_artifact_kind" => "drift_classification",
    "read_only" => true
  )

  sync = queue.stage_configs.find_by!(stage_name: "draft_sync_plan")
  expect(sync.adapter_type).to eq("inline_claude")
  expect(sync.completion_criteria).to eq(%w[sync_planned])
  expect(sync.forbidden_skills).to include("deploy", "mutate_infrastructure")
  expect(sync.agent_prompt).to include("one environment at a time")
  expect(sync.agent_prompt).to include("rollback")
  expect(sync.adapter_config).to include(
    "input_artifact_kind" => "drift_classification",
    "secondary_input_artifact_kind" => "environment_configs",
    "output_artifact_kind" => "sync_plan",
    "read_only" => true
  )
  expect(sync.adapter_config.fetch("spawn_targets")).to include(
    "dangerous_security_drift" => "security_scan",
    "missing_deployment_automation" => "development",
    "stale_deprecated_service" => "dead_code_removal"
  )

  review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(review.adapter_type).to eq("fake")
  expect(review.completion_criteria).to eq(%w[report_present])
  expect(review.timeout_seconds).to eq(86_400)
  expect(review.agent_prompt).to include("Apply changes manually")

  done = queue.stage_configs.find_by!(stage_name: "done")
  expect(done.adapter_type).to eq("fake")
  expect(done.completion_criteria).to eq(%w[report_present])

  serialized_queue = Rails.root.join("config/queues/infrastructure_drift.yml").read
  expect(serialized_queue).not_to include(Rails.root.to_s)
  expect(serialized_queue).not_to include("/Users/")
  expect(serialized_queue).not_to include("working_directory:")
  expect(serialized_queue).to include("file://prompts/drift_collect.md")
  expect(serialized_queue).to include("file://prompts/drift_diff.md")
  expect(serialized_queue).to include("file://prompts/drift_classify.md")
  expect(serialized_queue).to include("file://prompts/drift_sync_plan.md")
end
```

**Step 2: Run RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL with `Couldn't find WorkQueue` for `infrastructure_drift`.

**Step 3: Create queue YAML and prompt placeholders**

Create the queue YAML target above and minimal prompt files with matching H1 headings.

**Step 4: Run GREEN**

Run the same seed spec. Expected: PASS.

**Step 5: Commit**

```bash
git add config/queues/infrastructure_drift.yml prompts/drift_collect.md prompts/drift_diff.md prompts/drift_classify.md prompts/drift_sync_plan.md spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed infrastructure drift queue"
```

---

### Task 4: Expand drift prompts with safe schemas

**Objective:** Make prompts explicit enough for agents to produce structured artifacts without mutating infrastructure or leaking secrets.

**Files:**

- Modify: `prompts/drift_collect.md`
- Modify: `prompts/drift_diff.md`
- Modify: `prompts/drift_classify.md`
- Modify: `prompts/drift_sync_plan.md`
- Modify: `spec/models/work_queue_seed_spec.rb`

**Step 1: Add failing prompt expectations**

Enhance the seed spec with expectations that require:

```ruby
expect(collect.agent_prompt).to include("Docker Compose")
expect(collect.agent_prompt).to include("nginx")
expect(collect.agent_prompt).to include("Terraform")
expect(collect.agent_prompt).to include("Do not modify")
expect(collect.agent_prompt).to include("environment_configs")

expect(diff.agent_prompt).to include("services present in one environment")
expect(diff.agent_prompt).to include("version mismatches")
expect(diff.agent_prompt).to include("resource limits")
expect(diff.agent_prompt).to include("total_diffs")

expect(classify.agent_prompt).to include("git blame")
expect(classify.agent_prompt).to include("risk_if_unresolved")
expect(classify.agent_prompt).to include("confidence")

expect(sync.agent_prompt).to include("dangerous fixes first")
expect(sync.agent_prompt).to include("document intentional drift")
expect(sync.agent_prompt).to include("verification")
expect(sync.agent_prompt).to include("sync_order")
```

**Step 2: Run RED**

Run `spec/models/work_queue_seed_spec.rb`. Expected: FAIL on placeholder prompt details.

**Step 3: Replace prompt contents**

Use these headings and schemas:

- `prompts/drift_collect.md`: `# Infrastructure Drift: Collect Configs`, READ-ONLY instructions, sources (Docker Compose, env files, nginx, Terraform, database config), sensitive-value masking rules, and `environment_configs` JSON schema.
- `prompts/drift_diff.md`: `# Infrastructure Drift: Diff Environments`, compare staging/production, services present in one environment, version mismatches, env var differences with masking, web/database/resource-limit diffs, and `environment_diff` schema.
- `prompts/drift_classify.md`: `# Infrastructure Drift: Classify Drift`, classify `intentional|accidental|dangerous|stale`, use source context and git blame when available, include confidence and `risk_if_unresolved`, and `drift_classification` schema.
- `prompts/drift_sync_plan.md`: `# Infrastructure Drift: Draft Sync Plan`, draft human-executed changes only, order dangerous fixes first, sync accidental drift, remove stale drift, document intentional drift, include verification/rollback, spawn follow-up queue metadata, and `sync_plan` schema.

**Step 4: Run GREEN**

Run `spec/models/work_queue_seed_spec.rb`. Expected: PASS.

**Step 5: Commit**

```bash
git add prompts/drift_collect.md prompts/drift_diff.md prompts/drift_classify.md prompts/drift_sync_plan.md spec/models/work_queue_seed_spec.rb
git commit -m "docs: expand infrastructure drift prompts"
```

---

### Task 5: Add deterministic infrastructure drift fixture

**Objective:** Provide Docker-friendly sample staging/production configs with deliberate drift and a read-only collector script.

**Files:**

- Create all files under `test/fixtures/apps/infrastructure_drift/`
- Create: `spec/fixtures/infrastructure_drift_fixture_spec.rb`

**Step 1: Write RED fixture contract spec**

Create `spec/fixtures/infrastructure_drift_fixture_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "infrastructure drift fixture" do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/infrastructure_drift") }

  it "contains staging and production configs with representative drift" do
    expect(fixture_root.join("docker-compose.staging.yml")).to exist
    expect(fixture_root.join("docker-compose.production.yml")).to exist
    expect(fixture_root.join("env/.env.staging.example")).to exist
    expect(fixture_root.join("env/.env.production.example")).to exist
    expect(fixture_root.join("nginx/staging.conf")).to exist
    expect(fixture_root.join("nginx/production.conf")).to exist
    expect(fixture_root.join("terraform/staging.tfvars")).to exist
    expect(fixture_root.join("terraform/production.tfvars")).to exist
    expect(fixture_root.join("bin/collect-drift-fixture")).to exist

    staging_compose = fixture_root.join("docker-compose.staging.yml").read
    production_compose = fixture_root.join("docker-compose.production.yml").read
    expect(staging_compose).to include("postgres:15")
    expect(production_compose).to include("postgres:14")
    expect(production_compose).to include("redis:")
    expect(staging_compose).not_to include("redis:")

    staging_env = fixture_root.join("env/.env.staging.example").read
    production_env = fixture_root.join("env/.env.production.example").read
    expect(staging_env).to include("FEATURE_NEW_CHECKOUT=true")
    expect(production_env).to include("FEATURE_NEW_CHECKOUT=false")

    production_nginx = fixture_root.join("nginx/production.conf").read
    expect(production_nginx).to include("limit_req")
    expect(fixture_root.join("nginx/staging.conf").read).not_to include("limit_req")

    all_text = fixture_root.glob("**/*").select(&:file?).map(&:read).join("\n")
    expect(all_text).not_to include(Rails.root.to_s)
    expect(all_text).not_to include("/Users/")
  end

  it "collector script emits a normalized environment_configs shape" do
    output = Dir.chdir(Rails.root) { `ruby test/fixtures/apps/infrastructure_drift/bin/collect-drift-fixture` }
    expect($CHILD_STATUS).to be_success
    parsed = JSON.parse(output)
    expect(parsed.fetch("environments").keys).to contain_exactly("staging", "production")
    expect(parsed.dig("environments", "production", "services").map { |service| service.fetch("name") }).to include("redis")
    expect(parsed.dig("environments", "staging", "database", "version")).to eq("postgres:15")
    expect(parsed.dig("environments", "production", "database", "version")).to eq("postgres:14")
  end
end
```

Remember to `require "json"` and `require "English"` at the top if the spec helper does not already load them.

**Step 2: Run RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/fixtures/infrastructure_drift_fixture_spec.rb
```

Expected: FAIL because fixture files do not exist.

**Step 3: Create fixture files**

Fixture content should include:

- `docker-compose.staging.yml`: `web`, `worker`, `postgres:15`, no `redis`, lower resource limits.
- `docker-compose.production.yml`: `web`, `worker`, `postgres:14`, extra `redis`, higher resource limits.
- Env examples: matching keys plus deliberate differences (`FEATURE_NEW_CHECKOUT`, `PAYMENTS_TIMEOUT_SECONDS`, production-only `REDIS_URL`). Use fake placeholder values only and mask-like examples for secrets.
- nginx snippets: production has rate limiting and HSTS; staging lacks rate limiting and has debug headers.
- Terraform tfvars: instance counts, database version, and backup retention differences.
- `bin/collect-drift-fixture`: Ruby script using stdlib `json` and `yaml` to read fixture files and print an `environment_configs` JSON object. It must compute service names and database image versions from compose YAML and include normalized `env_vars`, `web_config`, `db_config`, and `resource_limits`. It should not shell out.
- `README.md`: clearly states the fixture is intentionally drifted and read-only.

Make the collector executable if desired, but the spec should invoke it with `ruby ...` so executable bits are not required.

**Step 4: Run GREEN**

Run the fixture spec. Expected: PASS.

**Step 5: Commit**

```bash
git add test/fixtures/apps/infrastructure_drift spec/fixtures/infrastructure_drift_fixture_spec.rb
git commit -m "test: add infrastructure drift fixture"
```

---

### Task 6: Add workflow integration spec

**Objective:** Prove the seeded queue, registry, predicates, artifact schemas, test results, and human review gate work together without live infrastructure.

**Files:**

- Create: `spec/services/engine/infrastructure_drift_workflow_integration_spec.rb`

**Step 1: Write integration spec**

Create a spec that loads seeds, creates a work item in `collect_configs`, and then creates one claim/artifact per stage:

```ruby
require "rails_helper"

RSpec.describe "infrastructure drift cookbook workflow" do
  before { load Rails.root.join("db/seeds.rb") }

  let(:queue) { WorkQueue.find_by!(slug: "infrastructure_drift") }
  let(:work_item) do
    WorkItem.create!(
      work_queue: queue,
      title: "Detect staging production drift",
      spec_url: "test/fixtures/apps/infrastructure_drift",
      stage_name: "collect_configs"
    )
  end

  it "accepts config, diff, classification, sync plan, and review artifacts" do
    collect_claim = Claim.create!(work_item: work_item, agent_type: "shell_script", status: "completed", started_at: Time.current)
    configs = Artifact.create!(
      work_item: work_item,
      claim: collect_claim,
      kind: "environment_configs",
      data: {
        "environments" => {
          "staging" => { "services" => [{ "name" => "web" }, { "name" => "postgres" }], "database" => { "version" => "postgres:15" } },
          "production" => { "services" => [{ "name" => "web" }, { "name" => "postgres" }, { "name" => "redis" }], "database" => { "version" => "postgres:14" } }
        }
      }
    )

    result = Engine::PredicateRegistry.resolve("configs_collected").new(claim: collect_claim).call
    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: configs.id, environment_count: 2 })

    diff_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    diff = Artifact.create!(
      work_item: work_item,
      claim: diff_claim,
      kind: "environment_diff",
      data: {
        "comparisons" => [
          {
            "env_a" => "staging",
            "env_b" => "production",
            "diffs" => [
              { "category" => "service", "key" => "redis", "value_a" => nil, "value_b" => "present", "type" => "missing" },
              { "category" => "database", "key" => "postgres", "value_a" => "15", "value_b" => "14", "type" => "different" }
            ]
          }
        ],
        "total_diffs" => 2
      }
    )

    result = Engine::PredicateRegistry.resolve("diff_produced").new(claim: diff_claim).call
    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: diff.id, comparison_count: 1, total_diffs: 2 })

    classify_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    classification = Artifact.create!(
      work_item: work_item,
      claim: classify_claim,
      kind: "drift_classification",
      data: {
        "drifts" => [
          { "diff_ref" => "redis", "classification" => "accidental", "confidence" => "high", "risk_if_unresolved" => "staging cannot test cache path" },
          { "diff_ref" => "postgres", "classification" => "dangerous", "confidence" => "medium", "risk_if_unresolved" => "migration behavior differs" }
        ],
        "accidental_count" => 1,
        "dangerous_count" => 1
      }
    )

    result = Engine::PredicateRegistry.resolve("drift_classified").new(claim: classify_claim).call
    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: classification.id, drift_count: 2, accidental_count: 1, dangerous_count: 1 })

    sync_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    plan = Artifact.create!(
      work_item: work_item,
      claim: sync_claim,
      kind: "sync_plan",
      data: {
        "actions" => [
          { "drift_ref" => "postgres", "classification" => "dangerous", "action" => "sync", "target_environment" => "production", "file" => "docker-compose.production.yml", "verification" => "run migration smoke test", "priority" => 1 },
          { "drift_ref" => "redis", "classification" => "accidental", "action" => "sync", "target_environment" => "staging", "file" => "docker-compose.staging.yml", "verification" => "cache-backed spec passes", "priority" => 2 }
        ],
        "sync_order" => ["postgres", "redis"]
      }
    )

    result = Engine::PredicateRegistry.resolve("sync_planned").new(claim: sync_claim).call
    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: plan.id, action_count: 2 })

    review_claim = Claim.create!(work_item: work_item, agent_type: "fake", status: "completed", started_at: Time.current)
    report = Report.create!(work_item: work_item, claim: review_claim, stage_name: "human_review", status: "success", body: { "approved_by" => "infra reviewer" })
    result = Engine::PredicateRegistry.resolve("report_present").new(claim: review_claim).call
    expect(result).to be_passed
    expect(result.evidence).to eq({ report_id: report.id })
  end
end
```

**Step 2: Run spec**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/infrastructure_drift_workflow_integration_spec.rb
```

Expected after Tasks 1-5: PASS. If it fails, add the smallest focused RED spec for the gap before changing production code.

**Step 3: Commit**

```bash
git add spec/services/engine/infrastructure_drift_workflow_integration_spec.rb
git commit -m "test: cover infrastructure drift workflow artifacts"
```

---

### Task 7: Add cookbook docs page

**Objective:** Document what the cookbook does, how to run the fixture check, and the manual-safety boundary.

**Files:**

- Create: `docs/cookbooks/infrastructure-drift.md`

**Step 1: Write docs**

Create:

```markdown
# Infrastructure Drift Detection Cookbook

The `infrastructure_drift` queue compares staging/production-style configuration snapshots, classifies drift, drafts a human-reviewed sync plan, and never mutates live infrastructure automatically.

## Stages

`collect_configs -> diff_environments -> classify_drift -> draft_sync_plan -> human_review -> done`

## Fixture

The fixture lives at `test/fixtures/apps/infrastructure_drift` and includes deliberate drift: a Redis service present only in production, Postgres version mismatch, environment variable differences, nginx rate-limit differences, and Terraform variable differences.

## Focused verification

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/infrastructure_drift_workflow_integration_spec.rb
```

## Safety

This cookbook is read-only and advisory. Humans apply sync actions manually one environment at a time with verification and rollback.

## Follow-up queues

- Dangerous security drift: `security_scan`
- Missing deployment automation: `development`
- Stale deprecated services: `dead_code_removal`
```

**Step 2: Verify docs path portability**

```bash
git grep -n "/Users/\|Rails.root.to_s\|working_directory:" -- docs/cookbooks/infrastructure-drift.md config/queues/infrastructure_drift.yml prompts/drift_collect.md prompts/drift_diff.md prompts/drift_classify.md prompts/drift_sync_plan.md || true
```

Expected: no output.

**Step 3: Commit**

```bash
git add docs/cookbooks/infrastructure-drift.md
git commit -m "docs: add infrastructure drift cookbook"
```

---

### Task 8: Final verification before completion

**Objective:** Prove the whole cookbook slice is green, portable, and scoped.

**Step 1: Run focused suite**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/configs_collected_spec.rb \
  spec/services/engine/predicates/diff_produced_spec.rb \
  spec/services/engine/predicates/drift_classified_spec.rb \
  spec/services/engine/predicates/sync_planned_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/fixtures/infrastructure_drift_fixture_spec.rb \
  spec/services/engine/infrastructure_drift_workflow_integration_spec.rb
```

Expected: PASS.

**Step 2: Run broader safe suite**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine spec/models/work_queue_seed_spec.rb spec/fixtures/infrastructure_drift_fixture_spec.rb
```

Expected: PASS. If unrelated dirty-worktree files cause failures, do not modify or stage unrelated files; document the unrelated failure and verify the focused cookbook suite cleanly.

**Step 3: Search for non-portable paths**

```bash
git grep -n "/Users/gregmushen\|/Users/\|working_directory:" -- \
  config/queues/infrastructure_drift.yml \
  prompts/drift_collect.md prompts/drift_diff.md prompts/drift_classify.md prompts/drift_sync_plan.md \
  test/fixtures/apps/infrastructure_drift \
  spec/services/engine/infrastructure_drift_workflow_integration_spec.rb \
  spec/fixtures/infrastructure_drift_fixture_spec.rb \
  docs/cookbooks/infrastructure-drift.md || true
```

Expected: no output.

**Step 4: Check git status**

```bash
git status --short
```

Expected before final commit/squash: only intentional infrastructure-drift files are dirty. Do not stage unrelated files such as `docs/superpowers/`.

**Step 5: Final commit or squash**

If the implementation card wants a single commit:

```bash
git reset --soft HEAD~7
git commit -m "feat: add infrastructure drift cookbook"
```

Then verify:

```bash
git show --stat --oneline HEAD
```

Expected: only infrastructure-drift queue, prompts, predicates/specs, fixture, integration spec, docs, and registry/seed spec changes.

---

## Implementation Acceptance Criteria

- `config/queues/infrastructure_drift.yml` seeds queue `infrastructure_drift` with stages `collect_configs`, `diff_environments`, `classify_drift`, `draft_sync_plan`, `human_review`, and `done`.
- Every YAML stage has a persisted `StageConfig`; seed spec asserts exact stage coverage with `contain_exactly(*queue.stages)`.
- Prompt indirection resolves; persisted prompt text does not start with `file://`.
- No implementation/config/prompt/fixture/doc file contains a hardcoded `/Users/...`, `Rails.root.to_s`, or `working_directory:` entry.
- `configs_collected`, `diff_produced`, `drift_classified`, and `sync_planned` exist, have focused predicate specs, are registered, and return actionable evidence hashes.
- Fixture app contains deterministic drift examples: Redis present only in production, Postgres version mismatch, env var differences, nginx rate-limit differences, and Terraform variable differences.
- Collection script is local/read-only and emits normalized `environment_configs` without invoking Docker/Terraform/cloud CLIs.
- Prompts explicitly mask sensitive values and forbid live mutations.
- Human review prompt requires manual one-environment-at-a-time sync with verification and rollback.
- Cross-queue follow-up intent is encoded for `security_scan`, `development`, and `dead_code_removal`.
- Focused and relevant broader specs pass before completion.

---

## Planning-task Completion Checklist

For this planning Kanban card only:

1. Save this plan at `docs/plans/cookbooks/21-infrastructure-drift.md`.
2. Run:

```bash
git diff -- docs/plans/cookbooks/21-infrastructure-drift.md
```

3. Commit only this plan file:

```bash
git add docs/plans/cookbooks/21-infrastructure-drift.md
git commit -m "docs: plan cookbook 21 infrastructure-drift"
```

4. Capture the commit hash:

```bash
git rev-parse HEAD
```

5. Complete the Kanban task with a summary containing the plan path and commit hash.
