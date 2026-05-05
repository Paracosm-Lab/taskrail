# Integration Test Generator Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `integration_tests` cookbook queue so StupidClaw can map critical end-to-end user flows, identify integration boundaries, generate runnable integration specs, run them, and gate the results through human review.

**Architecture:** This follows StupidClaw's seeded cookbook architecture: add portable queue YAML under `config/queues/`, keep long prompts in repo-relative prompt files, add two artifact predicates under `Engine::Predicates`, reuse and slightly broaden `tests_generated` so it accepts the cookbook's `integration_specs` artifact kind, and cover everything with focused RSpec seed/predicate/E2E specs. The deterministic E2E fixture uses StupidClaw itself as the integration target and avoids real Claude/Docker calls by adding cookbook-aware fake adapter outputs for the exact stage names.

**Tech Stack:** Rails, RSpec, seeded YAML queues, `file://` prompt resolution via `Rails.root`, `WorkQueue`/`StageConfig`/`WorkItem`/`Claim`/`Artifact`, `Engine::Runner`, `Engine::TransitionManager`, `Engine::PredicateRegistry`, `Adapters::FakeAdapter`, `Adapters::ShellScriptAdapter`, rbenv on Greg's Mac.

**Source Spec:** `docs/specs/cookbook-16-integration-test-generator.md`

---

## Implementation principles

- Use strict TDD for every production behavior change: write a failing spec, run it and confirm the expected failure, implement the smallest change, rerun the focused spec, then run the relevant broader spec.
- Do not hardcode `/Users/gregmushen/...` or any absolute checkout path in app/config code, queue YAML, prompts, fixture data, or specs. Use repo-relative paths and `Rails.root` in tests.
- Queue prompts must use relative `file://prompts/...` paths so `db/seeds.rb` resolves them from `Rails.root`.
- Do not add `working_directory` to queue YAML unless a failing adapter spec proves it is required. Existing shell adapters should default to `Rails.root.to_s`.
- Keep fake/docker-friendly infrastructure local and deterministic. Do not add cookbook-specific Docker Compose services; use StupidClaw's Rails app, the existing fake adapter, and a spec fixture flow.
- Use Greg's Mac rbenv command shape for focused tests:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Commit after each completed implementation task. If the Kanban assignment wants a single final commit, squash task commits before completion.

## Files to create or modify

Create:
- `app/services/engine/predicates/flows_mapped.rb`
- `app/services/engine/predicates/boundaries_identified.rb`
- `spec/services/engine/predicates/flows_mapped_spec.rb`
- `spec/services/engine/predicates/boundaries_identified_spec.rb`
- `config/queues/integration_tests.yml`
- `prompts/integration_map_flows.md`
- `prompts/integration_boundaries.md`
- `prompts/integration_generate.md`
- `spec/e2e/integration_tests_cookbook_spec.rb`
- `docs/cookbooks/integration-test-generator.md`

