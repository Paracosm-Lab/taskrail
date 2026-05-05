# Feature Development Cookbook Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Turn the original StupidClaw MVP development queue into a cookbook example that demonstrates intake, decomposition, async Codex build, shell validation, review regression, CLI visibility, and a Docker-friendly fixture feature workflow.

**Architecture:** Keep the existing `development`, `development-codex`, `development-claude`, and `development-shell` queues as the system examples, but promote `development-codex` into the cookbook-backed implementation by moving long prompts into `file://prompts/development_*.md`, adding seed/fixture/docs coverage, and proving the engine loop handles decomposition, async build polling, test validation, review regression, blocking, and CLI submission/status around the development queue. Reuse existing predicates (`report_present`, `branch_created`, `tests_passed`, `lint_clean`, `coverage_not_decreased`, `review_verdict`) and adapters; do not add new model providers or hardcode checkout paths.

**Tech Stack:** Rails 8, ActiveRecord, RSpec, YAML queue seeds, `db/seeds.rb` `file://` prompt resolver, `Engine::Runner`, `Engine::TransitionManager`, `CodexAdapter`, `ShellScriptAdapter`, `InlineClaudeAdapter`, `CheckAsyncClaimsJob`, `bin/stupidclaw`, Docker-friendly cookbook fixture apps.

**Source spec:** `/Users/gregmushen/docs/superpowers/specs/2026-05-04-stupidclaw-design.md`, especially Section 6 “The Engine Loop”, Section 8 “Queue Configuration — MVP Development Queue”, and Section 10 “CLI”.

**Output cookbook docs:** `docs/cookbooks/04-feature-development.md`

**Primary queue slug:** `development-codex`

---

## Current Codebase Facts

- Queue YAML files live in `config/queues/*.yml` and are loaded by `db/seeds.rb`.
- `db/seeds.rb` resolves `agent_prompt: file://prompts/name.md` relative to `Rails.root`; all new prompt paths must be repo-relative.
- `Adapters::ShellScriptAdapter` defaults command execution to `Rails.root.to_s`; do not put `/Users/gregmushen/work/code/stupidclaw` or any other absolute checkout path into queue YAML.
- Existing development queues are `config/queues/development.yml`, `config/queues/development_codex.yml`, `config/queues/development_claude.yml`, and `config/queues/development_shell.yml`.
- Existing development stages are `intake -> decompose -> build -> test -> review -> done`.
- Existing engine support already covers async Codex claims, child work item creation from decomposition reports, review regression back to `build`, waiting parents, CLI submit/status/list/answer/retry/cancel/costs/queues/stages, and dashboard rendering.
- Existing predicates for the MVP development queue are `report_present`, `branch_created`, `tests_passed`, `lint_clean`, `coverage_not_decreased`, and `review_verdict`.
- Shared cookbook infrastructure lives under `cookbooks/`; executable fixture apps for cookbooks should live under `test/fixtures/apps/...` unless the shared cookbook docs say otherwise when implementation starts.
- The repo currently has many unrelated dirty/untracked files from parallel cookbook work. Stage and commit only the files named by each task.

## Test Command Convention

Run focused specs on Greg's Mac with rbenv shims first in PATH:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec SPEC_PATH[:LINE] --format documentation
```

Run the final focused cookbook suite with:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/development_cookbook_workflow_spec.rb \
  spec/services/engine/codex_workflow_integration_spec.rb \
  spec/services/engine/transition_manager_regression_spec.rb \
  spec/cli/stupidclaw_spec.rb \
  spec/cookbooks/feature_development_cookbook_spec.rb
```

## Target Queue Behavior

The cookbook should demonstrate the original Section 8 cost funnel:

```text
intake -> decompose -> build -> test -> review -> done
 cheap      frontier    Codex   shell   frontier  terminal
```

Stage contracts:

- `intake`: inline Claude/cheap model, validates the spec is readable and emits a report with classification tags.
- `decompose`: inline Claude/frontier model, emits `body.children`, and the engine creates child `WorkItem` records at `build`; parent waits until children finish.
- `build`: async Codex adapter, creates a branch artifact with a branch name and implementation report.
- `test`: shell_script adapter, runs tests/lint/coverage, emits `test_results`, `lint`, and `coverage` artifacts; no edits allowed.
- `review`: inline Claude/frontier reviewer, emits `verdict: approved` to advance or `verdict: request_changes` plus feedback to regress to `build`.
- `done`: fake terminal state.

