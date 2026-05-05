# Dead Code Removal Cookbook Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Implement the `dead_code_removal` cookbook queue from `docs/specs/cookbook-05-dead-code-removal.md`, including portable queue config, prompt files, artifact predicates, fixture app coverage, and documentation.

**Architecture:** Add a seeded Rails `WorkQueue` for dead-code removal whose AI stages emit typed artifacts and whose shell stage validates proposed deletions. Keep all repository paths portable by relying on the existing `Rails.root`-relative `file://prompts/...` resolver and shell commands that run from the app root. Add small predicate classes that inspect `Artifact` records, then register and cover them with focused RSpec examples.

**Tech Stack:** Rails, ActiveRecord, RSpec, YAML queue seeds, inline Claude adapter, shell_script adapter, existing fake adapters for review/done stages.

---

## Source Inputs

- Source spec: `docs/specs/cookbook-05-dead-code-removal.md`
- Output queue YAML: `config/queues/dead_code_removal.yml`
- Prompt files:
  - `prompts/deadcode_scan_references.md`
  - `prompts/deadcode_verify_unused.md`
  - `prompts/deadcode_draft_removals.md`
- New predicates:
  - `app/services/engine/predicates/candidates_identified.rb`
  - `app/services/engine/predicates/removals_verified.rb`
  - `app/services/engine/predicates/removals_drafted.rb`
- Predicate registry: `app/services/engine/predicate_registry.rb`
- Specs:
  - `spec/services/engine/predicates/candidates_identified_spec.rb`
  - `spec/services/engine/predicates/removals_verified_spec.rb`
  - `spec/services/engine/predicates/removals_drafted_spec.rb`
  - `spec/services/engine/predicate_registry_spec.rb`
  - `spec/models/work_queue_seed_spec.rb`
  - `spec/services/engine/dead_code_removal_workflow_integration_spec.rb`
- Fixture app root: `test/fixtures/apps/dead_code_app/`
- Docs: `README.md` or a cookbook index if one exists when implementation starts.

## Infrastructure and Safety Notes

- Do not add new Docker Compose services for this cookbook. Use the shared cookbook/docker infrastructure from the shared infrastructure plan if present.
- Make the fixture app docker-friendly by keeping it self-contained, file-backed, and free of absolute paths or machine-specific dependencies.
- The `run_tests` stage may use fake/safe commands during cookbook seeding, but it must be shaped so later workers can swap in the shared Docker runner without changing the queue contract.
- Queue YAML must not contain `/Users/...`, the repository checkout path, or any other absolute path.
- Prompt indirection must be `file://prompts/...`, which the existing seed resolver resolves relative to `Rails.root`.
- The verification stage must err toward `needs_investigation` for dynamic Ruby references such as `send`, `public_send`, `const_get`, string interpolation, and `eval`.

## Test Command Prefix

Run focused specs on Greg's Mac with rbenv shims first in PATH:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec <spec path or example>
```

Run the final focused cookbook suite with:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/candidates_identified_spec.rb \
  spec/services/engine/predicates/removals_verified_spec.rb \
  spec/services/engine/predicates/removals_drafted_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/dead_code_removal_workflow_integration_spec.rb
```

---

### Task 1: Add RED specs for the removal candidate predicate

**Objective:** Prove `candidates_identified` passes only when the claim has a `removal_candidates` artifact.

**Files:**
- Create: `spec/services/engine/predicates/candidates_identified_spec.rb`
- Later create: `app/services/engine/predicates/candidates_identified.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/candidates_identified_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::CandidatesIdentified do
  def build_claim
    queue = WorkQueue.create!(
      name: "Dead Code #{SecureRandom.hex(4)}",
      slug: "dead-code-#{SecureRandom.hex(4)}",
      stages: %w[scan_references verify_unused]
    )
    work_item = WorkItem.create!(title: "Remove dead code", spec_url: "opaque spec", work_queue: queue, stage_name: "scan_references")
    Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
  end

  it "passes when a removal_candidates artifact exists for the claim" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "removal_candidates",
      data: {
        "dependencies" => ["unused_gem"],
        "files" => [],
        "methods" => [],
        "routes" => [],
        "other" => []
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when no removal_candidates artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing removal_candidates artifact")
  end
end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/candidates_identified_spec.rb
```

