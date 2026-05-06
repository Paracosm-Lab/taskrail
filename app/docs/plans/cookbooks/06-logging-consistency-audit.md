# Logging Consistency Audit Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `logging_audit` cookbook queue from `docs/specs/cookbook-06-logging-consistency-audit.md`, including portable queue YAML, prompt files, artifact predicates, fixture app coverage, and seed/E2E specs.

**Architecture:** This cookbook is a seeded Rails workflow queue backed by `config/queues/logging_audit.yml`. Inline Claude stages produce typed artifacts (`log_inventory`, `logging_assessment`, `logging_standard`, `log_patches`), small predicates verify those artifacts, the shell stage applies/runs tests through docker-friendly commands rooted at `Rails.root`, and a fake `human_review` gate pauses before completion.

**Tech Stack:** Rails, RSpec, YAML seed loader with `file://` prompt resolution, TaskRail `WorkQueue`/`StageConfig`/`Artifact` models, `Engine::PredicateRegistry`, `Engine::Predicates::*`, `Adapters::ShellScriptAdapter`.

---

## Source Requirements Summary

Source spec: `docs/specs/cookbook-06-logging-consistency-audit.md`

Implement the queue:

`scan_log_statements -> assess_quality -> draft_standard -> draft_fixes -> run_tests -> human_review -> done`

Required new predicates:

- `log_inventory_produced`: passes when a `log_inventory` artifact exists on the claim.
- `logging_assessed`: passes when a `logging_assessment` artifact exists on the claim.
- `standard_drafted`: passes when a `logging_standard` artifact exists on the claim.

Artifacts:

- `log_inventory`: `{ statements: [{ file, line, logger, level, format, content, context_present }], summary: { total, by_format, by_level, by_service } }`
- `logging_assessment`: `{ best_patterns: [], worst_offenders: [], scores_by_file: {}, recommended_standard: {} }`
- `logging_standard`: `{ standard: { format, required_fields_by_level, guidelines, examples, anti_patterns } }`
- `log_patches`: `{ patches: [{ file, original, replacement, reason }] }`

Portability constraints:

- Queue YAML must not contain `/Users/gregmushen/...` or any other absolute checkout path.
- Prompt references must use repo-relative `file://prompts/...` paths.
- Shell commands must rely on the adapter default `working_directory` of `Rails.root.to_s`, or use repo-relative paths only.
- Do not add duplicate shared infrastructure such as new Docker Compose services unless the shared cookbook infrastructure plan explicitly requires it.