Portable queue requirements:

- `development-codex` keeps slug `development-codex`; do not rename it and break current tests.
- Prompt references must be `file://prompts/development_intake.md`, `file://prompts/development_decompose.md`, `file://prompts/development_build.md`, `file://prompts/development_test.md`, and `file://prompts/development_review.md`.
- Shell commands in `development-codex` must be Docker-friendly placeholders or repo-root commands and must not set `working_directory` to an absolute path.
- Codex adapter config may include `command`, `args`, `poll_command`, and `poll_args`; it must not include a checkout-specific path.
- `config.max_regression_loops` should remain `3` to match Section 6.

---

### Task 1: Add RED seed coverage for cookbook-backed `development-codex` prompts

**Objective:** Prove `development-codex` is a cookbook-quality seeded queue with resolved prompt files, portable adapter config, and the original MVP development stage contract.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later modify: `config/queues/development_codex.yml`
- Later create: `prompts/development_intake.md`
- Later create: `prompts/development_decompose.md`
- Later create: `prompts/development_build.md`
- Later create: `prompts/development_test.md`
- Later create: `prompts/development_review.md`

**Step 1: Write failing test**

Append a new example near the existing `"seeds the codex-backed development queue"` example in `spec/models/work_queue_seed_spec.rb`:

```ruby
  it "seeds the feature development cookbook queue with resolved prompt files and portable adapters" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "development-codex")
    expect(queue.name).to eq("Development Codex")
    expect(queue.stages).to eq(%w[intake decompose build test review done])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
    expect(queue.config).to include(
      "default_max_retries" => 3,
      "default_timeout_seconds" => 600,
      "default_escalation" => "block_and_notify",
      "max_regression_loops" => 3
    )

    intake = queue.stage_configs.find_by!(stage_name: "intake")
    expect(intake.adapter_type).to eq("inline_claude")
    expect(intake.allowed_skills).to eq(%w[read_spec classify tag_work_item])
    expect(intake.completion_criteria).to eq(["report_present"])
    expect(intake.agent_prompt).to include("# Development Intake")
    expect(intake.agent_prompt).to include("classify")
    expect(intake.agent_prompt).not_to start_with("file://")

    decompose = queue.stage_configs.find_by!(stage_name: "decompose")
    expect(decompose.adapter_type).to eq("inline_claude")
    expect(decompose.allowed_skills).to eq(%w[read_spec create_child_items define_acceptance_criteria])
    expect(decompose.agent_prompt).to include("# Development Decompose")
    expect(decompose.agent_prompt).to include("children")
    expect(decompose.agent_prompt).not_to start_with("file://")

    build = queue.stage_configs.find_by!(stage_name: "build")
    expect(build.adapter_type).to eq("codex")
    expect(build.allowed_skills).to eq(%w[clone_repo create_branch edit_files run_tests])
    expect(build.forbidden_skills).to include("deploy", "merge_main", "mutate_database")
    expect(build.completion_criteria).to eq(%w[branch_created report_present])
    expect(build.agent_prompt).to include("# Development Build")
    expect(build.agent_prompt).to include("branch")
    expect(build.adapter_config).to include(
      "command" => "codex",
      "poll_command" => "codex"
    )
    expect(build.adapter_config).not_to have_key("working_directory")

    test_stage = queue.stage_configs.find_by!(stage_name: "test")
    expect(test_stage.adapter_type).to eq("shell_script")
    expect(test_stage.allowed_skills).to eq(%w[run_tests run_linter run_coverage])
    expect(test_stage.forbidden_skills).to include("edit_files")
    expect(test_stage.completion_criteria).to eq(%w[tests_passed lint_clean coverage_not_decreased])
    expect(test_stage.agent_prompt).to include("# Development Test")
    expect(test_stage.agent_prompt).not_to start_with("file://")
    expect(test_stage.adapter_config).not_to have_key("working_directory")
    expect(test_stage.adapter_config.fetch("commands").map { |command| command.fetch("artifact") }).to include("test_results", "lint", "coverage")

    review = queue.stage_configs.find_by!(stage_name: "review")
    expect(review.adapter_type).to eq("inline_claude")
    expect(review.max_retries).to eq(0)
    expect(review.allowed_skills).to eq(%w[read_diff read_spec approve request_changes])
    expect(review.completion_criteria).to eq(["review_verdict"])
    expect(review.agent_prompt).to include("# Development Review")
    expect(review.agent_prompt).to include("request_changes")
    expect(review.agent_prompt).not_to start_with("file://")

    done = queue.stage_configs.find_by!(stage_name: "done")
    expect(done.adapter_type).to eq("fake")
    expect(done.completion_criteria).to eq(["report_present"])
  end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb --format documentation
```