Expected: FAIL with an uninitialized constant for `Engine::Predicates::CandidatesIdentified`.

**Step 3: Commit?**

Do not commit red tests alone unless the team explicitly asks. Continue to Task 2 and commit after green.

---

### Task 2: Implement the `candidates_identified` predicate

**Objective:** Add the minimal predicate implementation for `removal_candidates` artifacts.

**Files:**
- Create: `app/services/engine/predicates/candidates_identified.rb`
- Test: `spec/services/engine/predicates/candidates_identified_spec.rb`

**Step 1: Write minimal implementation**

Create `app/services/engine/predicates/candidates_identified.rb`:

```ruby
module Engine
  module Predicates
    class CandidatesIdentified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "removal_candidates").first
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing removal_candidates artifact")
      end
    end
  end
end
```

**Step 2: Run test to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/candidates_identified_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/candidates_identified.rb spec/services/engine/predicates/candidates_identified_spec.rb
git commit -m "feat: add dead code candidate predicate"
```

---

### Task 3: Add RED specs for verified removals

**Objective:** Prove `removals_verified` requires at least one `safe_to_remove` item in a `verified_removals` artifact.

**Files:**
- Create: `spec/services/engine/predicates/removals_verified_spec.rb`
- Later create: `app/services/engine/predicates/removals_verified.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/removals_verified_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::RemovalsVerified do
  def build_claim
    queue = WorkQueue.create!(
      name: "Dead Code #{SecureRandom.hex(4)}",
      slug: "dead-code-#{SecureRandom.hex(4)}",
      stages: %w[verify_unused draft_removals]
    )
    work_item = WorkItem.create!(title: "Verify removals", spec_url: "opaque spec", work_queue: queue, stage_name: "verify_unused")
    Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
  end

  it "passes when verified_removals contains a safe_to_remove item" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "verified_removals",
      data: {
        "removals" => [
          {
            "type" => "method",
            "name" => "LegacyHelper#unused_method",
            "path" => "app/helpers/legacy_helper.rb",
            "classification" => "safe_to_remove",
            "reasoning" => "No inbound references after dynamic checks."
          }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, safe_to_remove_count: 1)
  end

  it "fails when verified_removals is absent" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing verified_removals artifact with safe_to_remove removals")
  end

  it "fails when all verified removals need investigation" do
    claim = build_claim
    Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "verified_removals",
      data: {
        "removals" => [
          { "type" => "method", "name" => "dynamic_method", "classification" => "needs_investigation" }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing verified_removals artifact with safe_to_remove removals")
  end
end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/removals_verified_spec.rb
```

Expected: FAIL with an uninitialized constant for `Engine::Predicates::RemovalsVerified`.

---

### Task 4: Implement the `removals_verified` predicate

**Objective:** Add predicate logic that counts safe removals and rejects empty or investigation-only artifacts.

**Files:**
- Create: `app/services/engine/predicates/removals_verified.rb`
- Test: `spec/services/engine/predicates/removals_verified_spec.rb`

**Step 1: Write minimal implementation**

Create `app/services/engine/predicates/removals_verified.rb`:

```ruby
module Engine
  module Predicates
    class RemovalsVerified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "verified_removals").detect do |item|
          safe_to_remove_count(item).positive?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id, safe_to_remove_count: safe_to_remove_count(artifact) }) if artifact

        PredicateResult.fail(reason: "missing verified_removals artifact with safe_to_remove removals")
      end

      private

      def safe_to_remove_count(artifact)
        Array(artifact.data["removals"]).count { |removal| removal["classification"] == "safe_to_remove" }
      end
    end
  end
end
```

**Step 2: Run test to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/removals_verified_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/removals_verified.rb spec/services/engine/predicates/removals_verified_spec.rb
git commit -m "feat: add verified removals predicate"
```

---

### Task 5: Add RED specs for drafted removal patches

**Objective:** Prove `removals_drafted` requires at least one patch in a `removal_patches` artifact.

