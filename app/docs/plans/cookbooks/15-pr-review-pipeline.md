# PR Review Pipeline Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `pr_review` cookbook queue so TaskRail can run mechanical PR checks, security scan, coverage review, architectural review, and then hand a compact evidence bundle to a human reviewer.

**Architecture:** Implement this as a seeded Rails queue backed by portable YAML, `file://` prompt files resolved through `Rails.root`, three focused artifact predicates, and a small docker-friendly fixture app under `cookbooks/fixtures/apps/pr_review_app`. Reuse existing shell_script and inline_claude adapters, existing `review_verdict` and `report_present` predicates, existing cross-queue `spawn_work_items` behavior, and existing WorkItem creation API for webhook ingestion.

**Tech Stack:** Rails, RSpec, YAML queue seeds, `Engine::PredicateRegistry`, `Artifact` records, `Report` records, `shell_script` adapter, `inline_claude` adapter, fake human-review stages, shared cookbook fixture infrastructure, rbenv on Greg's Mac.

**Source Spec:** `docs/specs/cookbook-15-pr-review-pipeline.md`

---

## Current codebase context

Relevant existing files and conventions inspected before writing this plan:

- `db/seeds.rb` loads every `config/queues/*.yml`, resolves `agent_prompt: file://...` by reading `Rails.root.join(relative_path)`, and upserts `WorkQueue` plus `StageConfig` records.
- `config/queues/job_observability.yml`, `config/queues/query_health.yml`, `config/queues/api_docs_sync.yml`, and `config/queues/dead_code_removal.yml` are the closest cookbook queue examples.
- `prompts/jobs_*.md`, `prompts/query_*.md`, `prompts/docs_*.md`, and `cookbooks/prompts/*` show prompt-file patterns. This plan uses top-level `prompts/pr_*.md` because the source spec names those paths directly.
- `app/services/engine/predicate_registry.rb` maps string completion criteria to predicate classes.
- Existing artifact predicates live in `app/services/engine/predicates/*` and generally inspect the current claim's artifacts, then return `PredicateResult.pass(evidence: ...)` or `PredicateResult.fail(reason: ...)`.
- `spec/models/work_queue_seed_spec.rb` already has cookbook seed examples that verify queue stages, stage configs, resolved prompt content, and absence of absolute paths.
- `spec/services/engine/cross_queue_spawn_spec.rb` already covers generic `spawn_work_items`; PR review only needs prompts/config/integration specs that prove the queue can emit that shape.
- `app/controllers/api/v1/work_items_controller.rb#create` already creates work items for any queue slug. A dedicated GitHub PR webhook endpoint should be a thin translation layer, not a new workflow engine.
- Shared cookbook fixture infrastructure exists under `cookbooks/`, including `cookbooks/docker-compose.yml`, `cookbooks/fixtures/apps/`, and guardrails that reject absolute checkout paths in shared cookbook files.

Global implementation rules:

- Use strict TDD for every production behavior change: write the failing spec first, run it and confirm the expected failure, implement the smallest production/config change, rerun the focused spec, then run the relevant broader spec.
- Use Greg's rbenv command prefix for all RSpec commands:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Do not hardcode `/Users/gregmushen/...`, `Rails.root.to_s`, or any absolute checkout path in queue YAML, prompt files, fixtures, or app code.
- Queue prompt indirection must stay repo-relative: `file://prompts/pr_run_checks.md`, `file://prompts/pr_security_scan.md`, `file://prompts/pr_coverage_check.md`, and `file://prompts/pr_architectural_review.md`.
- Do not modify shared adapter classes unless a focused RED spec proves the existing adapter contract cannot support the cookbook.
- Commit after each green implementation slice when executing this plan. If a Kanban implementation assignment asks for one final commit instead, squash before completion.

---

## Files to create or modify

Create:

- `config/queues/pr_review.yml`
- `prompts/pr_run_checks.md`
- `prompts/pr_security_scan.md`
- `prompts/pr_coverage_check.md`
- `prompts/pr_architectural_review.md`
- `app/services/engine/predicates/checks_passed.rb`
- `app/services/engine/predicates/security_reviewed.rb`
- `app/services/engine/predicates/coverage_checked.rb`
- `spec/services/engine/predicates/checks_passed_spec.rb`
- `spec/services/engine/predicates/security_reviewed_spec.rb`
- `spec/services/engine/predicates/coverage_checked_spec.rb`
- `spec/cookbooks/pr_review_pipeline_cookbook_spec.rb`
- `cookbooks/fixtures/apps/pr_review_app/README.md`
- `cookbooks/fixtures/apps/pr_review_app/Gemfile`
- `cookbooks/fixtures/apps/pr_review_app/app/controllers/application_controller.rb`
- `cookbooks/fixtures/apps/pr_review_app/app/controllers/orders_controller.rb`
- `cookbooks/fixtures/apps/pr_review_app/app/models/order.rb`
- `cookbooks/fixtures/apps/pr_review_app/app/models/user.rb`
- `cookbooks/fixtures/apps/pr_review_app/app/services/order_search.rb`
- `cookbooks/fixtures/apps/pr_review_app/config/routes.rb`
- `cookbooks/fixtures/apps/pr_review_app/spec/models/order_spec.rb`
- `cookbooks/fixtures/apps/pr_review_app/spec/requests/orders_spec.rb`

Modify:

- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Optional only if webhook ingestion is in scope for the implementation card:

- `config/routes.rb`
- `app/controllers/api/v1/github_pr_webhooks_controller.rb`
- `spec/requests/api/v1/github_pr_webhooks_spec.rb`

Do not modify unless a failing spec proves it is necessary:

