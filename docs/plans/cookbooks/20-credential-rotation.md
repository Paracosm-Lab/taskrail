# Credential Rotation Audit Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `credential_rotation` cookbook queue so StupidClaw can inventory secrets, map dependent services, assess credential risk, draft safe human-executed rotation procedures, and stop at a review gate without mutating external systems.

**Architecture:** This cookbook follows the existing seeded Rails queue pattern: portable YAML under `config/queues/`, long prompts loaded through repo-relative `file://prompts/...` paths, artifact-backed predicates under `Engine::Predicates`, registry/seed specs, and an artifact-driven workflow integration spec. The cookbook fixture is a Docker-friendly Rails-shaped app under `test/fixtures/apps/leaky_credentials/`; it is source text for read-only audit agents and smoke commands, not a production credential scanner.

**Tech Stack:** Rails, RSpec, YAML seed loader with `Rails.root` prompt resolution, `WorkQueue`/`StageConfig`/`Artifact`, `Engine::PredicateRegistry`, inline Claude adapters, fake human-review stages, shell-safe fixture smoke tests, rbenv on Greg's Mac.

**Source Spec:** `docs/specs/cookbook-20-credential-rotation.md`

---

## Source Requirements Summary

Implement cookbook-20, `Credential Rotation Audit`, category `Live DevOps`.

Queue stages:

`scan_secrets -> map_dependencies -> assess_risk -> draft_rotation_plan -> human_review -> done`

Required predicates:

- `secrets_scanned`: passes when the current claim has a `secret_inventory` artifact with a `secrets` array.
- `dependencies_mapped`: passes when the current claim has a `dependency_map` artifact with a `credentials` array.
- `risk_assessed`: passes when the current claim has a `risk_assessment` artifact with credential risk entries and a `summary`.
- `rotation_planned`: passes when the current claim has a `rotation_plan` artifact with at least one rotation procedure.

Artifacts:

- `secret_inventory`: `{ secrets: [{ name, type, locations: [{ file, line, how }], in_git_history }], total_count, hardcoded_count }`
- `dependency_map`: `{ credentials: [{ name, type, scope, services: [{ name, reads_at, fallback }], shared_across, rotation_requires_restart }] }`
- `risk_assessment`: `{ credentials: [{ name, exposure_risk, blast_radius, estimated_age_days, sharing_risk, overall_risk, rationale }], critical_count, summary }`
- `rotation_plan`: `{ rotations: [{ credential_name, risk_level, steps: [{ action, target, verification, rollback }], services_affected, estimated_downtime, requires_code_change, code_change_description }], rotation_order: [] }`

Safety:

- The queue is strictly read-only and advisory.
- Prompts must explicitly forbid generating, rotating, revoking, deploying, or modifying external credentials.
- The `human_review` stage is the only gate after a plan is drafted; humans execute rotations manually one credential at a time.
- Cross-queue follow-ups are only drafted as metadata in artifacts/prompts: code changes to `development`, exposed history to `security_scan`, missing secrets manager to `incident_readiness`.

---

## Current Codebase Context

Relevant existing files and patterns:

- `db/seeds.rb` loads every `config/queues/*.yml`, resolves `agent_prompt: file://...` with `Rails.root.join(relative_path).read`, and upserts `WorkQueue`/`StageConfig` rows.
- `config/queues/job_observability.yml`, `config/queues/incident_readiness.yml`, and `config/queues/query_health.yml` are close queue YAML examples with inline Claude stages, `adapter_config.output_artifact_kind`, fake review stages, and portable prompt paths.
- Existing prompts live both in root `prompts/` and cookbook-specific `cookbooks/prompts/...`; this plan uses root `prompts/credential_*.md` because the source queue config specifies `file://prompts/...`.
- Existing predicates live in `app/services/engine/predicates/` and generally return `PredicateResult.pass(evidence: { artifact_id: artifact.id, ... })` or `PredicateResult.fail(reason: "...")`.
- `app/services/engine/predicate_registry.rb` maps completion criteria names to predicate classes and `spec/services/engine/predicate_registry_spec.rb` asserts all registered names.
- `spec/models/work_queue_seed_spec.rb` already covers seeded cookbook queues, prompt file resolution, and portability checks such as no `Rails.root.to_s` or `/Users/` in serialized YAML.
- Existing workflow integration specs, for example `spec/services/engine/dead_code_removal_workflow_integration_spec.rb`, create real `WorkQueue`, `WorkItem`, `Claim`, and `Artifact` records and call predicates directly.
- Shared cookbook infrastructure exists under `cookbooks/` (`cookbooks/docker-compose.yml`, `cookbooks/fake_services/fake_service.rb`), but current implemented fixture apps are under `test/fixtures/apps/`. Use `test/fixtures/apps/leaky_credentials/` for this cookbook to match recent queue tests.

Global implementation rules:

- Follow strict TDD: write each failing spec first, run it and verify the expected RED failure, implement the smallest change, rerun focused specs, then run relevant broader specs.
- Use Greg's rbenv command shape for all RSpec commands:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Do not hardcode `/Users/gregmushen/work/code/stupidclaw` or any absolute checkout path in queue YAML, prompts, fixtures, specs, or implementation code.
- Keep generated app/config code repo-relative. Queue YAML should omit `working_directory`; adapters already default to `Rails.root` where needed.
- Commit after each task when implementing from this plan. If the Kanban implementation card requires one final commit, squash task commits before completion.

---

## Files to Create or Modify

Create:

- `config/queues/credential_rotation.yml`
- `prompts/credential_scan.md`
- `prompts/credential_dependencies.md`
- `prompts/credential_risk.md`
- `prompts/credential_rotation_plan.md`
- `app/services/engine/predicates/secrets_scanned.rb`
- `app/services/engine/predicates/dependencies_mapped.rb`
- `app/services/engine/predicates/risk_assessed.rb`
- `app/services/engine/predicates/rotation_planned.rb`
- `spec/services/engine/predicates/secrets_scanned_spec.rb`
- `spec/services/engine/predicates/dependencies_mapped_spec.rb`
- `spec/services/engine/predicates/risk_assessed_spec.rb`
- `spec/services/engine/predicates/rotation_planned_spec.rb`
- `spec/services/engine/credential_rotation_workflow_integration_spec.rb`
- `test/fixtures/apps/leaky_credentials/README.md`
- `test/fixtures/apps/leaky_credentials/Gemfile`
- `test/fixtures/apps/leaky_credentials/.env.example`
- `test/fixtures/apps/leaky_credentials/config/payment.yml`
- `test/fixtures/apps/leaky_credentials/config/secrets.yml`
- `test/fixtures/apps/leaky_credentials/config/docker-compose.yml`
- `test/fixtures/apps/leaky_credentials/.github/workflows/deploy.yml`
- `test/fixtures/apps/leaky_credentials/Dockerfile`
- `test/fixtures/apps/leaky_credentials/app/services/payment_gateway.rb`
- `test/fixtures/apps/leaky_credentials/app/services/billing_reconciler.rb`
- `test/fixtures/apps/leaky_credentials/app/services/analytics_client.rb`
- `test/fixtures/apps/leaky_credentials/app/jobs/nightly_billing_job.rb`
- `test/fixtures/apps/leaky_credentials/bin/credential-audit-smoke`

Modify:

- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Do not modify unless a failing spec proves it is necessary:

- `db/seeds.rb` because it already resolves `file://` relative to `Rails.root`.
- Shared adapter classes such as `Adapters::InlineClaudeAdapter`, `Adapters::ShellScriptAdapter`, or transition manager cross-queue code. Cross-queue spawn is prompt/artifact guidance only for this slice.
- Shared `cookbooks/docker-compose.yml`; the credential fixture should be plain source plus a local smoke script.

---

## Queue YAML Target

Create `config/queues/credential_rotation.yml` with portable prompt references and no absolute paths:

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
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [secrets_scanned]
    agent_prompt: file://prompts/credential_scan.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: secret_inventory
      fixture_app: test/fixtures/apps/leaky_credentials
      read_only: true
  map_dependencies:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [dependencies_mapped]
    agent_prompt: file://prompts/credential_dependencies.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: secret_inventory
      output_artifact_kind: dependency_map
      fixture_app: test/fixtures/apps/leaky_credentials
      read_only: true
  assess_risk:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [risk_assessed]
    agent_prompt: file://prompts/credential_risk.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: dependency_map
      secondary_input_artifact_kind: secret_inventory
      output_artifact_kind: risk_assessment
      read_only: true
      spawn_targets:
        exposed_history: security_scan
        missing_secrets_manager: incident_readiness
  draft_rotation_plan:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [rotation_planned]
    agent_prompt: file://prompts/credential_rotation_plan.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: risk_assessment
      secondary_input_artifact_kind: dependency_map
      output_artifact_kind: rotation_plan
      read_only: true
      spawn_targets:
        hardcoded_code_change: development
        exposed_history: security_scan
        missing_secrets_manager: incident_readiness
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: [deploy, mutate_database]
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review the credential rotation plan. Do not rotate automatically; execute one credential at a time with health checks and rollback ready.
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

- `read_only: true` is an adapter hint and safety assertion for tests/prompts. Do not add new adapter behavior unless a later spec requires it.
- `spawn_targets` documents the desired follow-up queues. The implementation does not need new cross-queue engine code; prompts should ask agents to include proposed `spawn_work_items` metadata when relevant.
- `max_regression_loops: 0` matches the source spec because credential rotation plans are advisory and should not cycle through auto-fix loops.

---

### Task 1: Add RED specs for credential artifact predicates

**Objective:** Define pass/fail behavior for all four credential predicates before adding production predicate classes.

**Files:**

- Create: `spec/services/engine/predicates/secrets_scanned_spec.rb`
- Create: `spec/services/engine/predicates/dependencies_mapped_spec.rb`
- Create: `spec/services/engine/predicates/risk_assessed_spec.rb`
- Create: `spec/services/engine/predicates/rotation_planned_spec.rb`

**Step 1: Write failing tests**

