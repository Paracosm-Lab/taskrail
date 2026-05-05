# Error Handling Audit Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add an `error_handling_audit` cookbook queue that scans a Rails codebase for unsafe error handling, classifies findings, drafts fixes, runs validation, and gates on human review.

**Architecture:** Seed a portable YAML-backed queue with file-backed prompts, add three artifact predicates for the new audit artifacts, and cover the full queue with seed, predicate, and workflow specs. Keep runtime infrastructure docker-friendly by using existing adapter boundaries and Rails.root-relative paths; do not introduce new shared Docker services in this cookbook slice.

**Tech Stack:** Rails, RSpec, YAML queue seeds, StupidClaw `inline_claude`, `shell_script`, and `fake` adapters, `Engine::PredicateRegistry`, `Engine::Predicates::*`, ActiveRecord artifacts/reports/claims.

**Source spec:** `docs/specs/cookbook-02-error-handling-audit.md`

---

## Ground Rules for the Implementer

- Work in repository: `/Users/gregmushen/work/code/stupidclaw`.
- Use strict TDD for every production behavior change:
  1. Write the focused failing spec first.
  2. Run it and verify the failure is for the expected missing behavior.
  3. Implement the smallest production change.
  4. Re-run the focused spec and then the relevant wider spec set.
  5. Commit after each task.
- On Greg's Mac, run Rails specs through rbenv shims:
  ```bash
  PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec <spec path>
  ```
- Queue YAML must be portable. Do not hardcode `/Users/gregmushen/...` or any other checkout path in queue config. Rely on Rails.root defaults and `file://` prompt paths relative to Rails.root.
- Do not duplicate shared cookbook infrastructure. This cookbook may reference existing shared adapters and docker-friendly shell commands, but any reusable Docker Compose services, shared fake app harnesses, or global prompt resolver changes belong in the shared cookbook infrastructure plan.

---

## Target File Map

### Create

- `config/queues/error_handling_audit.yml`
- `prompts/audit_scan_error_handling.md`
- `prompts/audit_classify_severity.md`
- `prompts/audit_draft_fixes.md`
- `app/services/engine/predicates/error_patterns_found.rb`
- `app/services/engine/predicates/severity_classified.rb`
- `app/services/engine/predicates/fixes_drafted.rb`
- `spec/services/engine/predicates/error_patterns_found_spec.rb`
- `spec/services/engine/predicates/severity_classified_spec.rb`
- `spec/services/engine/predicates/fixes_drafted_spec.rb`
- `spec/services/engine/error_handling_audit_workflow_integration_spec.rb`
- `test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb`
- `test/fixtures/apps/bad_error_handling/app/jobs/sync_job.rb`
- `test/fixtures/apps/bad_error_handling/app/services/external_api.rb`
- `test/fixtures/apps/bad_error_handling/README.md`
- `docs/cookbooks/error-handling-audit.md`

### Modify

- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

### Do Not Modify in This Cookbook Slice

- Shared Docker Compose files unless a focused failing spec proves this cookbook cannot use existing infrastructure.
- `db/seeds.rb` unless prompt resolution fails for Rails.root-relative `file://` paths. The current resolver already reads `Rails.root.join(prompt_path)`.
- Core transition/regression loop code unless an existing max regression loop behavior is not honored by current engine behavior.

---

## Artifact Contracts

Use these data contracts consistently in prompts, predicates, fixture expectations, and docs.

### `error_patterns`

```json
{
  "patterns": [
    {
      "file": "app/controllers/payments_controller.rb",
      "line": 6,
      "type": "bare_rescue_with_puts",
      "code_snippet": "rescue => e\n  puts e.message",
      "severity_hint": "high"
    }
  ]
}
```

Empty arrays are valid:

```json
{ "patterns": [] }
```

### `severity_report`

```json
{
  "findings": [
    {
      "patterns": ["bare_rescue_with_puts:app/controllers/payments_controller.rb:6"],
      "severity": "critical",
      "blast_radius": "user-facing payment controller",
      "data_risk": "failed charges are hidden behind a generic 500 response",
      "frequency": "hot path",
      "recommendation": "capture exception with Sentry context and return a specific error"
    }
  ]
}
```

### `fix_patches`

