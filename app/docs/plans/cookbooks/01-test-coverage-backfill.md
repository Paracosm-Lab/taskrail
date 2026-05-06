# Test Coverage Backfill Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `test_backfill` cookbook queue that scans coverage, identifies untested code paths, generates specs, runs them, regresses failed generated specs back for repair, and blocks for human review before merge.

**Architecture:** Seed a portable cookbook queue from `config/queues/test_backfill.yml`, resolve prompt text from relative `file://prompts/...` files through the existing `db/seeds.rb` resolver, and add three artifact-shape predicates for `coverage_map`, `test_plan`, and `generated_tests`. Keep shared infrastructure minimal: reuse Rails, the existing shell adapter, existing inline Claude adapter, existing fake/gate behavior, existing `tests_passed` predicate, and the default shell adapter `Rails.root` working directory instead of adding duplicated Docker or repo-clone infrastructure.

**Tech Stack:** Rails 8, PostgreSQL JSONB artifacts, RSpec, FactoryBot, YAML queue seeds, existing `Adapters::ShellScriptAdapter`, existing `Engine::TransitionManager`, existing `Engine::PredicateRegistry`.

**Source spec:** `docs/specs/cookbook-01-test-coverage-backfill.md`

**Output implementation dependencies:** This plan depends on the shared cookbook infrastructure plan for any common Docker service/fake external dependency setup. This plan only asks for a small fixture app and fake docker-friendly shell commands needed to exercise this cookbook queue.

---

## Current Codebase Facts

- Queue seed files live in `config/queues/*.yml` and are loaded by `db/seeds.rb`.
- `db/seeds.rb` resolves `agent_prompt: file://...` by reading `Rails.root.join(prompt_path)`, so prompt file paths must be relative to the Rails root.
- `Adapters::ShellScriptAdapter` defaults `working_directory` to `Rails.root.to_s`; do not hardcode `/Users/gregmushen/work/code/taskrail` in queue YAML.
- Existing predicate classes live in `app/services/engine/predicates/*.rb` and return `Engine::PredicateResult.pass(evidence: { artifact_id: artifact.id })` or a failure reason.
- `Engine::PredicateRegistry::PREDICATES` maps string names to predicate classes.
- Current regression handling in `Engine::TransitionManager` only supports review-stage `request_changes` regressions back to `build`; `run_tests -> generate_tests` regression needs new behavior.

## Focused Test Command Convention

Run focused specs with Greg's rbenv shims first in PATH:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec SPEC_PATH[:LINE] --format documentation
```

Run the relevant full slice before each commit:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/predicates/coverage_map_produced_spec.rb \
  spec/services/engine/predicates/test_plan_produced_spec.rb \
  spec/services/engine/predicates/tests_generated_spec.rb \
  spec/services/engine/transition_manager_regression_spec.rb
```

---

### Task 1: Add RED seed spec for the `test_backfill` queue skeleton

**Objective:** Prove the cookbook queue is seeded with the required stage order and portable stage configs before writing YAML.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/test_backfill.yml`
- Later create: `prompts/backfill_scan_coverage.md`
- Later create: `prompts/backfill_identify_gaps.md`
- Later create: `prompts/backfill_generate_tests.md`

**Step 1: Write failing spec**

Append this example inside `RSpec.describe "development queue seed" do` in `spec/models/work_queue_seed_spec.rb`:

```ruby
  it "seeds the test coverage backfill cookbook queue with resolved prompt files" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "test_backfill")
    expect(queue.name).to eq("Test Coverage Backfill")
    expect(queue.stages).to eq(%w[
      scan_coverage
      identify_gaps
      generate_tests
      run_tests
      human_review
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 3
    )

    scan = queue.stage_configs.find_by!(stage_name: "scan_coverage")
    expect(scan.adapter_type).to eq("shell_script")
    expect(scan.allowed_skills).to eq(["run_coverage"])
    expect(scan.forbidden_skills).to include("edit_files", "deploy")
    expect(scan.completion_criteria).to eq(["coverage_map_produced"])
    expect(scan.agent_prompt).to include("# Backfill Scan Coverage")
    expect(scan.agent_prompt).not_to start_with("file://")
    expect(scan.adapter_config).to include("output_artifact_kind" => "coverage_map")
    expect(scan.adapter_config).not_to have_key("working_directory")

    identify = queue.stage_configs.find_by!(stage_name: "identify_gaps")
    expect(identify.adapter_type).to eq("inline_claude")
    expect(identify.model_override).to eq("claude-sonnet-4-20250514")
    expect(identify.allowed_skills).to eq(["read_repo"])
    expect(identify.completion_criteria).to eq(["test_plan_produced"])
    expect(identify.agent_prompt).to include("# Backfill Identify Gaps")
    expect(identify.adapter_config).to include("output_artifact_kind" => "test_plan")

    generate = queue.stage_configs.find_by!(stage_name: "generate_tests")
    expect(generate.adapter_type).to eq("inline_claude")
    expect(generate.model_override).to eq("claude-sonnet-4-20250514")
    expect(generate.allowed_skills).to eq(["read_repo"])
    expect(generate.forbidden_skills).to include("deploy")
    expect(generate.completion_criteria).to eq(["tests_generated"])
    expect(generate.agent_prompt).to include("# Backfill Generate Tests")
    expect(generate.adapter_config).to include("output_artifact_kind" => "generated_tests")

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.allowed_skills).to eq(["run_tests"])
    expect(run_tests.completion_criteria).to eq(["tests_passed"])
    expect(run_tests.adapter_config).to include("output_artifact_kind" => "test_results")
    expect(run_tests.adapter_config).not_to have_key("working_directory")

    human_review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(human_review.adapter_type).to eq("fake")
    expect(human_review.timeout_seconds).to eq(86_400)
  end