Use this helper shape in each file, with randomized queue slugs to avoid uniqueness collisions:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::SecretsScanned do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Credential Rotation #{SecureRandom.hex(4)}",
      slug: "credential-rotation-predicate-#{SecureRandom.hex(4)}",
      stages: ["scan_secrets", "done"]
    )
    queue.stage_configs.create!(stage_name: "scan_secrets", adapter_type: "fake")
    item = WorkItem.create!(title: "Audit credentials", spec_url: "opaque spec", work_queue: queue, stage_name: "scan_secrets")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with counts when a secret_inventory artifact has a secrets array" do
    claim = build_claim(
      artifacts: [
        {
          kind: "secret_inventory",
          data: {
            "secrets" => [
              {
                "name" => "STRIPE_SECRET_KEY",
                "type" => "payment_api_key",
                "locations" => [{ "file" => "config/payment.yml", "line" => 3, "how" => "hardcoded" }],
                "in_git_history" => true
              }
            ],
            "total_count" => 1,
            "hardcoded_count" => 1
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "secret_inventory")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, total_count: 1, hardcoded_count: 1 })
  end

  it "fails when no secret_inventory artifact exists" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing secret_inventory artifact")
  end

  it "fails when the secret_inventory artifact does not contain a secrets array" do
    claim = build_claim(artifacts: [{ kind: "secret_inventory", data: { "summary" => "not structured" } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("secret_inventory artifact has no secrets array")
  end
end
```

Create analogous specs:

- `DependenciesMapped` requires `kind: "dependency_map"`, `data["credentials"]` as an array, and passes with evidence `{ artifact_id:, credential_count: credentials.count }`; fail reasons: `missing dependency_map artifact`, `dependency_map artifact has no credentials array`.
- `RiskAssessed` requires `kind: "risk_assessment"`, `data["credentials"]` as an array, and `data["summary"]`; passes with evidence `{ artifact_id:, critical_count: artifact.data.fetch("critical_count", 0), credential_count: credentials.count }`; fail reasons: `missing risk_assessment artifact`, `risk_assessment artifact has no credentials array`, `risk_assessment artifact has no summary`.
- `RotationPlanned` requires `kind: "rotation_plan"`, `data["rotations"]` as a non-empty array, and each rotation to include a non-empty `steps` array; passes with evidence `{ artifact_id:, rotations_count: rotations.count }`; fail reasons: `missing rotation_plan artifact`, `rotation_plan artifact has no rotations`, `rotation_plan rotations are missing steps`.

**Step 2: Run tests to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/secrets_scanned_spec.rb \
  spec/services/engine/predicates/dependencies_mapped_spec.rb \
  spec/services/engine/predicates/risk_assessed_spec.rb \
  spec/services/engine/predicates/rotation_planned_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::SecretsScanned` and equivalent missing constants for the other predicates.

**Step 3: Commit RED specs if your workflow commits RED separately**

```bash
git add spec/services/engine/predicates/secrets_scanned_spec.rb \
  spec/services/engine/predicates/dependencies_mapped_spec.rb \
  spec/services/engine/predicates/risk_assessed_spec.rb \
  spec/services/engine/predicates/rotation_planned_spec.rb
git commit -m "test: specify credential rotation predicates"
```

---

### Task 2: Implement the four credential predicates

**Objective:** Add minimal predicate classes that make Task 1's specs pass without adding queue/config behavior yet.

**Files:**

- Create: `app/services/engine/predicates/secrets_scanned.rb`
- Create: `app/services/engine/predicates/dependencies_mapped.rb`
- Create: `app/services/engine/predicates/risk_assessed.rb`
- Create: `app/services/engine/predicates/rotation_planned.rb`

**Step 1: Implement minimal production code**

Create `app/services/engine/predicates/secrets_scanned.rb`:

```ruby
module Engine
  module Predicates
    class SecretsScanned
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "secret_inventory").first
        return PredicateResult.fail(reason: "missing secret_inventory artifact") unless artifact

        secrets = artifact.data["secrets"]
        return PredicateResult.fail(reason: "secret_inventory artifact has no secrets array") unless secrets.is_a?(Array)

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            total_count: artifact.data.fetch("total_count", secrets.count),
            hardcoded_count: artifact.data.fetch("hardcoded_count", 0)
          }
        )
      end
    end
  end
end
```

Create the other classes with the same simple shape:

```ruby
module Engine
  module Predicates
    class DependenciesMapped
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "dependency_map").first
        return PredicateResult.fail(reason: "missing dependency_map artifact") unless artifact

        credentials = artifact.data["credentials"]
        return PredicateResult.fail(reason: "dependency_map artifact has no credentials array") unless credentials.is_a?(Array)

        PredicateResult.pass(evidence: { artifact_id: artifact.id, credential_count: credentials.count })
      end
    end
  end
end
```

```ruby
module Engine
  module Predicates
    class RiskAssessed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "risk_assessment").first
        return PredicateResult.fail(reason: "missing risk_assessment artifact") unless artifact

        credentials = artifact.data["credentials"]
        return PredicateResult.fail(reason: "risk_assessment artifact has no credentials array") unless credentials.is_a?(Array)
        return PredicateResult.fail(reason: "risk_assessment artifact has no summary") if artifact.data["summary"].blank?

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            critical_count: artifact.data.fetch("critical_count", 0),
            credential_count: credentials.count
          }
        )
      end
    end
  end
end
```

```ruby
module Engine
  module Predicates
    class RotationPlanned
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "rotation_plan").first
        return PredicateResult.fail(reason: "missing rotation_plan artifact") unless artifact

        rotations = artifact.data["rotations"]
        return PredicateResult.fail(reason: "rotation_plan artifact has no rotations") unless rotations.is_a?(Array) && rotations.any?
        return PredicateResult.fail(reason: "rotation_plan rotations are missing steps") unless rotations.all? { |rotation| rotation["steps"].is_a?(Array) && rotation["steps"].any? }

        PredicateResult.pass(evidence: { artifact_id: artifact.id, rotations_count: rotations.count })
      end
    end
  end
end
```

**Step 2: Run focused specs to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/secrets_scanned_spec.rb \
  spec/services/engine/predicates/dependencies_mapped_spec.rb \
  spec/services/engine/predicates/risk_assessed_spec.rb \
  spec/services/engine/predicates/rotation_planned_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/secrets_scanned.rb \
  app/services/engine/predicates/dependencies_mapped.rb \
  app/services/engine/predicates/risk_assessed.rb \
  app/services/engine/predicates/rotation_planned.rb \
  spec/services/engine/predicates/secrets_scanned_spec.rb \
  spec/services/engine/predicates/dependencies_mapped_spec.rb \
  spec/services/engine/predicates/risk_assessed_spec.rb \
  spec/services/engine/predicates/rotation_planned_spec.rb
git commit -m "feat: add credential rotation predicates"
```

---

### Task 3: Register credential predicates

**Objective:** Make the new completion criteria resolvable by `Engine::PredicateRegistry`.

**Files:**

- Modify: `app/services/engine/predicate_registry.rb`
- Modify: `spec/services/engine/predicate_registry_spec.rb`

**Step 1: Write failing registry spec**

In `spec/services/engine/predicate_registry_spec.rb`, add these expectations to the known predicate example:

```ruby
expect(described_class.resolve("secrets_scanned")).to eq(Engine::Predicates::SecretsScanned)
expect(described_class.resolve("dependencies_mapped")).to eq(Engine::Predicates::DependenciesMapped)
expect(described_class.resolve("risk_assessed")).to eq(Engine::Predicates::RiskAssessed)
expect(described_class.resolve("rotation_planned")).to eq(Engine::Predicates::RotationPlanned)
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate: secrets_scanned` or equivalent.

**Step 3: Register the predicates**

In `app/services/engine/predicate_registry.rb`, add mappings near the other cookbook artifact predicates:

```ruby
"secrets_scanned" => Predicates::SecretsScanned,
"dependencies_mapped" => Predicates::DependenciesMapped,
"risk_assessed" => Predicates::RiskAssessed,
"rotation_planned" => Predicates::RotationPlanned,
```

**Step 4: Run focused and predicate specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/predicates/secrets_scanned_spec.rb \
  spec/services/engine/predicates/dependencies_mapped_spec.rb \
  spec/services/engine/predicates/risk_assessed_spec.rb \
  spec/services/engine/predicates/rotation_planned_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register credential rotation predicates"
```

---

### Task 4: Add RED seed spec for the credential rotation queue

**Objective:** Specify queue stages, prompt resolution, safety metadata, artifact config, and path portability before adding YAML/prompts.

**Files:**

- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/credential_rotation.yml`
- Later create: `prompts/credential_scan.md`
- Later create: `prompts/credential_dependencies.md`
- Later create: `prompts/credential_risk.md`
- Later create: `prompts/credential_rotation_plan.md`

**Step 1: Write failing seed spec**

Add a new example to `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the credential rotation audit queue with resolved read-only prompts" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "credential_rotation")
  expect(queue.name).to eq("Credential Rotation Audit")
  expect(queue.stages).to eq(%w[
    scan_secrets
    map_dependencies
    assess_risk
    draft_rotation_plan
    human_review
    done
  ])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_max_retries" => 2,
    "default_timeout_seconds" => 600,
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 0
  )

  scan = queue.stage_configs.find_by!(stage_name: "scan_secrets")
  expect(scan.adapter_type).to eq("inline_claude")
  expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
  expect(scan.allowed_skills).to eq(["read_repo"])
  expect(scan.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
  expect(scan.completion_criteria).to eq(["secrets_scanned"])
  expect(scan.adapter_config).to include(
    "output_artifact_kind" => "secret_inventory",
    "fixture_app" => "test/fixtures/apps/leaky_credentials",
    "read_only" => true
  )
  expect(scan.agent_prompt).to include("# Credential Scan")
  expect(scan.agent_prompt).to include("secret_inventory")
  expect(scan.agent_prompt).to include("READ-ONLY")
  expect(scan.agent_prompt).not_to start_with("file://")

  dependencies = queue.stage_configs.find_by!(stage_name: "map_dependencies")
  expect(dependencies.model_override).to eq("claude-sonnet-4-20250514")
  expect(dependencies.completion_criteria).to eq(["dependencies_mapped"])
  expect(dependencies.adapter_config).to include(
    "input_artifact_kind" => "secret_inventory",
    "output_artifact_kind" => "dependency_map",
    "fixture_app" => "test/fixtures/apps/leaky_credentials",
    "read_only" => true
  )
  expect(dependencies.agent_prompt).to include("# Credential Dependencies")
  expect(dependencies.agent_prompt).to include("dependency_map")

  risk = queue.stage_configs.find_by!(stage_name: "assess_risk")
  expect(risk.completion_criteria).to eq(["risk_assessed"])
  expect(risk.adapter_config).to include(
    "input_artifact_kind" => "dependency_map",
    "secondary_input_artifact_kind" => "secret_inventory",
    "output_artifact_kind" => "risk_assessment",
    "read_only" => true
  )
  expect(risk.adapter_config.fetch("spawn_targets")).to include(
    "exposed_history" => "security_scan",
    "missing_secrets_manager" => "incident_readiness"
  )
  expect(risk.agent_prompt).to include("# Credential Risk")
  expect(risk.agent_prompt).to include("critical")

  plan = queue.stage_configs.find_by!(stage_name: "draft_rotation_plan")
  expect(plan.completion_criteria).to eq(["rotation_planned"])
  expect(plan.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
  expect(plan.adapter_config).to include(
    "input_artifact_kind" => "risk_assessment",
    "secondary_input_artifact_kind" => "dependency_map",
    "output_artifact_kind" => "rotation_plan",
    "read_only" => true
  )
  expect(plan.adapter_config.fetch("spawn_targets")).to include(
    "hardcoded_code_change" => "development",
    "exposed_history" => "security_scan",
    "missing_secrets_manager" => "incident_readiness"
  )
  expect(plan.agent_prompt).to include("# Credential Rotation Plan")
  expect(plan.agent_prompt).to include("Do not rotate")

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.completion_criteria).to eq(["report_present"])
  expect(human_review.timeout_seconds).to eq(86_400)
  expect(human_review.agent_prompt).to include("Do not rotate automatically")

  serialized_queue = Rails.root.join("config/queues/credential_rotation.yml").read
  expect(serialized_queue).to include("file://prompts/credential_scan.md")
  expect(serialized_queue).to include("file://prompts/credential_dependencies.md")
  expect(serialized_queue).to include("file://prompts/credential_risk.md")
  expect(serialized_queue).to include("file://prompts/credential_rotation_plan.md")
  expect(serialized_queue).not_to include(Rails.root.to_s)
  expect(serialized_queue).not_to include("/Users/")
  expect(serialized_queue).not_to include("working_directory")
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb:NEW_LINE_NUMBER
```

Expected: FAIL with `Couldn't find WorkQueue with [WHERE "work_queues"."slug" = $1]` for `credential_rotation`.

**Step 3: Commit RED spec if desired**

```bash
git add spec/models/work_queue_seed_spec.rb
git commit -m "test: specify credential rotation queue seed"
```

---

### Task 5: Add credential rotation queue YAML and prompts

**Objective:** Add portable seeded queue config plus prompt files that satisfy the seed spec and encode read-only safety requirements.

**Files:**

- Create: `config/queues/credential_rotation.yml`
- Create: `prompts/credential_scan.md`
- Create: `prompts/credential_dependencies.md`
- Create: `prompts/credential_risk.md`
- Create: `prompts/credential_rotation_plan.md`

**Step 1: Add queue YAML**

Create `config/queues/credential_rotation.yml` exactly from the Queue YAML Target section above.

**Step 2: Add prompt file `prompts/credential_scan.md`**

````markdown
# Credential Scan

You are the scan_secrets stage for the Credential Rotation Audit cookbook.

READ-ONLY SAFETY RULES:
- Do not edit files, deploy, contact providers, create credentials, rotate credentials, revoke credentials, or mutate external systems.
- Inspect repository text and provided artifacts only.
- Redact likely credential values in prose; identify names, paths, and evidence without copying full secret values.

Inputs:
- Repository path or fixture_app path.
- Infrastructure config, environment files, Docker/CI config, and git-history notes when available.

Task:
Find every secret, credential, and sensitive value reference:
- hardcoded API keys, tokens, passwords, DSNs, and OAuth secrets in source/config files;
- environment variable reads such as `ENV["..."]`, `ENV.fetch`, `os.environ`, and `process.env`;
- Dockerfile, docker-compose, GitHub Actions, and CI secret references;
- Vault, AWS SSM, Doppler, Rails credentials, and other secrets-manager references;
- references that appear to have existed in git history.

Return one `secret_inventory` artifact only:

```json
{
  "secrets": [
    {
      "name": "STRIPE_SECRET_KEY",
      "type": "payment_api_key",
      "locations": [
        { "file": "config/payment.yml", "line": 3, "how": "hardcoded" }
      ],
      "in_git_history": true
    }
  ],
  "total_count": 1,
  "hardcoded_count": 1
}
```
````

**Step 3: Add prompt file `prompts/credential_dependencies.md`**

````markdown
# Credential Dependencies

You are the map_dependencies stage for the Credential Rotation Audit cookbook.

READ-ONLY: Do not edit files, deploy, restart services, validate credentials against providers, or mutate external systems.

Inputs:
- `secret_inventory` artifact.
- Repository source and infrastructure configuration.

Task:
For each credential, trace which services read it, when they read it, whether fallback behavior exists, whether multiple services share it, whether rotation requires restart, and what scope/blast radius the credential appears to have.

Return one `dependency_map` artifact only:

```json
{
  "credentials": [
    {
      "name": "STRIPE_SECRET_KEY",
      "type": "payment_api_key",
      "scope": "payment admin",
      "services": [
        { "name": "web", "reads_at": "startup", "fallback": false },
        { "name": "billing-worker", "reads_at": "startup", "fallback": false }
      ],
      "shared_across": 2,
      "rotation_requires_restart": true
    }
  ]
}
```
````

**Step 4: Add prompt file `prompts/credential_risk.md`**

````markdown
# Credential Risk

You are the assess_risk stage for the Credential Rotation Audit cookbook.

READ-ONLY: Do not rotate, revoke, create, test, or contact providers. Score risk from repository evidence and input artifacts only.

Inputs:
- `secret_inventory` artifact.
- `dependency_map` artifact.

Task:
Score each credential by exposure risk, blast radius, estimated age, sharing risk, and overall risk. Classify as `critical`, `high`, `medium`, or `low`. Any credential in git history is at least `high`. Credentials with admin/provider scope, hardcoded values, or broad sharing should be `critical` when justified.

When follow-up work is warranted, include proposed follow-up references in the rationale or artifact metadata:
- hardcoded credentials needing code changes -> `development` queue;
- credentials in git history -> `security_scan` queue;
- missing secrets manager -> `incident_readiness` queue.

Return one `risk_assessment` artifact only:

```json
{
  "credentials": [
    {
      "name": "STRIPE_SECRET_KEY",
      "exposure_risk": "hardcoded and in git history",
      "blast_radius": "payment provider admin access",
      "estimated_age_days": 540,
      "sharing_risk": "shared by web and billing-worker",
      "overall_risk": "critical",
      "rationale": "Hardcoded admin payment key appears in history and is shared by two startup-read services. Follow-up: development and security_scan."
    }
  ],
  "critical_count": 1,
  "summary": "One critical payment credential requires coordinated rotation and code migration to a secrets manager."
}
```
````

**Step 5: Add prompt file `prompts/credential_rotation_plan.md`**

````markdown
# Credential Rotation Plan

You are the draft_rotation_plan stage for the Credential Rotation Audit cookbook.

READ-ONLY SAFETY RULES:
- Do not rotate credentials.
- Do not generate new provider keys.
- Do not revoke old keys.
- Do not deploy, restart, or modify services.
- Produce an advisory document for humans to execute manually one credential at a time.

Inputs:
- `risk_assessment` artifact.
- `dependency_map` artifact.
- Repository source for service health-check clues.

Task:
For every critical or high-risk credential, draft a safe human rotation procedure:
1. Generate a new credential in the provider dashboard/API manually.
2. Store it in the secrets manager or environment config.
3. Deploy/restart affected services in a safe order.
4. Verify each service is healthy with the new credential.
5. Revoke the old credential only after verification.
6. Note when git history exposure means rotation alone is not enough.
7. For hardcoded credentials, describe the code change to move them into a secrets manager before rotation.
8. Estimate downtime risk and rollback for every step.

Return one `rotation_plan` artifact only:

```json
{
  "rotations": [
    {
      "credential_name": "STRIPE_SECRET_KEY",
      "risk_level": "critical",
      "steps": [
        {
          "action": "Generate replacement Stripe secret key manually in the Stripe dashboard",
          "target": "Stripe dashboard",
          "verification": "New key exists and is not yet active in production services",
          "rollback": "Do not revoke the old key"
        }
      ],
      "services_affected": ["web", "billing-worker"],
      "estimated_downtime": "low if both services are restarted after secret update; high if only one service is updated",
      "requires_code_change": true,
      "code_change_description": "Move config/payment.yml hardcoded key to ENV.fetch(\"STRIPE_SECRET_KEY\") backed by the secrets manager before rotating."
    }
  ],
  "rotation_order": ["STRIPE_SECRET_KEY"]
}
```
````

**Step 6: Run seed spec to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb:NEW_LINE_NUMBER
```

Expected: PASS.

**Step 7: Commit**

```bash
git add config/queues/credential_rotation.yml \
  prompts/credential_scan.md \
  prompts/credential_dependencies.md \
  prompts/credential_risk.md \
  prompts/credential_rotation_plan.md \
  spec/models/work_queue_seed_spec.rb
git commit -m "feat: add credential rotation queue seed"
```

---

### Task 6: Add Docker-friendly leaky credential fixture app

**Objective:** Provide a deterministic repository-shaped fixture containing hardcoded secrets, environment variable references, CI/Docker references, and shared dependencies for prompt and workflow testing.

**Files:**

- Create: `test/fixtures/apps/leaky_credentials/README.md`
- Create: `test/fixtures/apps/leaky_credentials/Gemfile`
- Create: `test/fixtures/apps/leaky_credentials/.env.example`
- Create: `test/fixtures/apps/leaky_credentials/config/payment.yml`
- Create: `test/fixtures/apps/leaky_credentials/config/secrets.yml`
- Create: `test/fixtures/apps/leaky_credentials/config/docker-compose.yml`
- Create: `test/fixtures/apps/leaky_credentials/.github/workflows/deploy.yml`
- Create: `test/fixtures/apps/leaky_credentials/Dockerfile`
- Create: `test/fixtures/apps/leaky_credentials/app/services/payment_gateway.rb`
- Create: `test/fixtures/apps/leaky_credentials/app/services/billing_reconciler.rb`
- Create: `test/fixtures/apps/leaky_credentials/app/services/analytics_client.rb`
- Create: `test/fixtures/apps/leaky_credentials/app/jobs/nightly_billing_job.rb`
- Create: `test/fixtures/apps/leaky_credentials/bin/credential-audit-smoke`

**Step 1: Write fixture files**

Create `README.md` describing that all values are fake and intentionally unsafe for scanner tests:

```markdown
# Leaky Credentials Fixture

This fixture is intentionally unsafe source text for the Credential Rotation Audit cookbook. All credential-looking values are fake. Agents should use it to find hardcoded secrets, environment-variable references, Docker/CI references, shared payment credentials, and secrets-manager references without contacting external services.
```

Create `config/payment.yml`:

```yaml
production:
  stripe_secret_key: sk_live_FAKE_18_MONTH_OLD_ADMIN_KEY
  stripe_publishable_key: pk_live_FAKE_PUBLIC_KEY
  webhook_secret: whsec_FAKE_SHARED_WEBHOOK_SECRET
```

Create `config/secrets.yml`:

```yaml
production:
  database_password: <%= ENV.fetch("DATABASE_PASSWORD") %>
  github_token: <%= ENV["GITHUB_DEPLOY_TOKEN"] %>
  vault_payment_key: vault://payments/stripe_secret_key
```

Create `.env.example`:

```dotenv
DATABASE_PASSWORD=replace-me
STRIPE_SECRET_KEY=sk_live_FAKE_ENV_PAYMENT_KEY
ANALYTICS_WRITE_KEY=analytics_FAKE_WRITE_KEY
```

Create `Dockerfile`:

```dockerfile
FROM ruby:3.3
ENV LEGACY_DOCKER_TOKEN=docker-layer-FAKE-token
WORKDIR /app
COPY . .
CMD ["ruby", "bin/credential-audit-smoke"]
```

Create `.github/workflows/deploy.yml`:

```yaml
name: deploy
on: [push]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bundle exec rake deploy
        env:
          STRIPE_SECRET_KEY: ${{ secrets.STRIPE_SECRET_KEY }}
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

Create service/job files where the same `STRIPE_SECRET_KEY` is read by multiple services at startup and runtime:

```ruby
# app/services/payment_gateway.rb
class PaymentGateway
  CONFIG = YAML.load_file(File.expand_path("../../config/payment.yml", __dir__)).fetch("production")

  def self.charge(cents)
    key = CONFIG.fetch("stripe_secret_key")
    "charged #{cents} with #{key[0, 7]}"
  end
end
```

```ruby
# app/services/billing_reconciler.rb
class BillingReconciler
  def self.reconcile
    key = ENV.fetch("STRIPE_SECRET_KEY")
    "reconcile with #{key[0, 7]}"
  end
end
```

```ruby
# app/services/analytics_client.rb
class AnalyticsClient
  def self.write_key
    ENV["ANALYTICS_WRITE_KEY"]
  end
end
```

```ruby
# app/jobs/nightly_billing_job.rb
class NightlyBillingJob
  def perform
    PaymentGateway.charge(1000)
    BillingReconciler.reconcile
  end
end
```

Create `bin/credential-audit-smoke`:

```ruby
#!/usr/bin/env ruby
puts "credential audit fixture present"
```

Set it executable:

```bash
chmod +x test/fixtures/apps/leaky_credentials/bin/credential-audit-smoke
```

**Step 2: Run fixture smoke command**

```bash
test/fixtures/apps/leaky_credentials/bin/credential-audit-smoke
```

Expected: prints `credential audit fixture present`.

**Step 3: Run seed spec again**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb:NEW_LINE_NUMBER
```

Expected: PASS and confirms fixture path is repo-relative.

**Step 4: Commit**

```bash
git add test/fixtures/apps/leaky_credentials
git commit -m "test: add credential rotation fixture app"
```

---

### Task 7: Add workflow integration coverage

**Objective:** Prove the artifact-backed credential rotation workflow can advance through the staged predicate contract using realistic fixture-shaped artifacts.

**Files:**

- Create: `spec/services/engine/credential_rotation_workflow_integration_spec.rb`

**Step 1: Write failing integration spec**

Create `spec/services/engine/credential_rotation_workflow_integration_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "credential rotation workflow integration" do
  it "advances through read-only artifact-backed credential stages" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "credential_rotation")
    work_item = WorkItem.create!(
      title: "Audit leaky credential fixture",
      spec_url: "test/fixtures/apps/leaky_credentials/README.md",
      work_queue: queue,
      stage_name: "scan_secrets"
    )

    scan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: scan_claim,
      work_item: work_item,
      kind: "secret_inventory",
      data: {
        "secrets" => [
          {
            "name" => "STRIPE_SECRET_KEY",
            "type" => "payment_api_key",
            "locations" => [
              { "file" => "test/fixtures/apps/leaky_credentials/config/payment.yml", "line" => 2, "how" => "hardcoded" },
              { "file" => "test/fixtures/apps/leaky_credentials/app/services/billing_reconciler.rb", "line" => 3, "how" => "env_var" }
            ],
            "in_git_history" => true
          }
        ],
        "total_count" => 1,
        "hardcoded_count" => 1
      }
    )
    expect(Engine::Predicates::SecretsScanned.new(claim: scan_claim).call).to be_passed

    dependency_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: dependency_claim,
      work_item: work_item,
      kind: "dependency_map",
      data: {
        "credentials" => [
          {
            "name" => "STRIPE_SECRET_KEY",
            "type" => "payment_api_key",
            "scope" => "payment admin",
            "services" => [
              { "name" => "web", "reads_at" => "startup", "fallback" => false },
              { "name" => "billing-worker", "reads_at" => "startup", "fallback" => false }
            ],
            "shared_across" => 2,
            "rotation_requires_restart" => true
          }
        ]
      }
    )
    expect(Engine::Predicates::DependenciesMapped.new(claim: dependency_claim).call).to be_passed

    risk_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: risk_claim,
      work_item: work_item,
      kind: "risk_assessment",
      data: {
        "credentials" => [
          {
            "name" => "STRIPE_SECRET_KEY",
            "exposure_risk" => "hardcoded and in git history",
            "blast_radius" => "payment provider admin",
            "estimated_age_days" => 540,
            "sharing_risk" => "shared across web and billing-worker",
            "overall_risk" => "critical",
            "rationale" => "Rotate immediately after moving to a secrets manager."
          }
        ],
        "critical_count" => 1,
        "summary" => "One critical credential requires coordinated rotation."
      }
    )
    risk_result = Engine::Predicates::RiskAssessed.new(claim: risk_claim).call
    expect(risk_result).to be_passed
    expect(risk_result.evidence[:critical_count]).to eq(1)

    plan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: plan_claim,
      work_item: work_item,
      kind: "rotation_plan",
      data: {
        "rotations" => [
          {
            "credential_name" => "STRIPE_SECRET_KEY",
            "risk_level" => "critical",
            "steps" => [
              {
                "action" => "Generate replacement Stripe key manually",
                "target" => "Stripe dashboard",
                "verification" => "New key exists but old key remains active",
                "rollback" => "Keep old key active"
              },
              {
                "action" => "Update STRIPE_SECRET_KEY in the secrets manager and restart web then billing-worker",
                "target" => "web,billing-worker",
                "verification" => "Payment and nightly billing health checks pass",
                "rollback" => "Restore old secret value and restart services"
              }
            ],
            "services_affected" => ["web", "billing-worker"],
            "estimated_downtime" => "low with rolling restart",
            "requires_code_change" => true,
            "code_change_description" => "Move config/payment.yml hardcoded value to ENV.fetch before rotating."
          }
        ],
        "rotation_order" => ["STRIPE_SECRET_KEY"]
      }
    )
    plan_result = Engine::Predicates::RotationPlanned.new(claim: plan_claim).call
    expect(plan_result).to be_passed
    expect(plan_result.evidence[:rotations_count]).to eq(1)
  end