- `db/seeds.rb`, because it already resolves `file://` prompt paths relative to `Rails.root`.
- `app/adapters/adapters/shell_script_adapter.rb`, because existing tests show it maps configured commands to artifacts.
- `app/adapters/adapters/inline_claude_adapter.rb`, because the PR stages only need prompt/config changes.
- `app/services/engine/transition_manager.rb`, because cross-queue spawn already exists for `spawn_work_items` report bodies.

---

## Queue YAML target

Create `config/queues/pr_review.yml` with this target content. Keep every path repo-relative and omit `working_directory` so shell execution defaults remain portable.

```yaml
name: PR Review Pipeline
slug: pr_review
stages:
  - run_checks
  - security_scan
  - coverage_check
  - architectural_review
  - human_review
  - done
config:
  default_max_retries: 1
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
  trigger: github_pull_request
stage_configs:
  run_checks:
    adapter_type: shell_script
    allowed_skills: [run_tests, run_linter]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [checks_passed]
    agent_prompt: file://prompts/pr_run_checks.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: check_results
      fixture_app: cookbooks/fixtures/apps/pr_review_app
      compose_file: cookbooks/docker-compose.yml
      commands:
        - name: pr-review-fixture-lint
          command: ruby -c cookbooks/fixtures/apps/pr_review_app/app/controllers/orders_controller.rb
          artifact: lint
        - name: pr-review-fixture-tests
          command: ruby -e 'exit 0'
          artifact: tests
        - name: pr-review-fixture-build
          command: ruby -e 'exit 0'
          artifact: build
  security_scan:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [security_reviewed]
    agent_prompt: file://prompts/pr_security_scan.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: check_results
      output_artifact_kind: security_findings
      spawn_target_queues: [error_handling_audit, development]
  coverage_check:
    adapter_type: shell_script
    allowed_skills: [run_tests, run_coverage]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [coverage_checked]
    agent_prompt: file://prompts/pr_coverage_check.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: check_results
      output_artifact_kind: coverage_report
      fixture_app: cookbooks/fixtures/apps/pr_review_app
      compose_file: cookbooks/docker-compose.yml
      commands:
        - name: pr-review-fixture-coverage
          command: ruby -e 'puts({overall_delta: 0.0, changed_files: [{file: "app/controllers/orders_controller.rb", coverage_pct: 100, uncovered_lines: []}], new_files_without_tests: []}.to_json)'
          artifact: coverage_report
  architectural_review:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [review_verdict]
    agent_prompt: file://prompts/pr_architectural_review.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kinds: [security_findings, coverage_report]
      output_artifact_kind: architecture_review
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Human reviewer sees check_results, security_findings, coverage_report, and architecture_review. Focus on business logic, product fit, and design tradeoffs.
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

- The source spec says blocking check failures should stop immediately. `checks_passed` should fail when any check sub-result is not passed; existing transition behavior will block/escalate according to the stage config.
- The source spec says blocking security findings should escalate immediately and not proceed to architectural review. Implement this by making `security_reviewed` fail when `blocking_count` is positive; it still passes with zero findings or warning/info findings.
- `review_verdict` already handles architecture review verdicts. Do not add a duplicate architecture predicate.
- The shell command strings are safe placeholders for cookbook fixtures. If the shared shell adapter later supports structured command JSON output mapping, keep the stage contract and improve commands under TDD.

---

## Prompt file targets

### `prompts/pr_run_checks.md`

```markdown
# PR Review: Run Checks

You are the mechanical checks stage for the `pr_review` queue.

Inputs:
- Work item `spec_url`, expected to be a pull request URL or a local fixture identifier.
- Work item tags such as `branch`, `base_branch`, `repository`, `pull_request_number`, and `head_sha` when provided by webhook ingestion.
- Adapter command results from lint, test, and build steps.

Rules:
1. Do not edit files.
2. Do not deploy.
3. Treat missing check output as a failure.
4. Produce a `check_results` artifact with this shape:

```json
{
  "lint": { "passed": true, "errors": [] },
  "tests": { "passed": true, "failures": [] },
  "build": { "passed": true, "errors": [] },
  "summary": "lint, tests, and build passed"
}
```

If a check fails, include command name, exit status, stderr/stdout summary, and the smallest actionable failure details. The `checks_passed` predicate blocks downstream AI review when any check is failing.
```

### `prompts/pr_security_scan.md`

```markdown
# PR Review: Security Scan

You are the security review stage for the `pr_review` queue.

Inputs:
- Pull request URL or fixture identifier from `spec_url`.
- Diff content supplied by the runner, fetched from GitHub, or found in the fixture app.
- Prior `check_results` artifact.

Review only the diff and directly related context. Look for:
- SQL injection from string interpolation or unsafe query fragments.
- XSS from unescaped user input in templates or serializers.
- Missing authentication/authorization checks on new endpoints.
- Secrets, tokens, credentials, or private keys committed to code.
- Insecure dependency additions.
- Mass assignment or parameter tampering.
- SSRF, path traversal, command injection, deserialization, unsafe file access.

Produce a `security_findings` artifact:

```json
{
  "findings": [
    {
      "severity": "blocking",
      "category": "sql_injection",
      "file": "app/services/order_search.rb",
      "line": 12,
      "description": "Interpolates params[:q] into SQL",
      "fix_suggestion": "Use bound parameters or Arel"
    }
  ],
  "blocking_count": 1,
  "summary": "1 blocking SQL injection finding"
}
```

Severity must be one of `blocking`, `warning`, or `info`. If blocking findings reveal a broader pattern, include a top-level `spawn_work_items` array targeting `error_handling_audit` or `development` with a short title, `spec_inline`, and tags. Existing transition code handles spawn creation.
```

### `prompts/pr_coverage_check.md`

```markdown
# PR Review: Coverage Check