```

**Step 2: Verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb --format documentation
```

Expected: FAIL with `ActiveRecord::RecordNotFound` for slug `test_backfill`.

**Step 3: Commit?**

Do not commit yet; this task intentionally leaves a failing test for Task 2.

---

### Task 2: Add the portable queue YAML and prompt files

**Objective:** Seed the cookbook queue from portable YAML and relative prompt files.

**Files:**
- Create: `config/queues/test_backfill.yml`
- Create: `prompts/backfill_scan_coverage.md`
- Create: `prompts/backfill_identify_gaps.md`
- Create: `prompts/backfill_generate_tests.md`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Create `config/queues/test_backfill.yml`**

```yaml
name: Test Coverage Backfill
slug: test_backfill
stages:
  - scan_coverage
  - identify_gaps
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
  scan_coverage:
    adapter_type: shell_script
    allowed_skills: [run_coverage]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [coverage_map_produced]
    agent_prompt: file://prompts/backfill_scan_coverage.md
    timeout_seconds: 300
    adapter_config:
      output_artifact_kind: coverage_map
      commands:
        - name: coverage-map-fixture
          command: ruby -rjson -e 'puts JSON.generate({files: [{path: "test/fixtures/apps/untested_app/app/models/widget.rb", coverage_pct: 42.0, uncovered_lines: ["8-14"]}]})'
  identify_gaps:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [test_plan_produced]
    agent_prompt: file://prompts/backfill_identify_gaps.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: test_plan
  generate_tests:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [tests_generated]
    agent_prompt: file://prompts/backfill_generate_tests.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: generated_tests
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [tests_passed]
    agent_prompt: Write generated spec files to disk and run the test suite. Report pass/fail with output.
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: test_results
      commands:
        - name: fixture-generated-specs
          command: ruby -e 'puts "fake generated spec run"'
          artifact: test_results
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review generated tests before merge.
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
- Do not add `working_directory`; `Adapters::ShellScriptAdapter` already defaults to `Rails.root.to_s`.
- The fake shell commands are docker-friendly because they only use Ruby stdlib and relative fixture paths.
- Do not add Docker Compose files here; shared Docker/Postgres/Redis infrastructure belongs in the shared cookbook infrastructure plan.

**Step 2: Create `prompts/backfill_scan_coverage.md`**

```markdown
# Backfill Scan Coverage

You are the coverage scanning stage for the Test Coverage Backfill cookbook.

Inputs:
- Target repository path or implicit working directory.
- Test framework configuration, such as RSpec or Minitest.

Rules:
- Do not edit source files.
- Prefer the repository working directory provided by the adapter; do not assume an absolute checkout path.
- Run or parse the configured coverage tool.
- Return one `coverage_map` artifact.

Artifact schema:

```json
{
  "files": [
    {
      "path": "relative/path/from/repo/root.rb",
      "coverage_pct": 42.0,
      "uncovered_lines": ["8-14"]
    }
  ]
}
```