**Files:**
- Create: `spec/services/engine/predicates/removals_drafted_spec.rb`
- Later create: `app/services/engine/predicates/removals_drafted.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/removals_drafted_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::RemovalsDrafted do
  def build_claim
    queue = WorkQueue.create!(
      name: "Dead Code #{SecureRandom.hex(4)}",
      slug: "dead-code-#{SecureRandom.hex(4)}",
      stages: %w[draft_removals run_tests]
    )
    work_item = WorkItem.create!(title: "Draft removals", spec_url: "opaque spec", work_queue: queue, stage_name: "draft_removals")
    Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
  end

  it "passes when removal_patches contains at least one patch" do
    claim = build_claim
    artifact = Artifact.create!(
      claim: claim,
      work_item: claim.work_item,
      kind: "removal_patches",
      data: {
        "patches" => [
          { "action" => "delete", "path" => "app/helpers/unused_helper.rb", "description" => "Remove unused helper" }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id, patch_count: 1)
  end

  it "fails when no removal_patches artifact exists" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing removal_patches artifact with patches")
  end

  it "fails when removal_patches has an empty patch list" do
    claim = build_claim
    Artifact.create!(claim: claim, work_item: claim.work_item, kind: "removal_patches", data: { "patches" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing removal_patches artifact with patches")
  end
end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/removals_drafted_spec.rb
```

Expected: FAIL with an uninitialized constant for `Engine::Predicates::RemovalsDrafted`.

---

### Task 6: Implement the `removals_drafted` predicate

**Objective:** Add predicate logic that accepts a non-empty patch list.

**Files:**
- Create: `app/services/engine/predicates/removals_drafted.rb`
- Test: `spec/services/engine/predicates/removals_drafted_spec.rb`

**Step 1: Write minimal implementation**

Create `app/services/engine/predicates/removals_drafted.rb`:

```ruby
module Engine
  module Predicates
    class RemovalsDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "removal_patches").detect do |item|
          patch_count(item).positive?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id, patch_count: patch_count(artifact) }) if artifact

        PredicateResult.fail(reason: "missing removal_patches artifact with patches")
      end

      private

      def patch_count(artifact)
        Array(artifact.data["patches"]).count
      end
    end
  end
end
```

**Step 2: Run test to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/removals_drafted_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/removals_drafted.rb spec/services/engine/predicates/removals_drafted_spec.rb
git commit -m "feat: add drafted removals predicate"
```

---

### Task 7: Register the three new predicates

**Objective:** Make the transition engine able to resolve the cookbook predicates by name.

**Files:**
- Modify: `app/services/engine/predicate_registry.rb`
- Modify: `spec/services/engine/predicate_registry_spec.rb`

**Step 1: Write failing test**

Append these expectations to the existing registry spec:

```ruby
it "resolves dead code removal cookbook predicates" do
  expect(described_class.resolve("candidates_identified")).to eq(Engine::Predicates::CandidatesIdentified)
  expect(described_class.resolve("removals_verified")).to eq(Engine::Predicates::RemovalsVerified)
  expect(described_class.resolve("removals_drafted")).to eq(Engine::Predicates::RemovalsDrafted)
end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate: candidates_identified`.

**Step 3: Write minimal implementation**

Modify `app/services/engine/predicate_registry.rb` so `PREDICATES` includes:

```ruby
"candidates_identified" => Predicates::CandidatesIdentified,
"removals_verified" => Predicates::RemovalsVerified,
"removals_drafted" => Predicates::RemovalsDrafted,
```

Keep the existing predicates unchanged.

**Step 4: Run test to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register dead code predicates"
```

---

### Task 8: Add prompt files for the AI stages

**Objective:** Provide self-contained stage prompts that define inputs, safety checks, output artifact shape, and conservative classification behavior.

**Files:**
- Create: `prompts/deadcode_scan_references.md`
- Create: `prompts/deadcode_verify_unused.md`
- Create: `prompts/deadcode_draft_removals.md`

**Step 1: Write prompt file for scan_references**

Create `prompts/deadcode_scan_references.md`:

```markdown
# Dead Code Scan References

You are the scan_references agent for the dead_code_removal queue.

Goal: identify candidates for safe deletion, not apply changes.

Inputs:
- Work item spec_url or repository context
- Current repository files

Scan for:
- unused dependencies in Gemfile, Gemfile.lock, package.json, package-lock.json, yarn.lock, pnpm-lock.yaml
- Ruby, JavaScript, TypeScript, and CSS files with no inbound references
- public Ruby methods with no callers outside their own file
- routes mapped to missing controller actions
- empty or no-op migrations that may be squash candidates
- abandoned feature flags that appear fully rolled out or removed from the flag source

Output one artifact of kind `removal_candidates` with this JSON shape:

```json
{
  "dependencies": [],
  "files": [],
  "methods": [],
  "routes": [],
  "other": []
}
```

For each item include `name`, `path` when known, `evidence`, and `risk_notes`.
Do not edit files. Do not mark anything safe; this stage only identifies candidates.
```

**Step 2: Write prompt file for verify_unused**

Create `prompts/deadcode_verify_unused.md`:

```markdown
# Dead Code Verify Unused

You are the verify_unused agent for the dead_code_removal queue.

Goal: verify each candidate from the `removal_candidates` artifact and classify it conservatively.

For each candidate check:
- direct source references
- tests, fixtures, factories, and support files
- config files, rake tasks, scripts, binstubs, docs, and comments
- Ruby dynamic references: `send`, `public_send`, `method`, `const_get`, `constantize`, string interpolation, `eval`, and framework callbacks
- Rails autoloading, routes, helpers, concerns, jobs, mailers, and initializers

Classifications:
- `safe_to_remove`: no references found, including dynamic-reference checks
- `probably_safe`: no direct references, but weak/dynamic evidence remains
- `needs_investigation`: any dynamic reference, ambiguous ownership, or production-risk uncertainty

When in doubt use `needs_investigation`.

Output one artifact of kind `verified_removals` with this JSON shape:

```json
{
  "removals": [
    {
      "type": "file|method|dependency|route|migration|feature_flag|other",
      "name": "string",
      "path": "string or null",
      "classification": "safe_to_remove|probably_safe|needs_investigation",
      "reasoning": "string"
    }
  ]
}
```

Do not edit files.
```

**Step 3: Write prompt file for draft_removals**

Create `prompts/deadcode_draft_removals.md`:

```markdown
# Dead Code Draft Removals

You are the draft_removals agent for the dead_code_removal queue.

Goal: draft a minimal, reviewable set of removal patches for only `safe_to_remove` entries from the `verified_removals` artifact.

Rules:
- Use only removals classified as `safe_to_remove`.
- Group related removals, such as one unused dependency and files that exist only for it.
- Do not include `probably_safe` or `needs_investigation` items in patches.
- Prefer small patches that are easy to review.
- Describe test impact and expected validation command.

Output one artifact of kind `removal_patches` with this JSON shape:

```json
{
  "patches": [
    {
      "action": "delete|modify",
      "path": "string",
      "description": "string"
    }
  ]
}
```

Do not deploy. Do not touch production data.
```

**Step 4: Verify prompt files exist**

Run:

```bash
ruby -e 'abort "missing" unless %w[prompts/deadcode_scan_references.md prompts/deadcode_verify_unused.md prompts/deadcode_draft_removals.md].all? { |p| File.exist?(p) }'
```

Expected: exit 0.

**Step 5: Commit**

```bash
git add prompts/deadcode_scan_references.md prompts/deadcode_verify_unused.md prompts/deadcode_draft_removals.md
git commit -m "feat: add dead code cookbook prompts"
```

---

### Task 9: Add RED seed spec for the dead_code_removal queue