You are the coverage stage for the `pr_review` queue.

Inputs:
- Pull request diff.
- Prior `check_results` artifact.
- Coverage command output when supplied by the shell adapter.

Determine whether the changed code has meaningful test coverage. Check:
1. Overall coverage delta.
2. Changed file coverage percentage.
3. Uncovered changed lines.
4. New files without matching tests.
5. Low-value tests such as assertions that only prove `true` is true.

Produce a `coverage_report` artifact:

```json
{
  "overall_delta": 0.0,
  "changed_files": [
    {
      "file": "app/controllers/orders_controller.rb",
      "coverage_pct": 92.5,
      "uncovered_lines": [42, 43]
    }
  ],
  "new_files_without_tests": [],
  "meaningful_tests": true,
  "summary": "coverage is acceptable; two uncovered defensive branches"
}
```

Do not fail simply because coverage is imperfect. The predicate only proves a coverage report exists and is structurally useful; human and architecture review can decide whether gaps are acceptable.
```

### `prompts/pr_architectural_review.md`

```markdown
# PR Review: Architectural Review

You are the architecture review stage for the `pr_review` queue.

Inputs:
- Pull request diff.
- `security_findings` artifact.
- `coverage_report` artifact.
- Project conventions such as `CLAUDE.md`, docs, and nearby code patterns when available.

Review for design and maintainability:
- Does the PR follow existing patterns?
- Are names consistent with the codebase?
- Is the abstraction level appropriate?
- Are there performance risks such as N+1 queries, missing indexes, or hot-path expensive work?
- Does it introduce unnecessary coupling?
- Are tests located at the correct layer?

Produce an `architecture_review` artifact/report compatible with the existing `review_verdict` predicate:

```json
{
  "verdict": "approve",
  "comments": [
    {
      "file": "app/controllers/orders_controller.rb",
      "line": 21,
      "severity": "info",
      "comment": "Consider extracting this branch if it grows."
    }
  ],
  "summary": "Follows existing controller/service pattern."
}
```

Use verdict `request_changes` for architectural blockers, `comment` for non-blocking concerns, and `approve` when no human-blocking design concerns remain.
```

---

### Task 1: Add RED specs for the `checks_passed` predicate

**Objective:** Prove `checks_passed` only passes when the latest `check_results` artifact shows lint, tests, and build all passing.

**Files:**
- Create: `spec/services/engine/predicates/checks_passed_spec.rb`
- Later create: `app/services/engine/predicates/checks_passed.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/checks_passed_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ChecksPassed do
  def build_claim
    queue = WorkQueue.create!(
      name: "PR Review #{SecureRandom.hex(4)}",
      slug: "pr-review-#{SecureRandom.hex(4)}",
      stages: %w[run_checks security_scan]
    )
    work_item = WorkItem.create!(title: "Review PR", spec_url: "https://github.example/repo/pull/1", work_queue: queue, stage_name: "run_checks")
    Claim.create!(work_item: work_item, agent_type: "shell_script", status: :active)
  end

  it "passes with evidence when lint, tests, and build all pass" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "check_results",
      data: {
        "lint" => { "passed" => true, "errors" => [] },
        "tests" => { "passed" => true, "failures" => [] },
        "build" => { "passed" => true, "errors" => [] }
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, checks: %w[lint tests build])
  end

  it "fails when check_results is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing check_results artifact")
  end

  it "fails with the failing check name when any check did not pass" do
    claim = build_claim
    Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "check_results",
      data: {
        "lint" => { "passed" => true, "errors" => [] },
        "tests" => { "passed" => false, "failures" => [{ "file" => "spec/models/order_spec.rb", "message" => "expected true" }] },
        "build" => { "passed" => true, "errors" => [] }
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("PR checks failed: tests")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/checks_passed_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::ChecksPassed`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/checks_passed.rb`:

```ruby
module Engine
  module Predicates
    class ChecksPassed
      REQUIRED_CHECKS = %w[lint tests build].freeze

      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "check_results").order(created_at: :desc).first
        return PredicateResult.fail(reason: "missing check_results artifact") unless artifact

        failed = REQUIRED_CHECKS.reject { |name| artifact.data.dig(name, "passed") == true }
        return PredicateResult.fail(reason: "PR checks failed: #{failed.join(", ")}") if failed.any?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, checks: REQUIRED_CHECKS })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/checks_passed_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/checks_passed.rb spec/services/engine/predicates/checks_passed_spec.rb
git commit -m "feat: add PR checks predicate"
```

---

### Task 2: Add RED/GREEN specs for `security_reviewed`

**Objective:** Prove `security_reviewed` passes for a present security report with no blocking findings, fails when missing, and blocks when `blocking_count` is positive.

**Files:**
- Create: `spec/services/engine/predicates/security_reviewed_spec.rb`
- Create: `app/services/engine/predicates/security_reviewed.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/security_reviewed_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::SecurityReviewed do
  def build_claim
    queue = WorkQueue.create!(name: "PR Review #{SecureRandom.hex(4)}", slug: "pr-review-sec-#{SecureRandom.hex(4)}", stages: %w[security_scan coverage_check])
    work_item = WorkItem.create!(title: "Review PR", spec_url: "https://github.example/repo/pull/2", work_queue: queue, stage_name: "security_scan")
    Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
  end

  it "passes when a security_findings artifact exists with no blocking findings" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "security_findings",
      data: { "findings" => [{ "severity" => "warning", "category" => "dependency" }], "blocking_count" => 0 }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, findings_count: 1, blocking_count: 0)
  end

  it "passes when zero findings are present" do
    claim = build_claim
    Artifact.create!(claim: claim, work_item: claim.work_item, kind: "security_findings", data: { "findings" => [], "blocking_count" => 0 })

    expect(described_class.new(claim: claim).call).to be_passed
  end

  it "fails when the security_findings artifact is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing security_findings artifact")
  end

  it "fails when blocking security findings exist" do
    claim = build_claim
    Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "security_findings",
      data: { "findings" => [{ "severity" => "blocking", "category" => "sql_injection" }], "blocking_count" => 1 }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("blocking security findings: 1")
  end
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/security_reviewed_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::SecurityReviewed`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/security_reviewed.rb`:

```ruby
module Engine
  module Predicates
    class SecurityReviewed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "security_findings").order(created_at: :desc).first
        return PredicateResult.fail(reason: "missing security_findings artifact") unless artifact

        findings = Array(artifact.data["findings"])
        blocking_count = artifact.data.fetch("blocking_count", findings.count { |finding| finding["severity"] == "blocking" }).to_i
        return PredicateResult.fail(reason: "blocking security findings: #{blocking_count}") if blocking_count.positive?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, findings_count: findings.count, blocking_count: blocking_count })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/security_reviewed_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/security_reviewed.rb spec/services/engine/predicates/security_reviewed_spec.rb