```json
{
  "patches": [
    {
      "file": "app/controllers/payments_controller.rb",
      "original": "rescue => e\n  puts e.message",
      "replacement": "rescue PaymentGateway::Error => e\n  Sentry.capture_exception(e, extra: { amount: params[:amount] })\n  Rails.logger.error(event: \"payment_charge_failed\", error_class: e.class.name)",
      "finding_ref": "bare_rescue_with_puts:app/controllers/payments_controller.rb:6",
      "severity": "critical"
    }
  ]
}
```

`fixes_drafted` requires at least one patch. If `error_patterns.patterns` is empty, the workflow should not reach `draft_fixes` in normal usage; the predicate should still fail a blank `patches` array because there is nothing to apply.

---

## Task 1: Add RED Predicate Specs for Error Pattern Artifacts

**Objective:** Specify the new predicate behavior before implementation.

**Files:**
- Create: `spec/services/engine/predicates/error_patterns_found_spec.rb`
- Create: `spec/services/engine/predicates/severity_classified_spec.rb`
- Create: `spec/services/engine/predicates/fixes_drafted_spec.rb`

**Step 1: Write failing spec for `error_patterns_found`**

Create `spec/services/engine/predicates/error_patterns_found_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ErrorPatternsFound do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Error Patterns Found",
      slug: "error-patterns-found-#{SecureRandom.hex(4)}",
      stages: ["scan", "done"]
    )
    queue.stage_configs.create!(stage_name: "scan", adapter_type: "fake")
    item = WorkItem.create!(title: "Audit", spec_url: "opaque spec", work_queue: queue, stage_name: "scan")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when an error_patterns artifact exists with findings" do
    claim = build_claim(artifacts: [
      { kind: "error_patterns", data: { "patterns" => [{ "file" => "app/controllers/payments_controller.rb" }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "error_patterns")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, pattern_count: 1 })
  end

  it "passes when an error_patterns artifact exists with an empty patterns array" do
    claim = build_claim(artifacts: [
      { kind: "error_patterns", data: { "patterns" => [] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "error_patterns")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, pattern_count: 0 })
  end

  it "fails when no error_patterns artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no error_patterns artifact found")
  end
end
```

**Step 2: Write failing spec for `severity_classified`**

Create `spec/services/engine/predicates/severity_classified_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::SeverityClassified do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Severity Classified",
      slug: "severity-classified-#{SecureRandom.hex(4)}",
      stages: ["classify", "done"]
    )
    queue.stage_configs.create!(stage_name: "classify", adapter_type: "fake")
    item = WorkItem.create!(title: "Audit", spec_url: "opaque spec", work_queue: queue, stage_name: "classify")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when severity_report has findings" do
    claim = build_claim(artifacts: [
      { kind: "severity_report", data: { "findings" => [{ "severity" => "high" }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "severity_report")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, finding_count: 1 })
  end

  it "fails when severity_report has no findings" do
    claim = build_claim(artifacts: [
      { kind: "severity_report", data: { "findings" => [] } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("severity_report artifact has no findings")
  end

  it "fails when no severity_report artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no severity_report artifact found")
  end
end
```

**Step 3: Write failing spec for `fixes_drafted`**

Create `spec/services/engine/predicates/fixes_drafted_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::FixesDrafted do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Fixes Drafted",
      slug: "fixes-drafted-#{SecureRandom.hex(4)}",
      stages: ["draft", "done"]
    )
    queue.stage_configs.create!(stage_name: "draft", adapter_type: "fake")
    item = WorkItem.create!(title: "Audit", spec_url: "opaque spec", work_queue: queue, stage_name: "draft")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when fix_patches has at least one patch" do
    claim = build_claim(artifacts: [
      { kind: "fix_patches", data: { "patches" => [{ "file" => "app/controllers/payments_controller.rb" }] } }
    ])
    artifact = claim.artifacts.find_by!(kind: "fix_patches")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, patch_count: 1 })
  end

  it "fails when fix_patches has no patches" do
    claim = build_claim(artifacts: [
      { kind: "fix_patches", data: { "patches" => [] } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("fix_patches artifact has no patches")
  end

  it "fails when no fix_patches artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no fix_patches artifact found")
  end
end
```

**Step 4: Run RED specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/error_patterns_found_spec.rb \
  spec/services/engine/predicates/severity_classified_spec.rb \
  spec/services/engine/predicates/fixes_drafted_spec.rb