**Objective:** Prove seeds create a portable dead-code-removal queue with all stages, stage configs, prompt file resolution, and no absolute repository paths.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/dead_code_removal.yml`

**Step 1: Write failing test**

Add this example before the idempotence example in `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the dead code removal cookbook queue with resolved prompt files" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "dead_code_removal")
  expect(queue.name).to eq("Dead Code Removal")
  expect(queue.stages).to eq(%w[scan_references verify_unused draft_removals run_tests human_review done])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 2
  )

  scan = queue.stage_configs.find_by!(stage_name: "scan_references")
  expect(scan.adapter_type).to eq("inline_claude")
  expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
  expect(scan.allowed_skills).to eq(["read_repo"])
  expect(scan.forbidden_skills).to include("edit_files", "deploy")
  expect(scan.completion_criteria).to eq(["candidates_identified"])
  expect(scan.agent_prompt).to include("# Dead Code Scan References")
  expect(scan.agent_prompt).not_to start_with("file://")
  expect(scan.adapter_config).to eq("output_artifact_kind" => "removal_candidates")

  verify = queue.stage_configs.find_by!(stage_name: "verify_unused")
  expect(verify.model_override).to eq("claude-sonnet-4-20250514")
  expect(verify.completion_criteria).to eq(["removals_verified"])
  expect(verify.agent_prompt).to include("needs_investigation")
  expect(verify.adapter_config).to eq("output_artifact_kind" => "verified_removals")

  draft = queue.stage_configs.find_by!(stage_name: "draft_removals")
  expect(draft.completion_criteria).to eq(["removals_drafted"])
  expect(draft.agent_prompt).to include("safe_to_remove")
  expect(draft.adapter_config).to eq("output_artifact_kind" => "removal_patches")

  run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
  expect(run_tests.adapter_type).to eq("shell_script")
  expect(run_tests.allowed_skills).to include("run_tests")
  expect(run_tests.forbidden_skills).to include("edit_files", "deploy")
  expect(run_tests.completion_criteria).to eq(["tests_passed"])

  serialized_queue = Rails.root.join("config/queues/dead_code_removal.yml").read
  expect(serialized_queue).not_to include(Rails.root.to_s)
  expect(serialized_queue).not_to include("/Users/")
  expect(serialized_queue).to include("file://prompts/deadcode_scan_references.md")
end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL because `dead_code_removal` queue does not exist yet.

---

### Task 10: Add the portable dead_code_removal queue YAML

**Objective:** Seed the queue exactly as the cookbook spec requires, using portable prompt paths and no absolute working directory.

**Files:**
- Create: `config/queues/dead_code_removal.yml`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Write queue YAML**

Create `config/queues/dead_code_removal.yml`:

```yaml
name: Dead Code Removal
slug: dead_code_removal
stages:
  - scan_references
  - verify_unused
  - draft_removals
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2
stage_configs:
  scan_references:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [candidates_identified]
    agent_prompt: file://prompts/deadcode_scan_references.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: removal_candidates
  verify_unused:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [removals_verified]
    agent_prompt: file://prompts/deadcode_verify_unused.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: verified_removals
  draft_removals:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [removals_drafted]
    agent_prompt: file://prompts/deadcode_draft_removals.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: removal_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [tests_passed]
    agent_prompt: Apply removal patches from the removal_patches artifact, run the full test suite and linter from the repository root, and report pass/fail as a test_results artifact.
    timeout_seconds: 600
    adapter_config:
      commands:
        - name: dead-code-removal-fixture-tests
          command: ruby -e 'exit 0'
          artifact: test_results
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review dead code removals before merge.
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

Important: keep `command: ruby -e 'exit 0'` as a fake docker-friendly placeholder unless the shared cookbook infrastructure plan has already defined a canonical Docker command. Do not duplicate shared compose/service setup in this cookbook.

**Step 2: Run seed spec to verify pass**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add config/queues/dead_code_removal.yml spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed dead code removal queue"
```

---

### Task 11: Add fixture app files for dead-code scenarios

**Objective:** Create a small fixture application tree with every dead-code case named in the source spec.

**Files:**
- Create directory: `test/fixtures/apps/dead_code_app/`
- Create: `test/fixtures/apps/dead_code_app/Gemfile`
- Create: `test/fixtures/apps/dead_code_app/Gemfile.lock`
- Create: `test/fixtures/apps/dead_code_app/config/routes.rb`
- Create: `test/fixtures/apps/dead_code_app/app/controllers/reports_controller.rb`
- Create: `test/fixtures/apps/dead_code_app/app/helpers/unused_helper.rb`
- Create: `test/fixtures/apps/dead_code_app/app/models/customer.rb`
- Create: `test/fixtures/apps/dead_code_app/app/models/unused_legacy_model.rb`
- Create: `test/fixtures/apps/dead_code_app/db/migrate/20240101000000_noop_migration.rb`
- Create: `test/fixtures/apps/dead_code_app/config/feature_flags.yml`
- Create: `test/fixtures/apps/dead_code_app/README.md`