Greg's focused RSpec command pattern:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec path/to/spec.rb[:line]
```

---

## Implementation Notes for the Worker

Existing patterns to follow:

- `db/seeds.rb` already loads every `config/queues/*.yml` and resolves `agent_prompt: file://...` with `Rails.root.join(relative_path).read`.
- Existing artifact predicates live in `app/services/engine/predicates/` and return `Engine::PredicateResult.pass(evidence: { artifact_id: artifact.id })` or `Engine::PredicateResult.fail(reason: "...")`.
- Existing predicate specs use helper methods that create `WorkQueue`, `WorkItem`, `Claim`, and optional `Artifact` rows.
- `Adapters::ShellScriptAdapter` defaults `working_directory` to `Rails.root.to_s`; omit `adapter_config.working_directory` in the cookbook YAML unless a test proves a different value is required.
- Existing seed specs live in `spec/models/work_queue_seed_spec.rb` and already assert `file://` prompt resolution for the `operations` queue.

Fake/docker-friendly infrastructure boundary:

- This cookbook should be runnable in a container with only the Rails app source, bundle, database, and shell access.
- Do not create a cookbook-specific `docker-compose.yml`, database service, Redis service, or external logging service.
- The fixture app under `test/fixtures/apps/bad_logging/` is plain Ruby/Rails-shaped source text for audit agents to inspect; it does not need to boot as a full Rails app.
- The `run_tests` stage should use a shell command that works in local and containerized Rails contexts:
  `bundle exec rspec spec/e2e/logging_audit_cookbook_spec.rb`
- If the shared cookbook infrastructure later provides standardized shell commands or docker-compose wrappers, replace only the `run_tests.adapter_config.commands` entry, not the queue stages or predicates.

---

### Task 1: Add RED specs for the three logging artifact predicates

**Objective:** Prove the new predicates are missing and define their exact pass/fail behavior before implementation.

**Files:**
- Create: `spec/services/engine/predicates/log_inventory_produced_spec.rb`
- Create: `spec/services/engine/predicates/logging_assessed_spec.rb`
- Create: `spec/services/engine/predicates/standard_drafted_spec.rb`

**Step 1: Write failing tests**

Create `spec/services/engine/predicates/log_inventory_produced_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::LogInventoryProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Logging Audit #{SecureRandom.hex(4)}",
      slug: "logging-audit-predicate-#{SecureRandom.hex(4)}",
      stages: ["scan_log_statements", "done"]
    )
    queue.stage_configs.create!(stage_name: "scan_log_statements", adapter_type: "fake")
    item = WorkItem.create!(title: "Audit logs", spec_url: "opaque spec", work_queue: queue, stage_name: "scan_log_statements")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when a log inventory artifact exists" do
    claim = build_claim(
      artifacts: [
        {
          kind: "log_inventory",
          data: {
            "statements" => [
              {
                "file" => "app/controllers/orders_controller.rb",
                "line" => 12,
                "logger" => "Rails.logger",
                "level" => "info",
                "format" => "unstructured",
                "content" => "processing order",
                "context_present" => false
              }
            ],
            "summary" => { "total" => 1, "by_format" => { "unstructured" => 1 }, "by_level" => { "info" => 1 }, "by_service" => {} }
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "log_inventory")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when no log inventory artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no log inventory artifact found")
  end

  it "fails when only a different artifact kind exists" do
    claim = build_claim(artifacts: [{ kind: "logging_assessment", data: { "present" => true } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no log inventory artifact found")
  end
end
```

Create `spec/services/engine/predicates/logging_assessed_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::LoggingAssessed do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Logging Assessment #{SecureRandom.hex(4)}",
      slug: "logging-assessed-predicate-#{SecureRandom.hex(4)}",
      stages: ["assess_quality", "done"]
    )
    queue.stage_configs.create!(stage_name: "assess_quality", adapter_type: "fake")
    item = WorkItem.create!(title: "Assess logs", spec_url: "opaque spec", work_queue: queue, stage_name: "assess_quality")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when a logging assessment artifact exists" do
    claim = build_claim(
      artifacts: [
        {
          kind: "logging_assessment",
          data: {
            "best_patterns" => [{ "file" => "app/services/good_logger.rb", "reason" => "structured context" }],
            "worst_offenders" => [{ "file" => "app/controllers/orders_controller.rb", "reason" => "puts params.inspect" }],
            "scores_by_file" => { "app/controllers/orders_controller.rb" => 20 },
            "recommended_standard" => { "format" => "structured_json" }
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "logging_assessment")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when no logging assessment artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no logging assessment artifact found")
  end

  it "fails when only a different artifact kind exists" do
    claim = build_claim(artifacts: [{ kind: "log_inventory", data: { "present" => true } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no logging assessment artifact found")
  end
end
```

Create `spec/services/engine/predicates/standard_drafted_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::StandardDrafted do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Logging Standard #{SecureRandom.hex(4)}",
      slug: "standard-drafted-predicate-#{SecureRandom.hex(4)}",
      stages: ["draft_standard", "done"]
    )
    queue.stage_configs.create!(stage_name: "draft_standard", adapter_type: "fake")
    item = WorkItem.create!(title: "Draft logging standard", spec_url: "opaque spec", work_queue: queue, stage_name: "draft_standard")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when a logging standard artifact exists" do
    claim = build_claim(
      artifacts: [
        {
          kind: "logging_standard",
          data: {
            "standard" => {
              "format" => "structured_json",
              "required_fields_by_level" => { "error" => ["request_id", "operation", "error_class"] },
              "guidelines" => ["info for lifecycle events"],
              "examples" => [{ "scenario" => "job", "log" => { "event" => "job_started" } }],
              "anti_patterns" => ["puts params.inspect"]
            }
          }
        }
      ]
    )
    artifact = claim.artifacts.find_by!(kind: "logging_standard")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id })
  end

  it "fails when no logging standard artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no logging standard artifact found")
  end

  it "fails when only a different artifact kind exists" do
    claim = build_claim(artifacts: [{ kind: "logging_assessment", data: { "present" => true } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no logging standard artifact found")
  end
end
```

**Step 2: Run tests to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/log_inventory_produced_spec.rb \
  spec/services/engine/predicates/logging_assessed_spec.rb \
  spec/services/engine/predicates/standard_drafted_spec.rb
```

Expected: FAIL with missing constant errors such as `uninitialized constant Engine::Predicates::LogInventoryProduced`.

**Step 3: Commit?**

Do not commit yet. Commit after the minimal implementation in Task 2 passes.

---

### Task 2: Implement the logging artifact predicates and registry entries

**Objective:** Add the minimal predicate classes and registry mappings needed to satisfy Task 1.

**Files:**
- Create: `app/services/engine/predicates/log_inventory_produced.rb`
- Create: `app/services/engine/predicates/logging_assessed.rb`
- Create: `app/services/engine/predicates/standard_drafted.rb`
- Modify: `app/services/engine/predicate_registry.rb`
- Test: `spec/services/engine/predicates/log_inventory_produced_spec.rb`
- Test: `spec/services/engine/predicates/logging_assessed_spec.rb`
- Test: `spec/services/engine/predicates/standard_drafted_spec.rb`
- Test: `spec/services/engine/predicate_registry_spec.rb`

**Step 1: Write minimal implementation**

Create `app/services/engine/predicates/log_inventory_produced.rb`:

```ruby
module Engine
  module Predicates
    class LogInventoryProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "log_inventory").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "no log inventory artifact found")
      end
    end
  end
end
```

Create `app/services/engine/predicates/logging_assessed.rb`:

```ruby
module Engine
  module Predicates
    class LoggingAssessed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "logging_assessment").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "no logging assessment artifact found")
      end
    end
  end
end
```

Create `app/services/engine/predicates/standard_drafted.rb`:

```ruby
module Engine
  module Predicates
    class StandardDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "logging_standard").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "no logging standard artifact found")
      end
    end
  end
end
```

Modify `app/services/engine/predicate_registry.rb` so `PREDICATES` includes the new mappings. Keep the existing entries and add a trailing comma to the previous final entry if needed:

```ruby
"validation_passed" => Predicates::ValidationPassed,
"log_inventory_produced" => Predicates::LogInventoryProduced,
"logging_assessed" => Predicates::LoggingAssessed,
"standard_drafted" => Predicates::StandardDrafted
```

**Step 2: Add registry expectations**

Modify `spec/services/engine/predicate_registry_spec.rb` and add these expectations to the known predicate example:

```ruby
expect(described_class.resolve("log_inventory_produced")).to eq(Engine::Predicates::LogInventoryProduced)
expect(described_class.resolve("logging_assessed")).to eq(Engine::Predicates::LoggingAssessed)
expect(described_class.resolve("standard_drafted")).to eq(Engine::Predicates::StandardDrafted)
```

**Step 3: Run focused predicate tests to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/log_inventory_produced_spec.rb \
  spec/services/engine/predicates/logging_assessed_spec.rb \
  spec/services/engine/predicates/standard_drafted_spec.rb \
  spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add \
  app/services/engine/predicates/log_inventory_produced.rb \
  app/services/engine/predicates/logging_assessed.rb \
  app/services/engine/predicates/standard_drafted.rb \
  app/services/engine/predicate_registry.rb \
  spec/services/engine/predicates/log_inventory_produced_spec.rb \
  spec/services/engine/predicates/logging_assessed_spec.rb \
  spec/services/engine/predicates/standard_drafted_spec.rb \
  spec/services/engine/predicate_registry_spec.rb

git commit -m "feat: add logging audit artifact predicates"
```

---

### Task 3: Add RED seed spec for the logging audit queue

**Objective:** Define the seeded `logging_audit` queue contract before adding YAML or prompts.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`

**Step 1: Write failing seed spec**

Append this example inside `RSpec.describe "development queue seed" do` in `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the logging audit cookbook queue with resolved prompt files" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "logging_audit")
  expect(queue.name).to eq("Logging Consistency Audit")
  expect(queue.stages).to eq(%w[
    scan_log_statements
    assess_quality
    draft_standard
    draft_fixes
    run_tests
    human_review
    done
  ])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_max_retries" => 2,
    "default_timeout_seconds" => 600,
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 2
  )

  scan = queue.stage_configs.find_by!(stage_name: "scan_log_statements")
  expect(scan.adapter_type).to eq("inline_claude")
  expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
  expect(scan.allowed_skills).to eq(["read_repo"])
  expect(scan.forbidden_skills).to include("edit_files", "deploy")
  expect(scan.completion_criteria).to eq(["log_inventory_produced"])
  expect(scan.adapter_config).to eq({ "output_artifact_kind" => "log_inventory" })
  expect(scan.agent_prompt).to include("# Logging Scan Statements")
  expect(scan.agent_prompt).to include("log_inventory")
  expect(scan.agent_prompt).not_to start_with("file://")

  assess = queue.stage_configs.find_by!(stage_name: "assess_quality")
  expect(assess.adapter_type).to eq("inline_claude")
  expect(assess.model_override).to eq("claude-sonnet-4-20250514")
  expect(assess.completion_criteria).to eq(["logging_assessed"])
  expect(assess.adapter_config).to eq({ "output_artifact_kind" => "logging_assessment" })
  expect(assess.agent_prompt).to include("# Logging Assess Quality")
  expect(assess.agent_prompt).not_to start_with("file://")

  standard = queue.stage_configs.find_by!(stage_name: "draft_standard")
  expect(standard.adapter_type).to eq("inline_claude")
  expect(standard.model_override).to eq("claude-sonnet-4-20250514")
  expect(standard.completion_criteria).to eq(["standard_drafted"])
  expect(standard.adapter_config).to eq({ "output_artifact_kind" => "logging_standard" })
  expect(standard.agent_prompt).to include("# Logging Draft Standard")
  expect(standard.agent_prompt).not_to start_with("file://")

  fixes = queue.stage_configs.find_by!(stage_name: "draft_fixes")
  expect(fixes.adapter_type).to eq("inline_claude")
  expect(fixes.model_override).to eq("claude-sonnet-4-20250514")
  expect(fixes.allowed_skills).to eq(["read_repo"])
  expect(fixes.forbidden_skills).to include("deploy")
  expect(fixes.completion_criteria).to eq(["fixes_drafted"])
  expect(fixes.adapter_config).to eq({ "output_artifact_kind" => "log_patches" })
  expect(fixes.agent_prompt).to include("# Logging Draft Fixes")
  expect(fixes.agent_prompt).not_to start_with("file://")

  run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
  expect(run_tests.adapter_type).to eq("shell_script")
  expect(run_tests.allowed_skills).to eq(["run_tests"])
  expect(run_tests.forbidden_skills).to include("edit_files", "deploy")
  expect(run_tests.completion_criteria).to eq(["tests_passed"])
  expect(run_tests.adapter_config).not_to have_key("working_directory")
  expect(run_tests.adapter_config.fetch("commands")).to contain_exactly(
    include(
      "name" => "logging audit cookbook e2e",
      "artifact" => "test_results",
      "command" => "bundle exec rspec spec/e2e/logging_audit_cookbook_spec.rb"
    )
  )

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.completion_criteria).to eq(["report_present"])
  expect(human_review.timeout_seconds).to eq(86_400)

  done = queue.stage_configs.find_by!(stage_name: "done")
  expect(done.adapter_type).to eq("fake")
  expect(done.completion_criteria).to eq(["report_present"])
end
```

**Step 2: Run the focused seed spec to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL with `Couldn't find WorkQueue with [WHERE "work_queues"."slug" = $1]` for `logging_audit`.

---

### Task 4: Add portable logging audit queue YAML

**Objective:** Seed the `logging_audit` queue with all stages and portable prompt references.

**Files:**
- Create: `config/queues/logging_audit.yml`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Create queue YAML**

Create `config/queues/logging_audit.yml`:

```yaml
name: Logging Consistency Audit
slug: logging_audit
stages:
  - scan_log_statements
  - assess_quality
  - draft_standard
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
  scan_log_statements:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [log_inventory_produced]
    agent_prompt: file://prompts/logging_scan_statements.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: log_inventory
  assess_quality:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [logging_assessed]
    agent_prompt: file://prompts/logging_assess_quality.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: logging_assessment
  draft_standard:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [standard_drafted]
    agent_prompt: file://prompts/logging_draft_standard.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: logging_standard
  draft_fixes:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [fixes_drafted]
    agent_prompt: file://prompts/logging_draft_fixes.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: log_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [tests_passed]
    agent_prompt: Apply logging patches and run the logging audit cookbook E2E spec. Report pass/fail.
    timeout_seconds: 600
    adapter_config:
      commands:
        - name: logging audit cookbook e2e
          command: bundle exec rspec spec/e2e/logging_audit_cookbook_spec.rb
          artifact: test_results
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review the logging standard and drafted fixes before merge.
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

Important: Do not add `working_directory` to `run_tests.adapter_config`. `Adapters::ShellScriptAdapter` already defaults to `Rails.root.to_s`.

**Step 2: Run seed spec to verify expected next failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL because prompt files such as `prompts/logging_scan_statements.md` do not exist yet.

**Step 3: Commit?**

Do not commit yet. Commit after prompts are added and the seed spec passes.

---

### Task 5: Add logging audit prompt files

**Objective:** Provide implementation-ready prompts for each inline Claude stage and make seed prompt resolution pass.

**Files:**
- Create: `prompts/logging_scan_statements.md`
- Create: `prompts/logging_assess_quality.md`
- Create: `prompts/logging_draft_standard.md`
- Create: `prompts/logging_draft_fixes.md`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Create scan prompt**

Create `prompts/logging_scan_statements.md`:

```markdown
# Logging Scan Statements

You are the scan_log_statements agent for the TaskRail Logging Consistency Audit cookbook.

## Inputs

- Assignment repository path or default working directory.
- Any upstream context included in the assignment.

## Task

Find every log-like statement across the codebase, including:

- `Rails.logger.*`
- `Logger.*`
- `console.log`
- `puts`
- `print`
- `p`
- `pp`
- Custom logger calls such as `logger.info`, `ApplicationLogger`, or service-specific wrappers
- Sentry breadcrumbs, tags, context, and captured exception context calls

For each statement, capture:

- `file`: repo-relative file path
- `line`: integer line number
- `logger`: logger API or debug output function used
- `level`: `debug`, `info`, `warn`, `error`, `fatal`, `breadcrumb`, `context`, or `unknown`
- `format`: `structured`, `unstructured`, or `debug_output`
- `content`: concise description or literal logged content
- `context_present`: true when correlation or useful diagnostic fields are present

Classify structured logs as key-value/hash/JSON-style output, unstructured logs as bare strings/interpolation, and debug output as `puts`/`print`/`p`/`pp` style statements.

## Output

Return a successful report and one artifact of kind `log_inventory` with this shape:

```json
{
  "statements": [
    {
      "file": "app/controllers/orders_controller.rb",
      "line": 12,
      "logger": "Rails.logger",
      "level": "info",
      "format": "unstructured",
      "content": "processing order",
      "context_present": false
    }
  ],
  "summary": {
    "total": 1,
    "by_format": { "unstructured": 1 },
    "by_level": { "info": 1 },
    "by_service": { "rails_app": 1 }
  }
}
```

Do not edit files in this stage.
```

**Step 2: Create assessment prompt**

Create `prompts/logging_assess_quality.md`:

```markdown
# Logging Assess Quality

You are the assess_quality agent for the TaskRail Logging Consistency Audit cookbook.

## Inputs

- The upstream `log_inventory` artifact.
- Relevant source files from the repository.

## Task

Score logging quality per file/module. Consider:

- Structured: key-value/hash/JSON logs score higher than bare strings.
- Contextual: request_id, user_id, operation, job_id, external service name, and error class improve usefulness.
- Appropriate level: identify debug noise at info/error levels and expected conditions logged as errors.
- Useful: decide whether a log would help reconstruct an incident.
- Existing good patterns: identify patterns already present in the codebase that can become the standard.
- Worst offenders: prioritize controllers, jobs, service objects, error handlers, and critical paths with no logging or debug output.

## Output

Return a successful report and one artifact of kind `logging_assessment` with this shape:

```json
{
  "best_patterns": [
    { "file": "app/services/payment_processor.rb", "line": 18, "reason": "structured event with operation and user_id" }
  ],
  "worst_offenders": [
    { "file": "app/controllers/orders_controller.rb", "line": 12, "reason": "puts params.inspect leaks noisy unstructured data", "priority": "high" }
  ],
  "scores_by_file": {
    "app/controllers/orders_controller.rb": { "score": 20, "reasons": ["debug output", "missing context"] }
  },
  "recommended_standard": {
    "format": "structured_json",
    "required_context": ["operation", "request_id"],
    "source": "best existing patterns"
  }
}
```

Do not edit files in this stage.
```

**Step 3: Create standard prompt**

Create `prompts/logging_draft_standard.md`:

```markdown
# Logging Draft Standard

You are the draft_standard agent for the TaskRail Logging Consistency Audit cookbook.

## Inputs

- The upstream `logging_assessment` artifact.
- Any examples of best patterns from the source code.

## Task

Draft a logging standard based on the best working patterns already found in the codebase.

Include:

- Required fields by log level.
- Structured format specification.
- Level guidelines for debug/info/warn/error/fatal.
- Anti-patterns to avoid.
- Example log lines for request handling, job processing, external API calls, and error recovery.

## Output

Return a successful report and one artifact of kind `logging_standard` with this shape:

```json
{
  "standard": {
    "format": "structured_json",
    "required_fields_by_level": {
      "info": ["event", "operation"],
      "warn": ["event", "operation", "reason"],
      "error": ["event", "operation", "error_class", "error_message", "request_id"]
    },
    "guidelines": [
      "Use info for business lifecycle events.",
      "Use warn for recoverable unexpected conditions.",
      "Use error for failed operations requiring investigation."
    ],
    "examples": [
      { "scenario": "job processing", "log": { "event": "job_started", "operation": "SyncUserJob", "user_id": "..." } }
    ],
    "anti_patterns": [
      "puts params.inspect",
      "Rails.logger.error e.message without error_class or backtrace context"
    ]
  }
}
```

Do not edit files in this stage.
```

**Step 4: Create fixes prompt**

Create `prompts/logging_draft_fixes.md`:

```markdown
# Logging Draft Fixes

You are the draft_fixes agent for the TaskRail Logging Consistency Audit cookbook.

## Inputs

- The upstream `logging_standard` artifact.
- The upstream `logging_assessment` artifact, especially `worst_offenders`.
- Relevant source code.

## Task

Draft focused patches for the worst offending log statements.

Prioritize:

- Controllers, jobs, service objects, and error handlers.
- Replacing `puts`, `print`, `p`, and `pp` with structured logger calls.
- Adding available context fields such as request_id, user_id, operation, job_id, and error_class.
- Fixing inappropriate log levels.
- Removing noise logs such as `puts "here"`.

Do not rewrite the whole application. Keep patches small and reviewable.

## Output

Return a successful report and one artifact of kind `log_patches` with this shape:

```json
{
  "patches": [
    {
      "file": "app/controllers/orders_controller.rb",
      "original": "puts params.inspect",
      "replacement": "Rails.logger.info({ event: \"order_request_received\", operation: \"OrdersController#create\", request_id: request.request_id, user_id: current_user&.id }.compact.to_json)",
      "reason": "Replace debug output with structured request context."
    }
  ]
}
```

The next shell stage applies or validates the patches and runs tests. Do not deploy.
```

**Step 5: Run seed spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 6: Search for portability regressions**

Run:

```bash
grep -R "/Users/gregmushen/work/code/taskrail\|file:///." config/queues/logging_audit.yml prompts/logging_*.md
```

Expected: no output.

**Step 7: Commit**

```bash
git add \
  config/queues/logging_audit.yml \
  prompts/logging_scan_statements.md \
  prompts/logging_assess_quality.md \
  prompts/logging_draft_standard.md \
  prompts/logging_draft_fixes.md \
  spec/models/work_queue_seed_spec.rb

git commit -m "feat: seed logging audit cookbook queue"
```

---

### Task 6: Add fixture app files for bad logging patterns

**Objective:** Provide a deterministic fixture app that audit stages can scan, assess, standardize, and patch.

**Files:**
- Create: `test/fixtures/apps/bad_logging/app/controllers/orders_controller.rb`
- Create: `test/fixtures/apps/bad_logging/app/jobs/process_user_job.rb`
- Create: `test/fixtures/apps/bad_logging/app/services/structured_payment_logger.rb`
- Create: `test/fixtures/apps/bad_logging/app/services/payment_error_handler.rb`
- Create: `test/fixtures/apps/bad_logging/app/services/critical_account_reconciler.rb`
- Create: `test/fixtures/apps/bad_logging/README.md`
- Test: `spec/e2e/logging_audit_cookbook_spec.rb` (created in Task 7)

**Step 1: Create controller with debug output**

Create `test/fixtures/apps/bad_logging/app/controllers/orders_controller.rb`:

```ruby
class OrdersController < ApplicationController
  def create
    puts params.inspect
    OrderCreator.call(params: params)
    head :accepted
  end
end
```

**Step 2: Create job with unstructured info log**

Create `test/fixtures/apps/bad_logging/app/jobs/process_user_job.rb`:

```ruby
class ProcessUserJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    Rails.logger.info "processing user"
    UserProcessor.call(user_id: user_id)
  end
end
```

**Step 3: Create service with good structured logging pattern**

Create `test/fixtures/apps/bad_logging/app/services/structured_payment_logger.rb`:

```ruby
class StructuredPaymentLogger
  def self.payment_authorized(payment_id:, user_id:, request_id:)
    Rails.logger.info(
      {
        event: "payment_authorized",
        operation: "StructuredPaymentLogger.payment_authorized",
        payment_id: payment_id,
        user_id: user_id,
        request_id: request_id
      }.to_json
    )
  end
end
```

**Step 4: Create error handler with missing context**

Create `test/fixtures/apps/bad_logging/app/services/payment_error_handler.rb`:

```ruby
class PaymentErrorHandler
  def self.handle(error)
    Rails.logger.error error.message
    false
  end
end
```

**Step 5: Create critical path with no logging**

Create `test/fixtures/apps/bad_logging/app/services/critical_account_reconciler.rb`:

```ruby
class CriticalAccountReconciler
  def self.call(account_id:)
    account = Account.find(account_id)
    account.reconcile!
    account.save!
  end
end
```

**Step 6: Create fixture README**

Create `test/fixtures/apps/bad_logging/README.md`:

```markdown
# Bad Logging Fixture App

Fixture for `docs/specs/cookbook-06-logging-consistency-audit.md`.

Contains intentionally mixed logging patterns:

- `app/controllers/orders_controller.rb`: `puts params.inspect` debug output.
- `app/jobs/process_user_job.rb`: unstructured `Rails.logger.info "processing user"` with no `user_id`.
- `app/services/structured_payment_logger.rb`: good structured JSON-style logging pattern.
- `app/services/payment_error_handler.rb`: `Rails.logger.error error.message` without error class, stack, or operation context.
- `app/services/critical_account_reconciler.rb`: critical path with no logging.
```

**Step 7: Commit?**

Do not commit yet. Commit after the E2E spec in Task 7 passes.

---

### Task 7: Add RED E2E spec for the logging audit cookbook fixture and queue

**Objective:** Prove the cookbook wiring and fixture content satisfy the source spec.

**Files:**
- Create: `spec/e2e/logging_audit_cookbook_spec.rb`
- Test fixture files from Task 6
- Queue/prompt files from Tasks 4-5

**Step 1: Write the E2E spec**

Create `spec/e2e/logging_audit_cookbook_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "logging audit cookbook" do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/bad_logging") }

  it "provides the configured logging_audit queue with docker-friendly shell validation" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "logging_audit")

    expect(queue.stages).to eq(%w[
      scan_log_statements
      assess_quality
      draft_standard
      draft_fixes
      run_tests
      human_review
      done
    ])

    run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
    expect(run_tests.adapter_type).to eq("shell_script")
    expect(run_tests.adapter_config).not_to have_key("working_directory")
    expect(run_tests.adapter_config.fetch("commands")).to include(
      include(
        "name" => "logging audit cookbook e2e",
        "command" => "bundle exec rspec spec/e2e/logging_audit_cookbook_spec.rb",
        "artifact" => "test_results"
      )
    )
  end

  it "resolves every inline Claude prompt from repo-relative file paths" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "logging_audit")
    inline_stages = %w[scan_log_statements assess_quality draft_standard draft_fixes]

    inline_stages.each do |stage_name|
      stage = queue.stage_configs.find_by!(stage_name: stage_name)
      expect(stage.agent_prompt).to be_present
      expect(stage.agent_prompt).not_to start_with("file://")
      expect(stage.agent_prompt).to include("# Logging")
    end
  end

  it "contains fixture files for bad, missing, and good logging patterns" do
    expect(fixture_root.join("app/controllers/orders_controller.rb").read).to include("puts params.inspect")
    expect(fixture_root.join("app/jobs/process_user_job.rb").read).to include('Rails.logger.info "processing user"')
    expect(fixture_root.join("app/services/structured_payment_logger.rb").read).to include("payment_authorized")
    expect(fixture_root.join("app/services/structured_payment_logger.rb").read).to include("request_id")
    expect(fixture_root.join("app/services/payment_error_handler.rb").read).to include("Rails.logger.error error.message")

    critical_path = fixture_root.join("app/services/critical_account_reconciler.rb").read
    expect(critical_path).to include("reconcile!")
    expect(critical_path).not_to include("Rails.logger")
    expect(critical_path).not_to include("puts")
  end

  it "can satisfy the logging audit predicates with expected artifact kinds" do
    queue = WorkQueue.create!(
      name: "Logging Audit Predicate Flow #{SecureRandom.hex(4)}",
      slug: "logging-audit-predicate-flow-#{SecureRandom.hex(4)}",
      stages: %w[scan_log_statements assess_quality draft_standard done]
    )
    item = WorkItem.create!(title: "Audit fixture logging", spec_url: fixture_root.to_s, work_queue: queue, stage_name: "scan_log_statements")

    scan_claim = Claim.create!(work_item: item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    log_inventory = Artifact.create!(
      work_item: item,
      claim: scan_claim,
      kind: "log_inventory",
      data: {
        "statements" => [
          { "file" => "app/controllers/orders_controller.rb", "line" => 3, "logger" => "puts", "level" => "unknown", "format" => "debug_output", "content" => "params.inspect", "context_present" => false }
        ],
        "summary" => { "total" => 1, "by_format" => { "debug_output" => 1 }, "by_level" => { "unknown" => 1 }, "by_service" => { "bad_logging" => 1 } }
      }
    )
    scan_result = Engine::Predicates::LogInventoryProduced.new(claim: scan_claim).call
    expect(scan_result).to be_passed
    expect(scan_result.evidence).to eq({ artifact_id: log_inventory.id })

    assess_claim = Claim.create!(work_item: item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    assessment = Artifact.create!(
      work_item: item,
      claim: assess_claim,
      kind: "logging_assessment",
      data: { "best_patterns" => [], "worst_offenders" => [], "scores_by_file" => {}, "recommended_standard" => {} }
    )
    assess_result = Engine::Predicates::LoggingAssessed.new(claim: assess_claim).call
    expect(assess_result).to be_passed
    expect(assess_result.evidence).to eq({ artifact_id: assessment.id })

    standard_claim = Claim.create!(work_item: item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    standard = Artifact.create!(
      work_item: item,
      claim: standard_claim,
      kind: "logging_standard",
      data: { "standard" => { "format" => "structured_json" } }
    )
    standard_result = Engine::Predicates::StandardDrafted.new(claim: standard_claim).call
    expect(standard_result).to be_passed
    expect(standard_result.evidence).to eq({ artifact_id: standard.id })
  end
end
```

**Step 2: Run E2E spec to verify RED or GREEN depending on prior task state**

If fixture files from Task 6 are not present yet, run now and expect RED:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/logging_audit_cookbook_spec.rb
```

Expected before Task 6 files: FAIL because fixture files are missing.

Expected after Task 6 files and predicate classes exist: PASS.

**Step 3: Run focused cookbook specs to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/e2e/logging_audit_cookbook_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicates/log_inventory_produced_spec.rb \
  spec/services/engine/predicates/logging_assessed_spec.rb \
  spec/services/engine/predicates/standard_drafted_spec.rb \
  spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add \
  test/fixtures/apps/bad_logging/README.md \
  test/fixtures/apps/bad_logging/app/controllers/orders_controller.rb \
  test/fixtures/apps/bad_logging/app/jobs/process_user_job.rb \
  test/fixtures/apps/bad_logging/app/services/structured_payment_logger.rb \
  test/fixtures/apps/bad_logging/app/services/payment_error_handler.rb \
  test/fixtures/apps/bad_logging/app/services/critical_account_reconciler.rb \
  spec/e2e/logging_audit_cookbook_spec.rb

git commit -m "test: add logging audit cookbook fixture"
```

---

### Task 8: Add explicit portability and source-spec coverage checks

**Objective:** Guard against hardcoded paths, unresolved `file://` prompts, missing stage configs, and drift from the source spec.

**Files:**
- Modify: `spec/e2e/logging_audit_cookbook_spec.rb`
- Optional Modify: `spec/models/work_queue_seed_spec.rb` if the seed spec needs smaller focused assertions

**Step 1: Add failing portability examples**

Add these examples to `spec/e2e/logging_audit_cookbook_spec.rb`:

```ruby
it "keeps queue YAML portable and references only repo-relative prompt files" do
  yaml_path = Rails.root.join("config/queues/logging_audit.yml")
  yaml = yaml_path.read

  expect(yaml).not_to include(Rails.root.to_s)
  expect(yaml).not_to include("/Users/")
  expect(yaml).not_to include("file:///")
  expect(yaml.scan(/file:\/\/prompts\/logging_[a-z_]+\.md/).uniq).to contain_exactly(
    "file://prompts/logging_scan_statements.md",
    "file://prompts/logging_assess_quality.md",
    "file://prompts/logging_draft_standard.md",
    "file://prompts/logging_draft_fixes.md"
  )
end

it "covers the source cookbook spec stages, artifacts, and predicates" do
  source_spec = Rails.root.join("docs/specs/cookbook-06-logging-consistency-audit.md").read
  queue_yaml = Rails.root.join("config/queues/logging_audit.yml").read

  %w[
    scan_log_statements
    assess_quality
    draft_standard
    draft_fixes
    run_tests
    human_review
    done
    log_inventory
    logging_assessment
    logging_standard
    log_patches
    log_inventory_produced
    logging_assessed
    standard_drafted
  ].each do |required_term|
    expect(source_spec).to include(required_term)
    expect(queue_yaml).to include(required_term)
  end
end
```

**Step 2: Run E2E spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/logging_audit_cookbook_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add spec/e2e/logging_audit_cookbook_spec.rb
git commit -m "test: enforce logging audit cookbook portability"
```

---

### Task 9: Run cookbook-focused regression suite

**Objective:** Verify the logging audit cookbook integrates with existing seed, predicate, and shell adapter behavior.

**Files:**
- No production file changes expected.

**Step 1: Run focused specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicates/log_inventory_produced_spec.rb \
  spec/services/engine/predicates/logging_assessed_spec.rb \
  spec/services/engine/predicates/standard_drafted_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/e2e/logging_audit_cookbook_spec.rb \
  spec/adapters/adapters/shell_script_adapter_spec.rb
```

Expected: PASS.

**Step 2: Run optional broader safety suite if time allows**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models spec/services/engine spec/adapters/adapters/shell_script_adapter_spec.rb spec/e2e/logging_audit_cookbook_spec.rb
```

Expected: PASS.

**Step 3: Inspect git status**

Run:

```bash
git status --short
```

Expected: only intentional committed files are clean. Untracked unrelated docs/spec PDFs may already exist in the working tree; do not stage them for this cookbook implementation.

---

## Implementation Task Checklist

- [ ] Add RED specs for `Engine::Predicates::LogInventoryProduced`, `Engine::Predicates::LoggingAssessed`, and `Engine::Predicates::StandardDrafted`.
- [ ] Implement the three predicate classes with `artifact_id` evidence and actionable failure reasons.
- [ ] Register `log_inventory_produced`, `logging_assessed`, and `standard_drafted` in `Engine::PredicateRegistry`.
- [ ] Add a RED seed spec for the `logging_audit` queue, stage configs, resolved prompt bodies, and docker-friendly `run_tests` command.
- [ ] Add `config/queues/logging_audit.yml` with portable `file://prompts/...` paths and no absolute working directory.
- [ ] Add four prompt files under `prompts/` for scan, assess, standard, and fixes stages.
- [ ] Add bad logging fixture app files under `test/fixtures/apps/bad_logging/`.
- [ ] Add `spec/e2e/logging_audit_cookbook_spec.rb` covering queue wiring, prompt resolution, fixture patterns, predicate artifacts, source-spec terms, and portability.
- [ ] Run focused RSpec commands with Greg's rbenv PATH prefix.
- [ ] Search the new queue YAML/prompts for hardcoded checkout paths and `file:///` prompt URIs.
- [ ] Commit each completed slice after tests pass.

Expected final implementation commit message:

```bash
git commit -m "feat: add logging consistency audit cookbook"
```

If following the slice commits above instead, the final commits should be:

- `feat: add logging audit artifact predicates`
- `feat: seed logging audit cookbook queue`
- `test: add logging audit cookbook fixture`
- `test: enforce logging audit cookbook portability`

---

## Final Verification Commands

Run before marking the implementation task complete:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicates/log_inventory_produced_spec.rb \
  spec/services/engine/predicates/logging_assessed_spec.rb \
  spec/services/engine/predicates/standard_drafted_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/e2e/logging_audit_cookbook_spec.rb \
  spec/adapters/adapters/shell_script_adapter_spec.rb

grep -R "/Users/gregmushen/work/code/taskrail\|file:///." \
  config/queues/logging_audit.yml \
  prompts/logging_scan_statements.md \
  prompts/logging_assess_quality.md \
  prompts/logging_draft_standard.md \
  prompts/logging_draft_fixes.md

git status --short
```

Expected:

- RSpec exits 0.
- `grep` emits no output.
- `git status --short` has no uncommitted implementation files, aside from unrelated pre-existing untracked documents that should not be staged.

## Implementation Dependencies

- The shared cookbook infrastructure must already support loading all `config/queues/*.yml` through `db/seeds.rb`; this exists today.
- `file://` prompt resolution must stay repo-relative through `Rails.root.join`; this exists today.
- The existing `fixes_drafted`, `tests_passed`, and `report_present` predicates must remain registered.
- The shell adapter must continue to default to `Rails.root.to_s` when no `working_directory` is configured.
- No cookbook-specific Docker Compose services are required for this plan.