```

Expected: FAIL with uninitialized constants such as `Engine::Predicates::ErrorPatternsFound`.

**Step 5: Commit?**

Do not commit RED-only tests unless this repo's workflow explicitly wants RED commits. Continue to Task 2 and commit GREEN implementation with the specs.

---

## Task 2: Implement New Artifact Predicates

**Objective:** Add minimal predicate classes that satisfy the RED specs.

**Files:**
- Create: `app/services/engine/predicates/error_patterns_found.rb`
- Create: `app/services/engine/predicates/severity_classified.rb`
- Create: `app/services/engine/predicates/fixes_drafted.rb`

**Step 1: Implement `ErrorPatternsFound`**

Create `app/services/engine/predicates/error_patterns_found.rb`:

```ruby
module Engine
  module Predicates
    class ErrorPatternsFound
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "error_patterns").first
        return PredicateResult.fail(reason: "no error_patterns artifact found") unless artifact

        patterns = artifact.data.fetch("patterns", [])
        PredicateResult.pass(evidence: { artifact_id: artifact.id, pattern_count: patterns.count })
      end
    end
  end
end
```

**Step 2: Implement `SeverityClassified`**

Create `app/services/engine/predicates/severity_classified.rb`:

```ruby
module Engine
  module Predicates
    class SeverityClassified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "severity_report").first
        return PredicateResult.fail(reason: "no severity_report artifact found") unless artifact

        findings = artifact.data.fetch("findings", [])
        return PredicateResult.fail(reason: "severity_report artifact has no findings") if findings.empty?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, finding_count: findings.count })
      end
    end
  end
end
```

**Step 3: Implement `FixesDrafted`**

Create `app/services/engine/predicates/fixes_drafted.rb`:

```ruby
module Engine
  module Predicates
    class FixesDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "fix_patches").first
        return PredicateResult.fail(reason: "no fix_patches artifact found") unless artifact

        patches = artifact.data.fetch("patches", [])
        return PredicateResult.fail(reason: "fix_patches artifact has no patches") if patches.empty?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, patch_count: patches.count })
      end
    end
  end
end
```

**Step 4: Run GREEN predicate specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/error_patterns_found_spec.rb \
  spec/services/engine/predicates/severity_classified_spec.rb \
  spec/services/engine/predicates/fixes_drafted_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add \
  app/services/engine/predicates/error_patterns_found.rb \
  app/services/engine/predicates/severity_classified.rb \
  app/services/engine/predicates/fixes_drafted.rb \
  spec/services/engine/predicates/error_patterns_found_spec.rb \
  spec/services/engine/predicates/severity_classified_spec.rb \
  spec/services/engine/predicates/fixes_drafted_spec.rb
git commit -m "feat: add error handling audit predicates"
```

---

## Task 3: Register Predicates

**Objective:** Make the new predicate names available to queue completion criteria.

**Files:**
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing registry expectations**

Modify `spec/services/engine/predicate_registry_spec.rb` in the known predicate example to include:

```ruby
expect(described_class.resolve("error_patterns_found")).to eq(Engine::Predicates::ErrorPatternsFound)
expect(described_class.resolve("severity_classified")).to eq(Engine::Predicates::SeverityClassified)
expect(described_class.resolve("fixes_drafted")).to eq(Engine::Predicates::FixesDrafted)
```

**Step 2: Run RED registry spec**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate: error_patterns_found`.

**Step 3: Register predicates**

Modify `app/services/engine/predicate_registry.rb` by adding these entries to `PREDICATES`:

```ruby
"error_patterns_found" => Predicates::ErrorPatternsFound,
"severity_classified" => Predicates::SeverityClassified,
"fixes_drafted" => Predicates::FixesDrafted,
```

Place them near related artifact predicates such as `clusters_created` and `assessment_complete`.

**Step 4: Run GREEN registry and predicate specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/predicates/error_patterns_found_spec.rb \
  spec/services/engine/predicates/severity_classified_spec.rb \
  spec/services/engine/predicates/fixes_drafted_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register error handling audit predicates"
```

---

## Task 4: Add RED Seed Spec for the Error Handling Audit Queue