git commit -m "feat: add PR security predicate"
```

---

### Task 3: Add RED/GREEN specs for `coverage_checked`

**Objective:** Prove `coverage_checked` requires a structurally useful `coverage_report` artifact.

**Files:**
- Create: `spec/services/engine/predicates/coverage_checked_spec.rb`
- Create: `app/services/engine/predicates/coverage_checked.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/coverage_checked_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::CoverageChecked do
  def build_claim
    queue = WorkQueue.create!(name: "PR Review #{SecureRandom.hex(4)}", slug: "pr-review-cov-#{SecureRandom.hex(4)}", stages: %w[coverage_check architectural_review])
    work_item = WorkItem.create!(title: "Review PR", spec_url: "https://github.example/repo/pull/3", work_queue: queue, stage_name: "coverage_check")
    Claim.create!(work_item: work_item, agent_type: "shell_script", status: :active)
  end

  it "passes when coverage_report has changed file coverage data" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "coverage_report",
      data: {
        "overall_delta" => 0.0,
        "changed_files" => [{ "file" => "app/controllers/orders_controller.rb", "coverage_pct" => 92.5, "uncovered_lines" => [42] }],
        "new_files_without_tests" => []
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, changed_files_count: 1, new_files_without_tests_count: 0)
  end

  it "fails when coverage_report is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing coverage_report artifact")
  end

  it "fails when changed_files is not an array" do
    claim = build_claim
    Artifact.create!(claim: claim, work_item: claim.work_item, kind: "coverage_report", data: { "overall_delta" => 0.0, "changed_files" => nil })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("coverage_report changed_files must be an array")
  end
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/coverage_checked_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::CoverageChecked`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/coverage_checked.rb`:

```ruby
module Engine
  module Predicates
    class CoverageChecked
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "coverage_report").order(created_at: :desc).first
        return PredicateResult.fail(reason: "missing coverage_report artifact") unless artifact

        changed_files = artifact.data["changed_files"]
        return PredicateResult.fail(reason: "coverage_report changed_files must be an array") unless changed_files.is_a?(Array)

        PredicateResult.pass(
          evidence: {
            artifact_id: artifact.id,
            changed_files_count: changed_files.count,
            new_files_without_tests_count: Array(artifact.data["new_files_without_tests"]).count
          }
        )
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/coverage_checked_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/coverage_checked.rb spec/services/engine/predicates/coverage_checked_spec.rb
git commit -m "feat: add PR coverage predicate"
```

---

### Task 4: Register PR review predicates

**Objective:** Add `checks_passed`, `security_reviewed`, and `coverage_checked` to the predicate registry.

**Files:**
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing registry expectations**

Append these expectations inside the existing `resolves known predicate names` example in `spec/services/engine/predicate_registry_spec.rb`:

```ruby
expect(described_class.resolve("checks_passed")).to eq(Engine::Predicates::ChecksPassed)
expect(described_class.resolve("security_reviewed")).to eq(Engine::Predicates::SecurityReviewed)
expect(described_class.resolve("coverage_checked")).to eq(Engine::Predicates::CoverageChecked)
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate: checks_passed`.

**Step 3: Register predicates**

Modify `app/services/engine/predicate_registry.rb` and add:

```ruby
"checks_passed" => Predicates::ChecksPassed,
"security_reviewed" => Predicates::SecurityReviewed,
"coverage_checked" => Predicates::CoverageChecked,
```

Place them near existing validation/review predicates or near the other cookbook predicates. Keep names snake_case and matching the queue YAML exactly.

**Step 4: Run test to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register PR review predicates"
```

---

### Task 5: Add RED seed spec for the `pr_review` queue

**Objective:** Prove the new YAML queue is seeded with all stages, resolved prompt files, portable adapter config, and correct completion criteria.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/pr_review.yml`
- Later create: prompt files

**Step 1: Write failing seed spec**

Add this example to `spec/models/work_queue_seed_spec.rb` before the idempotency example:

```ruby
it "seeds the PR review pipeline queue with resolved portable prompts" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "pr_review")
  expect(queue.name).to eq("PR Review Pipeline")
  expect(queue.stages).to eq(%w[run_checks security_scan coverage_check architectural_review human_review done])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_max_retries" => 1,
    "default_timeout_seconds" => 600,
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 0,
    "trigger" => "github_pull_request"
  )

  run_checks = queue.stage_configs.find_by!(stage_name: "run_checks")
  expect(run_checks.adapter_type).to eq("shell_script")
  expect(run_checks.allowed_skills).to eq(%w[run_tests run_linter])
  expect(run_checks.forbidden_skills).to include("edit_files", "deploy")
  expect(run_checks.completion_criteria).to eq(%w[checks_passed])
  expect(run_checks.agent_prompt).to include("# PR Review: Run Checks")
  expect(run_checks.agent_prompt).to include("check_results")
  expect(run_checks.agent_prompt).not_to start_with("file://")
  expect(run_checks.agent_prompt).not_to include(Rails.root.to_s)
  expect(run_checks.adapter_config).to include(
    "output_artifact_kind" => "check_results",
    "fixture_app" => "cookbooks/fixtures/apps/pr_review_app",
    "compose_file" => "cookbooks/docker-compose.yml"
  )
  expect(run_checks.adapter_config.fetch("commands").map { |command| command.fetch("artifact") }).to include("lint", "tests", "build")

  security = queue.stage_configs.find_by!(stage_name: "security_scan")
  expect(security.adapter_type).to eq("inline_claude")
  expect(security.model_override).to eq("claude-sonnet-4-20250514")
  expect(security.completion_criteria).to eq(%w[security_reviewed])
  expect(security.agent_prompt).to include("# PR Review: Security Scan")
  expect(security.agent_prompt).to include("security_findings")
  expect(security.agent_prompt).to include("spawn_work_items")
  expect(security.adapter_config).to include("output_artifact_kind" => "security_findings", "input_artifact_kind" => "check_results")

  coverage = queue.stage_configs.find_by!(stage_name: "coverage_check")
  expect(coverage.adapter_type).to eq("shell_script")
  expect(coverage.allowed_skills).to eq(%w[run_tests run_coverage])
  expect(coverage.completion_criteria).to eq(%w[coverage_checked])
  expect(coverage.agent_prompt).to include("# PR Review: Coverage Check")
  expect(coverage.adapter_config).to include("output_artifact_kind" => "coverage_report")

  architecture = queue.stage_configs.find_by!(stage_name: "architectural_review")
  expect(architecture.adapter_type).to eq("inline_claude")
  expect(architecture.model_override).to eq("claude-sonnet-4-20250514")
  expect(architecture.completion_criteria).to eq(%w[review_verdict])
  expect(architecture.agent_prompt).to include("# PR Review: Architectural Review")
  expect(architecture.adapter_config).to include("output_artifact_kind" => "architecture_review")

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.completion_criteria).to eq(%w[report_present])
  expect(human_review.timeout_seconds).to eq(86_400)

  done = queue.stage_configs.find_by!(stage_name: "done")
  expect(done.adapter_type).to eq("fake")
  expect(done.completion_criteria).to eq(%w[report_present])

  serialized_queue = Rails.root.join("config/queues/pr_review.yml").read
  expect(serialized_queue).not_to include(Rails.root.to_s)
  expect(serialized_queue).not_to include("/Users/")
  expect(serialized_queue).not_to include("working_directory:")
  expect(serialized_queue).to include("file://prompts/pr_run_checks.md")
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL with `Couldn't find WorkQueue` for slug `pr_review` or missing prompt/YAML file.

**Step 3: Commit?**

Do not commit the red seed spec alone. Continue to Tasks 6 and 7, then commit once the queue and prompts make the spec green.

---

### Task 6: Add PR review prompt files

**Objective:** Add the four prompt files used by the PR review queue and ensure they describe artifact shapes, blocking behavior, and cross-queue spawn payloads.

**Files:**
- Create: `prompts/pr_run_checks.md`
- Create: `prompts/pr_security_scan.md`
- Create: `prompts/pr_coverage_check.md`
- Create: `prompts/pr_architectural_review.md`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Create prompt files**

Create the four prompt files from the Prompt File Targets section above. Keep headings exactly:

- `# PR Review: Run Checks`
- `# PR Review: Security Scan`
- `# PR Review: Coverage Check`
- `# PR Review: Architectural Review`

**Step 2: Run seed spec to confirm still RED for queue YAML**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: Still FAIL because `config/queues/pr_review.yml` does not exist yet. If it fails because a prompt contains an absolute path, fix the prompt immediately.

**Step 3: Do not commit yet**

Wait until the YAML is added and the seed spec passes.

---

### Task 7: Add PR review queue YAML

**Objective:** Seed the `pr_review` queue with all stage configs and portable prompt indirection.

**Files:**
- Create: `config/queues/pr_review.yml`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Create queue YAML**

Create `config/queues/pr_review.yml` from the Queue YAML Target section above.

**Step 2: Run seed spec to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS for the new PR review seed example and existing seed examples.

**Step 3: Run a focused portable-path content check**

```bash
ruby -e 'paths = %w[config/queues/pr_review.yml prompts/pr_run_checks.md prompts/pr_security_scan.md prompts/pr_coverage_check.md prompts/pr_architectural_review.md]; bad = paths.select { |p| File.read(p).include?(Dir.pwd) || File.read(p).include?("/Users/") }; abort("absolute paths: #{bad.join(", ")}") unless bad.empty?'
```

Expected: exit 0 with no output.

**Step 4: Commit**

```bash
git add config/queues/pr_review.yml prompts/pr_run_checks.md prompts/pr_security_scan.md prompts/pr_coverage_check.md prompts/pr_architectural_review.md spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed PR review cookbook queue"
```

---

### Task 8: Add docker-friendly fixture app contract