Expected: FAIL because `development-codex` prompts are still inline strings and do not include the required cookbook headings.

**Step 3: Do not commit yet**

Keep this red spec uncommitted until Task 2 turns it green.

---

### Task 2: Move development prompts into repo-relative prompt files

**Objective:** Make the MVP development queue prompts portable, reviewable, and consistent with the other cookbook queues.

**Files:**
- Create: `prompts/development_intake.md`
- Create: `prompts/development_decompose.md`
- Create: `prompts/development_build.md`
- Create: `prompts/development_test.md`
- Create: `prompts/development_review.md`
- Modify: `config/queues/development_codex.yml`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Create `prompts/development_intake.md`**

```markdown
# Development Intake

You are the cheap intake agent for the StupidClaw feature development queue.

Read the work item spec and return a structured report that:

- Confirms the spec is readable.
- Classifies the work as feature, bugfix, refactor, docs, or test-only.
- Tags likely domain, risk, complexity, and expected cost.
- Identifies missing acceptance criteria or blocking ambiguity.

Return `status: success` only when the item is ready for decomposition. If required context is missing, return `status: blocked` and a concise `blocked_question`.
```

**Step 2: Create `prompts/development_decompose.md`**

```markdown
# Development Decompose

You are the decomposition agent for the StupidClaw feature development queue.

Break the accepted spec into small, ordered child work items. Each child must have:

- `title`
- `spec_inline`
- `tags`
- acceptance criteria
- explicit file or subsystem boundaries when known
- a test-first implementation note

Return the children in `body.children` so the engine can create child `WorkItem` records at the `build` stage. Keep slices independently buildable when possible; otherwise order them with clear dependency notes.
```

**Step 3: Create `prompts/development_build.md`**

```markdown
# Development Build

You are the Codex build agent for the StupidClaw feature development queue.

Implement exactly the assigned child slice using TDD:

1. Create a branch named from the work item id/title.
2. Write the failing test first and record the RED command/output.
3. Implement the minimal code needed to pass.
4. Run focused tests, then the relevant slice suite.
5. Commit the slice on the branch.
6. Return a branch artifact: `{ "kind": "branch", "data": { "name": "...", "commit": "..." } }`.

Do not deploy, merge main, mutate production databases, or broaden scope beyond the assigned child item.
```

**Step 4: Create `prompts/development_test.md`**

```markdown
# Development Test

You are the shell validation stage for the StupidClaw feature development queue.

Run tests, lint, and coverage checks without editing files. Produce artifacts with these shapes:

- `test_results`: `{ "passed": true/false, "summary": "...", "failures": [] }`
- `lint`: `{ "clean": true/false, "summary": "..." }`
- `coverage`: `{ "previous": 0.0, "current": 0.0, "decreased": false }`

If validation fails, preserve actionable output so the transition manager can regress the item back to `build` with feedback.
```

**Step 5: Create `prompts/development_review.md`**

```markdown
# Development Review

You are the frontier review agent for the StupidClaw feature development queue.

Review the branch diff against the original spec and child acceptance criteria after automated tests have passed.

Return one of:

- `{ "verdict": "approved", "summary": "..." }`
- `{ "verdict": "request_changes", "feedback": "specific build-stage instructions" }`

Ask for changes only for spec compliance, correctness, security, maintainability, or test quality issues. The engine treats `request_changes` as a regression to `build`, not a review-stage retry.
```

**Step 6: Update `config/queues/development_codex.yml`**

Replace inline `agent_prompt` values with:

```yaml
agent_prompt: file://prompts/development_intake.md
```