**Step 1: Add fixture Gemfile with unused dependency**

Create `test/fixtures/apps/dead_code_app/Gemfile`:

```ruby
source "https://rubygems.org"

gem "rails"
gem "unused_charting_gem"
```

Create `test/fixtures/apps/dead_code_app/Gemfile.lock` with minimal fixture content:

```text
GEM
  remote: https://rubygems.org/
  specs:
    rails (7.2.0)
    unused_charting_gem (1.0.0)

PLATFORMS
  ruby

DEPENDENCIES
  rails
  unused_charting_gem
```

**Step 2: Add orphan route**

Create `test/fixtures/apps/dead_code_app/config/routes.rb`:

```ruby
Rails.application.routes.draw do
  get "/reports", to: "reports#index"
  get "/reports/export", to: "reports#export"
end
```

Create `test/fixtures/apps/dead_code_app/app/controllers/reports_controller.rb`:

```ruby
class ReportsController < ApplicationController
  def index
    render plain: "ok"
  end
end
```

`reports#export` is intentionally missing.

**Step 3: Add unused helper and unused file**

Create `test/fixtures/apps/dead_code_app/app/helpers/unused_helper.rb`:

```ruby
module UnusedHelper
  def unused_format(value)
    "unused: #{value}"
  end
end
```

Create `test/fixtures/apps/dead_code_app/app/models/unused_legacy_model.rb`:

```ruby
class UnusedLegacyModel
  def self.call
    :unused
  end
end
```

**Step 4: Add model with dead method and dynamic-reference safety example**

Create `test/fixtures/apps/dead_code_app/app/models/customer.rb`:

```ruby
class Customer
  def active?
    true
  end

  def stale_score
    0
  end

  def dynamic_billing_status
    public_send(:active?)
  end
end
```

`stale_score` is intentionally dead. `active?` is dynamically referenced and must not be marked `safe_to_remove` by verification prompts.

**Step 5: Add no-op migration and abandoned flag**

Create `test/fixtures/apps/dead_code_app/db/migrate/20240101000000_noop_migration.rb`:

```ruby
class NoopMigration < ActiveRecord::Migration[7.2]
  def change
  end
end
```

Create `test/fixtures/apps/dead_code_app/config/feature_flags.yml`:

```yaml
new_reports_ui:
  status: removed
  rollout: 100
```

**Step 6: Add fixture README**

Create `test/fixtures/apps/dead_code_app/README.md`:

```markdown
# Dead Code Fixture App

Fixture for the dead_code_removal cookbook.

Intentional candidates:
- `unused_charting_gem` dependency is never required.
- `UnusedHelper` is never included.
- `/reports/export` routes to a missing controller action.
- `Customer#stale_score` is never called.
- `UnusedLegacyModel` is never referenced.
- `NoopMigration` has an empty change method.
- `new_reports_ui` is marked removed and fully rolled out.