**Objective:** Add a tiny fixture app that exercises the PR-review scenario without depending on GitHub, external services, or local absolute paths.

**Files:**
- Create: `cookbooks/fixtures/apps/pr_review_app/README.md`
- Create: `cookbooks/fixtures/apps/pr_review_app/Gemfile`
- Create: `cookbooks/fixtures/apps/pr_review_app/app/controllers/application_controller.rb`
- Create: `cookbooks/fixtures/apps/pr_review_app/app/controllers/orders_controller.rb`
- Create: `cookbooks/fixtures/apps/pr_review_app/app/models/order.rb`
- Create: `cookbooks/fixtures/apps/pr_review_app/app/models/user.rb`
- Create: `cookbooks/fixtures/apps/pr_review_app/app/services/order_search.rb`
- Create: `cookbooks/fixtures/apps/pr_review_app/config/routes.rb`
- Create: `cookbooks/fixtures/apps/pr_review_app/spec/models/order_spec.rb`
- Create: `cookbooks/fixtures/apps/pr_review_app/spec/requests/orders_spec.rb`
- Create: `spec/cookbooks/pr_review_pipeline_cookbook_spec.rb`

**Step 1: Write failing fixture contract spec**

Create `spec/cookbooks/pr_review_pipeline_cookbook_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "PR review pipeline cookbook fixture" do
  let(:fixture_root) { Rails.root.join("cookbooks/fixtures/apps/pr_review_app") }

  it "provides a docker-friendly fixture app with security, coverage, and architecture examples" do
    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("Gemfile")).to exist
    expect(fixture_root.join("app/controllers/orders_controller.rb")).to exist
    expect(fixture_root.join("app/services/order_search.rb")).to exist
    expect(fixture_root.join("spec/requests/orders_spec.rb")).to exist

    readme = fixture_root.join("README.md").read
    expect(readme).to include("PR Review Pipeline")
    expect(readme).to include("SQL injection fixture")
    expect(readme).to include("missing authorization fixture")

    search_service = fixture_root.join("app/services/order_search.rb").read
    expect(search_service).to include("unsafe_search")
    expect(search_service).to include("safe_search")

    serialized = Dir[fixture_root.join("**", "*")].select { |path| File.file?(path) }.map { |path| File.read(path) }.join("\n")
    expect(serialized).not_to include(Rails.root.to_s)
    expect(serialized).not_to include("/Users/")
  end
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/pr_review_pipeline_cookbook_spec.rb
```

Expected: FAIL because the fixture files are missing.

**Step 3: Create fixture files**

Create `cookbooks/fixtures/apps/pr_review_app/README.md`:

```markdown
# PR Review Pipeline Fixture App

This tiny Rails-style fixture app gives the `pr_review` cookbook deterministic PR-review inputs.

It intentionally contains examples a PR review pipeline should identify:

- SQL injection fixture: `OrderSearch#unsafe_search` interpolates user input.
- Missing authorization fixture: `OrdersController#destroy` lacks an ownership/admin check.
- Coverage fixture: request specs cover index/create but intentionally omit destroy.
- Architecture fixture: controller logic is small enough for deterministic review comments.

The fixture is file-only and docker-friendly. Do not add absolute checkout paths or machine-specific credentials.
```

Create `cookbooks/fixtures/apps/pr_review_app/Gemfile`:

```ruby
source "https://rubygems.org"

gem "rails"
gem "sqlite3"
gem "rspec-rails"
```

Create `cookbooks/fixtures/apps/pr_review_app/app/controllers/application_controller.rb`:

```ruby
class ApplicationController
  def current_user
    @current_user
  end
end
```

Create `cookbooks/fixtures/apps/pr_review_app/app/controllers/orders_controller.rb`:

```ruby
class OrdersController < ApplicationController
  def index
    @orders = OrderSearch.new.safe_search(params[:q])
  end

  def create
    @order = Order.create!(order_params.merge(user: current_user))
  end

  def destroy
    Order.find(params[:id]).destroy!
  end

  private

  def order_params
    params.require(:order).permit(:name, :total_cents)
  end
end
```

Create `cookbooks/fixtures/apps/pr_review_app/app/models/order.rb`:

```ruby
class Order < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :total_cents, numericality: { greater_than_or_equal_to: 0 }
end
```

Create `cookbooks/fixtures/apps/pr_review_app/app/models/user.rb`:

```ruby
class User < ApplicationRecord
  has_many :orders
end
```

Create `cookbooks/fixtures/apps/pr_review_app/app/services/order_search.rb`:

```ruby
class OrderSearch
  def unsafe_search(query)
    Order.where("name LIKE '%#{query}%'")
  end

  def safe_search(query)
    Order.where("name LIKE ?", "%#{query}%")
  end
end
```

Create `cookbooks/fixtures/apps/pr_review_app/config/routes.rb`:

```ruby
Rails.application.routes.draw do
  resources :orders, only: [:index, :create, :destroy]
end
```

Create minimal fixture specs:

```ruby
# cookbooks/fixtures/apps/pr_review_app/spec/models/order_spec.rb
RSpec.describe Order do
  it "requires a name" do
    order = described_class.new(name: nil, total_cents: 100)
    expect(order).not_to be_valid
  end
end
```

```ruby
# cookbooks/fixtures/apps/pr_review_app/spec/requests/orders_spec.rb
RSpec.describe "Orders" do
  it "lists orders" do
    expect(true).to eq(true)
  end

  it "creates an order" do
    expect(true).to eq(true)
  end
end
```

**Step 4: Run fixture contract spec to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/pr_review_pipeline_cookbook_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add cookbooks/fixtures/apps/pr_review_app spec/cookbooks/pr_review_pipeline_cookbook_spec.rb
git commit -m "test: add PR review cookbook fixture"
```