for `intake`, and the matching `development_decompose.md`, `development_build.md`, `development_test.md`, and `development_review.md` files for the other non-terminal stages.

For the `build` stage, ensure completion criteria include both branch and report evidence:

```yaml
completion_criteria:
  - branch_created
  - report_present
```

For `done`, keep a simple inline terminal prompt and completion criteria:

```yaml
completion_criteria:
  - report_present
agent_prompt: Terminal state.
```

Do not add `working_directory` under any stage `adapter_config`.

**Step 7: Run test to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb --format documentation
```

Expected: PASS for the new `development-codex` seed example and no regressions in existing queue seed examples.

**Step 8: Commit**

```bash
git add spec/models/work_queue_seed_spec.rb config/queues/development_codex.yml prompts/development_intake.md prompts/development_decompose.md prompts/development_build.md prompts/development_test.md prompts/development_review.md
git commit -m "feat: add feature development cookbook queue prompts"
```

---

### Task 3: Add RED workflow spec for decomposition creating child build items

**Objective:** Prove the development queue demonstrates Section 6 decomposition: a completed `decompose` report with child definitions creates child work items at `build` and leaves the parent waiting.

**Files:**
- Create: `spec/services/engine/development_cookbook_workflow_spec.rb`
- Exercise existing: `app/services/engine/transition_manager.rb`

**Step 1: Write failing spec**

Create `spec/services/engine/development_cookbook_workflow_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "feature development cookbook workflow", type: :model do
  it "creates child build items from a successful decompose report" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "development-codex")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Add calendar export",
      spec_url: "specs/add-calendar-export.md",
      stage_name: "decompose",
      status: :claimed
    )
    stage_config = queue.stage_configs.find_by!(stage_name: "decompose")
    claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :completed)
    Report.create!(
      claim: claim,
      work_item: work_item,
      stage_name: "decompose",
      status: :success,
      body: {
        "summary" => "Split into model and API slices",
        "children" => [
          {
            "title" => "Add calendar export model",
            "spec_inline" => "Create export model and validations using TDD",
            "tags" => { "domain" => "models" }
          },
          {
            "title" => "Add calendar export endpoint",
            "spec_inline" => "Expose export endpoint using TDD",
            "tags" => { "domain" => "api" }
          }
        ]
      }
    )

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload).to be_waiting
    expect(work_item.stage_name).to eq("decompose")
    expect(work_item.children.count).to eq(2)
    expect(work_item.children.pluck(:stage_name)).to eq(%w[build build])
    expect(work_item.children.pluck(:status).uniq).to eq(["pending"])
    expect(work_item.children.first.spec_inline).to include("Create export model")
    expect(work_item.transition_logs.last.trigger).to eq("decompose")
  end
end
```

**Step 2: Run test to verify failure or current pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/development_cookbook_workflow_spec.rb --format documentation
```

Expected: If the current engine already supports this exactly, the spec may pass immediately. That is acceptable for this cookbook characterization task because the behavior already exists; if it fails, continue with Step 3.

**Step 3: Implement minimal fix only if needed**

If the spec fails, update `app/services/engine/transition_manager.rb` so successful decompose reports read `body["children"]`, create child `WorkItem` records with `parent_id`, `work_queue`, `title`, `spec_inline`, `tags`, `stage_name: "build"`, and `status: :pending`, then set the parent status to `waiting`.

Do not change unrelated transition behavior.