Safety case:
- `Customer#active?` is dynamically referenced via `public_send(:active?)` and should be classified as `needs_investigation` if considered.
```

**Step 7: Verify fixture files exist**

Run:

```bash
ruby -e 'required = %w[Gemfile Gemfile.lock config/routes.rb app/controllers/reports_controller.rb app/helpers/unused_helper.rb app/models/customer.rb app/models/unused_legacy_model.rb db/migrate/20240101000000_noop_migration.rb config/feature_flags.yml README.md].map { |p| File.join("test/fixtures/apps/dead_code_app", p) }; missing = required.reject { |p| File.exist?(p) }; abort("missing #{missing.join(", ")}") unless missing.empty?'
```

Expected: exit 0.

**Step 8: Commit**

```bash
git add test/fixtures/apps/dead_code_app
git commit -m "test: add dead code fixture app"
```

---

### Task 12: Add RED integration spec for the dead-code workflow contract

**Objective:** Prove the queue stages advance through the artifact predicates and that unsafe verified items do not satisfy the verification predicate.

**Files:**
- Create: `spec/services/engine/dead_code_removal_workflow_integration_spec.rb`

**Step 1: Write failing integration spec**

Create `spec/services/engine/dead_code_removal_workflow_integration_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "dead code removal workflow integration" do
  it "advances through artifact-backed cookbook stages" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "dead_code_removal")
    work_item = WorkItem.create!(
      title: "Remove fixture dead code",
      spec_url: "./test/fixtures/apps/dead_code_app/README.md",
      work_queue: queue,
      stage_name: "scan_references"
    )

    scan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: scan_claim,
      work_item: work_item,
      kind: "removal_candidates",
      data: {
        "dependencies" => [{ "name" => "unused_charting_gem", "path" => "Gemfile" }],
        "files" => [{ "path" => "app/models/unused_legacy_model.rb" }],
        "methods" => [{ "name" => "Customer#stale_score", "path" => "app/models/customer.rb" }],
        "routes" => [{ "name" => "reports#export", "path" => "config/routes.rb" }],
        "other" => []
      }
    )

    expect(Engine::Predicates::CandidatesIdentified.new(claim: scan_claim).call).to be_passed

    verify_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: verify_claim,
      work_item: work_item,
      kind: "verified_removals",
      data: {
        "removals" => [
          { "type" => "method", "name" => "Customer#stale_score", "path" => "app/models/customer.rb", "classification" => "safe_to_remove", "reasoning" => "No inbound or dynamic references." },
          { "type" => "method", "name" => "Customer#active?", "path" => "app/models/customer.rb", "classification" => "needs_investigation", "reasoning" => "Referenced through public_send." }
        ]
      }
    )

    verify_result = Engine::Predicates::RemovalsVerified.new(claim: verify_claim).call
    expect(verify_result).to be_passed
    expect(verify_result.evidence[:safe_to_remove_count]).to eq(1)

    draft_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :active)
    Artifact.create!(
      claim: draft_claim,
      work_item: work_item,
      kind: "removal_patches",
      data: {
        "patches" => [
          { "action" => "modify", "path" => "app/models/customer.rb", "description" => "Remove Customer#stale_score only." }
        ]
      }
    )

    expect(Engine::Predicates::RemovalsDrafted.new(claim: draft_claim).call).to be_passed
  end
end
```

**Step 2: Run test to verify expected state**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/dead_code_removal_workflow_integration_spec.rb
```

Expected before prior tasks: FAIL due to missing predicates/queue. Expected after prior tasks: PASS. If it passes immediately because all production behavior already exists, keep it as regression coverage and note that RED was satisfied by earlier tasks.

**Step 3: Commit**

```bash
git add spec/services/engine/dead_code_removal_workflow_integration_spec.rb
git commit -m "test: cover dead code workflow contract"
```

---

### Task 13: Document the new cookbook queue

**Objective:** Make the queue discoverable and document safety expectations for users.

**Files:**
- Modify: `README.md` or the project cookbook index if one exists at implementation time.

**Step 1: Write failing doc check if a doc convention exists**

If existing docs have an RSpec/docs check, add a focused example before editing docs. If no docs spec exists, this is a documentation-only change and may proceed without a new production test.

**Step 2: Update documentation**

Add a concise section:

```markdown
### Dead Code Removal Cookbook

The `dead_code_removal` queue scans for unused dependencies, unreferenced files, dead methods, orphan routes, no-op migrations, and abandoned feature flags.

Pipeline:

`scan_references -> verify_unused -> draft_removals -> run_tests -> human_review -> done`

Safety:
- `verify_unused` is intentionally conservative.
- Dynamic Ruby references such as `send`, `public_send`, `const_get`, `constantize`, and `eval` should force `needs_investigation` unless the agent can prove the candidate is safe.
- Only `safe_to_remove` items may become removal patches.
- Human review remains mandatory before done.
```

**Step 3: Verify docs mention queue slug**

Run:

```bash
ruby -e 'text = File.read("README.md"); abort "missing slug" unless text.include?("dead_code_removal")'
```