Modify:
- `app/services/engine/predicate_registry.rb`
- `app/services/engine/predicates/tests_generated.rb`
- `app/adapters/adapters/fake_adapter.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/services/engine/predicates/tests_generated_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Do not modify unless a failing spec proves it is necessary:
- `db/seeds.rb` because it already loads every `config/queues/*.yml` and resolves `file://` prompt paths relative to `Rails.root`.
- `Adapters::ShellScriptAdapter` because this cookbook should rely on existing Rails-root defaults and existing `tests_passed` predicate behavior.
- shared cookbook Docker infrastructure under `cookbooks/docker-compose.yml`.

---

### Task 1: Add RED specs for the `flows_mapped` predicate

**Objective:** Define the `flows_mapped` predicate contract: it passes only when a claim has a `user_flows` artifact with at least one well-formed flow.

**Files:**
- Create: `spec/services/engine/predicates/flows_mapped_spec.rb`
- Later create: `app/services/engine/predicates/flows_mapped.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/flows_mapped_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::FlowsMapped do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Integration Tests #{SecureRandom.hex(4)}",
      slug: "integration-tests-flows-#{SecureRandom.hex(4)}",
      stages: %w[map_user_flows done]
    )
    queue.stage_configs.create!(stage_name: "map_user_flows", adapter_type: "fake")
    item = WorkItem.create!(title: "Map critical flows", spec_url: "opaque spec", work_queue: queue, stage_name: "map_user_flows")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: :completed, started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when a user_flows artifact has at least one flow" do
    claim = build_claim(
      artifacts: [
        {
          kind: "user_flows",
          data: {
            "flows" => [
              {
                "name" => "Create work item and advance",
                "entry_point" => "POST /api/v1/work_items",
                "steps" => [
                  {
                    "action" => "create work item",
                    "service" => "Api::V1::WorkItemsController",
                    "endpoint_or_method" => "create",
                    "data_deps" => ["integration_tests queue"]
                  }
                ],
                "expected_outcome" => "work item advances after engine tick",
                "services_involved" => ["API", "Engine::Runner", "Adapters::FakeAdapter"]
              }
            ]
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "user_flows")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, flows_count: 1 })
  end

  it "fails when the user_flows artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no user_flows artifact found")
  end

  it "fails when flows is empty" do
    claim = build_claim(artifacts: [{ kind: "user_flows", data: { "flows" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("user_flows artifact has no flows")
  end

  it "fails when the flow has no steps" do
    claim = build_claim(
      artifacts: [
        {
          kind: "user_flows",
          data: { "flows" => [{ "name" => "Incomplete", "entry_point" => "POST /api/v1/work_items", "steps" => [] }] }
        }
      ]
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("user_flows artifact has flows without steps: Incomplete")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/flows_mapped_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::FlowsMapped`.

**Step 3: Commit?**

Do not commit the failing spec alone. Continue to Task 2 and commit once the predicate is green.

---

### Task 2: Implement the `flows_mapped` predicate

**Objective:** Add the minimal predicate implementation needed to satisfy Task 1.

**Files:**
- Create: `app/services/engine/predicates/flows_mapped.rb`
- Test: `spec/services/engine/predicates/flows_mapped_spec.rb`

**Step 1: Write minimal implementation**

Create `app/services/engine/predicates/flows_mapped.rb`:

```ruby
module Engine
  module Predicates
    class FlowsMapped
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "user_flows").order(created_at: :desc, id: :desc).first
        return PredicateResult.fail(reason: "no user_flows artifact found") unless artifact

        flows = artifact.data["flows"]
        return PredicateResult.fail(reason: "user_flows artifact has no flows") unless flows.is_a?(Array) && flows.any?

        flows_without_steps = flows.select { |flow| Array(flow["steps"]).empty? }
        if flows_without_steps.any?
          names = flows_without_steps.map { |flow| flow["name"].presence || "unnamed flow" }.join(", ")
          return PredicateResult.fail(reason: "user_flows artifact has flows without steps: #{names}")
        end

        PredicateResult.pass(evidence: { artifact_id: artifact.id, flows_count: flows.count })
      end
    end
  end
end
```

**Step 2: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/flows_mapped_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/flows_mapped.rb spec/services/engine/predicates/flows_mapped_spec.rb
git commit -m "feat: add flows mapped predicate"
```

---

### Task 3: Add RED specs for the `boundaries_identified` predicate

**Objective:** Define the `boundaries_identified` predicate contract: it passes only when a `boundary_map` artifact contains at least one flow and every flow has at least one boundary.

**Files:**
- Create: `spec/services/engine/predicates/boundaries_identified_spec.rb`
- Later create: `app/services/engine/predicates/boundaries_identified.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/boundaries_identified_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::BoundariesIdentified do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Integration Boundaries #{SecureRandom.hex(4)}",
      slug: "integration-boundaries-#{SecureRandom.hex(4)}",
      stages: %w[identify_boundaries done]
    )
    queue.stage_configs.create!(stage_name: "identify_boundaries", adapter_type: "fake")
    item = WorkItem.create!(title: "Identify boundaries", spec_url: "opaque spec", work_queue: queue, stage_name: "identify_boundaries")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: :completed, started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when a boundary_map artifact has boundaries for each flow" do
    claim = build_claim(
      artifacts: [
        {
          kind: "boundary_map",
          data: {
            "flows" => [
              {
                "name" => "Create work item and advance",
                "boundaries" => [
                  { "from" => "API", "to" => "WorkItem", "contract" => "persist item", "stub_strategy" => "real database" },
                  { "from" => "Engine::Runner", "to" => "Adapters::FakeAdapter", "contract" => "claim assignment", "stub_strategy" => "fake adapter" }
                ],
                "setup_data" => ["integration_tests queue"],
                "teardown" => "database cleanup"
              }
            ]
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "boundary_map")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, flows_count: 1, boundaries_count: 2 })
  end

  it "fails when the boundary_map artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no boundary_map artifact found")
  end

  it "fails when the boundary_map has no flows" do
    claim = build_claim(artifacts: [{ kind: "boundary_map", data: { "flows" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("boundary_map artifact has no flows")
  end

  it "fails when any flow has no boundaries" do
    claim = build_claim(
      artifacts: [
        { kind: "boundary_map", data: { "flows" => [{ "name" => "Incomplete", "boundaries" => [] }] } }
      ]
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("boundary_map artifact has flows without boundaries: Incomplete")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/boundaries_identified_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::BoundariesIdentified`.

**Step 3: Commit?**

Do not commit the failing spec alone. Continue to Task 4 and commit once the predicate is green.

---

### Task 4: Implement the `boundaries_identified` predicate

**Objective:** Add the minimal predicate implementation needed to satisfy Task 3.

**Files:**
- Create: `app/services/engine/predicates/boundaries_identified.rb`
- Test: `spec/services/engine/predicates/boundaries_identified_spec.rb`

**Step 1: Write minimal implementation**

Create `app/services/engine/predicates/boundaries_identified.rb`:

```ruby
module Engine
  module Predicates
    class BoundariesIdentified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "boundary_map").order(created_at: :desc, id: :desc).first
        return PredicateResult.fail(reason: "no boundary_map artifact found") unless artifact

        flows = artifact.data["flows"]
        return PredicateResult.fail(reason: "boundary_map artifact has no flows") unless flows.is_a?(Array) && flows.any?

        flows_without_boundaries = flows.select { |flow| Array(flow["boundaries"]).empty? }
        if flows_without_boundaries.any?
          names = flows_without_boundaries.map { |flow| flow["name"].presence || "unnamed flow" }.join(", ")
          return PredicateResult.fail(reason: "boundary_map artifact has flows without boundaries: #{names}")
        end

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            flows_count: flows.count,
            boundaries_count: flows.sum { |flow| Array(flow["boundaries"]).count }
          }
        )
      end
    end
  end
end
```

**Step 2: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/boundaries_identified_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/boundaries_identified.rb spec/services/engine/predicates/boundaries_identified_spec.rb
git commit -m "feat: add boundaries identified predicate"
```

---

### Task 5: Register the new predicates

**Objective:** Make `Engine::PredicateRegistry.resolve` return both new predicate classes.

**Files:**
- Modify: `app/services/engine/predicate_registry.rb`
- Modify: `spec/services/engine/predicate_registry_spec.rb`

**Step 1: Write failing registry expectations**

Modify `spec/services/engine/predicate_registry_spec.rb` and add these expectations to the known predicate example:

```ruby
expect(described_class.resolve("flows_mapped")).to eq(Engine::Predicates::FlowsMapped)
expect(described_class.resolve("boundaries_identified")).to eq(Engine::Predicates::BoundariesIdentified)
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate: flows_mapped`.

**Step 3: Register predicates**

Modify `app/services/engine/predicate_registry.rb` so `PREDICATES` includes:

```ruby
"flows_mapped" => Predicates::FlowsMapped,
"boundaries_identified" => Predicates::BoundariesIdentified,
```

Put the mappings near the existing cookbook artifact predicates (`tests_generated`, `job_inventory_produced`, `observability_assessed`) to keep related predicates grouped.

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register integration test predicates"
```

---

### Task 6: Broaden `tests_generated` to accept `integration_specs`

**Objective:** Reuse the existing `tests_generated` predicate for this cookbook while honoring the source spec artifact kind `integration_specs`.

**Files:**
- Modify: `spec/services/engine/predicates/tests_generated_spec.rb`
- Modify: `app/services/engine/predicates/tests_generated.rb`

**Step 1: Write failing spec**

Append this example to `spec/services/engine/predicates/tests_generated_spec.rb`:

```ruby
it "passes when an integration_specs artifact has non-empty specs" do
  claim = build_claim(artifacts: [
    {
      kind: "integration_specs",
      data: {
        "specs" => [
          {
            "path" => "spec/requests/create_work_item_flow_spec.rb",
            "content" => "require \"rails_helper\"\n",
            "flow_name" => "Create work item and advance",
            "boundaries_tested" => ["API", "Engine"]
          }
        ]
      }
    }
  ])
  artifact = claim.artifacts.find_by!(kind: "integration_specs")

  result = described_class.new(claim: claim).call

  expect(result).to be_passed
  expect(result.evidence).to eq({ artifact_id: artifact.id, artifact_kind: "integration_specs", specs_count: 1 })
end
```

Update the existing passing `generated_tests` expectation to the richer evidence:

```ruby
expect(result.evidence).to eq({ artifact_id: artifact.id, artifact_kind: "generated_tests", specs_count: 1 })
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/tests_generated_spec.rb
```

Expected: FAIL because `integration_specs` is ignored, and the existing evidence does not include artifact kind/count yet.

**Step 3: Implement minimal broadening**

Modify `app/services/engine/predicates/tests_generated.rb`:

```ruby
module Engine
  module Predicates
    class TestsGenerated
      ACCEPTED_KINDS = %w[generated_tests integration_specs].freeze

      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: ACCEPTED_KINDS).order(created_at: :desc, id: :desc).detect do |item|
          item.data["specs"].is_a?(Array) && item.data["specs"].any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id, artifact_kind: artifact.kind, specs_count: artifact.data["specs"].count }) if artifact

        PredicateResult.fail(reason: "missing generated_tests or integration_specs artifact with specs")
      end
    end
  end
end
```

Update the missing/empty artifact failure expectations in `spec/services/engine/predicates/tests_generated_spec.rb` to:

```ruby
expect(result.reason).to eq("missing generated_tests or integration_specs artifact with specs")
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/tests_generated_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/tests_generated.rb spec/services/engine/predicates/tests_generated_spec.rb
git commit -m "feat: accept integration specs as generated tests"
```

---

### Task 7: Add RED seed spec for the `integration_tests` queue

**Objective:** Define the seeded queue contract before adding YAML or prompt files.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/integration_tests.yml`
- Later create: `prompts/integration_map_flows.md`
- Later create: `prompts/integration_boundaries.md`
- Later create: `prompts/integration_generate.md`

**Step 1: Write failing seed spec**

Append this example inside `RSpec.describe "development queue seed" do` in `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the integration test generator queue with resolved portable prompts" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "integration_tests")
  expect(queue.name).to eq("Integration Test Generator")
  expect(queue.stages).to eq(%w[
    map_user_flows
    identify_boundaries
    generate_tests
    run_tests
    human_review
    done
  ])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_max_retries" => 2,
    "default_timeout_seconds" => 600,
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 3
  )

  map = queue.stage_configs.find_by!(stage_name: "map_user_flows")
  expect(map.adapter_type).to eq("inline_claude")
  expect(map.model_override).to eq("claude-sonnet-4-20250514")
  expect(map.allowed_skills).to eq(["read_repo"])
  expect(map.forbidden_skills).to include("edit_files", "deploy")
  expect(map.max_retries).to eq(1)
  expect(map.completion_criteria).to eq(["flows_mapped"])
  expect(map.agent_prompt).to include("# Integration Tests: Map User Flows")
  expect(map.agent_prompt).to include("user_flows")
  expect(map.agent_prompt).not_to start_with("file://")
  expect(map.agent_prompt).not_to include(Rails.root.to_s)
  expect(map.adapter_config).to eq("output_artifact_kind" => "user_flows")

  boundaries = queue.stage_configs.find_by!(stage_name: "identify_boundaries")
  expect(boundaries.adapter_type).to eq("inline_claude")
  expect(boundaries.model_override).to eq("claude-sonnet-4-20250514")
  expect(boundaries.allowed_skills).to eq(["read_repo"])
  expect(boundaries.forbidden_skills).to include("edit_files", "deploy")
  expect(boundaries.max_retries).to eq(1)
  expect(boundaries.completion_criteria).to eq(["boundaries_identified"])
  expect(boundaries.agent_prompt).to include("# Integration Tests: Identify Boundaries")
  expect(boundaries.agent_prompt).to include("boundary_map")
  expect(boundaries.agent_prompt).not_to start_with("file://")
  expect(boundaries.adapter_config).to eq("output_artifact_kind" => "boundary_map")

  generate = queue.stage_configs.find_by!(stage_name: "generate_tests")
  expect(generate.adapter_type).to eq("inline_claude")
  expect(generate.model_override).to eq("claude-sonnet-4-20250514")
  expect(generate.allowed_skills).to eq(["read_repo"])
  expect(generate.forbidden_skills).to eq(["deploy"])
  expect(generate.max_retries).to eq(2)
  expect(generate.completion_criteria).to eq(["tests_generated"])
  expect(generate.agent_prompt).to include("# Integration Tests: Generate Tests")
  expect(generate.agent_prompt).to include("integration_specs")
  expect(generate.agent_prompt).not_to start_with("file://")
  expect(generate.adapter_config).to eq("output_artifact_kind" => "integration_specs")

  run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
  expect(run_tests.adapter_type).to eq("shell_script")
  expect(run_tests.allowed_skills).to eq(["run_tests"])
  expect(run_tests.forbidden_skills).to include("edit_files", "deploy")
  expect(run_tests.max_retries).to eq(1)
  expect(run_tests.completion_criteria).to eq(["tests_passed"])
  expect(run_tests.timeout_seconds).to eq(600)
  expect(run_tests.adapter_config).not_to have_key("working_directory")
  expect(run_tests.adapter_config.fetch("commands")).to contain_exactly(
    include(
      "name" => "integration tests cookbook e2e",
      "artifact" => "test_results",
      "command" => "bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb"
    )
  )

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.completion_criteria).to eq(["report_present"])
  expect(human_review.timeout_seconds).to eq(86_400)

  done = queue.stage_configs.find_by!(stage_name: "done")
  expect(done.adapter_type).to eq("fake")
  expect(done.completion_criteria).to eq(["report_present"])

  serialized_queue = Rails.root.join("config/queues/integration_tests.yml").read
  expect(serialized_queue).not_to include(Rails.root.to_s)
  expect(serialized_queue).not_to include("/Users/")
  expect(serialized_queue).not_to include("working_directory:")
  expect(serialized_queue).to include("file://prompts/integration_map_flows.md")
end
```

**Step 2: Run seed spec to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL with `Couldn't find WorkQueue` for slug `integration_tests`.

**Step 3: Commit?**

Do not commit yet. Continue to Tasks 8-9 to add queue YAML and prompts, then commit the passing seed slice together.

---

### Task 8: Add portable queue YAML for `integration_tests`

**Objective:** Seed the `integration_tests` queue exactly from the cookbook spec using portable prompt file references and docker-friendly shell validation.

**Files:**
- Create: `config/queues/integration_tests.yml`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Create queue YAML**

Create `config/queues/integration_tests.yml`:

```yaml
name: Integration Test Generator
slug: integration_tests
stages:
  - map_user_flows
  - identify_boundaries
  - generate_tests
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 3
stage_configs:
  map_user_flows:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [flows_mapped]
    agent_prompt: file://prompts/integration_map_flows.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: user_flows
  identify_boundaries:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [boundaries_identified]
    agent_prompt: file://prompts/integration_boundaries.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: boundary_map
  generate_tests:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [tests_generated]
    agent_prompt: file://prompts/integration_generate.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: integration_specs
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [tests_passed]
    agent_prompt: Write generated integration spec files, run the focused integration suite, and report pass/fail with command output.
    timeout_seconds: 600
    adapter_config:
      commands:
        - name: integration tests cookbook e2e
          command: bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb
          artifact: test_results
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review mapped user flows, boundary map, and generated integration specs before applying them to production code.
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

Important:
- Do not include `working_directory`; rely on `ShellScriptAdapter` defaults.
- Keep the run command portable (`bundle exec rspec ...`) because the queue YAML is application config. Greg's rbenv path belongs in human/plan test commands, not seeded app config.
- The queue uses `output_artifact_kind: integration_specs`; Task 6 makes `tests_generated` accept that artifact kind.

**Step 2: Run seed spec to verify expected next failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL because prompt files such as `prompts/integration_map_flows.md` do not exist yet.

**Step 3: Commit?**

Do not commit yet. Continue to Task 9, then commit the queue/prompt/seed spec together after GREEN.

---

### Task 9: Add integration prompt files

**Objective:** Provide implementation-ready prompts for each inline Claude stage and make seed prompt resolution pass.

**Files:**
- Create: `prompts/integration_map_flows.md`
- Create: `prompts/integration_boundaries.md`
- Create: `prompts/integration_generate.md`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Create map flows prompt**

Create `prompts/integration_map_flows.md`:

```markdown
# Integration Tests: Map User Flows

You are the `map_user_flows` stage for the StupidClaw Integration Test Generator cookbook.

## Inputs

- Repository source files, routes, controllers, jobs, services, models, and documentation.
- Assignment context, including any target feature area or failing production scenario.
- Existing test directories and helper/factory patterns.

## Task

Identify the critical end-to-end flows that deserve integration tests. Prioritize:

1. Authentication: sign up, verify email, log in, access protected resource.
2. Core business flow: create thing, process thing, deliver thing, bill for thing.
3. Background processing: event fires, job enqueued, job runs, side effects happen.
4. Webhook handling: external service sends webhook, handler parses it, state changes.
5. Error recovery: operation fails, retries, then succeeds or escalates.

For each flow, include:

- `name`: short descriptive name.
- `entry_point`: route, controller action, command, job, webhook, or scheduler that starts the flow.
- `steps`: ordered actions with `action`, `service`, `endpoint_or_method`, and `data_deps`.
- `expected_outcome`: final externally visible state or durable side effect.
- `services_involved`: controllers, jobs, services, models, external APIs, queues, and stores touched.

## Output

Return only JSON that StupidClaw can parse:

```json
{
  "status": "success",
  "summary": "Mapped critical integration flows.",
  "reports": [
    { "status": "success", "body": "Mapped N critical user flows." }
  ],
  "artifacts": [
    {
      "kind": "user_flows",
      "data": {
        "flows": [
          {
            "name": "Create work item and advance",
            "entry_point": "POST /api/v1/work_items",
            "steps": [
              {
                "action": "create work item",
                "service": "Api::V1::WorkItemsController",
                "endpoint_or_method": "create",
                "data_deps": ["seeded integration_tests queue"]
              }
            ],
            "expected_outcome": "Engine tick claims work and advances the stage after predicates pass.",
            "services_involved": ["API", "WorkItem", "Engine::Runner", "Adapters::FakeAdapter", "Engine::TransitionManager"]
          }
        ]
      }
    }
  ]
}
```

Do not edit files in this stage.
```

**Step 2: Create boundaries prompt**

Create `prompts/integration_boundaries.md`:

```markdown
# Integration Tests: Identify Boundaries

You are the `identify_boundaries` stage for the StupidClaw Integration Test Generator cookbook.

## Inputs

- The upstream `user_flows` artifact.
- Source code for routes, controllers, jobs, services, models, adapters, and existing tests.

## Task

For each mapped flow, identify integration boundaries where one component talks to another:

- Controller to service to model to database.
- Service to external API.
- Controller to background job to side effect.
- Webhook to handler to state change.
- Engine/service to adapter to artifact/report persistence.

For each boundary, state:

- `from`: caller/component initiating the boundary.
- `to`: callee/component receiving the boundary.
- `contract`: the data or behavior contract between them.
- `stub_strategy`: `real` for internal app/database boundaries, `fake adapter`, `stub external API`, or `fixture` for non-app systems.

Also include setup data and teardown requirements.

## Output

Return only JSON that StupidClaw can parse:

```json
{
  "status": "success",
  "summary": "Identified integration boundaries for mapped flows.",
  "reports": [
    { "status": "success", "body": "Identified boundaries for N flows." }
  ],
  "artifacts": [
    {
      "kind": "boundary_map",
      "data": {
        "flows": [
          {
            "name": "Create work item and advance",
            "boundaries": [
              { "from": "HTTP client", "to": "Api::V1::WorkItemsController", "contract": "JSON request creates a pending WorkItem", "stub_strategy": "real request spec" },
              { "from": "Engine::Runner", "to": "Adapters::FakeAdapter", "contract": "assignment produces reports and artifacts", "stub_strategy": "fake adapter" },
              { "from": "Engine::TransitionManager", "to": "Engine::PredicateRegistry", "contract": "predicates validate artifacts and advance stage", "stub_strategy": "real predicates" }
            ],
            "setup_data": ["seeded integration_tests queue", "pending work item"],
            "teardown": "RSpec database transaction cleanup"
          }
        ]
      }
    }
  ]
}
```

Do not edit files in this stage.
```

**Step 3: Create generate tests prompt**

Create `prompts/integration_generate.md`:

```markdown
# Integration Tests: Generate Tests

You are the `generate_tests` stage for the StupidClaw Integration Test Generator cookbook.

## Inputs

- The upstream `boundary_map` artifact.
- Source code and existing test helpers/factories.
- Existing request, system, service, and E2E specs.

## Task

Write integration test files for the mapped flows. Use the project's actual test framework and style. For Rails/RSpec projects:

- Prefer request specs for HTTP/API boundaries.
- Use service/E2E specs when the flow crosses engine/adapter/background job boundaries.
- Set up data with existing models/factories/fixtures.
- Make real HTTP requests through the stack for controller/API flows.
- Assert durable final state and persisted artifacts/reports, not private intermediate method calls.
- Stub only external systems; keep internal controllers, services, jobs, models, and database real.
- Include a sad path for at least one critical flow.
- Keep generated files small, focused, and runnable in isolation.

## Output

Return only JSON that StupidClaw can parse:

```json
{
  "status": "success",
  "summary": "Generated integration specs for mapped flows.",
  "reports": [
    { "status": "success", "body": "Generated N integration specs." }
  ],
  "artifacts": [
    {
      "kind": "integration_specs",
      "data": {
        "specs": [
          {
            "path": "spec/e2e/create_work_item_flow_spec.rb",
            "content": "require \"rails_helper\"\n\nRSpec.describe \"create work item flow\" do\n  it \"advances through the engine\" do\n    # generated spec body\n  end\nend\n",
            "flow_name": "Create work item and advance",
            "boundaries_tested": ["API", "Engine", "Adapter", "Database"]
          }
        ]
      }
    }
  ]
}
```

Do not deploy. Do not mutate production data. Generated tests should use repo-relative paths only.
```

**Step 4: Run seed spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 5: Search for portability regressions**

Run:

```bash
grep -R "/Users/gregmushen/work/code/stupidclaw\|file:///.\|working_directory:" config/queues/integration_tests.yml prompts/integration_*.md
```

Expected: no output.

**Step 6: Commit**

```bash
git add \
  config/queues/integration_tests.yml \
  prompts/integration_map_flows.md \
  prompts/integration_boundaries.md \
  prompts/integration_generate.md \
  spec/models/work_queue_seed_spec.rb

git commit -m "feat: seed integration test generator queue"
```

---

### Task 10: Add deterministic fake adapter outputs for integration cookbook stages

**Objective:** Make the cookbook E2E spec able to exercise StupidClaw's real API, engine runner, adapter boundary, report/artifact persistence, predicates, and stage advancement without invoking real Claude or shell commands.

**Files:**
- Modify: `app/adapters/adapters/fake_adapter.rb`
- Test: `spec/e2e/integration_tests_cookbook_spec.rb` (created in Task 11)

**Step 1: Write the failing E2E first**

Do not implement adapter changes yet. Task 11 creates the failing E2E that proves why these fake outputs are needed.

Expected failure after Task 11 RED: the fake adapter's generic output does not create `user_flows`, `boundary_map`, `integration_specs`, or `test_results` artifacts, so predicates cannot advance the work item.

**Step 2: Add stage-specific fake results**

After Task 11 establishes RED, modify `app/adapters/adapters/fake_adapter.rb`.

Add stage cases in `execute`:

```ruby
when "map_user_flows"
  map_user_flows_result
when "identify_boundaries"
  identify_boundaries_result
when "generate_tests"
  generate_integration_tests_result
when "run_tests"
  integration_run_tests_result
```

Add private methods:

```ruby
def map_user_flows_result
  AgentResult.success(
    report: { "summary" => "mapped StupidClaw self-integration flow" },
    artifacts: [
      {
        "kind" => "user_flows",
        "data" => {
          "flows" => [
            {
              "name" => "Create work item and advance",
              "entry_point" => "POST /api/v1/work_items",
              "steps" => [
                { "action" => "create work item", "service" => "Api::V1::WorkItemsController", "endpoint_or_method" => "create", "data_deps" => ["integration queue"] },
                { "action" => "run engine tick", "service" => "Engine::Runner", "endpoint_or_method" => "call", "data_deps" => ["pending work item"] }
              ],
              "expected_outcome" => "work item advances after predicates pass",
              "services_involved" => ["API", "Engine::Runner", "Adapters::FakeAdapter", "Engine::TransitionManager", "Database"]
            }
          ]
        }
      }
    ],
    trace_events: [trace_event("mapped integration user flows")]
  )
end

def identify_boundaries_result
  AgentResult.success(
    report: { "summary" => "identified StupidClaw self-integration boundaries" },
    artifacts: [
      {
        "kind" => "boundary_map",
        "data" => {
          "flows" => [
            {
              "name" => "Create work item and advance",
              "boundaries" => [
                { "from" => "HTTP client", "to" => "Api::V1::WorkItemsController", "contract" => "creates pending work item", "stub_strategy" => "real request" },
                { "from" => "Engine::Runner", "to" => "Adapters::FakeAdapter", "contract" => "claim result includes reports/artifacts", "stub_strategy" => "fake adapter" },
                { "from" => "Engine::TransitionManager", "to" => "Engine::PredicateRegistry", "contract" => "artifacts satisfy criteria", "stub_strategy" => "real predicates" }
              ],
              "setup_data" => ["seeded queue", "pending work item"],
              "teardown" => "database cleanup"
            }
          ]
        }
      }
    ],
    trace_events: [trace_event("identified integration boundaries")]
  )
end

def generate_integration_tests_result
  AgentResult.success(
    report: { "summary" => "generated integration specs" },
    artifacts: [
      {
        "kind" => "integration_specs",
        "data" => {
          "specs" => [
            {
              "path" => "spec/e2e/create_work_item_flow_spec.rb",
              "content" => "require \"rails_helper\"\n\nRSpec.describe \"create work item flow\" do\n  it \"advances\" do\n    expect(true).to be(true)\n  end\nend\n",
              "flow_name" => "Create work item and advance",
              "boundaries_tested" => ["API", "Engine", "Adapter", "Database"]
            }
          ]
        }
      }
    ],
    trace_events: [trace_event("generated integration specs")]
  )
end

def integration_run_tests_result
  AgentResult.success(
    report: { "summary" => "integration specs passed" },
    artifacts: [
      { "kind" => "test_results", "data" => { "passed" => true, "command" => "bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb" } }
    ],
    trace_events: [trace_event("ran integration specs")]
  )
end
```

Note: This intentionally lives in the fake adapter because the E2E fixture must exercise the adapter boundary without network/model/shell dependencies. The production queue still uses `inline_claude` and `shell_script`; the spec will create a fake-backed deterministic queue.

**Step 3: Commit?**

Do not commit yet. Continue to Task 11 and commit fake adapter plus E2E spec together after GREEN.

---

### Task 11: Add StupidClaw self-integration E2E spec

**Objective:** Prove the cookbook can generate integration-test artifacts using a real API request, real engine ticks, real fake adapter boundary, real artifact/report persistence, real predicate checks, and real stage transitions.

**Files:**
- Create: `spec/e2e/integration_tests_cookbook_spec.rb`
- Modify: `app/adapters/adapters/fake_adapter.rb` from Task 10

**Step 1: Write failing E2E spec**

Create `spec/e2e/integration_tests_cookbook_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "integration test generator cookbook" do
  def create_fake_integration_queue
    queue = WorkQueue.create!(
      name: "Integration Test Generator Fixture #{SecureRandom.hex(4)}",
      slug: "integration-tests-fixture-#{SecureRandom.hex(4)}",
      stages: %w[map_user_flows identify_boundaries generate_tests run_tests done],
      config: { "default_max_retries" => 0, "max_regression_loops" => 0 }
    )

    queue.stage_configs.create!(stage_name: "map_user_flows", adapter_type: "fake", completion_criteria: ["flows_mapped"])
    queue.stage_configs.create!(stage_name: "identify_boundaries", adapter_type: "fake", completion_criteria: ["boundaries_identified"])
    queue.stage_configs.create!(stage_name: "generate_tests", adapter_type: "fake", completion_criteria: ["tests_generated"])
    queue.stage_configs.create!(stage_name: "run_tests", adapter_type: "fake", completion_criteria: ["tests_passed"])
    queue.stage_configs.create!(stage_name: "done", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end

  it "provides the configured integration_tests queue with docker-friendly shell validation" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "integration_tests")
    expect(queue.stages).to eq(%w[map_user_flows identify_boundaries generate_tests run_tests human_review done])

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.adapter_config).not_to have_key("working_directory")
    expect(run_tests.adapter_config.fetch("commands")).to include(
      include(
        "name" => "integration tests cookbook e2e",
        "command" => "bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb",
        "artifact" => "test_results"
      )
    )
  end

  it "resolves every inline Claude prompt from repo-relative file paths" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "integration_tests")
    %w[map_user_flows identify_boundaries generate_tests].each do |stage_name|
      stage = queue.stage_configs.find_by!(stage_name: stage_name)
      expect(stage.agent_prompt).to be_present
      expect(stage.agent_prompt).not_to start_with("file://")
      expect(stage.agent_prompt).to include("# Integration Tests:")
      expect(stage.agent_prompt).not_to include(Rails.root.to_s)
    end
  end

  it "drives a work item through API creation, engine ticks, adapter runs, artifacts, predicates, and transitions" do
    queue = create_fake_integration_queue

    post "/api/v1/work_items", params: {
      queue: queue.slug,
      title: "Generate integration specs for StupidClaw itself",
      spec_url: "docs/specs/cookbook-16-integration-test-generator.md",
      tags: { cookbook: "integration_tests" }
    }

    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending
    expect(work_item.stage_name).to eq("map_user_flows")

    10.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.claims.count).to eq(4)
    expect(work_item.transition_logs.pluck(:from_stage, :to_stage, :trigger)).to include(
      ["map_user_flows", "identify_boundaries", "rule_satisfied"],
      ["identify_boundaries", "generate_tests", "rule_satisfied"],
      ["generate_tests", "run_tests", "rule_satisfied"],
      ["run_tests", "done", "rule_satisfied"]
    )

    expect(work_item.artifacts.pluck(:kind)).to include("user_flows", "boundary_map", "integration_specs", "test_results")
    expect(work_item.artifacts.find_by!(kind: "user_flows").data.fetch("flows").first.fetch("steps")).not_to be_empty
    expect(work_item.artifacts.find_by!(kind: "boundary_map").data.fetch("flows").first.fetch("boundaries")).not_to be_empty
    expect(work_item.artifacts.find_by!(kind: "integration_specs").data.fetch("specs").first).to include(
      "path" => "spec/e2e/create_work_item_flow_spec.rb",
      "flow_name" => "Create work item and advance"
    )
    expect(work_item.artifacts.find_by!(kind: "test_results").data).to include("passed" => true)
  end

  it "keeps queue YAML portable and references only repo-relative prompt files" do
    yaml = Rails.root.join("config/queues/integration_tests.yml").read

    expect(yaml).not_to include(Rails.root.to_s)
    expect(yaml).not_to include("/Users/")
    expect(yaml).not_to include("file:///")
    expect(yaml).not_to include("working_directory:")
    expect(yaml.scan(/file:\/\/prompts\/integration_[a-z_]+\.md/).uniq).to contain_exactly(
      "file://prompts/integration_map_flows.md",
      "file://prompts/integration_boundaries.md",
      "file://prompts/integration_generate.md"
    )
  end

  it "covers the source cookbook spec stages, artifacts, and predicates" do
    source_spec = Rails.root.join("docs/specs/cookbook-16-integration-test-generator.md").read
    queue_yaml = Rails.root.join("config/queues/integration_tests.yml").read

    %w[
      map_user_flows
      identify_boundaries
      generate_tests
      run_tests
      human_review
      done
      user_flows
      boundary_map
      integration_specs
      flows_mapped
      boundaries_identified
      tests_generated
      tests_passed
    ].each do |required_term|
      expect(source_spec).to include(required_term)
      expect(queue_yaml).to include(required_term)
    end
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb
```

Expected before Task 10 implementation: FAIL because the fake adapter does not create the required artifacts for `map_user_flows`, `identify_boundaries`, `generate_tests`, or `run_tests`.

**Step 3: Implement Task 10 fake adapter methods**

Apply the `Adapters::FakeAdapter` additions from Task 10.

**Step 4: Run E2E spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/adapters/adapters/fake_adapter.rb spec/e2e/integration_tests_cookbook_spec.rb
git commit -m "test: cover integration test generator cookbook flow"
```

---

### Task 12: Add user-facing cookbook docs

**Objective:** Document how to run and interpret the Integration Test Generator cookbook without duplicating shared infrastructure setup.

**Files:**
- Create: `docs/cookbooks/integration-test-generator.md`

**Step 1: Write docs**

Create `docs/cookbooks/integration-test-generator.md`:

```markdown
# Integration Test Generator Cookbook

Source spec: `docs/specs/cookbook-16-integration-test-generator.md`

The `integration_tests` queue maps critical end-to-end user flows, identifies boundaries between components, generates integration specs, runs them, and pauses for human review.

## Stages

1. `map_user_flows`: writes a `user_flows` artifact with critical flows, steps, expected outcomes, and services involved.
2. `identify_boundaries`: writes a `boundary_map` artifact that describes component contracts and real-vs-stubbed boundaries.
3. `generate_tests`: writes an `integration_specs` artifact containing spec paths, contents, flow names, and boundaries tested.
4. `run_tests`: runs the generated/focused integration specs and writes `test_results`.
5. `human_review`: blocks for review before generated tests are accepted.
6. `done`: terminal state.

## Deterministic fixture

The E2E fixture in `spec/e2e/integration_tests_cookbook_spec.rb` uses StupidClaw itself as the integration target:

- API request creates a `WorkItem`.
- `Engine::Runner` claims each stage.
- `Adapters::FakeAdapter` emits deterministic reports/artifacts for cookbook stage names.
- Predicates verify `user_flows`, `boundary_map`, `integration_specs`, and `test_results`.
- `Engine::TransitionManager` advances the item to `done`.

This touches the API, engine, adapter, database, report/artifact persistence, predicates, and stage transition logs without calling real Claude, Docker, or external services.

## Infrastructure expectations

This cookbook assumes the shared StupidClaw development/test infrastructure is available. It does not define new Docker Compose services. Queue YAML uses repo-relative prompt files and relies on adapter defaults for the working directory.

## Focused tests

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/flows_mapped_spec.rb \
  spec/services/engine/predicates/boundaries_identified_spec.rb \
  spec/services/engine/predicates/tests_generated_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/e2e/integration_tests_cookbook_spec.rb
```
```

**Step 2: Verify docs mention source spec and focused commands**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add docs/cookbooks/integration-test-generator.md
git commit -m "docs: document integration test generator cookbook"
```

---

### Task 13: Run final focused verification

**Objective:** Verify all cookbook behavior is green and portable before handing off.

**Files:**
- No new files.

**Step 1: Run focused specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/flows_mapped_spec.rb \
  spec/services/engine/predicates/boundaries_identified_spec.rb \
  spec/services/engine/predicates/tests_generated_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/e2e/integration_tests_cookbook_spec.rb
```

Expected: PASS.

**Step 2: Run broader safety check if time allows**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine spec/models/work_queue_seed_spec.rb spec/e2e/integration_tests_cookbook_spec.rb
```

Expected: PASS. If this broader check fails because of unrelated existing failures, record the unrelated failures and keep the focused cookbook specs green.

**Step 3: Verify portability and source references**

Run:

```bash
! grep -R "/Users/gregmushen/work/code/stupidclaw\|file:///.\|working_directory:" \
  config/queues/integration_tests.yml \
  prompts/integration_*.md \
  spec/e2e/integration_tests_cookbook_spec.rb \
  docs/cookbooks/integration-test-generator.md

grep -R "docs/specs/cookbook-16-integration-test-generator.md" docs/cookbooks/integration-test-generator.md spec/e2e/integration_tests_cookbook_spec.rb
```

Expected:
- First command exits 0 with no matching hardcoded absolute paths or forbidden config.
- Second command prints the source spec references.

**Step 4: Verify final git state**

Run:

```bash
git status --short
git log --oneline -5
```

Expected: clean worktree and recent cookbook commits visible.

**Step 5: Final commit if needed**

If any verification-only doc/spec adjustments remain, commit them:

```bash
git add <changed files>
git commit -m "test: verify integration test generator cookbook"
```

---

## Acceptance checklist

- [ ] `flows_mapped` predicate passes only for non-empty `user_flows.flows` with steps and returns actionable evidence.
- [ ] `boundaries_identified` predicate passes only for non-empty `boundary_map.flows` with boundaries and returns actionable evidence.
- [ ] Predicate registry resolves `flows_mapped` and `boundaries_identified`.
- [ ] `tests_generated` accepts both legacy `generated_tests` and cookbook-specific `integration_specs` artifacts.
- [ ] `config/queues/integration_tests.yml` is seeded and has all six stages: `map_user_flows`, `identify_boundaries`, `generate_tests`, `run_tests`, `human_review`, `done`.
- [ ] Queue YAML uses repo-relative `file://prompts/integration_*.md` references and no hardcoded checkout paths.
- [ ] Prompt files describe exact JSON artifact shapes for `user_flows`, `boundary_map`, and `integration_specs`.
- [ ] Run-tests stage is docker-friendly, does not set `working_directory`, and uses `bundle exec rspec spec/e2e/integration_tests_cookbook_spec.rb`.
- [ ] E2E spec uses StupidClaw itself: API creates work item, engine tick claims stages, fake adapter runs, reports/artifacts are stored, predicates pass, stage advances to `done`.
- [ ] User-facing docs explain stages, artifact kinds, deterministic fixture, infrastructure expectations, and focused test command.
- [ ] Focused specs pass with Greg's rbenv command prefix.
- [ ] Final worktree is clean.