end
```

**Step 2: Run integration spec to verify RED or GREEN**

If Tasks 1-6 are complete, this should pass on first run. If it fails, it should fail for missing implementation detail in the current slice, not because of typos.

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/credential_rotation_workflow_integration_spec.rb
```

Expected after implementation: PASS.

**Step 3: Run broader relevant specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/credential_rotation_workflow_integration_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/predicates/secrets_scanned_spec.rb \
  spec/services/engine/predicates/dependencies_mapped_spec.rb \
  spec/services/engine/predicates/risk_assessed_spec.rb \
  spec/services/engine/predicates/rotation_planned_spec.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add spec/services/engine/credential_rotation_workflow_integration_spec.rb
git commit -m "test: cover credential rotation workflow"
```

---

### Task 8: Documentation and safety review

**Objective:** Verify the cookbook implementation remains portable, read-only, and documented enough for future workers.

**Files:**

- Optional create: `docs/cookbooks/credential-rotation-audit.md` only if the repository's current cookbook docs index expects per-cookbook narrative docs by implementation time.
- Modify: existing cookbook index only if there is an established index file and the nearby implemented cookbooks already use it.

**Step 1: Inspect docs convention**

```bash
ls docs/cookbooks 2>/dev/null || true
```

If files such as `docs/cookbooks/background-job-observability.md` exist and are source-controlled by then, create `docs/cookbooks/credential-rotation-audit.md` with:

```markdown
# Credential Rotation Audit