Expected: exit 0.

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document dead code removal cookbook"
```

---

### Task 14: Run the focused cookbook verification suite

**Objective:** Verify all new production behavior and seed behavior work together.

**Files:**
- No file changes expected.

**Step 1: Run focused specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/candidates_identified_spec.rb \
  spec/services/engine/predicates/removals_verified_spec.rb \
  spec/services/engine/predicates/removals_drafted_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/dead_code_removal_workflow_integration_spec.rb
```

Expected: PASS.

**Step 2: Verify queue YAML portability**

Run:

```bash
ruby -e 'text = File.read("config/queues/dead_code_removal.yml"); abort "absolute path found" if text.include?(Dir.pwd) || text.include?("/Users/"); abort "missing prompt indirection" unless text.include?("file://prompts/deadcode_scan_references.md")'
```

Expected: exit 0.

**Step 3: Verify prompt files resolve through seeds**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rails runner 'load Rails.root.join("db/seeds.rb"); q = WorkQueue.find_by!(slug: "dead_code_removal"); abort "unresolved prompt" if q.stage_configs.where("agent_prompt LIKE ?", "file://%").exists?; puts q.stage_configs.pluck(:stage_name).join(",")'
```

Expected output includes:

```text
scan_references,verify_unused,draft_removals,run_tests,human_review,done
```

**Step 4: Commit only if verification caused intentional file changes**

No commit should be needed in this task. If seed execution changes generated files unexpectedly, inspect and revert them unless they are intentionally part of the cookbook implementation.

---

### Task 15: Final implementation review and cleanup

**Objective:** Ensure the cookbook is complete, committed in small slices, and ready for reviewer handoff.

**Files:**
- No new files expected.

**Step 1: Inspect git status**

Run:

```bash
git status --short
```

Expected: clean except for unrelated pre-existing files. If unrelated pre-existing files are present, do not stage them.

**Step 2: Inspect relevant commit log**

Run:

```bash
git log --oneline -n 8
```

Expected: includes the cookbook commits from Tasks 2, 4, 6, 7, 8, 10, 11, 12, and 13.

**Step 3: Optional final smoke test**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb spec/services/engine/dead_code_removal_workflow_integration_spec.rb
```

Expected: PASS.

**Step 4: Handoff summary for Kanban completion**

Include:
- queue YAML path
- prompt paths
- predicate paths
- fixture app path
- docs path
- exact focused test command and pass/fail result
- final commit hashes
- implementation dependency: shared cookbook/docker infrastructure if the real `run_tests` command will be swapped from the fake placeholder to Docker validation

---

## Implementation Task Checklist

- [ ] Add RED/GREEN specs and implementation for `candidates_identified`.
- [ ] Add RED/GREEN specs and implementation for `removals_verified`.
- [ ] Add RED/GREEN specs and implementation for `removals_drafted`.
- [ ] Register predicates in `Engine::PredicateRegistry` with a failing registry spec first.
- [ ] Add three prompt files under `prompts/`.
- [ ] Add RED/GREEN seed coverage for `config/queues/dead_code_removal.yml`.
- [ ] Ensure queue YAML uses `file://prompts/...` and contains no absolute paths.
- [ ] Add the `test/fixtures/apps/dead_code_app/` fixture tree.
- [ ] Add workflow integration coverage for artifact-backed stage progression.
- [ ] Document the `dead_code_removal` cookbook and conservative dynamic-reference safety rule.
- [ ] Run focused RSpec suite with rbenv PATH prefix.
- [ ] Verify queue YAML portability and prompt resolution.
- [ ] Commit each slice separately.

## Expected Final Commit Message

Use this for the final cookbook implementation commit if the work is squashed into one commit:

```bash
git commit -m "feat: add dead code removal cookbook"
```

If keeping the task-level commit sequence, the final documentation commit should be:

```bash
git commit -m "docs: document dead code removal cookbook"
```

## Implementation Dependencies

- Existing `db/seeds.rb` `file://` prompt resolver must remain Rails.root-relative.
- Existing `shell_script` adapter and `tests_passed` predicate are reused.
- Shared cookbook/docker infrastructure may later replace the fake `ruby -e 'exit 0'` placeholder in `run_tests.adapter_config.commands`; do not duplicate that infrastructure in this cookbook.
- The implementation assumes Rails autoloading loads new predicate files under `app/services/engine/predicates/` consistently with existing predicates.