**Objective:** Specify the queue seed, stage configs, prompt resolution, portable config, and shell validation command before adding YAML and prompts.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`

**Step 1: Add failing seed spec**

Append this example before the idempotency example in `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the error handling audit queue with resolved prompt files and portable config" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "error_handling_audit")
  expect(queue.name).to eq("Error Handling Audit")
  expect(queue.stages).to eq(%w[
    scan_error_handling
    classify_severity
    draft_fixes
    run_tests
    human_review
    done
  ])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_escalation" => "block_and_notify",
    "default_timeout_seconds" => 600,
    "max_regression_loops" => 3
  )

  scan = queue.stage_configs.find_by!(stage_name: "scan_error_handling")
  expect(scan.adapter_type).to eq("inline_claude")
  expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
  expect(scan.allowed_skills).to eq(["read_repo"])
  expect(scan.forbidden_skills).to include("edit_files", "deploy")
  expect(scan.completion_criteria).to eq(["error_patterns_found"])
  expect(scan.agent_prompt).to include("# Audit Scan Error Handling")
  expect(scan.agent_prompt).to include("error_patterns")
  expect(scan.agent_prompt).not_to start_with("file://")
  expect(scan.adapter_config).to eq("output_artifact_kind" => "error_patterns")

  classify = queue.stage_configs.find_by!(stage_name: "classify_severity")
  expect(classify.adapter_type).to eq("inline_claude")
  expect(classify.model_override).to eq("claude-sonnet-4-20250514")
  expect(classify.completion_criteria).to eq(["severity_classified"])
  expect(classify.agent_prompt).to include("# Audit Classify Severity")
  expect(classify.adapter_config).to eq("output_artifact_kind" => "severity_report")

  draft = queue.stage_configs.find_by!(stage_name: "draft_fixes")
  expect(draft.adapter_type).to eq("inline_claude")
  expect(draft.completion_criteria).to eq(["fixes_drafted"])
  expect(draft.agent_prompt).to include("# Audit Draft Fixes")
  expect(draft.adapter_config).to eq("output_artifact_kind" => "fix_patches")

  run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
  expect(run_tests.adapter_type).to eq("shell_script")
  expect(run_tests.completion_criteria).to eq(["tests_passed"])
  expect(run_tests.adapter_config).not_to have_key("working_directory")
  expect(run_tests.adapter_config.fetch("commands").first).to include(
    "name" => "error handling audit fixture smoke",
    "artifact" => "test_results"
  )
  expect(run_tests.adapter_config.fetch("commands").first.fetch("command")).to include("test/fixtures/apps/bad_error_handling")

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.timeout_seconds).to eq(86_400)
end
```

**Step 2: Run RED seed spec**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL with `Couldn't find WorkQueue` for slug `error_handling_audit` or missing prompt files once the YAML is partially added.

---

## Task 5: Add Queue YAML and Prompt Files

**Objective:** Seed the cookbook queue from portable YAML and resolved file-backed prompts.

**Files:**
- Create: `config/queues/error_handling_audit.yml`
- Create: `prompts/audit_scan_error_handling.md`
- Create: `prompts/audit_classify_severity.md`
- Create: `prompts/audit_draft_fixes.md`

**Step 1: Add portable queue YAML**

Create `config/queues/error_handling_audit.yml`:

```yaml
name: Error Handling Audit
slug: error_handling_audit
stages:
  - scan_error_handling
  - classify_severity
  - draft_fixes
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 3
stage_configs:
  scan_error_handling:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [error_patterns_found]
    agent_prompt: file://prompts/audit_scan_error_handling.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: error_patterns
  classify_severity:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [severity_classified]
    agent_prompt: file://prompts/audit_classify_severity.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: severity_report
  draft_fixes:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [fixes_drafted]
    agent_prompt: file://prompts/audit_draft_fixes.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: fix_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [tests_passed]
    agent_prompt: Apply fix patches and run the bad error handling fixture smoke check. Report pass/fail with command output.
    timeout_seconds: 600
    adapter_config:
      commands:
        - name: error handling audit fixture smoke
          artifact: test_results
          command: ruby -c test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb && ruby -c test/fixtures/apps/bad_error_handling/app/jobs/sync_job.rb && ruby -c test/fixtures/apps/bad_error_handling/app/services/external_api.rb
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review error handling findings and drafted fixes before merge.
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
- There is no `working_directory` key. `Adapters::ShellScriptAdapter` defaults to `Rails.root.to_s`.
- The smoke command is docker-friendly because it uses relative paths and the system Ruby available inside the app container. If the shared infrastructure plan later provides a dedicated fixture runner, replace only the command string and keep the artifact contract.
- This stage validates the fixture files and the shell artifact path; it does not apply real patches yet unless shared patch-application infrastructure exists.

**Step 2: Add scan prompt**

Create `prompts/audit_scan_error_handling.md`:

```markdown
# Audit Scan Error Handling

