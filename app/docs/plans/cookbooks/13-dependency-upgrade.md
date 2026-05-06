# Dependency Upgrade Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `dependency_upgrade` cookbook queue so TaskRail can audit outdated dependencies, prioritize safe upgrade groups, draft one upgrade at a time, run tests, and route a clean human review for each dependency PR.

**Architecture:** This cookbook follows the existing seeded queue pattern: portable YAML in `config/queues/`, long prompts loaded through `file://prompts/...` by `db/seeds.rb`, artifact predicates registered through `Engine::PredicateRegistry`, and a small Docker-friendly fixture app under `cookbooks/fixtures/apps/dependency_upgrade/`. Shell stages should use repo-relative fixture paths and command strings only; do not add hardcoded checkout paths or a second shared Compose stack.

**Tech Stack:** Rails, RSpec, YAML queue seeds, `Engine::PredicateRegistry`, `Artifact` JSON data, shell_script and inline_claude adapters, fake human-review stages, shared cookbook fixture infrastructure, Greg's rbenv Ruby environment.

**Source Spec:** `docs/specs/cookbook-13-dependency-upgrade.md`

---

## Current codebase context

Relevant existing files inspected before writing this plan:

- `db/seeds.rb` loads every `config/queues/*.yml`, resolves `agent_prompt: file://...` relative to `Rails.root`, and persists `StageConfig#adapter_config` as-is.
- `config/queues/job_observability.yml`, `config/queues/query_health.yml`, and `config/queues/dead_code_removal.yml` are the closest cookbook queue examples.
- `prompts/jobs_scan_classes.md`, `prompts/query_collect.md`, and related files show the current root-level prompt convention used by newer cookbook queues.
- `app/services/engine/predicate_registry.rb` maps completion criteria names to predicate classes and currently has many cookbook predicates in a single hash.
- `app/services/engine/predicates/query_inventory_produced.rb` is the simplest artifact-presence predicate shape.
- `spec/services/engine/predicates/query_inventory_produced_spec.rb` demonstrates compact predicate specs using real `WorkQueue`, `WorkItem`, `Claim`, and `Artifact` records.
- `spec/models/work_queue_seed_spec.rb` already verifies seeded cookbook queues, resolved prompt bodies, stage config details, and portability guardrails.
- `cookbooks/README.md` defines shared cookbook infrastructure and portability rules: use Rails-root-relative fixture and prompt paths, and prefer adapter defaults over explicit `working_directory`.

Implementation rules for every task:

- Follow strict TDD: write the failing spec first, run it and confirm the expected failure, implement the smallest production/config change, rerun the focused spec, then run the relevant broader spec.
- Use this RSpec command shape on Greg's Mac:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Commit after each completed implementation task unless the Kanban assignment requests a final/squashed commit; if so, squash before completion.
- Do not hardcode `/Users/gregmushen/work/code/taskrail`, `/Users/`, or any absolute checkout path in queue YAML, prompts, specs, fixture files, or implementation code.
- Use root-level prompt files matching the source spec: `file://prompts/deps_audit.md`, `file://prompts/deps_prioritize.md`, and `file://prompts/deps_upgrade_one.md`.
- Use a fixture app path of `cookbooks/fixtures/apps/dependency_upgrade` in adapter configs. Do not create a second Docker Compose file; reuse `cookbooks/docker-compose.yml` only if a stage truly needs shared fake services.

---

## Files to create or modify

Create:

- `config/queues/dependency_upgrade.yml`
- `prompts/deps_audit.md`
- `prompts/deps_prioritize.md`
- `prompts/deps_upgrade_one.md`
- `app/services/engine/predicates/audit_produced.rb`
- `app/services/engine/predicates/upgrade_plan_produced.rb`
- `app/services/engine/predicates/upgrade_drafted.rb`
- `spec/services/engine/predicates/audit_produced_spec.rb`
- `spec/services/engine/predicates/upgrade_plan_produced_spec.rb`
- `spec/services/engine/predicates/upgrade_drafted_spec.rb`
- `cookbooks/fixtures/apps/dependency_upgrade/README.md`
- `cookbooks/fixtures/apps/dependency_upgrade/Gemfile`
- `cookbooks/fixtures/apps/dependency_upgrade/Gemfile.lock`
- `cookbooks/fixtures/apps/dependency_upgrade/package.json`
- `cookbooks/fixtures/apps/dependency_upgrade/app/models/order.rb`
- `cookbooks/fixtures/apps/dependency_upgrade/app/services/payment_gateway.rb`
- `cookbooks/fixtures/apps/dependency_upgrade/spec/models/order_spec.rb`
- `cookbooks/fixtures/apps/dependency_upgrade/bin/dependency-audit`
- `docs/cookbooks/dependency-upgrade.md`
- `spec/e2e/dependency_upgrade_cookbook_spec.rb`

Modify:

- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Do not modify unless a failing spec proves it is necessary:

- `db/seeds.rb` because it already resolves prompt `file://` paths with `Rails.root.join(...)`.
- Shared adapter implementations such as shell, inline Claude, Docker Compose, or transition managers.
- `cookbooks/docker-compose.yml`; this slice only needs static fixture files plus deterministic shell command targets.

---

## Queue YAML target

Create `config/queues/dependency_upgrade.yml` with this shape. Keep every path repo-relative and omit `working_directory` so adapter defaults can use `Rails.root`.