The `credential_rotation` cookbook is a read-only advisory queue for finding credentials, mapping dependencies, scoring rotation risk, and drafting human-executed rotation plans. It never rotates, revokes, deploys, restarts, or contacts credential providers automatically.
```

If no per-cookbook docs convention exists yet, skip this file.

**Step 2: Run portability checks**

```bash
grep -R "/Users/gregmushen\|/Users/" \
  config/queues/credential_rotation.yml \
  prompts/credential_scan.md \
  prompts/credential_dependencies.md \
  prompts/credential_risk.md \
  prompts/credential_rotation_plan.md \
  test/fixtures/apps/leaky_credentials \
  spec/services/engine/credential_rotation_workflow_integration_spec.rb \
  spec/services/engine/predicates/secrets_scanned_spec.rb \
  spec/services/engine/predicates/dependencies_mapped_spec.rb \
  spec/services/engine/predicates/risk_assessed_spec.rb \
  spec/services/engine/predicates/rotation_planned_spec.rb
```

Expected: no output. If the command exits 1 with no matches, that is acceptable.

**Step 3: Run final relevant test suite**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/credential_rotation_workflow_integration_spec.rb \
  spec/services/engine/predicates/secrets_scanned_spec.rb \
  spec/services/engine/predicates/dependencies_mapped_spec.rb \
  spec/services/engine/predicates/risk_assessed_spec.rb \
  spec/services/engine/predicates/rotation_planned_spec.rb
```