You are the scan stage for the StupidClaw `error_handling_audit` queue.

## Input

- Repository path from the work item assignment.
- Read-only repository access.

## Task

Scan the target repository for error handling anti-patterns:

- Bare `rescue => e` or `rescue StandardError`.
- Empty rescue blocks or swallowed exceptions.
- `puts`, `p`, or `pp` for error output instead of structured logging.
- `rescue` without re-raise, structured logging, or Sentry capture.
- Generic error messages with no useful context, such as `something went wrong`.
- HTTP calls without explicit timeout configuration.
- Retry loops without backoff.

## Output Artifact

Return exactly one artifact with kind `error_patterns` and this JSON shape:

```json
{
  "patterns": [
    {
      "file": "relative/path.rb",
      "line": 123,
      "type": "bare_rescue_with_puts",
      "code_snippet": "rescue => e\\n  puts e.message",
      "severity_hint": "high"
    }
  ]
}
```

An empty `patterns` array is valid for a clean codebase. Use repository-relative file paths only.
```

**Step 3: Add classify prompt**

Create `prompts/audit_classify_severity.md`:

```markdown
# Audit Classify Severity

You are the classify stage for the StupidClaw `error_handling_audit` queue.

## Input

- The prior `error_patterns` artifact.
- Read-only repository source code.

## Task

For each pattern, assess:

- Blast radius: user-facing controller, background job, internal helper, data pipeline, etc.
- Data risk: data loss, silent payment failure, corrupted state, or low-risk observability gap.
- Frequency: hot path, scheduled job, rare edge case, or unknown.
- Severity: one of `critical`, `high`, `medium`, or `low`.
- Related patterns that should be fixed together.

If a critical finding requires architectural work beyond direct error handling cleanup, include a `spawn_work_items` entry targeting the `development` queue with a concise inline spec for the larger refactor.

## Output Artifact

Return exactly one artifact with kind `severity_report` and this JSON shape:

```json
{
  "findings": [
    {
      "patterns": ["type:relative/path.rb:line"],
      "severity": "high",
      "blast_radius": "user-facing controller",
      "data_risk": "silent failed payment",
      "frequency": "hot path",
      "recommendation": "capture exception with Sentry context and structured logging"
    }
  ]
}
```

If architectural follow-up is required, the report body may also include:

```json
{
  "spawn_work_items": [
    {
      "queue_slug": "development",
      "title": "Refactor payment gateway error boundary",
      "spec_inline": "Add a typed PaymentGateway::Error hierarchy and update callers.",
      "tags": { "source": "error_handling_audit", "severity": "critical" }
    }
  ]
}
```
```

**Step 4: Add draft prompt**

Create `prompts/audit_draft_fixes.md`:

```markdown
# Audit Draft Fixes

You are the draft fixes stage for the StupidClaw `error_handling_audit` queue.

## Input

- The `severity_report` artifact.
- Repository source code.
- Existing project examples of good error handling, structured logging, and Sentry context.

## Task

Draft focused patches for each finding, starting with critical and high severity findings.

Use these remediation patterns where appropriate:

- Replace bare rescues with specific exception classes.
- Add `Sentry.capture_exception` with useful tags/extra context.
- Add structured `Rails.logger` messages with operation, record id, job id, request id, and error class where available.
- Preserve user-facing behavior unless the severity report recommends a behavior change.
- Add timeout configuration for HTTP calls that lack timeouts.
- Add bounded retry with backoff for retry loops that currently spin or retry immediately.
- Follow existing project style and do not introduce broad dependencies.

## Output Artifact

Return exactly one artifact with kind `fix_patches` and this JSON shape:

```json
{
  "patches": [
    {
      "file": "relative/path.rb",
      "original": "exact original snippet",
      "replacement": "exact replacement snippet",
      "finding_ref": "type:relative/path.rb:line",
      "severity": "high"
    }
  ]
}
```