Success criteria:
- The artifact kind is `coverage_map`.
- `files` is non-empty.
- Each file path is relative to the repository root.
```

**Step 3: Create `prompts/backfill_identify_gaps.md`**

```markdown
# Backfill Identify Gaps

You are the gap analysis stage for the Test Coverage Backfill cookbook.

Inputs:
- The latest `coverage_map` artifact.
- Repository source code and existing tests.

Rules:
- Read only. Do not edit files.
- Classify uncovered code into testable units.
- Prioritize public APIs and risky behavior over internal helpers.
- Prefer small units that can each become one focused spec example.

Artifact schema:

```json
{
  "units": [
    {
      "file": "relative/source/path.rb",
      "method": "method_or_action_name",
      "gap_type": "model validation | controller action | service method | error path | edge case",
      "risk": "high | medium | low",
      "description": "Specific behavior that needs a spec"
    }
  ]
}
```

Success criteria:
- The artifact kind is `test_plan`.
- `units` is non-empty.
```

**Step 4: Create `prompts/backfill_generate_tests.md`**

```markdown
# Backfill Generate Tests

You are the test generation stage for the Test Coverage Backfill cookbook.

Inputs:
- The latest `test_plan` artifact.
- Relevant source files.
- Existing test patterns in the repository.
- If this is a regression from `run_tests`, the prior failure output is provided as feedback.

Rules:
- Generate test files only; do not deploy or mutate production data.
- Match the repository's existing spec style, fixtures, and helper conventions.
- Use relative file paths from the repository root.
- If fixing a previous failed generated spec, preserve the intended coverage gap and adjust only what is needed for the spec to run.

Artifact schema:

```json
{
  "specs": [
    {
      "path": "spec/path/to/generated_spec.rb",
      "content": "require \"rails_helper\"\n..."
    }
  ]
}
```

Success criteria:
- The artifact kind is `generated_tests`.
- `specs` is non-empty.
- Each spec has a relative `path` and non-empty `content`.
```

**Step 5: Verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb --format documentation
```

Expected: PASS for the new seed example and existing seed examples.

**Step 6: Commit**

```bash
git add spec/models/work_queue_seed_spec.rb config/queues/test_backfill.yml prompts/backfill_scan_coverage.md prompts/backfill_identify_gaps.md prompts/backfill_generate_tests.md
git commit -m "feat: seed test coverage backfill queue"
```

---

### Task 3: Add RED specs for `coverage_map_produced`

**Objective:** Define the predicate behavior for a non-empty `coverage_map.files` artifact.