**Step 4: Run test to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/development_cookbook_workflow_spec.rb --format documentation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/development_cookbook_workflow_spec.rb app/services/engine/transition_manager.rb
git commit -m "test: cover feature development decomposition workflow"
```

If no production code changed, omit `app/services/engine/transition_manager.rb` from `git add`.

---

### Task 4: Add RED workflow spec for async Codex build and validation handoff

**Objective:** Prove a child item in `build` starts an async Codex claim and advances to `test` only after `CheckAsyncClaimsJob` observes a successful poll with branch evidence.

**Files:**
- Modify: `spec/services/engine/codex_workflow_integration_spec.rb`
- Exercise existing: `app/adapters/adapters/codex_adapter.rb`, `app/jobs/check_async_claims_job.rb`, `app/services/engine/transition_manager.rb`

**Step 1: Add or tighten the failing spec**

The existing `spec/services/engine/codex_workflow_integration_spec.rb` already covers the core shape. Extend it with these assertions after the claim is created:

```ruby
expect(claim.assignment.dig("stage_config", "agent_prompt")).to include("# Development Build")
expect(claim.assignment.dig("stage_config", "completion_criteria")).to include("branch_created", "report_present")
expect(claim.assignment.dig("stage_config", "adapter_config", "command")).to eq("codex")
expect(claim.assignment.dig("stage_config", "adapter_config")).not_to have_key("working_directory")
```

And after polling completes:

```ruby
expect(work_item.reload.stage_name).to eq("test")
expect(work_item.artifacts.find_by!(kind: "branch").data["name"]).to eq("stupidclaw/build-smoke")
expect(work_item.transition_logs.last.trigger).to eq("rule_satisfied")
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/codex_workflow_integration_spec.rb --format documentation
```

Expected: FAIL if the assignment payload does not expose the resolved stage prompt/config or if `build` still lacks the cookbook prompt/criteria from Task 2.

**Step 3: Implement minimal fix only if needed**

If assignment data is incomplete, update `app/services/engine/assignment_builder.rb` to include the resolved `stage_config` fields already required by the adapter: `stage_name`, `adapter_type`, `allowed_skills`, `forbidden_skills`, `completion_criteria`, `agent_prompt`, `timeout_seconds`, and `adapter_config`.

Do not include secrets. Do not include absolute paths.

**Step 4: Run test to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/codex_workflow_integration_spec.rb --format documentation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/codex_workflow_integration_spec.rb app/services/engine/assignment_builder.rb
git commit -m "test: cover feature development codex handoff"
```

If no production code changed, omit `app/services/engine/assignment_builder.rb` from `git add`.

---

### Task 5: Add RED regression coverage for test-stage failure back to build

**Objective:** Prove the feature development cookbook handles Section 6 retry-with-feedback: failed validation at `test` returns the item to `build` with actionable feedback rather than looping in the shell stage.

**Files:**
- Modify: `spec/services/engine/transition_manager_regression_spec.rb`
- Exercise existing or modify: `app/services/engine/transition_manager.rb`

**Step 1: Write failing spec**

Append this example to `spec/services/engine/transition_manager_regression_spec.rb`:

```ruby
  it "moves failed feature validation from test back to build with failure feedback" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "development-codex")
    stage_config = queue.stage_configs.find_by!(stage_name: "test")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Feature validation",
      spec_url: "opaque spec",
      stage_name: "test",
      regression_count: 0,
      status: :claimed
    )
    claim = Claim.create!(work_item: work_item, agent_type: "shell_script", status: :completed)
    Artifact.create!(
      claim: claim,
      work_item: work_item,
      kind: "test_results",
      data: {
        "passed" => false,
        "output" => "expected CalendarExport#to_ics to include DTSTART",
        "failures" => ["CalendarExport#to_ics"]
      }
    )

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload.stage_name).to eq("build")
    expect(work_item).to be_pending
    expect(work_item.retry_count).to eq(0)
    expect(work_item.regression_count).to eq(1)
    expect(work_item.metadata["feedback"]).to include("expected CalendarExport#to_ics")
    expect(work_item.transition_logs.last.trigger).to eq("regression")
  end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/transition_manager_regression_spec.rb --format documentation
```

Expected: FAIL if only review-stage regressions and test-backfill `run_tests -> generate_tests` regressions are supported.

**Step 3: Implement minimal transition rule**

In `app/services/engine/transition_manager.rb`, add the smallest generalized regression mapping needed:

- When the current queue slug is `development-codex` or the current stage is `test` in a queue whose stages include `build` before `test`, and a `test_results` artifact has `passed: false`, regress to `build`.
- Copy useful failure output/failures into `work_item.metadata["feedback"]`.
- Increment `regression_count`.
- Reset `retry_count` to `0`.
- Respect `queue.config["max_regression_loops"]` and block with human escalation when exhausted.

Do not make shell stages edit files.