Use repository-relative paths only. Do not include absolute checkout paths. If a finding should not be auto-fixed, omit it from `patches` and explain why in the report summary.
```

**Step 5: Run GREEN seed spec**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS after Task 6 fixture files are present. If it fails because fixture files are missing, continue to Task 6 and re-run before committing.

**Step 6: Commit after Task 6 passes**

Do not commit this task until the fixture files in Task 6 make the shell command valid and the seed spec passes.

---

## Task 6: Add Bad Error Handling Fixture App

**Objective:** Provide a small fixture app with deliberately bad patterns for scan and workflow smoke coverage.

**Files:**
- Create: `test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb`
- Create: `test/fixtures/apps/bad_error_handling/app/jobs/sync_job.rb`
- Create: `test/fixtures/apps/bad_error_handling/app/services/external_api.rb`
- Create: `test/fixtures/apps/bad_error_handling/README.md`

**Step 1: Create payments controller fixture**

Create `test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb`:

```ruby
class PaymentsController
  def params
    { amount: 100 }
  end

  def render(json:, status: 200)
    { json: json, status: status }
  end

  def create
    charge = PaymentGateway.charge(params[:amount])
    render json: charge
  rescue => e
    puts e.message
    render json: { error: "something went wrong" }, status: 500
  end
end
```

**Step 2: Create sync job fixture**

Create `test/fixtures/apps/bad_error_handling/app/jobs/sync_job.rb`:

```ruby
class SyncJob
  def perform(user_id)
    user = User.find(user_id)
    ExternalApi.sync(user)
  rescue
    # silently swallowed
  end
end
```

**Step 3: Create external API fixture**

Create `test/fixtures/apps/bad_error_handling/app/services/external_api.rb`:

```ruby
class ExternalApi
  def self.sync(user)
    HTTP.get("https://api.example.com/sync/#{user.id}") # no timeout
  end
end
```

**Step 4: Document fixture intent**

Create `test/fixtures/apps/bad_error_handling/README.md`:

```markdown
# Bad Error Handling Fixture

This fixture intentionally contains unsafe patterns for the `error_handling_audit` cookbook:

- `PaymentsController#create` uses a bare `rescue => e`, `puts`, and a generic error message.
- `SyncJob#perform` swallows all exceptions.
- `ExternalApi.sync` performs an HTTP call without an explicit timeout.

Do not clean up these patterns in the fixture unless the cookbook spec changes.
```

**Step 5: Run fixture syntax smoke command**

Run:

```bash
ruby -c test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb && \
ruby -c test/fixtures/apps/bad_error_handling/app/jobs/sync_job.rb && \
ruby -c test/fixtures/apps/bad_error_handling/app/services/external_api.rb
```

Expected: all three commands print `Syntax OK`.

**Step 6: Re-run seed spec**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 7: Commit queue, prompts, fixture, and seed spec**

```bash
git add \
  config/queues/error_handling_audit.yml \
  prompts/audit_scan_error_handling.md \
  prompts/audit_classify_severity.md \
  prompts/audit_draft_fixes.md \
  test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb \
  test/fixtures/apps/bad_error_handling/app/jobs/sync_job.rb \
  test/fixtures/apps/bad_error_handling/app/services/external_api.rb \
  test/fixtures/apps/bad_error_handling/README.md \
  spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed error handling audit queue"