```yaml
name: Dependency Upgrade
slug: dependency_upgrade
stages:
  - audit_dependencies
  - prioritize_upgrades
  - upgrade_one
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 3
stage_configs:
  audit_dependencies:
    adapter_type: shell_script
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo, run_audit]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [audit_produced]
    agent_prompt: file://prompts/deps_audit.md
    timeout_seconds: 300
    adapter_config:
      output_artifact_kind: dependency_audit
      fixture_app: cookbooks/fixtures/apps/dependency_upgrade
      commands:
        - name: dependency audit fixture
          command: ruby cookbooks/fixtures/apps/dependency_upgrade/bin/dependency-audit
          artifact: dependency_audit
  prioritize_upgrades:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [upgrade_plan_produced]
    agent_prompt: file://prompts/deps_prioritize.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: dependency_audit
      output_artifact_kind: upgrade_plan
      spawn_target_queue: development
  upgrade_one:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo, edit_files]
    forbidden_skills: [deploy]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [upgrade_drafted]
    agent_prompt: file://prompts/deps_upgrade_one.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: upgrade_plan
      output_artifact_kind: upgrade_patches
      fixture_app: cookbooks/fixtures/apps/dependency_upgrade
      branch_prefix: dependency-upgrade
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [tests_passed]
    agent_prompt: Apply dependency upgrade patches, install dependencies, run the focused fixture specs, then run the relevant application test suite. Report pass/fail with command output.
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: upgrade_patches
      output_artifact_kind: test_results
      fixture_app: cookbooks/fixtures/apps/dependency_upgrade
      commands:
        - name: dependency upgrade fixture specs
          command: PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/dependency_upgrade_cookbook_spec.rb
          artifact: test_results
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review the dependency upgrade PR draft, including version delta, CVE/changelog context, test results, branch name, and any migration notes before merge.
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

- The `ruby cookbooks/fixtures/apps/dependency_upgrade/bin/dependency-audit` command is deterministic and Docker-friendly: it reads static fixture manifests and prints one JSON object. It must not run real `bundle outdated`, `npm audit`, or network calls in specs.
- The prompt files can tell real operators to run `bundle outdated`, `bundler-audit`, `npm outdated`, and `npm audit`; fixture specs should exercise only the deterministic local script.
- `spawn_target_queue: development` documents where large migrations should be spawned. The existing engine handles generic cross-queue spawning from report payloads; this cookbook only needs prompt instructions unless a failing integration spec proves more wiring is required.

---

## Prompt file targets

### `prompts/deps_audit.md`

```markdown
# Dependency Upgrade Audit

You are the audit stage for the `dependency_upgrade` queue.

Inputs:
- Repository root from the runner working directory; never assume an absolute path.
- Optional fixture app from adapter config: `cookbooks/fixtures/apps/dependency_upgrade`.
- Ruby and Node manifests when present: `Gemfile`, `Gemfile.lock`, `package.json`, lockfiles, and audit reports.

Collect a dependency audit:

1. For Ruby projects, run safe local checks such as `bundle outdated --parseable` and `bundler-audit check --format json` when available.
2. For Node projects, run safe local checks such as `npm outdated --json` and `npm audit --json` when available.
3. Do not install new global tools or make network calls unless the runner explicitly permits it.
4. For each outdated dependency, record current version, latest version, dependency ecosystem, semantic upgrade type (`major`, `minor`, or `patch`), CVEs, changelog URL when discoverable, and notes about unavailable data.
5. Preserve enough source evidence for downstream review: manifest file, lockfile, and audit command output summary.

Return exactly one `dependency_audit` artifact as JSON:

```json
{
  "dependencies": [
    {
      "name": "rails",
      "ecosystem": "rubygems",
      "current": "7.1.3",
      "latest": "8.0.1",
      "type": "major",
      "cves": [],
      "changelog_url": "https://github.com/rails/rails/releases",
      "manifest": "Gemfile"
    }
  ],
  "total_outdated": 1,
  "cve_count": 0,
  "audit_commands": ["bundle outdated --parseable"],
  "notes": []
}
```
```

### `prompts/deps_prioritize.md`

```markdown
# Dependency Upgrade Prioritize

You are the prioritization stage for the `dependency_upgrade` queue.

Inputs:
- Latest `dependency_audit` artifact.
- Repository source and manifests from the runner working directory.

Rank upgrade groups by urgency and risk:

1. CVE fixes are highest priority.
2. Major version bumps with deprecation or support deadlines come next.
3. Minor versions that unblock requested features come next.
4. Patch versions are low risk and may be grouped when safe.
5. Group related dependencies that must move together, such as `rails`, `railties`, `activerecord`, and `actionpack`.
6. Scan the repository for APIs called out by changelogs or known breaking changes.
7. If a major version bump requires feature-sized migration work, include a `spawn_work_items` entry targeting the `development` queue instead of forcing the entire migration through `upgrade_one`.

Return exactly one `upgrade_plan` artifact as JSON:

```json
{
  "upgrades": [
    {
      "deps": ["rack"],
      "priority": 1,
      "risk": "medium",
      "reason": "CVE fix available",
      "notes": "Review middleware API changes",
      "changelog_urls": ["https://github.com/rack/rack/releases"]
    }
  ],
  "spawn_work_items": [
    {
      "target_queue": "development",
      "title": "Plan Rails 8 migration",
      "reason": "Major version upgrade requires application migration"
    }
  ]
}
```
```

### `prompts/deps_upgrade_one.md`

```markdown
# Dependency Upgrade One

You are the upgrade drafting stage for the `dependency_upgrade` queue.

Inputs:
- Latest `upgrade_plan` artifact.
- Repository manifests and source files.
- Optional fixture app from adapter config: `cookbooks/fixtures/apps/dependency_upgrade`.

Draft exactly one upgrade from the highest-priority pending group:

1. Choose the first upgrade group that is safe to draft in this queue.
2. Identify exact manifest and lockfile changes (`Gemfile`, `Gemfile.lock`, `package.json`, lockfiles).
3. Read changelog notes and scan repository code for affected APIs.
4. Draft minimal patches for version changes and required code migration.
5. Choose a branch name using the adapter `branch_prefix`, for example `dependency-upgrade/rack-3-0-9`.
6. Do not apply changes directly unless the runner explicitly requests mutation; return patch data for review and the run_tests stage.

Return exactly one `upgrade_patches` artifact as JSON:

```json
{
  "dep_name": "rack",
  "from_version": "2.2.8",
  "to_version": "3.0.9",
  "branch_name": "dependency-upgrade/rack-3-0-9",
  "changelog_url": "https://github.com/rack/rack/releases/tag/v3.0.9",
  "patches": [
    {
      "file": "Gemfile",
      "original": "gem \"rack\", \"~> 2.2.8\"",
      "replacement": "gem \"rack\", \"~> 3.0.9\""
    }
  ],
  "test_commands": [
    "PATH=\"$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH\" bundle exec rspec"
  ],
  "notes": ["No application API migration required"]
}
```
```

---

### Task 1: Add RED specs for `audit_produced`

**Objective:** Prove the `audit_produced` predicate only passes when the claim has a non-empty `dependency_audit` artifact and the summary counts match the dependency list.

**Files:**
- Create: `spec/services/engine/predicates/audit_produced_spec.rb`
- Later create: `app/services/engine/predicates/audit_produced.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/audit_produced_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::AuditProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Dependency Upgrade #{SecureRandom.hex(4)}",
      slug: "dependency-upgrade-#{SecureRandom.hex(4)}",
      stages: ["audit_dependencies", "done"]
    )
    queue.stage_configs.create!(stage_name: "audit_dependencies", adapter_type: "fake")
    item = WorkItem.create!(title: "Upgrade dependencies", spec_url: "local", work_queue: queue, stage_name: "audit_dependencies")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when dependency_audit lists outdated dependencies" do
    claim = build_claim(artifacts: [{
      kind: "dependency_audit",
      data: {
        "dependencies" => [
          { "name" => "rack", "current" => "2.2.8", "latest" => "3.0.9", "type" => "major", "cves" => ["CVE-2024-1234"], "changelog_url" => "https://example.test/rack" },
          { "name" => "puma", "current" => "6.4.0", "latest" => "6.4.2", "type" => "patch", "cves" => [], "changelog_url" => "https://example.test/puma" }
        ],
        "total_outdated" => 2,
        "cve_count" => 1
      }
    }])
    artifact = claim.artifacts.find_by!(kind: "dependency_audit")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, dependencies_count: 2, cve_count: 1 })
  end

  it "fails when the dependency_audit artifact is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no dependency_audit artifact found")
  end

  it "fails when dependency_audit has no dependencies" do
    claim = build_claim(artifacts: [{ kind: "dependency_audit", data: { "dependencies" => [], "total_outdated" => 0, "cve_count" => 0 } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("dependency_audit artifact has no outdated dependencies")
  end

  it "fails when total_outdated does not match the dependency list" do
    claim = build_claim(artifacts: [{
      kind: "dependency_audit",
      data: { "dependencies" => [{ "name" => "rack" }], "total_outdated" => 2, "cve_count" => 0 }
    }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("dependency_audit total_outdated does not match dependencies")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/audit_produced_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::AuditProduced`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/audit_produced.rb`:

```ruby
module Engine
  module Predicates
    class AuditProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "dependency_audit").first
        return PredicateResult.fail(reason: "no dependency_audit artifact found") unless artifact

        dependencies = Array(artifact.data["dependencies"])
        return PredicateResult.fail(reason: "dependency_audit artifact has no outdated dependencies") if dependencies.empty?

        total_outdated = artifact.data["total_outdated"]
        if total_outdated && total_outdated != dependencies.count
          return PredicateResult.fail(reason: "dependency_audit total_outdated does not match dependencies")
        end

        cve_count = artifact.data.fetch("cve_count", dependencies.sum { |dependency| Array(dependency["cves"]).count })
        PredicateResult.pass(evidence: { artifact_id: artifact.id, dependencies_count: dependencies.count, cve_count: cve_count })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/audit_produced_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/audit_produced.rb spec/services/engine/predicates/audit_produced_spec.rb
git commit -m "feat: add dependency audit predicate"
```

---

### Task 2: Add RED specs for `upgrade_plan_produced`

**Objective:** Prove the `upgrade_plan_produced` predicate validates a prioritized `upgrade_plan` artifact with at least one upgrade group.

**Files:**
- Create: `spec/services/engine/predicates/upgrade_plan_produced_spec.rb`
- Later create: `app/services/engine/predicates/upgrade_plan_produced.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/upgrade_plan_produced_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::UpgradePlanProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Dependency Upgrade #{SecureRandom.hex(4)}",
      slug: "dependency-upgrade-plan-#{SecureRandom.hex(4)}",
      stages: ["prioritize_upgrades", "done"]
    )
    queue.stage_configs.create!(stage_name: "prioritize_upgrades", adapter_type: "fake")
    item = WorkItem.create!(title: "Prioritize upgrades", spec_url: "local", work_queue: queue, stage_name: "prioritize_upgrades")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when upgrade_plan has prioritized upgrades" do
    claim = build_claim(artifacts: [{
      kind: "upgrade_plan",
      data: {
        "upgrades" => [
          { "deps" => ["rack"], "priority" => 1, "risk" => "medium", "notes" => "CVE fix" },
          { "deps" => ["puma"], "priority" => 2, "risk" => "low", "notes" => "patch" }
        ]
      }
    }])
    artifact = claim.artifacts.find_by!(kind: "upgrade_plan")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, upgrade_count: 2, highest_priority: 1 })
  end

  it "fails when the upgrade_plan artifact is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no upgrade_plan artifact found")
  end

  it "fails when upgrade_plan has no upgrades" do
    claim = build_claim(artifacts: [{ kind: "upgrade_plan", data: { "upgrades" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("upgrade_plan artifact has no upgrades")
  end

  it "fails when an upgrade has no dependency names" do
    claim = build_claim(artifacts: [{ kind: "upgrade_plan", data: { "upgrades" => [{ "deps" => [], "priority" => 1, "risk" => "low" }] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("upgrade_plan upgrade is missing deps")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/upgrade_plan_produced_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::UpgradePlanProduced`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/upgrade_plan_produced.rb`:

```ruby
module Engine
  module Predicates
    class UpgradePlanProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "upgrade_plan").first
        return PredicateResult.fail(reason: "no upgrade_plan artifact found") unless artifact

        upgrades = Array(artifact.data["upgrades"])
        return PredicateResult.fail(reason: "upgrade_plan artifact has no upgrades") if upgrades.empty?

        return PredicateResult.fail(reason: "upgrade_plan upgrade is missing deps") if upgrades.any? { |upgrade| Array(upgrade["deps"]).empty? }

        priorities = upgrades.filter_map { |upgrade| upgrade["priority"] }
        PredicateResult.pass(evidence: { artifact_id: artifact.id, upgrade_count: upgrades.count, highest_priority: priorities.min })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/upgrade_plan_produced_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/upgrade_plan_produced.rb spec/services/engine/predicates/upgrade_plan_produced_spec.rb
git commit -m "feat: add upgrade plan predicate"
```

---

### Task 3: Add RED specs for `upgrade_drafted`

**Objective:** Prove the `upgrade_drafted` predicate validates an `upgrade_patches` artifact with a dependency name, version delta, branch name, and at least one patch.

**Files:**
- Create: `spec/services/engine/predicates/upgrade_drafted_spec.rb`
- Later create: `app/services/engine/predicates/upgrade_drafted.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/upgrade_drafted_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::UpgradeDrafted do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Dependency Upgrade #{SecureRandom.hex(4)}",
      slug: "dependency-upgrade-draft-#{SecureRandom.hex(4)}",
      stages: ["upgrade_one", "done"]
    )
    queue.stage_configs.create!(stage_name: "upgrade_one", adapter_type: "fake")
    item = WorkItem.create!(title: "Draft upgrade", spec_url: "local", work_queue: queue, stage_name: "upgrade_one")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when upgrade_patches has a version change and patches" do
    claim = build_claim(artifacts: [{
      kind: "upgrade_patches",
      data: {
        "dep_name" => "rack",
        "from_version" => "2.2.8",
        "to_version" => "3.0.9",
        "branch_name" => "dependency-upgrade/rack-3-0-9",
        "patches" => [
          { "file" => "Gemfile", "original" => "gem \"rack\", \"~> 2.2.8\"", "replacement" => "gem \"rack\", \"~> 3.0.9\"" }
        ]
      }
    }])
    artifact = claim.artifacts.find_by!(kind: "upgrade_patches")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, dep_name: "rack", patch_count: 1 })
  end

  it "fails when the upgrade_patches artifact is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no upgrade_patches artifact found")
  end

  it "fails when the dependency name is missing" do
    claim = build_claim(artifacts: [{ kind: "upgrade_patches", data: { "from_version" => "2.2.8", "to_version" => "3.0.9", "branch_name" => "dependency-upgrade/rack", "patches" => [{ "file" => "Gemfile" }] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("upgrade_patches artifact is missing dep_name")
  end

  it "fails when the version did not change" do
    claim = build_claim(artifacts: [{ kind: "upgrade_patches", data: { "dep_name" => "rack", "from_version" => "2.2.8", "to_version" => "2.2.8", "branch_name" => "dependency-upgrade/rack", "patches" => [{ "file" => "Gemfile" }] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("upgrade_patches artifact has no version change")
  end

  it "fails when no patches are included" do
    claim = build_claim(artifacts: [{ kind: "upgrade_patches", data: { "dep_name" => "rack", "from_version" => "2.2.8", "to_version" => "3.0.9", "branch_name" => "dependency-upgrade/rack", "patches" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("upgrade_patches artifact has no patches")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/upgrade_drafted_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::UpgradeDrafted`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/upgrade_drafted.rb`:

```ruby
module Engine
  module Predicates
    class UpgradeDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "upgrade_patches").first
        return PredicateResult.fail(reason: "no upgrade_patches artifact found") unless artifact

        dep_name = artifact.data["dep_name"].to_s
        return PredicateResult.fail(reason: "upgrade_patches artifact is missing dep_name") if dep_name.empty?

        from_version = artifact.data["from_version"].to_s
        to_version = artifact.data["to_version"].to_s
        return PredicateResult.fail(reason: "upgrade_patches artifact has no version change") if from_version.empty? || to_version.empty? || from_version == to_version

        patches = Array(artifact.data["patches"])
        return PredicateResult.fail(reason: "upgrade_patches artifact has no patches") if patches.empty?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, dep_name: dep_name, patch_count: patches.count })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/upgrade_drafted_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/upgrade_drafted.rb spec/services/engine/predicates/upgrade_drafted_spec.rb
git commit -m "feat: add dependency upgrade draft predicate"
```

---

### Task 4: Register dependency upgrade predicates

**Objective:** Make the new completion criteria resolvable by `Engine::PredicateRegistry`.

**Files:**
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing test**

Add these expectations inside `spec/services/engine/predicate_registry_spec.rb`'s `"resolves known predicate names"` example:

```ruby
expect(described_class.resolve("audit_produced")).to eq(Engine::Predicates::AuditProduced)
expect(described_class.resolve("upgrade_plan_produced")).to eq(Engine::Predicates::UpgradePlanProduced)
expect(described_class.resolve("upgrade_drafted")).to eq(Engine::Predicates::UpgradeDrafted)
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate: audit_produced`.

**Step 3: Register predicates**

Add these entries to `Engine::PredicateRegistry::PREDICATES` near related cookbook predicates:

```ruby
"audit_produced" => Predicates::AuditProduced,
"upgrade_plan_produced" => Predicates::UpgradePlanProduced,
"upgrade_drafted" => Predicates::UpgradeDrafted,
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register dependency upgrade predicates"
```

---

### Task 5: Add seed spec for the `dependency_upgrade` queue

**Objective:** Prove the queue YAML is seeded with resolved prompts, expected stages, portable adapter config, and no hardcoded paths.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/dependency_upgrade.yml`
- Later create: prompt files from the prompt targets above

**Step 1: Write failing test**

Append this example to `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the dependency upgrade cookbook queue with resolved portable prompts" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "dependency_upgrade")
  expect(queue.name).to eq("Dependency Upgrade")
  expect(queue.stages).to eq(%w[
    audit_dependencies
    prioritize_upgrades
    upgrade_one
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

  audit = queue.stage_configs.find_by!(stage_name: "audit_dependencies")
  expect(audit.adapter_type).to eq("shell_script")
  expect(audit.model_override).to eq("claude-haiku-4-5-20251001")
  expect(audit.allowed_skills).to eq(%w[read_repo run_audit])
  expect(audit.forbidden_skills).to include("edit_files", "deploy")
  expect(audit.completion_criteria).to eq(["audit_produced"])
  expect(audit.timeout_seconds).to eq(300)
  expect(audit.agent_prompt).to include("# Dependency Upgrade Audit")
  expect(audit.agent_prompt).to include("dependency_audit")
  expect(audit.agent_prompt).not_to start_with("file://")
  expect(audit.adapter_config).to include(
    "output_artifact_kind" => "dependency_audit",
    "fixture_app" => "cookbooks/fixtures/apps/dependency_upgrade"
  )
  expect(audit.adapter_config.fetch("commands")).to contain_exactly(
    include(
      "name" => "dependency audit fixture",
      "command" => "ruby cookbooks/fixtures/apps/dependency_upgrade/bin/dependency-audit",
      "artifact" => "dependency_audit"
    )
  )

  prioritize = queue.stage_configs.find_by!(stage_name: "prioritize_upgrades")
  expect(prioritize.adapter_type).to eq("inline_claude")
  expect(prioritize.model_override).to eq("claude-sonnet-4-20250514")
  expect(prioritize.completion_criteria).to eq(["upgrade_plan_produced"])
  expect(prioritize.agent_prompt).to include("# Dependency Upgrade Prioritize")
  expect(prioritize.agent_prompt).to include("spawn_work_items")
  expect(prioritize.agent_prompt).not_to start_with("file://")
  expect(prioritize.adapter_config).to include(
    "input_artifact_kind" => "dependency_audit",
    "output_artifact_kind" => "upgrade_plan",
    "spawn_target_queue" => "development"
  )

  upgrade = queue.stage_configs.find_by!(stage_name: "upgrade_one")
  expect(upgrade.adapter_type).to eq("inline_claude")
  expect(upgrade.model_override).to eq("claude-sonnet-4-20250514")
  expect(upgrade.allowed_skills).to eq(%w[read_repo edit_files])
  expect(upgrade.forbidden_skills).to include("deploy")
  expect(upgrade.completion_criteria).to eq(["upgrade_drafted"])
  expect(upgrade.agent_prompt).to include("# Dependency Upgrade One")
  expect(upgrade.agent_prompt).to include("upgrade_patches")
  expect(upgrade.adapter_config).to include(
    "input_artifact_kind" => "upgrade_plan",
    "output_artifact_kind" => "upgrade_patches",
    "fixture_app" => "cookbooks/fixtures/apps/dependency_upgrade",
    "branch_prefix" => "dependency-upgrade"
  )

  run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
  expect(run_tests.adapter_type).to eq("shell_script")
  expect(run_tests.allowed_skills).to eq(["run_tests"])
  expect(run_tests.forbidden_skills).to include("edit_files", "deploy")
  expect(run_tests.completion_criteria).to eq(["tests_passed"])
  expect(run_tests.adapter_config).to include(
    "input_artifact_kind" => "upgrade_patches",
    "output_artifact_kind" => "test_results",
    "fixture_app" => "cookbooks/fixtures/apps/dependency_upgrade"
  )
  expect(run_tests.adapter_config).not_to have_key("working_directory")
  expect(run_tests.adapter_config.fetch("commands")).to contain_exactly(
    include(
      "name" => "dependency upgrade fixture specs",
      "artifact" => "test_results",
      "command" => "PATH=\"$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH\" bundle exec rspec spec/e2e/dependency_upgrade_cookbook_spec.rb"
    )
  )

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.completion_criteria).to eq(["report_present"])
  expect(human_review.timeout_seconds).to eq(86_400)

  done = queue.stage_configs.find_by!(stage_name: "done")
  expect(done.adapter_type).to eq("fake")
  expect(done.completion_criteria).to eq(["report_present"])

  serialized_queue = Rails.root.join("config/queues/dependency_upgrade.yml").read
  expect(serialized_queue).not_to include(Rails.root.to_s)
  expect(serialized_queue).not_to include("/Users/")
  expect(serialized_queue).to include("file://prompts/deps_audit.md")
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL with `Couldn't find WorkQueue with [WHERE "work_queues"."slug" = ?]` for `dependency_upgrade`.

**Step 3: Add YAML and prompt files**

Create `config/queues/dependency_upgrade.yml`, `prompts/deps_audit.md`, `prompts/deps_prioritize.md`, and `prompts/deps_upgrade_one.md` using the exact targets earlier in this plan.

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS for the new dependency-upgrade seed example. If unrelated examples fail because of other uncommitted cookbook work, run the single example by line number and note the unrelated failures in the handoff.

**Step 5: Commit**

```bash
git add config/queues/dependency_upgrade.yml prompts/deps_audit.md prompts/deps_prioritize.md prompts/deps_upgrade_one.md spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed dependency upgrade queue"
```

---

### Task 6: Add Docker-friendly dependency fixture app

**Objective:** Provide deterministic Ruby/Node dependency manifests and a local audit script that cookbook specs can use without network calls.

**Files:**
- Create: `cookbooks/fixtures/apps/dependency_upgrade/README.md`
- Create: `cookbooks/fixtures/apps/dependency_upgrade/Gemfile`
- Create: `cookbooks/fixtures/apps/dependency_upgrade/Gemfile.lock`
- Create: `cookbooks/fixtures/apps/dependency_upgrade/package.json`
- Create: `cookbooks/fixtures/apps/dependency_upgrade/app/models/order.rb`
- Create: `cookbooks/fixtures/apps/dependency_upgrade/app/services/payment_gateway.rb`
- Create: `cookbooks/fixtures/apps/dependency_upgrade/spec/models/order_spec.rb`
- Create: `cookbooks/fixtures/apps/dependency_upgrade/bin/dependency-audit`

**Step 1: Write failing fixture contract spec**

Create `spec/e2e/dependency_upgrade_cookbook_spec.rb` with only the fixture contract example first:

```ruby
require "rails_helper"
require "json"

RSpec.describe "dependency upgrade cookbook" do
  let(:fixture_root) { Rails.root.join("cookbooks/fixtures/apps/dependency_upgrade") }

  it "ships a deterministic fixture app and audit script" do
    expect(fixture_root.join("Gemfile")).to exist
    expect(fixture_root.join("Gemfile.lock")).to exist
    expect(fixture_root.join("package.json")).to exist
    expect(fixture_root.join("bin/dependency-audit")).to exist

    audit = JSON.parse(`ruby #{fixture_root.join("bin/dependency-audit")}`)

    expect(audit.fetch("dependencies").map { |dep| dep.fetch("name") }).to include("rack", "puma", "lodash")
    expect(audit.fetch("total_outdated")).to eq(audit.fetch("dependencies").count)
    expect(audit.fetch("cve_count")).to be >= 1
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/dependency_upgrade_cookbook_spec.rb
```

Expected: FAIL because `cookbooks/fixtures/apps/dependency_upgrade/Gemfile` does not exist.

**Step 3: Create fixture files**

Create `cookbooks/fixtures/apps/dependency_upgrade/README.md`:

```markdown
# Dependency Upgrade Fixture App

This tiny fixture simulates a Rails-ish application with stale Ruby and Node dependencies.
It is intentionally static and safe for Docker/local cookbook tests: the audit script prints deterministic JSON and does not run networked package manager commands.
```

Create `cookbooks/fixtures/apps/dependency_upgrade/Gemfile`:

```ruby
source "https://rubygems.org"

gem "rack", "2.2.8"
gem "puma", "6.4.0"
gem "sidekiq", "7.1.0"
```

Create a minimal `cookbooks/fixtures/apps/dependency_upgrade/Gemfile.lock` containing the same stale versions:

```text
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.2.8)
    puma (6.4.0)
    sidekiq (7.1.0)

PLATFORMS
  ruby

DEPENDENCIES
  rack (= 2.2.8)
  puma (= 6.4.0)
  sidekiq (= 7.1.0)

BUNDLED WITH
   2.5.0
```

Create `cookbooks/fixtures/apps/dependency_upgrade/package.json`:

```json
{
  "name": "dependency-upgrade-fixture",
  "private": true,
  "dependencies": {
    "lodash": "4.17.20",
    "vite": "4.5.0"
  },
  "scripts": {
    "test": "echo fixture tests pass"
  }
}
```

Create `cookbooks/fixtures/apps/dependency_upgrade/app/models/order.rb`:

```ruby
class Order
  attr_reader :total_cents

  def initialize(total_cents:)
    @total_cents = total_cents
  end

  def payable?
    total_cents.positive?
  end
end
```

Create `cookbooks/fixtures/apps/dependency_upgrade/app/services/payment_gateway.rb`:

```ruby
class PaymentGateway
  def initialize(client: nil)
    @client = client
  end

  def charge(order)
    return :skipped unless order.payable?

    :charged
  end
end
```

Create `cookbooks/fixtures/apps/dependency_upgrade/spec/models/order_spec.rb`:

```ruby
require_relative "../../app/models/order"

RSpec.describe Order do
  it "marks positive totals payable" do
    expect(Order.new(total_cents: 1200)).to be_payable
  end
end
```

Create `cookbooks/fixtures/apps/dependency_upgrade/bin/dependency-audit`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

puts JSON.pretty_generate(
  dependencies: [
    {
      name: "rack",
      ecosystem: "rubygems",
      current: "2.2.8",
      latest: "3.0.9",
      type: "major",
      cves: ["CVE-2024-25126"],
      changelog_url: "https://github.com/rack/rack/releases",
      manifest: "Gemfile"
    },
    {
      name: "puma",
      ecosystem: "rubygems",
      current: "6.4.0",
      latest: "6.4.2",
      type: "patch",
      cves: [],
      changelog_url: "https://github.com/puma/puma/releases",
      manifest: "Gemfile"
    },
    {
      name: "lodash",
      ecosystem: "npm",
      current: "4.17.20",
      latest: "4.17.21",
      type: "patch",
      cves: ["CVE-2021-23337"],
      changelog_url: "https://github.com/lodash/lodash/releases",
      manifest: "package.json"
    }
  ],
  total_outdated: 3,
  cve_count: 2,
  audit_commands: ["fixture dependency audit"],
  notes: ["Static fixture output; no network calls performed"]
)
```

Make it executable:

```bash
chmod +x cookbooks/fixtures/apps/dependency_upgrade/bin/dependency-audit
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/dependency_upgrade_cookbook_spec.rb
```

Expected: PASS for the fixture contract example.

**Step 5: Commit**

```bash
git add cookbooks/fixtures/apps/dependency_upgrade spec/e2e/dependency_upgrade_cookbook_spec.rb
git commit -m "test: add dependency upgrade fixture app"
```

---

### Task 7: Add e2e cookbook spec for queue, predicates, and fixture flow

**Objective:** Prove the cookbook queue, artifact predicates, deterministic fixture audit, and run_tests configuration work together.

**Files:**
- Modify: `spec/e2e/dependency_upgrade_cookbook_spec.rb`

**Step 1: Write failing integration examples**

Extend `spec/e2e/dependency_upgrade_cookbook_spec.rb`:

```ruby
it "loads the dependency_upgrade queue and validates each cookbook artifact" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "dependency_upgrade")
  work_item = WorkItem.create!(work_queue: queue, title: "Upgrade stale deps", spec_url: "fixture", stage_name: "audit_dependencies")

  audit_claim = Claim.create!(work_item: work_item, stage_name: "audit_dependencies", agent_type: "shell_script", status: "completed", started_at: Time.current)
  audit_data = JSON.parse(`ruby #{fixture_root.join("bin/dependency-audit")}`)
  Artifact.create!(work_item: work_item, claim: audit_claim, kind: "dependency_audit", data: audit_data)
  expect(Engine::PredicateRegistry.resolve("audit_produced").new(claim: audit_claim).call).to be_passed

  plan_claim = Claim.create!(work_item: work_item, stage_name: "prioritize_upgrades", agent_type: "inline_claude", status: "completed", started_at: Time.current)
  Artifact.create!(
    work_item: work_item,
    claim: plan_claim,
    kind: "upgrade_plan",
    data: {
      "upgrades" => [
        { "deps" => ["rack"], "priority" => 1, "risk" => "medium", "reason" => "CVE fix" },
        { "deps" => ["puma"], "priority" => 2, "risk" => "low", "reason" => "patch" }
      ],
      "spawn_work_items" => []
    }
  )
  expect(Engine::PredicateRegistry.resolve("upgrade_plan_produced").new(claim: plan_claim).call).to be_passed

  upgrade_claim = Claim.create!(work_item: work_item, stage_name: "upgrade_one", agent_type: "inline_claude", status: "completed", started_at: Time.current)
  Artifact.create!(
    work_item: work_item,
    claim: upgrade_claim,
    kind: "upgrade_patches",
    data: {
      "dep_name" => "rack",
      "from_version" => "2.2.8",
      "to_version" => "3.0.9",
      "branch_name" => "dependency-upgrade/rack-3-0-9",
      "patches" => [
        { "file" => "Gemfile", "original" => "gem \"rack\", \"2.2.8\"", "replacement" => "gem \"rack\", \"3.0.9\"" }
      ]
    }
  )
  expect(Engine::PredicateRegistry.resolve("upgrade_drafted").new(claim: upgrade_claim).call).to be_passed
end

it "keeps dependency upgrade queue paths portable" do
  queue_yaml = Rails.root.join("config/queues/dependency_upgrade.yml").read

  expect(queue_yaml).not_to include(Rails.root.to_s)
  expect(queue_yaml).not_to include("/Users/")
  expect(queue_yaml).to include("cookbooks/fixtures/apps/dependency_upgrade")
  expect(queue_yaml).to include("file://prompts/deps_audit.md")
end
```

**Step 2: Run test to verify RED**

Run before the predicates/registry/queue tasks are complete if doing TDD strictly in sequence:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/dependency_upgrade_cookbook_spec.rb
```

Expected: FAIL at the first missing production/config component, such as missing queue, unresolved predicate, or missing fixture.

**Step 3: Implement only missing wiring from prior tasks**

If Tasks 1-6 were completed, no new production code should be needed. If this spec exposes a real gap, add the smallest missing queue/predicate/fixture change and keep it within the files already listed.

**Step 4: Run e2e and surrounding specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/dependency_upgrade_cookbook_spec.rb
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/audit_produced_spec.rb spec/services/engine/predicates/upgrade_plan_produced_spec.rb spec/services/engine/predicates/upgrade_drafted_spec.rb spec/services/engine/predicate_registry_spec.rb spec/models/work_queue_seed_spec.rb
```

Expected: PASS for dependency-upgrade examples. If the broader seed spec is polluted by unrelated uncommitted cookbook work, run the dependency-upgrade example line directly and record the unrelated failures.

**Step 5: Commit**

```bash
git add spec/e2e/dependency_upgrade_cookbook_spec.rb
git commit -m "test: cover dependency upgrade cookbook flow"
```

---

### Task 8: Add cookbook documentation page

**Objective:** Document how the dependency upgrade cookbook works, what artifacts each stage emits, and how to run the deterministic fixture locally.

**Files:**
- Create: `docs/cookbooks/dependency-upgrade.md`

**Step 1: Write docs content**

Create `docs/cookbooks/dependency-upgrade.md`:

```markdown
# Dependency Upgrade Cookbook

The Dependency Upgrade cookbook audits stale Ruby and Node dependencies, prioritizes safe upgrade groups, drafts one upgrade at a time, runs tests, and sends a clean review package to a human.

## Queue

`dependency_upgrade`: `audit_dependencies -> prioritize_upgrades -> upgrade_one -> run_tests -> human_review -> done`

## Artifacts

- `dependency_audit`: outdated dependencies, semantic upgrade type, CVEs, changelog links, and audit command notes.
- `upgrade_plan`: prioritized dependency groups with risk notes and optional `spawn_work_items` for feature-sized migrations.
- `upgrade_patches`: the selected dependency, version delta, branch name, manifest/code patches, test commands, and migration notes.
- `test_results`: focused test output after applying the drafted patches.

## Fixture

The deterministic fixture lives in `cookbooks/fixtures/apps/dependency_upgrade`.

Run the fixture audit without network calls:

```bash
ruby cookbooks/fixtures/apps/dependency_upgrade/bin/dependency-audit
```

Run the cookbook e2e spec:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/dependency_upgrade_cookbook_spec.rb
```

## Portability

All queue and fixture paths are repo-relative. The cookbook does not commit absolute checkout paths and does not require a dedicated Docker Compose file.
```

**Step 2: Verify docs mention required artifacts and commands**

Run:

```bash
grep -n "dependency_audit\|upgrade_plan\|upgrade_patches\|dependency-audit" docs/cookbooks/dependency-upgrade.md
```

Expected: lines for all three artifacts and the fixture audit command.

**Step 3: Commit**

```bash
git add docs/cookbooks/dependency-upgrade.md
git commit -m "docs: add dependency upgrade cookbook"
```

---

### Task 9: Final verification and cleanup

**Objective:** Run the focused dependency-upgrade test set, verify no hardcoded paths were introduced, and ensure the branch has clean dependency-upgrade commits.

**Files:**
- No new files unless a verification failure exposes a bug.

**Step 1: Run focused predicate and registry specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/audit_produced_spec.rb \
  spec/services/engine/predicates/upgrade_plan_produced_spec.rb \
  spec/services/engine/predicates/upgrade_drafted_spec.rb \
  spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 2: Run seed and e2e specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb spec/e2e/dependency_upgrade_cookbook_spec.rb
```

Expected: PASS. If unrelated uncommitted cookbook work causes failures in existing examples, rerun only the dependency-upgrade seed example by line number plus the e2e spec, and include the unrelated failure names in the handoff.

**Step 3: Check for hardcoded checkout paths in dependency-upgrade files**

Run:

```bash
grep -R "/Users/\|/Users/gregmushen/work/code/taskrail" \
  config/queues/dependency_upgrade.yml \
  prompts/deps_audit.md \
  prompts/deps_prioritize.md \
  prompts/deps_upgrade_one.md \
  app/services/engine/predicates/audit_produced.rb \
  app/services/engine/predicates/upgrade_plan_produced.rb \
  app/services/engine/predicates/upgrade_drafted.rb \
  spec/services/engine/predicates/audit_produced_spec.rb \
  spec/services/engine/predicates/upgrade_plan_produced_spec.rb \
  spec/services/engine/predicates/upgrade_drafted_spec.rb \
  spec/e2e/dependency_upgrade_cookbook_spec.rb \
  cookbooks/fixtures/apps/dependency_upgrade \
  docs/cookbooks/dependency-upgrade.md
```

Expected: no output and exit status 1 from `grep`.

**Step 4: Inspect staged/committed work**

Run:

```bash
git status --short
git log --oneline -n 10
```

Expected: dependency-upgrade files are committed. Existing unrelated dirty files may remain in the shared workspace; do not stage or modify them.

**Step 5: Optional final squash if assigned by Kanban**

If the implementation assignment requires one final commit, squash only the dependency-upgrade task commits into:

```bash
git commit -m "feat: add dependency upgrade cookbook"
```

Do not include unrelated dirty or untracked files from other cookbook work.

---

## Acceptance checklist

- [ ] `config/queues/dependency_upgrade.yml` seeds `Dependency Upgrade` with stages `audit_dependencies`, `prioritize_upgrades`, `upgrade_one`, `run_tests`, `human_review`, and `done`.
- [ ] Queue prompt paths use `file://prompts/deps_audit.md`, `file://prompts/deps_prioritize.md`, and `file://prompts/deps_upgrade_one.md`, and seed specs prove prompts are resolved.
- [ ] Queue config has no hardcoded absolute checkout paths and no explicit `working_directory`.
- [ ] `audit_produced`, `upgrade_plan_produced`, and `upgrade_drafted` predicates are implemented, registered, and covered by focused specs.
- [ ] The fixture app under `cookbooks/fixtures/apps/dependency_upgrade` has deterministic Ruby/Node dependency manifests and a no-network audit script.
- [ ] The e2e spec proves the seeded queue, predicates, deterministic fixture audit, and portability guardrails.
- [ ] Prompt files instruct real dependency audit/prioritization/upgrade drafting behavior, including CVE prioritization, related dependency grouping, changelog checks, one upgrade per run, and cross-queue spawn for major migrations.
- [ ] Documentation page `docs/cookbooks/dependency-upgrade.md` explains artifacts, fixture usage, commands, and portability.
- [ ] Focused RSpec commands pass with Greg's rbenv path prefix or any unrelated failures are explicitly documented.
- [ ] Work is committed without staging unrelated files from other cookbook tasks.