**Step 4: Run test to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/transition_manager_regression_spec.rb --format documentation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/services/engine/transition_manager_regression_spec.rb app/services/engine/transition_manager.rb
git commit -m "feat: regress failed feature validation to build"
```

---

### Task 6: Add a Docker-friendly fixture feature app

**Objective:** Provide a tiny app/spec fixture that the feature development cookbook can use without external services or machine-specific paths.

**Files:**
- Create: `test/fixtures/apps/feature_development/README.md`
- Create: `test/fixtures/apps/feature_development/Gemfile`
- Create: `test/fixtures/apps/feature_development/lib/calendar_export.rb`
- Create: `test/fixtures/apps/feature_development/spec/calendar_export_spec.rb`
- Create: `spec/cookbooks/feature_development_cookbook_spec.rb`

**Step 1: Write failing fixture contract spec**

Create `spec/cookbooks/feature_development_cookbook_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "feature development cookbook fixture" do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/feature_development") }

  it "ships a self-contained fixture app without absolute paths" do
    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("Gemfile")).to exist
    expect(fixture_root.join("lib/calendar_export.rb")).to exist
    expect(fixture_root.join("spec/calendar_export_spec.rb")).to exist

    files = Dir[fixture_root.join("**/*")].select { |path| File.file?(path) }
    contents = files.map { |path| File.read(path) }.join("\n")
    expect(contents).not_to include("/Users/gregmushen")
    expect(contents).not_to include(Rails.root.to_s)
  end
end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/feature_development_cookbook_spec.rb --format documentation
```

Expected: FAIL because the fixture app does not exist.

**Step 3: Create fixture README**

Create `test/fixtures/apps/feature_development/README.md`:

```markdown
# Feature Development Fixture

Small Ruby fixture app for the StupidClaw feature development cookbook.

The intended feature request is: add iCalendar export support for a calendar event. The initial implementation is intentionally incomplete so a build agent can add behavior test-first.

Run inside this directory:

```bash
bundle exec rspec
```
```

**Step 4: Create fixture Gemfile**

Create `test/fixtures/apps/feature_development/Gemfile`:

```ruby
source "https://rubygems.org"

gem "rspec", "~> 3.13"
```

Do not commit `Gemfile.lock` unless the fixture bundle command creates one and the team wants locked fixture dependencies.

**Step 5: Create initial fixture production code**

Create `test/fixtures/apps/feature_development/lib/calendar_export.rb`:

```ruby
class CalendarExport
  def initialize(title:, starts_at:)
    @title = title
    @starts_at = starts_at
  end

  def to_ics
    "BEGIN:VCALENDAR\nSUMMARY:#{@title}\nEND:VCALENDAR\n"
  end
end
```

**Step 6: Create fixture spec showing desired feature behavior**

Create `test/fixtures/apps/feature_development/spec/calendar_export_spec.rb`:

```ruby
require "time"
require_relative "../lib/calendar_export"

RSpec.describe CalendarExport do
  it "exports a VEVENT with DTSTART and SUMMARY" do
    event = described_class.new(title: "Launch", starts_at: Time.utc(2026, 5, 5, 12, 0, 0))

    output = event.to_ics

    expect(output).to include("BEGIN:VCALENDAR")
    expect(output).to include("BEGIN:VEVENT")
    expect(output).to include("DTSTART:20260505T120000Z")
    expect(output).to include("SUMMARY:Launch")
    expect(output).to include("END:VEVENT")
    expect(output).to include("END:VCALENDAR")
  end
end
```

This spec should fail inside the fixture until a build agent implements the feature; that is the cookbook demonstration.

**Step 7: Run fixture contract spec to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/feature_development_cookbook_spec.rb --format documentation
```

Expected: PASS.

**Step 8: Optionally verify the fixture's intended RED state**

Run:

```bash
cd test/fixtures/apps/feature_development && bundle exec rspec --format documentation
```

Expected: FAIL because `CalendarExport#to_ics` does not yet emit `VEVENT`/`DTSTART`. Do not make this fixture spec pass in this task; the failing fixture is the feature request the cookbook will demonstrate.

**Step 9: Commit**

```bash
git add spec/cookbooks/feature_development_cookbook_spec.rb test/fixtures/apps/feature_development
git commit -m "test: add feature development cookbook fixture"
```

---

### Task 7: Add cookbook documentation and CLI demonstration

**Objective:** Document how to run the feature development cookbook through the CLI and how to inspect the engine-loop behavior.