```

---

## Task 7: Add RED Workflow Integration Spec

**Objective:** Prove the seeded queue can advance through the scan, classify, draft, and run_tests stages using existing adapter boundaries and the new predicates.

**Files:**
- Create: `spec/services/engine/error_handling_audit_workflow_integration_spec.rb`

**Step 1: Write failing workflow spec**

Create `spec/services/engine/error_handling_audit_workflow_integration_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "error handling audit workflow", type: :model do
  it "advances through audit stages using produced artifacts" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "error_handling_audit")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Audit bad error handling fixture",
      spec_url: "test/fixtures/apps/bad_error_handling",
      stage_name: "scan_error_handling",
      status: :pending
    )

    scan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    Artifact.create!(
      work_item: work_item,
      claim: scan_claim,
      kind: "error_patterns",
      data: {
        "patterns" => [
          {
            "file" => "test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb",
            "line" => 12,
            "type" => "bare_rescue_with_puts",
            "code_snippet" => "rescue => e\n    puts e.message",
            "severity_hint" => "high"
          }
        ]
      }
    )
    Engine::TransitionManager.new(
      work_item: work_item,
      claim: scan_claim,
      stage_config: queue.stage_configs.find_by!(stage_name: "scan_error_handling")
    ).call
    expect(work_item.reload.stage_name).to eq("classify_severity")

    classify_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    Artifact.create!(
      work_item: work_item,
      claim: classify_claim,
      kind: "severity_report",
      data: {
        "findings" => [
          {
            "patterns" => ["bare_rescue_with_puts:test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb:12"],
            "severity" => "high",
            "blast_radius" => "user-facing controller",
            "data_risk" => "generic failure hides payment errors",
            "frequency" => "hot path",
            "recommendation" => "capture exception and log structured context"
          }
        ]
      }
    )
    Engine::TransitionManager.new(
      work_item: work_item,
      claim: classify_claim,
      stage_config: queue.stage_configs.find_by!(stage_name: "classify_severity")
    ).call
    expect(work_item.reload.stage_name).to eq("draft_fixes")

    draft_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
    Artifact.create!(
      work_item: work_item,
      claim: draft_claim,
      kind: "fix_patches",
      data: {
        "patches" => [
          {
            "file" => "test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb",
            "original" => "rescue => e\n    puts e.message",
            "replacement" => "rescue PaymentGateway::Error => e\n    Rails.logger.error(event: 'payment_failed', error_class: e.class.name)",
            "finding_ref" => "bare_rescue_with_puts:test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb:12",
            "severity" => "high"
          }
        ]
      }
    )
    Engine::TransitionManager.new(
      work_item: work_item,
      claim: draft_claim,
      stage_config: queue.stage_configs.find_by!(stage_name: "draft_fixes")
    ).call
    expect(work_item.reload.stage_name).to eq("run_tests")

    processed = Engine::Runner.new.call

    expect(processed).to eq(work_item)
    expect(work_item.reload.stage_name).to eq("human_review")
    test_results = work_item.artifacts.find_by!(kind: "test_results")
    expect(test_results.data["passed"]).to eq(true)
    expect(work_item.transition_logs.pluck(:to_stage)).to include(
      "classify_severity",
      "draft_fixes",
      "run_tests",
      "human_review"
    )
  end
end
```

**Step 2: Run RED/GREEN workflow spec depending on prior tasks**

If Tasks 1-6 are complete, this may pass immediately because it exercises already-built behavior. If it fails, the failure is a real integration gap to fix with the smallest production change.

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/error_handling_audit_workflow_integration_spec.rb
```

Expected after implementation: PASS.

**Step 3: Run focused queue/predicate regression set**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/error_handling_audit_workflow_integration_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/predicates/error_patterns_found_spec.rb \
  spec/services/engine/predicates/severity_classified_spec.rb \
  spec/services/engine/predicates/fixes_drafted_spec.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add spec/services/engine/error_handling_audit_workflow_integration_spec.rb
git commit -m "test: cover error handling audit workflow"
```

---

## Task 8: Add Cookbook Documentation

**Objective:** Document how to use the cookbook queue and what infrastructure it expects.

**Files:**
- Create: `docs/cookbooks/error-handling-audit.md`

**Step 1: Write documentation**

Create `docs/cookbooks/error-handling-audit.md`:

```markdown
# Error Handling Audit Cookbook

Source spec: `docs/specs/cookbook-02-error-handling-audit.md`

The `error_handling_audit` queue scans a repository for unsafe error handling, classifies findings by operational risk, drafts fixes, runs a fixture validation command, and waits for human review.

## Queue Stages

`scan_error_handling -> classify_severity -> draft_fixes -> run_tests -> human_review -> done`

## Artifacts

- `error_patterns`: scan output with `{ patterns: [...] }`. Empty arrays are valid.
- `severity_report`: classified findings with severity, blast radius, data risk, frequency, and recommendation.
- `fix_patches`: proposed patches for findings that can be directly remediated.
- `test_results`: shell validation output from the existing `shell_script` adapter.

## Infrastructure Requirements

This cookbook uses existing StupidClaw infrastructure:

- `inline_claude` for scan/classify/draft stages.
- `shell_script` for validation.
- `fake` for human review and terminal done stages.
- Rails.root-relative prompt files under `prompts/`.
- Rails.root-relative fixture files under `test/fixtures/apps/bad_error_handling/`.