**Files:**
- Create: `spec/services/engine/predicates/coverage_map_produced_spec.rb`
- Later create: `app/services/engine/predicates/coverage_map_produced.rb`
- Later modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::CoverageMapProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Coverage Map Queue", slug: "coverage-map-#{SecureRandom.hex(4)}", stages: ["scan_coverage", "done"])
    queue.stage_configs.create!(stage_name: "scan_coverage", adapter_type: "fake")
    item = WorkItem.create!(title: "Backfill", spec_url: "opaque spec", work_queue: queue, stage_name: "scan_coverage")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when coverage_map artifact has non-empty files" do
    claim = build_claim(artifacts: [
      { kind: "coverage_map", data: { "files" => [{ "path" => "app/models/widget.rb", "coverage_pct" => 42.0, "uncovered_lines" => ["8-14"] }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "coverage_map")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when coverage_map artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing coverage_map artifact with files")
  end

  it "fails when files is empty" do
    claim = build_claim(artifacts: [{ kind: "coverage_map", data: { "files" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing coverage_map artifact with files")
  end
end
```

**Step 2: Verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/coverage_map_produced_spec.rb --format documentation
```

Expected: FAIL with `NameError: uninitialized constant Engine::Predicates::CoverageMapProduced`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/coverage_map_produced.rb`:

```ruby
module Engine
  module Predicates
    class CoverageMapProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "coverage_map").detect do |item|
          item.data["files"].is_a?(Array) && item.data["files"].any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing coverage_map artifact with files")
      end
    end
  end
end
```

**Step 4: Verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/coverage_map_produced_spec.rb --format documentation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/predicates/coverage_map_produced_spec.rb app/services/engine/predicates/coverage_map_produced.rb
git commit -m "feat: add coverage map predicate"
```

---

### Task 4: Add RED specs for `test_plan_produced`

**Objective:** Define predicate behavior for a non-empty `test_plan.units` artifact.

**Files:**
- Create: `spec/services/engine/predicates/test_plan_produced_spec.rb`
- Create: `app/services/engine/predicates/test_plan_produced.rb`

**Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::TestPlanProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Test Plan Queue", slug: "test-plan-#{SecureRandom.hex(4)}", stages: ["identify_gaps", "done"])
    queue.stage_configs.create!(stage_name: "identify_gaps", adapter_type: "fake")
    item = WorkItem.create!(title: "Backfill", spec_url: "opaque spec", work_queue: queue, stage_name: "identify_gaps")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when test_plan artifact has non-empty units" do
    claim = build_claim(artifacts: [
      { kind: "test_plan", data: { "units" => [{ "file" => "app/models/widget.rb", "method" => "#valid?", "gap_type" => "model validation", "risk" => "high", "description" => "validates name" }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "test_plan")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when test_plan artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing test_plan artifact with units")
  end

  it "fails when units is empty" do
    claim = build_claim(artifacts: [{ kind: "test_plan", data: { "units" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing test_plan artifact with units")
  end
end
```

**Step 2: Verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/test_plan_produced_spec.rb --format documentation
```

Expected: FAIL with `NameError`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/test_plan_produced.rb`:

```ruby
module Engine
  module Predicates
    class TestPlanProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "test_plan").detect do |item|
          item.data["units"].is_a?(Array) && item.data["units"].any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing test_plan artifact with units")
      end
    end
  end
end
```

**Step 4: Verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/test_plan_produced_spec.rb --format documentation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/predicates/test_plan_produced_spec.rb app/services/engine/predicates/test_plan_produced.rb
git commit -m "feat: add test plan predicate"
```

---

### Task 5: Add RED specs for `tests_generated`

**Objective:** Define predicate behavior for a non-empty `generated_tests.specs` artifact.

**Files:**
- Create: `spec/services/engine/predicates/tests_generated_spec.rb`
- Create: `app/services/engine/predicates/tests_generated.rb`

**Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::TestsGenerated do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Tests Generated Queue", slug: "tests-generated-#{SecureRandom.hex(4)}", stages: ["generate_tests", "done"])
    queue.stage_configs.create!(stage_name: "generate_tests", adapter_type: "fake")
    item = WorkItem.create!(title: "Backfill", spec_url: "opaque spec", work_queue: queue, stage_name: "generate_tests")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when generated_tests artifact has non-empty specs" do
    claim = build_claim(artifacts: [
      { kind: "generated_tests", data: { "specs" => [{ "path" => "spec/models/widget_spec.rb", "content" => "require \"rails_helper\"\n" }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "generated_tests")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when generated_tests artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing generated_tests artifact with specs")
  end

  it "fails when specs is empty" do
    claim = build_claim(artifacts: [{ kind: "generated_tests", data: { "specs" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing generated_tests artifact with specs")
  end
end
```

**Step 2: Verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/tests_generated_spec.rb --format documentation
```

Expected: FAIL with `NameError`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/tests_generated.rb`:

```ruby
module Engine
  module Predicates
    class TestsGenerated
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "generated_tests").detect do |item|
          item.data["specs"].is_a?(Array) && item.data["specs"].any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing generated_tests artifact with specs")
      end
    end
  end
end
```

**Step 4: Verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/tests_generated_spec.rb --format documentation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/predicates/tests_generated_spec.rb app/services/engine/predicates/tests_generated.rb
git commit -m "feat: add generated tests predicate"
```

---

### Task 6: Register the new predicates

**Objective:** Make queue completion criteria resolve through `Engine::PredicateRegistry`.

**Files:**
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing registry expectations**

Add these expectations to the `it "resolves known predicates"` example in `spec/services/engine/predicate_registry_spec.rb`:

```ruby
    expect(described_class.resolve("coverage_map_produced")).to eq(Engine::Predicates::CoverageMapProduced)
    expect(described_class.resolve("test_plan_produced")).to eq(Engine::Predicates::TestPlanProduced)
    expect(described_class.resolve("tests_generated")).to eq(Engine::Predicates::TestsGenerated)
```

**Step 2: Verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb --format documentation
```

Expected: FAIL with `Engine::PredicateRegistry::UnknownPredicate` for the first new predicate.

**Step 3: Register predicates**

Modify `app/services/engine/predicate_registry.rb` so `PREDICATES` includes:

```ruby
      "coverage_map_produced" => Predicates::CoverageMapProduced,
      "test_plan_produced" => Predicates::TestPlanProduced,
      "tests_generated" => Predicates::TestsGenerated,
```

Place them near the existing artifact predicates. Keep the hash frozen.

**Step 4: Verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb --format documentation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/predicate_registry_spec.rb app/services/engine/predicate_registry.rb
git commit -m "feat: register test backfill predicates"
```

---

### Task 7: Add a fixture app for end-to-end cookbook testing

**Objective:** Provide a tiny deliberately under-tested app surface for scan/gap/generation fixtures without depending on TaskRail's current incidental coverage gaps.

**Files:**
- Create: `test/fixtures/apps/untested_app/app/models/widget.rb`
- Create: `test/fixtures/apps/untested_app/spec/models/widget_spec.rb`
- Create: `test/fixtures/apps/untested_app/README.md`

**Step 1: Create fixture model**

Create `test/fixtures/apps/untested_app/app/models/widget.rb`:

```ruby
class Widget
  attr_reader :name, :quantity

  def initialize(name:, quantity:)
    @name = name
    @quantity = quantity
  end

  def valid?
    name.to_s.strip != "" && quantity.to_i.positive?
  end

  def reorder_message(threshold: 10)
    return "invalid widget" unless valid?
    return "reorder #{name}" if quantity < threshold

    "stock ok"
  end
end
```

**Step 2: Create intentionally incomplete spec**

Create `test/fixtures/apps/untested_app/spec/models/widget_spec.rb`:

```ruby
require_relative "../../../app/models/widget"

RSpec.describe Widget do
  it "is valid with a name and positive quantity" do
    widget = described_class.new(name: "Sprocket", quantity: 5)

    expect(widget).to be_valid
  end
end
```

**Step 3: Create fixture README**

Create `test/fixtures/apps/untested_app/README.md`:

```markdown
# Untested App Fixture

This tiny fixture app exists for the Test Coverage Backfill cookbook. It intentionally has behavior in `Widget#reorder_message` that is not covered by its spec so coverage scanning and test generation can use stable, deterministic paths.

The fixture is not a standalone Rails app and should not duplicate shared Docker infrastructure. Cookbook tests should run it from the TaskRail Rails root with relative paths.
```

**Step 4: Verify files parse**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec ruby -c test/fixtures/apps/untested_app/app/models/widget.rb
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec ruby -c test/fixtures/apps/untested_app/spec/models/widget_spec.rb
```

Expected: both print `Syntax OK`.

**Step 5: Commit**

```bash
git add test/fixtures/apps/untested_app/app/models/widget.rb test/fixtures/apps/untested_app/spec/models/widget_spec.rb test/fixtures/apps/untested_app/README.md
git commit -m "test: add untested app fixture for backfill cookbook"
```

---

### Task 8: Add RED spec for `run_tests` regression back to `generate_tests`

**Objective:** Prove failed generated specs regress from `run_tests` to `generate_tests` with failure feedback and max-loop enforcement.

**Files:**
- Modify: `spec/services/engine/transition_manager_regression_spec.rb`
- Modify: `app/services/engine/transition_manager.rb`

**Step 1: Write failing regression spec**

Append to `spec/services/engine/transition_manager_regression_spec.rb`:

```ruby
  it "moves failed generated tests from run_tests back to generate_tests with failure feedback" do
    queue = WorkQueue.create!(
      name: "Test Backfill",
      slug: "test-backfill-#{SecureRandom.hex(4)}",
      stages: %w[scan_coverage identify_gaps generate_tests run_tests human_review done],
      config: { "max_regression_loops" => 3 }
    )
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "run_tests", completion_criteria: ["tests_passed"])
    work_item = WorkItem.create!(work_queue: queue, title: "Backfill", spec_url: "opaque spec", stage_name: "run_tests", regression_count: 0, status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "shell", status: :completed)
    Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "test_results",
      data: { "passed" => false, "output" => "expected Widget#reorder_message to return stock ok", "failures" => ["Widget#reorder_message"] }
    )

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload.stage_name).to eq("generate_tests")
    expect(work_item).to be_pending
    expect(work_item.retry_count).to eq(0)
    expect(work_item.regression_count).to eq(1)
    expect(work_item.metadata["feedback"]).to include("expected Widget#reorder_message")
    expect(work_item.transition_logs.last.trigger).to eq("regression")
    expect(work_item.transition_logs.last.details).to include("regression_count" => 1)
  end

  it "blocks failed generated tests when regression loop budget is exhausted" do
    queue = WorkQueue.create!(
      name: "Test Backfill",
      slug: "test-backfill-#{SecureRandom.hex(4)}",
      stages: %w[scan_coverage identify_gaps generate_tests run_tests human_review done],
      config: { "max_regression_loops" => 1 }
    )
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "run_tests", completion_criteria: ["tests_passed"])
    work_item = WorkItem.create!(work_queue: queue, title: "Backfill", spec_url: "opaque spec", stage_name: "run_tests", regression_count: 1, status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "shell", status: :completed)
    Artifact.create!(claim: claim, work_item: work_item, kind: "test_results", data: { "passed" => false, "output" => "still failing" })

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload).to be_blocked
    expect(work_item.metadata["blocked_reason"]).to include("regression loop budget exhausted")
    expect(work_item.transition_logs.last.trigger).to eq("blocked")
  end
```

**Step 2: Verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/transition_manager_regression_spec.rb --format documentation
```

Expected: FAIL because the work item stays in `run_tests` retry/block behavior instead of moving to `generate_tests`.

**Step 3: Implement minimal transition behavior**

Modify `app/services/engine/transition_manager.rb`:

- In `call`, insert a run-test regression branch before generic `retry_or_block(results)`:

```ruby
      return regress_or_block_generated_tests if generated_test_regression_requested?(results)
```

- Add private helpers near the existing review regression helpers:

```ruby
    def generated_test_regression_requested?(results)
      @work_item.stage_name == "run_tests" && results.any? { |result| !result.passed? } && previous_stage_named?("generate_tests")
    end

    def previous_stage_named?(stage_name)
      stages = @work_item.work_queue.stages
      current_index = stages.index(@work_item.stage_name)
      current_index.present? && current_index.positive? && stages.fetch(current_index - 1) == stage_name
    end

    def regress_or_block_generated_tests
      if @work_item.regression_count < max_regression_loops
        regress_generated_tests
      else
        block_regression_exhausted
      end
    end

    def regress_generated_tests
      from_stage = @work_item.stage_name
      feedback = generated_test_feedback
      next_regression_count = @work_item.regression_count + 1

      @work_item.update!(
        stage_name: "generate_tests",
        status: :pending,
        retry_count: 0,
        regression_count: next_regression_count,
        metadata: @work_item.metadata.merge("feedback" => feedback)
      )

      @work_item.transition_logs.create!(
        from_stage: from_stage,
        to_stage: "generate_tests",
        trigger: "regression",
        details: { feedback: feedback, regression_count: next_regression_count }
      )
    end

    def generated_test_feedback
      artifact = @claim.artifacts.where(kind: "test_results").order(created_at: :desc, id: :desc).first
      output = artifact&.data&.fetch("output", nil).presence
      failures = Array(artifact&.data&.fetch("failures", [])).join("; ").presence
      [output, failures].compact.join("\n").presence || "generated tests failed"
    end
```

Implementation notes:
- Do not change review regression behavior.
- Keep the target stage name explicit (`generate_tests`) because this cookbook's documented loop is `run_tests -> generate_tests`.
- Do not implement generalized arbitrary stage graph regressions unless another spec requires it.

**Step 4: Verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/transition_manager_regression_spec.rb --format documentation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/transition_manager_regression_spec.rb app/services/engine/transition_manager.rb
git commit -m "feat: regress failed generated tests"
```

---

### Task 9: Add cookbook documentation

**Objective:** Document how to seed and run the Test Coverage Backfill cookbook queue.

**Files:**
- Create: `docs/cookbooks/test-coverage-backfill.md`

**Step 1: Create docs**

Create `docs/cookbooks/test-coverage-backfill.md`:

```markdown
# Test Coverage Backfill Cookbook

Source spec: `docs/specs/cookbook-01-test-coverage-backfill.md`

## Queue

Slug: `test_backfill`

Stages:

```text
scan_coverage -> identify_gaps -> generate_tests -> run_tests -> human_review -> done
```

## What it does

The queue scans a target repository for coverage gaps, turns uncovered paths into prioritized test units, generates specs that match repository conventions, runs the generated specs, and sends the result to human review before merge.

## Portable paths

Queue YAML and prompt references are relative to `Rails.root`. The `shell_script` stages intentionally omit `working_directory` so `Adapters::ShellScriptAdapter` uses its `Rails.root` default. Do not add absolute paths such as `/Users/gregmushen/work/code/taskrail` to queue YAML or fixtures.

## Fixture app

The deterministic fixture app lives in `test/fixtures/apps/untested_app/`. It provides a small `Widget` class with intentionally uncovered behavior for cookbook tests.

## Shared infrastructure

This cookbook does not define shared Docker, database, or network infrastructure. Use the shared cookbook infrastructure setup for those concerns. The cookbook-specific fake shell commands use Ruby stdlib only so they work in local and dockerized Rails environments.

## Verification

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rails db:seed
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb --format documentation
```
```

**Step 2: Verify docs mention source spec**

Run:

```bash
grep -n "docs/specs/cookbook-01-test-coverage-backfill.md" docs/cookbooks/test-coverage-backfill.md
```

Expected: one matching line.

**Step 3: Commit**

```bash
git add docs/cookbooks/test-coverage-backfill.md
git commit -m "docs: document test coverage backfill cookbook"
```

---

### Task 10: Run final focused verification

**Objective:** Verify the whole cookbook slice works without committing unrelated files.

**Files:**
- Read/verify only.

**Step 1: Run the focused slice**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/predicates/coverage_map_produced_spec.rb \
  spec/services/engine/predicates/test_plan_produced_spec.rb \
  spec/services/engine/predicates/tests_generated_spec.rb \
  spec/services/engine/transition_manager_regression_spec.rb \
  --format documentation
```

Expected: PASS.

**Step 2: Search for hardcoded local repo paths in new implementation files**

```bash
grep -R "/Users/gregmushen/work/code/taskrail" \
  config/queues/test_backfill.yml \
  prompts/backfill_scan_coverage.md \
  prompts/backfill_identify_gaps.md \
  prompts/backfill_generate_tests.md \
  test/fixtures/apps/untested_app \
  docs/cookbooks/test-coverage-backfill.md
```

Expected: no output and exit status 1.

**Step 3: Verify source spec is referenced by docs**

```bash
grep -n "docs/specs/cookbook-01-test-coverage-backfill.md" docs/cookbooks/test-coverage-backfill.md
```

Expected: one matching line.

**Step 4: Verify git state before final commit**

```bash
git status --short
```

Expected: only intended cookbook implementation files are modified/untracked. Do not add `.DS_Store`, generated PDFs, or unrelated docs/spec files unless they were already part of the worker's explicit task.

**Step 5: Final commit if anything remains uncommitted**

If Task 1-9 commits were done exactly, this step should have nothing to commit. If a verification/doc tweak remains, commit only that intended file:

```bash
git add EXACT_INTENDED_FILE
git commit -m "chore: verify test coverage backfill cookbook"
```

---

## Implementation Task Checklist

- [ ] Add RED seed spec for `test_backfill` queue.
- [ ] Create `config/queues/test_backfill.yml` with relative `file://prompts/...` prompt references and no absolute working directory.
- [ ] Create prompt files: `prompts/backfill_scan_coverage.md`, `prompts/backfill_identify_gaps.md`, `prompts/backfill_generate_tests.md`.
- [ ] Add `coverage_map_produced` predicate spec and implementation.
- [ ] Add `test_plan_produced` predicate spec and implementation.
- [ ] Add `tests_generated` predicate spec and implementation.
- [ ] Register all three predicates in `Engine::PredicateRegistry`.
- [ ] Add deterministic fixture app under `test/fixtures/apps/untested_app/`.
- [ ] Add `run_tests -> generate_tests` regression handling with max-loop blocking.
- [ ] Add `docs/cookbooks/test-coverage-backfill.md`.
- [ ] Run focused rbenv/RSpec verification.
- [ ] Search new files for hardcoded absolute repo paths.

## Expected Final Commit Message

Use this message for the final implementation commit if the implementation is squashed into one commit:

```bash
git commit -m "feat: add test coverage backfill cookbook"
```

If implemented task-by-task, use the per-task commit messages above and keep each commit green.