**Files:**
- Create: `docs/cookbooks/04-feature-development.md`
- Modify: `spec/cookbooks/feature_development_cookbook_spec.rb`
- Exercise existing: `bin/stupidclaw`

**Step 1: Add RED docs contract spec**

Append to `spec/cookbooks/feature_development_cookbook_spec.rb`:

```ruby
  it "documents the feature development cookbook workflow and CLI commands" do
    doc = Rails.root.join("docs/cookbooks/04-feature-development.md")
    expect(doc).to exist

    content = doc.read
    expect(content).to include("# Cookbook 04: Feature Development")
    expect(content).to include("development-codex")
    expect(content).to include("intake -> decompose -> build -> test -> review -> done")
    expect(content).to include("stupidclaw submit --queue development-codex")
    expect(content).to include("stupidclaw status")
    expect(content).to include("stupidclaw answer")
    expect(content).to include("test/fixtures/apps/feature_development")
    expect(content).not_to include("/Users/gregmushen")
  end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/feature_development_cookbook_spec.rb --format documentation
```

Expected: FAIL because the cookbook doc does not exist.

**Step 3: Create `docs/cookbooks/04-feature-development.md`**

Use this structure:

```markdown
# Cookbook 04: Feature Development

## Purpose

Demonstrates the original StupidClaw MVP development queue: cheap intake, frontier decomposition, async Codex implementation, shell validation, frontier review, and terminal completion.

## Queue

`development-codex`

```text
intake -> decompose -> build -> test -> review -> done
```

## Fixture Request

Use `test/fixtures/apps/feature_development` as the sample repository slice. The request is to make `CalendarExport#to_ics` emit a valid `VEVENT` with `DTSTART` and `SUMMARY`.

## Run

```bash
stupidclaw submit --queue development-codex --spec test/fixtures/apps/feature_development/README.md --title "Add iCalendar VEVENT export"
stupidclaw status SC-104 --traces
stupidclaw list --queue development-codex --stage build
stupidclaw answer SC-104 "Use UTC timestamps in basic iCalendar format"
stupidclaw retry SC-104
stupidclaw costs --work-item SC-104
```

## Expected Engine Loop

1. `intake` validates and classifies the request.
2. `decompose` emits child work items with acceptance criteria.
3. Child items start at `build` and Codex runs asynchronously.
4. `CheckAsyncClaimsJob` polls Codex and stores branch artifacts.
5. `test` runs shell validation and emits test/lint/coverage artifacts.
6. Failed validation regresses to `build` with feedback.
7. `review` approves or requests changes.
8. The parent advances after all children are `done`.

## Safety

- No stage may deploy or merge.
- Test stage may not edit files.
- Queue config and prompts are repo-relative.
- Blocking questions are answered through `stupidclaw answer`.
```

**Step 4: Run docs contract spec to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/feature_development_cookbook_spec.rb --format documentation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add docs/cookbooks/04-feature-development.md spec/cookbooks/feature_development_cookbook_spec.rb
git commit -m "docs: add feature development cookbook"
```

---

### Task 8: Add CLI characterization for cookbook queue submission

**Objective:** Prove the existing CLI examples from Section 10 work for the cookbook queue name without changing the API contract.

**Files:**
- Modify: `spec/cli/stupidclaw_spec.rb`
- Exercise existing: `bin/stupidclaw`

**Step 1: Write failing or characterization spec**

Add this example near the existing submit/list command examples in `spec/cli/stupidclaw_spec.rb`:

```ruby
  it "submits a feature development cookbook work item" do
    with_server({ id: "SC-104" }) do |api_url, requests|
      stdout, _stderr, status = run_cli(
        api_url,
        "submit",
        "--queue", "development-codex",
        "--spec", "test/fixtures/apps/feature_development/README.md",
        "--title", "Add iCalendar VEVENT export"
      )

      expect(status).to be_success
      expect(stdout).to include("SC-104")
      request = requests.pop
      expect(request[:method]).to eq("POST")
      expect(request[:path]).to eq("/api/v1/work_items")
      expect(JSON.parse(request[:body])).to include(
        "queue" => "development-codex",
        "spec_url" => "test/fixtures/apps/feature_development/README.md",
        "title" => "Add iCalendar VEVENT export"
      )
    end
  end
```