It does not add dedicated Docker Compose services. In Docker, run the app with the shared cookbook infrastructure and ensure Ruby is available for the fixture syntax command.

## Cross-Queue Spawn

The classify stage may include `spawn_work_items` in its report body for critical findings that need broader architectural work. Those items should target the `development` queue and include `tags.source = error_handling_audit`.

## Local Verification

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/error_handling_audit_workflow_integration_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/predicates/error_patterns_found_spec.rb \
  spec/services/engine/predicates/severity_classified_spec.rb \
  spec/services/engine/predicates/fixes_drafted_spec.rb
```
```

**Step 2: Verify docs mention the source spec**

Run:

```bash
grep -n "docs/specs/cookbook-02-error-handling-audit.md" docs/cookbooks/error-handling-audit.md
```

Expected: at least one matching line.

**Step 3: Commit**

```bash
git add docs/cookbooks/error-handling-audit.md
git commit -m "docs: add error handling audit cookbook"
```

---

## Task 9: Full Focused Verification

**Objective:** Verify the whole cookbook slice before final handoff.

**Files:**
- No file changes.

**Step 1: Run focused regression set**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/error_handling_audit_workflow_integration_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/predicates/error_patterns_found_spec.rb \
  spec/services/engine/predicates/severity_classified_spec.rb \
  spec/services/engine/predicates/fixes_drafted_spec.rb
```

Expected: PASS.

**Step 2: Run fixture syntax command**

Run:

```bash
ruby -c test/fixtures/apps/bad_error_handling/app/controllers/payments_controller.rb && \
ruby -c test/fixtures/apps/bad_error_handling/app/jobs/sync_job.rb && \
ruby -c test/fixtures/apps/bad_error_handling/app/services/external_api.rb
```

Expected: all files report `Syntax OK`.

**Step 3: Check for non-portable paths**

Run:

```bash
grep -R "/Users/gregmushen/work/code/stupidclaw" \
  config/queues/error_handling_audit.yml \
  prompts/audit_scan_error_handling.md \
  prompts/audit_classify_severity.md \
  prompts/audit_draft_fixes.md \
  test/fixtures/apps/bad_error_handling \
  docs/cookbooks/error-handling-audit.md
```

Expected: no output and exit status 1 from grep.

**Step 4: Confirm clean staged state**

Run:

```bash
git status --short
```

Expected: no modified or untracked files from this implementation slice. Existing unrelated untracked docs/spec files may remain; do not add them unless they are part of this cookbook implementation.

---

## Fake Docker-Friendly Infrastructure Notes

- The cookbook should run inside the existing app container or local Rails process. The only shell command uses relative paths and Ruby syntax checks, so it is safe in Docker and on macOS.
- Do not add a cookbook-specific database, Sentry, Redis, or external HTTP mock service in this slice.
- If later implementation needs actual patch application, add that to shared cookbook infrastructure as a reusable adapter/helper, then update `run_tests.adapter_config.commands` or adapter behavior in a separate plan.
- Keep `adapter_config.working_directory` omitted unless a future spec proves it is necessary. Current `ShellScriptAdapter::DEFAULT_WORKING_DIRECTORY` is `Rails.root.to_s`, which is portable across checkouts and Docker containers.

---

## Implementation Task Checklist

- [ ] Task 1: RED predicate specs added and verified failing.
- [ ] Task 2: Predicate classes implemented, predicate specs passing, committed.
- [ ] Task 3: Predicate registry updated, registry spec passing, committed.
- [ ] Task 4: RED seed spec added and verified failing.
- [ ] Task 5: Queue YAML and prompt files added with portable `file://` paths.
- [ ] Task 6: Bad error handling fixture files added; seed spec passing; committed.
- [ ] Task 7: Workflow integration spec added and passing; committed.
- [ ] Task 8: Cookbook documentation added and source spec reference verified; committed.
- [ ] Task 9: Focused regression set, fixture syntax smoke, and hardcoded-path check all pass.

## Expected Final Commit Message

Use this final implementation commit message if the implementer squashes the task commits:

```bash
git commit -m "feat: add error handling audit cookbook queue"
```

If preserving the per-task commits above, no extra final commit is needed after Task 9.