Expected: PASS.

**Step 4: Review changed files**

```bash
git status --short
git diff --stat
git diff -- config/queues/credential_rotation.yml prompts/credential_scan.md prompts/credential_dependencies.md prompts/credential_risk.md prompts/credential_rotation_plan.md
```

Expected:

- All credential rotation files are repo-relative.
- Prompt files say READ-ONLY and explicitly prohibit rotation/deploy/revocation.
- Queue YAML has no `working_directory` and no absolute paths.
- Human review stage uses `fake`, `report_present`, and `timeout_seconds: 86400`.

**Step 5: Commit docs if created**

```bash
git add docs/cookbooks/credential-rotation-audit.md
git commit -m "docs: add credential rotation cookbook notes"
```

Skip if no docs file was added.

---

## Final Acceptance Criteria

Implementation is complete when:

- `config/queues/credential_rotation.yml` seeds a queue named `Credential Rotation Audit` with stages `scan_secrets`, `map_dependencies`, `assess_risk`, `draft_rotation_plan`, `human_review`, and `done`.
- All queue prompt paths are repo-relative `file://prompts/credential_*.md` entries and resolve through `db/seeds.rb`.
- Prompt text is resolved into `StageConfig#agent_prompt` and does not remain a `file://` literal after seeding.
- Queue YAML, prompts, specs, and fixtures contain no absolute checkout paths such as `/Users/gregmushen/...`.
- Predicates `secrets_scanned`, `dependencies_mapped`, `risk_assessed`, and `rotation_planned` are implemented, registered, and covered by focused specs.
- The `rotation_planned` predicate requires at least one rotation and at least one step per rotation.
- The fixture app under `test/fixtures/apps/leaky_credentials/` includes fake hardcoded credentials, env var references, Docker/CI references, and multiple services sharing a payment credential.
- `spec/services/engine/credential_rotation_workflow_integration_spec.rb` proves the staged artifact contract with realistic artifacts.
- The implementation remains read-only/advisory: no stage has `deploy`, `mutate_database`, or external mutation permissions; prompts prohibit actual rotation/revocation.
- Relevant tests pass with Greg's rbenv command shape.

Final verification command:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/credential_rotation_workflow_integration_spec.rb \
  spec/services/engine/predicates/secrets_scanned_spec.rb \
  spec/services/engine/predicates/dependencies_mapped_spec.rb \
  spec/services/engine/predicates/risk_assessed_spec.rb \
  spec/services/engine/predicates/rotation_planned_spec.rb
```

Expected: all examples pass.

---

## Suggested Implementation Commit Boundaries

1. `test: specify credential rotation predicates`
2. `feat: add credential rotation predicates`
3. `feat: register credential rotation predicates`
4. `test: specify credential rotation queue seed`
5. `feat: add credential rotation queue seed`
6. `test: add credential rotation fixture app`
7. `test: cover credential rotation workflow`
8. Optional: `docs: add credential rotation cookbook notes`

If the Kanban implementation card asks for a single commit, squash these into:

`feat: add credential rotation cookbook`