**Step 2: Run test to verify failure or current pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cli/stupidclaw_spec.rb --format documentation
```

Expected: PASS if CLI submission already prints the returned id and forwards arbitrary queue slugs. If it fails, continue to Step 3.

**Step 3: Implement minimal CLI fix only if needed**

Update `bin/stupidclaw` so `submit` accepts `--queue development-codex`, posts the queue slug unchanged, and prints the returned id. Do not special-case cookbook queues.

**Step 4: Run test to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cli/stupidclaw_spec.rb --format documentation
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/cli/stupidclaw_spec.rb bin/stupidclaw
git commit -m "test: cover feature development cookbook CLI submit"
```

If no production code changed, omit `bin/stupidclaw` from `git add`.

---

### Task 9: Run final focused cookbook verification

**Objective:** Verify the feature development cookbook implementation without requiring the entire dirty parallel workspace to be clean.

**Files:**
- No new files unless a failure requires a focused fix.

**Step 1: Run final focused suite**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/development_cookbook_workflow_spec.rb \
  spec/services/engine/codex_workflow_integration_spec.rb \
  spec/services/engine/transition_manager_regression_spec.rb \
  spec/cli/stupidclaw_spec.rb \
  spec/cookbooks/feature_development_cookbook_spec.rb \
  --format documentation
```

Expected: PASS.

**Step 2: Search for absolute paths in implementation files**

Run:

```bash
grep -R "/Users/gregmushen\|/Users/" \
  config/queues/development_codex.yml \
  prompts/development_intake.md \
  prompts/development_decompose.md \
  prompts/development_build.md \
  prompts/development_test.md \
  prompts/development_review.md \
  docs/cookbooks/04-feature-development.md \
  test/fixtures/apps/feature_development \
  spec/cookbooks/feature_development_cookbook_spec.rb
```

Expected: no matches. If grep exits `1` because there were no matches, that is success.

**Step 3: Confirm only intended files are staged**

Run:

```bash
git status --short
git diff --cached --name-only
```

Expected: staged files belong only to this cookbook task. Do not stage unrelated dirty files from other parallel cookbook work.

**Step 4: Commit any final fixes**

If Task 9 required final fixes, commit only those files:

```bash
git add <focused files>
git commit -m "test: verify feature development cookbook"
```

If Task 9 passes without changes, do not create an empty commit.

---

## Implementation Notes and Pitfalls

- Treat existing development queue files as shared product examples, not disposable cookbook scaffolding. Keep slugs stable.
- Do not add a separate `feature_development` queue unless the product owner explicitly wants a duplicate. The cookbook should demonstrate the original `development-codex` workflow.
- Keep `development.yml` fake-backed so existing base-seed tests keep showing the fake MVP baseline; promote cookbook prompt/docs behavior through `development_codex.yml`.
- Avoid adding hardcoded `working_directory` to shell commands. If a command must run from a fixture app, use a repo-relative shell command such as `cd test/fixtures/apps/feature_development && bundle exec rspec`.
- Do not make the fixture feature spec green in the fixture task. The fixture intentionally gives the build agent a failing feature request to implement.
- If the shared workspace remains dirty from other agents, use `git commit --only <paths>` or stage only the files named in the current task. Never commit unrelated staged files.
- Follow strict TDD for every production behavior change: write the spec, watch it fail for the expected reason, implement the minimal fix, rerun focused spec, then commit.

## Acceptance Criteria

- `docs/cookbooks/04-feature-development.md` exists and explains the development-codex cookbook workflow and CLI commands.
- `config/queues/development_codex.yml` uses repo-relative prompt files for all non-terminal stages.
- Development cookbook prompt files exist under `prompts/` and are resolved by `db/seeds.rb`.
- Seed specs prove the cookbook queue has the expected stage order, stage configs, completion criteria, allowed/forbidden skills, resolved prompts, and no absolute `working_directory`.
- Workflow specs prove decomposition, async Codex build handoff, failed test regression to build, and review regression behavior.
- CLI specs prove cookbook queue submission uses the existing API contract.
- Fixture specs prove the cookbook fixture app is self-contained and path-portable.
- Final focused RSpec command passes with Greg's rbenv PATH prefix.
- Each implementation slice is committed separately with only intended files staged.