---

### Task 9: Prove blocking security findings can spawn cross-queue work

**Objective:** Add a focused cookbook integration spec that documents how PR security findings use the existing `spawn_work_items` transition behavior.

**Files:**
- Modify: `spec/cookbooks/pr_review_pipeline_cookbook_spec.rb`
- No production changes expected unless the RED spec reveals a gap.

**Step 1: Add failing-or-green integration spec**

Append to `spec/cookbooks/pr_review_pipeline_cookbook_spec.rb`:

```ruby
it "documents security scan spawn payloads for blocking systemic findings" do
  load Rails.root.join("db/seeds.rb")

  pr_queue = WorkQueue.find_by!(slug: "pr_review")
  development = WorkQueue.find_by!(slug: "development")
  item = WorkItem.create!(
    title: "Review PR #42",
    spec_url: "https://github.example/acme/store/pull/42",
    work_queue: pr_queue,
    stage_name: "security_scan",
    tags: { "pull_request_number" => "42", "branch" => "feature/search" }
  )
  claim = Claim.create!(work_item: item, agent_type: "inline_claude", status: "completed", started_at: Time.current)
  Report.create!(
    claim: claim,
    work_item: item,
    stage_name: "security_scan",
    status: "success",
    body: {
      "security_findings" => {
        "findings" => [{ "severity" => "blocking", "category" => "sql_injection", "file" => "app/services/order_search.rb" }],
        "blocking_count" => 1
      },
      "spawn_work_items" => [{
        "queue_slug" => development.slug,
        "title" => "Replace unsafe order search SQL",
        "spec_inline" => "Use bound parameters in OrderSearch and add regression coverage.",
        "tags" => { "domain" => "security", "source" => "pr_review" }
      }]
    }
  )

  stage_config = pr_queue.stage_configs.find_by!(stage_name: "security_scan")
  expect do
    Engine::TransitionManager.new(work_item: item, claim: claim, stage_config: stage_config).call
  end.to change { WorkItem.where(work_queue: development).count }.by(1)

  spawned = WorkItem.where(work_queue: development).order(:created_at).last
  expect(spawned.title).to eq("Replace unsafe order search SQL")
  expect(spawned.parent_id).to eq(item.id)
  expect(spawned.tags).to include("domain" => "security", "source_queue" => "pr_review")
end
```

**Step 2: Run the spec**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/pr_review_pipeline_cookbook_spec.rb
```

Expected: PASS if existing cross-queue spawn behavior handles the payload. If it fails because the queue blocks before spawning when `security_reviewed` fails, split the behavior: keep `security_reviewed` blocking in predicate specs and document spawn payload in prompt/fixtures only, or add a human-approved transition design before changing core transition order.

**Step 3: Commit**

```bash
git add spec/cookbooks/pr_review_pipeline_cookbook_spec.rb
git commit -m "test: document PR security cross-queue spawn"
```

---

### Task 10: Optional webhook trigger endpoint

**Objective:** If the implementation assignment includes webhook ingestion, add a thin GitHub PR webhook endpoint that creates a `pr_review` work item from opened/synchronize/reopened pull request events.

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/api/v1/github_pr_webhooks_controller.rb`
- Create: `spec/requests/api/v1/github_pr_webhooks_spec.rb`

**Step 1: Write failing request spec**

Create `spec/requests/api/v1/github_pr_webhooks_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "GitHub PR webhooks" do
  it "creates a PR review work item for opened pull requests" do
    load Rails.root.join("db/seeds.rb")

    payload = {
      "action" => "opened",
      "repository" => { "full_name" => "acme/store", "html_url" => "https://github.example/acme/store" },
      "pull_request" => {
        "number" => 42,
        "html_url" => "https://github.example/acme/store/pull/42",
        "head" => { "ref" => "feature/search", "sha" => "abc123" },
        "base" => { "ref" => "main" },
        "title" => "Add order search"
      }
    }

    expect do
      post "/api/v1/webhooks/github/pull_request", params: payload, as: :json
    end.to change(WorkItem, :count).by(1)

    expect(response).to have_http_status(:created)
    item = WorkItem.order(:created_at).last
    expect(item.work_queue.slug).to eq("pr_review")
    expect(item.title).to eq("PR #42: Add order search")
    expect(item.spec_url).to eq("https://github.example/acme/store/pull/42")
    expect(item.stage_name).to eq("run_checks")
    expect(item.tags).to include(
      "repository" => "acme/store",
      "pull_request_number" => "42",
      "branch" => "feature/search",
      "base_branch" => "main",
      "head_sha" => "abc123"
    )
  end

  it "ignores unsupported pull request actions" do
    load Rails.root.join("db/seeds.rb")

    expect do
      post "/api/v1/webhooks/github/pull_request", params: { action: "closed", pull_request: { number: 1 } }, as: :json
    end.not_to change(WorkItem, :count)

    expect(response).to have_http_status(:accepted)
  end
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/requests/api/v1/github_pr_webhooks_spec.rb
```

Expected: FAIL with routing error.

**Step 3: Add route**

Modify `config/routes.rb` inside the `api/v1` namespace:

```ruby
post "webhooks/github/pull_request", to: "github_pr_webhooks#create"
```

**Step 4: Add controller**

Create `app/controllers/api/v1/github_pr_webhooks_controller.rb`:

```ruby
module Api
  module V1
    class GithubPrWebhooksController < ApplicationController
      SUPPORTED_ACTIONS = %w[opened reopened synchronize ready_for_review].freeze

      def create
        return render json: { ignored: true, action: params[:action] }, status: :accepted unless SUPPORTED_ACTIONS.include?(params[:action])

        pr = params.require(:pull_request)
        repository = params.require(:repository)
        queue = WorkQueue.find_by!(slug: "pr_review")
        item = WorkItem.create!(
          work_queue: queue,
          title: "PR ##{pr.require(:number)}: #{pr.require(:title)}",
          spec_url: pr.require(:html_url),
          stage_name: queue.stages.first,
          status: :pending,
          tags: {
            repository: repository.require(:full_name),
            pull_request_number: pr.require(:number).to_s,
            branch: pr.require(:head).require(:ref),
            base_branch: pr.require(:base).require(:ref),
            head_sha: pr.require(:head).require(:sha)
          }
        )

        render json: { id: item.id, queue: queue.slug, stage_name: item.stage_name, status: item.status }, status: :created
      end
    end
  end
end
```

**Step 5: Run test to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/requests/api/v1/github_pr_webhooks_spec.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/github_pr_webhooks_controller.rb spec/requests/api/v1/github_pr_webhooks_spec.rb
git commit -m "feat: add PR review webhook trigger"
```

---

### Task 11: Final focused verification

**Objective:** Run the focused PR review suite and a broad enough safety suite before handoff.

**Files:**
- No new files.

**Step 1: Run focused predicate specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/checks_passed_spec.rb \
  spec/services/engine/predicates/security_reviewed_spec.rb \
  spec/services/engine/predicates/coverage_checked_spec.rb
```

Expected: PASS.

**Step 2: Run registry and seed specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 3: Run cookbook fixture/integration specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/pr_review_pipeline_cookbook_spec.rb
```

Expected: PASS.

**Step 4: If webhook endpoint was implemented, run request spec**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/requests/api/v1/github_pr_webhooks_spec.rb
```

Expected: PASS.

**Step 5: Run portable path guard**

```bash
ruby -e 'paths = Dir["config/queues/pr_review.yml", "prompts/pr_*.md", "cookbooks/fixtures/apps/pr_review_app/**/*"].select { |p| File.file?(p) }; bad = paths.select { |p| File.read(p).include?(Dir.pwd) || File.read(p).include?("/Users/") }; abort("absolute paths: #{bad.join(", ")}") unless bad.empty?'
```

Expected: exit 0 with no output.

**Step 6: Run git status and review only intended files**

```bash
git status --short
git diff --stat HEAD
```

Expected: only PR-review files are uncommitted. If unrelated dirty files exist from other workers, do not stage them.

**Step 7: Final commit if needed**

If any PR-review files remain uncommitted after the prior tasks:

```bash
git add config/queues/pr_review.yml prompts/pr_run_checks.md prompts/pr_security_scan.md prompts/pr_coverage_check.md prompts/pr_architectural_review.md \
  app/services/engine/predicates/checks_passed.rb app/services/engine/predicates/security_reviewed.rb app/services/engine/predicates/coverage_checked.rb \
  spec/services/engine/predicates/checks_passed_spec.rb spec/services/engine/predicates/security_reviewed_spec.rb spec/services/engine/predicates/coverage_checked_spec.rb \
  spec/services/engine/predicate_registry_spec.rb spec/models/work_queue_seed_spec.rb spec/cookbooks/pr_review_pipeline_cookbook_spec.rb \
  cookbooks/fixtures/apps/pr_review_app
git commit -m "feat: add PR review cookbook pipeline"
```

Expected: commit succeeds. Do not stage or commit unrelated files.

---

## Acceptance criteria

- `config/queues/pr_review.yml` seeds a `WorkQueue` with stages `run_checks`, `security_scan`, `coverage_check`, `architectural_review`, `human_review`, and `done`.
- Every stage listed in the queue has a persisted `StageConfig`.
- Prompt files are resolved into stage configs; persisted `agent_prompt` values do not start with `file://`.
- Queue YAML and prompts contain no absolute checkout paths and no `working_directory` pointing at a local machine path.
- `checks_passed`, `security_reviewed`, and `coverage_checked` are registered and covered by focused predicate specs.
- `checks_passed` fails if lint, tests, or build are missing/failing.
- `security_reviewed` passes with zero findings, passes with warning/info findings, and fails with blocking findings.
- `coverage_checked` passes only when a structurally valid coverage report exists.
- `architectural_review` reuses the existing `review_verdict` predicate.
- Fixture app files under `cookbooks/fixtures/apps/pr_review_app` are self-contained, docker-friendly, and free of absolute paths.
- Security scan prompt documents `spawn_work_items` for systemic follow-up work targeting `error_handling_audit` or `development`.
- If webhook trigger is implemented, it creates `pr_review` work items for opened/reopened/synchronize/ready_for_review pull request events and ignores closed events.
- All focused PR review specs pass with Greg's rbenv-prefixed RSpec commands.

---

## Implementation handoff notes

- Prefer implementing Tasks 1-4 first because predicate behavior is independent and gives fast feedback.
- Tasks 5-7 should be done as one TDD slice: RED seed spec, prompts/YAML, GREEN seed spec, commit.
- Task 8 keeps fixture files separate from queue/predicate behavior so fixture churn does not obscure seed diffs.
- Task 9 should not change core transition behavior unless the implementation owner explicitly decides that blocking predicates should still allow spawn side effects. Existing `cross_queue_spawn_spec` is the source of truth for spawn mechanics.
- Task 10 is optional because the existing `POST /api/v1/work_items` endpoint can already create `pr_review` items when called by a webhook bridge. Implement a dedicated endpoint only if the product requirement is to receive GitHub payloads directly.
