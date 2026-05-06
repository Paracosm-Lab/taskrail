# Database Query Health Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add a `query_health` cookbook queue that inventories Rails database queries, analyzes query performance risks, drafts query/index fixes, validates them, and routes human review for DBA-sensitive changes.

**Architecture:** This cookbook is implemented as a seeded TaskRail queue backed by portable YAML, prompt files resolved through `Rails.root`, three artifact predicates, and a slow-query fixture app for end-to-end coverage. Query collection and test execution use shell-compatible stages; reasoning stages use `inline_claude` and persist structured artifacts that downstream stages and predicates can inspect. Shared Docker/Rails infrastructure should be reused from the shared cookbook infrastructure work; this plan only adds the query-health-specific fixture app and queue configuration.

**Tech Stack:** Rails 8, RSpec, PostgreSQL JSONB artifacts, YAML queue seeds, TaskRail adapters (`shell_script`, `inline_claude`, `fake`), portable `file://` prompt indirection.

**Source Spec:** `docs/specs/cookbook-07-database-query-health.md`

---

## Current Codebase Context

Relevant existing files:

- `db/seeds.rb` loads every `config/queues/*.yml`, resolves any `agent_prompt: file://...` path relative to `Rails.root`, and upserts `WorkQueue` plus `StageConfig` records.
- `config/queues/operations.yml` is the best existing queue seed example with `file://prompts/...` prompt indirection and adapter configs.
- `app/services/engine/predicate_registry.rb` maps completion-criteria names to predicate classes.
- `app/services/engine/predicates/clusters_created.rb` is the simplest existing artifact-presence predicate shape.
- `spec/services/engine/predicates/clusters_created_spec.rb` demonstrates predicate specs with real `WorkQueue`, `WorkItem`, `Claim`, and `Artifact` records.
- `spec/models/work_queue_seed_spec.rb` already verifies seeded queues and prompt-file resolution.
- `spec/services/engine/cross_queue_spawn_spec.rb` already verifies generic `spawn_work_items`; query-health only needs prompt instructions and an e2e/seed assertion, not a new spawn engine.

Global implementation rules:

- Follow strict TDD from `test-driven-development`: write each failing spec first, run it and confirm the expected failure, implement minimal code/config, then rerun the focused spec and relevant surrounding specs.
- Use Greg's rbenv path for every RSpec command:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Do not hardcode `/Users/gregmushen/work/code/taskrail` or any absolute repository path in queue YAML, prompts, specs, fixtures, or implementation code.
- For prompt indirection, use `file://prompts/query_collect.md`, `file://prompts/query_analyze.md`, and `file://prompts/query_draft_fixes.md`; `db/seeds.rb` already resolves these with `Rails.root.join(...)`.
- Do not duplicate shared cookbook infrastructure such as a top-level Compose stack, generic app runner, or shared shell adapter setup. This cookbook may add `adapter_config` knobs that point at already-shared fake/docker-friendly inputs.

---

## Files to Create or Modify

Create:

- `config/queues/query_health.yml`
- `prompts/query_collect.md`
- `prompts/query_analyze.md`
- `prompts/query_draft_fixes.md`
- `app/services/engine/predicates/query_inventory_produced.rb`
- `app/services/engine/predicates/query_analyzed.rb`
- `app/services/engine/predicates/query_fixes_drafted.rb`
- `spec/services/engine/predicates/query_inventory_produced_spec.rb`
- `spec/services/engine/predicates/query_analyzed_spec.rb`
- `spec/services/engine/predicates/query_fixes_drafted_spec.rb`
- `test/fixtures/apps/slow_queries/README.md`
- `test/fixtures/apps/slow_queries/Gemfile`
- `test/fixtures/apps/slow_queries/config/routes.rb`
- `test/fixtures/apps/slow_queries/app/models/author.rb`
- `test/fixtures/apps/slow_queries/app/models/post.rb`
- `test/fixtures/apps/slow_queries/app/models/wide_report.rb`
- `test/fixtures/apps/slow_queries/app/controllers/posts_controller.rb`
- `test/fixtures/apps/slow_queries/app/views/posts/index.html.erb`
- `test/fixtures/apps/slow_queries/app/services/wide_report_search.rb`
- `test/fixtures/apps/slow_queries/db/schema.rb`
- `test/fixtures/apps/slow_queries/db/seeds.rb`

Modify:

- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Optional docs update if the repository has a cookbook queue index by implementation time:

- `docs/cookbook-failure-readiness.md` or a future `docs/cookbooks.md` index; add a single row/link for Query Health only if the existing docs structure clearly expects it. Do not edit generated PDFs in this implementation task.

---

## Query Health Queue YAML Target

Create `config/queues/query_health.yml` with this content. Keep prompt paths relative and omit `working_directory`; shell adapters should default to the checked-out app root or shared cookbook infrastructure defaults.

```yaml
name: Database Query Health Check
slug: query_health
stages:
  - collect_queries
  - analyze_performance
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
  collect_queries:
    adapter_type: shell_script
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [run_tests, read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [query_inventory_produced]
    agent_prompt: file://prompts/query_collect.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: query_inventory
      fixture_app: test/fixtures/apps/slow_queries
      docker_profile: cookbook-query-health
      commands:
        - artifact: query_inventory
          command: bin/query-health collect --format=json
  analyze_performance:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [query_analyzed]
    agent_prompt: file://prompts/query_analyze.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: query_inventory
      output_artifact_kind: query_analysis
      spawn_target_queue: development
  draft_fixes:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy, mutate_database]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [query_fixes_drafted]
    agent_prompt: file://prompts/query_draft_fixes.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: query_analysis
      output_artifact_kind: query_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [tests_passed]
    agent_prompt: Apply migrations and code patches, run the test suite, and report pass/fail plus any query-count delta.
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: query_patches
      output_artifact_kind: test_results
      docker_profile: cookbook-query-health
      commands:
        - artifact: test_results
          command: bin/query-health apply-and-test --format=json
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review query optimizations and index migrations. Flag large-table indexes for concurrent migration and DBA approval before production rollout.
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

- `bin/query-health ...` does not need to exist in this slice if the shared cookbook infrastructure plan owns generic shell command implementation. If this worker is also assigned that missing script, implement it there; otherwise the YAML records the intended docker-friendly commands for future infrastructure.
- `fixture_app` and `docker_profile` are query-health-specific configuration hints. They should not introduce a second Compose file or hardcoded checkout path.
- `spawn_target_queue: development` documents the cross-queue destination for architectural findings; the existing transition manager consumes `spawn_work_items` in reports, so the prompt must instruct `analyze_performance` how to emit those items.

---

## Prompt File Targets

### `prompts/query_collect.md`

```markdown
# Query Health Collect Queries

You are the collection stage for the `query_health` queue.

Inputs:
- Repository root from the runner working directory; do not assume an absolute path.
- Database config from the target app.
- Optional fixture path from adapter config: `test/fixtures/apps/slow_queries`.

Collect a query inventory from all available safe sources:

1. Run the test suite with SQL/query logging enabled when the runner provides a safe test command.
2. Parse `log/test.log` and `log/development.log` when present.
3. Scan Rails source files for ActiveRecord query calls such as `.where`, `.find`, `.joins`, `.includes`, `.preload`, `.eager_load`, `.select`, `.count`, `.pluck`, `.order`, and `.limit`.
4. If Postgres `pg_stat_statements` or a slow-query log is provided by the runner, parse it; otherwise record that it was unavailable.
5. For each query, record SQL or query expression, origin (`file:line` when known), touched tables, frequency hint, and whether an index hint exists.
6. Estimate table row counts from `db/schema.rb`, seed data, or database metadata if safely available.

Return exactly one `query_inventory` artifact as JSON:

```json
{
  "queries": [
    {
      "sql": "SELECT * FROM posts WHERE status = ?",
      "origin": "app/controllers/posts_controller.rb:8",
      "tables": ["posts"],
      "frequency": "per_request",
      "has_index_hint": false
    }
  ],
  "table_stats": {
    "row_counts": { "posts": 1000 }
  },
  "collection_notes": []
}
```

The artifact must include at least one query. Do not edit files, deploy, or mutate non-test databases.
```

### `prompts/query_analyze.md`

```markdown
# Query Health Analyze Performance

You are the analysis stage for the `query_health` queue.

Inputs:
- `query_inventory` artifact.
- Rails schema from `db/schema.rb` or equivalent.
- Existing index definitions.
- Source files around query origins.

Analyze each query for:

- N+1 query risk from loops, views, serializers, or repeated association access.
- Missing indexes on WHERE, JOIN, ORDER, and foreign-key columns.
- Full table scans on large tables.
- Unnecessary loads such as `SELECT *` when only a few columns are used.
- Redundant queries that fetch the same data repeatedly.
- Counter queries that should use counter caches.

Score severity as `critical`, `high`, `medium`, or `low` using table size, frequency, and blast radius. Recommend one of: `add_index`, `eager_load`, `rewrite_query`, `add_counter_cache`, `add_pagination`, `use_select`, `architectural_change`, or `no_change`.

Return one `query_analysis` artifact as JSON:

```json
{
  "findings": [
    {
      "query": "SELECT * FROM posts WHERE status = ?",
      "origin": "app/controllers/posts_controller.rb:8",
      "issue_type": "missing_index",
      "severity": "high",
      "tables": ["posts"],
      "recommendation": "add_index",
      "estimated_impact": "Filters a high-frequency request on an unindexed status column."
    }
  ],
  "spawn_work_items": [
    {
      "queue_slug": "development",
      "title": "Design caching layer for expensive feed query",
      "spec_inline": "The query health analysis found an architectural_change finding that should be handled by the development queue instead of an index-only patch.",
      "tags": { "domain": "query_health", "issue_type": "architectural_change" }
    }
  ]
}
```

Only include `spawn_work_items` for architectural changes such as denormalization, caching layers, or read-replica routing. Do not spawn work for normal index/eager-loading fixes that `draft_fixes` can handle.
```

### `prompts/query_draft_fixes.md`

```markdown
# Query Health Draft Fixes

You are the fix-drafting stage for the `query_health` queue.

Inputs:
- `query_analysis` artifact.
- Source code around each finding.
- Rails schema and existing indexes.

Draft fixes only for `critical` and `high` findings that are safe to represent as migrations or source patches:

- Missing indexes: generate Rails migration files with `add_index`; for large-table risk, add notes that DBA review should consider concurrent index creation.
- N+1 queries: add `includes`, `preload`, or `eager_load` at the query boundary.
- Full table scans: add targeted filters or pagination only when the source behavior makes the intended constraint clear.
- `SELECT *`: use `.select(:id, ...)` only when downstream code proves the reduced column set is safe.
- Counter queries: draft counter-cache migrations and model association updates only when the relationship is clear.

Return one `query_patches` artifact as JSON:

```json
{
  "migrations": [
    {
      "filename": "db/migrate/20260505000000_add_index_to_posts_on_status.rb",
      "content": "class AddIndexToPostsOnStatus < ActiveRecord::Migration[8.0]\n  def change\n    add_index :posts, :status\n  end\nend\n"
    }
  ],
  "code_patches": [
    {
      "file": "app/controllers/posts_controller.rb",
      "original": "@posts = Post.all",
      "replacement": "@posts = Post.includes(:author).all"
    }
  ],
  "review_notes": ["DBA should review index strategy for large tables before production rollout."]
}
```

Do not apply patches. Do not edit files directly. If no critical/high finding can be safely fixed, return empty arrays and explain why in `review_notes`.
```

---

## Task 1: Add Predicate Specs for Query Artifacts

**Objective:** Define the expected behavior for the three query-health predicates before adding production predicate classes.

**Files:**
- Create: `spec/services/engine/predicates/query_inventory_produced_spec.rb`
- Create: `spec/services/engine/predicates/query_analyzed_spec.rb`
- Create: `spec/services/engine/predicates/query_fixes_drafted_spec.rb`

**Step 1: Write failing specs**

Use real records, matching `spec/services/engine/predicates/clusters_created_spec.rb`. Keep helper methods local to each spec file to avoid broad test coupling.

`spec/services/engine/predicates/query_inventory_produced_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::QueryInventoryProduced do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Query Inventory #{SecureRandom.hex(4)}", slug: "query-inventory-#{SecureRandom.hex(4)}", stages: ["collect_queries", "done"])
    queue.stage_configs.create!(stage_name: "collect_queries", adapter_type: "fake")
    item = WorkItem.create!(title: "Query health", spec_url: "opaque spec", work_queue: queue, stage_name: "collect_queries")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when query_inventory artifact has at least one query" do
    claim = build_claim(artifacts: [{ kind: "query_inventory", data: { "queries" => [{ "sql" => "SELECT * FROM posts" }] } }])
    artifact = claim.artifacts.find_by!(kind: "query_inventory")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, query_count: 1 })
  end

  it "fails when query_inventory artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no query_inventory artifact found")
  end

  it "fails when query_inventory has no queries" do
    claim = build_claim(artifacts: [{ kind: "query_inventory", data: { "queries" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("query_inventory artifact has no queries")
  end
end
```

`spec/services/engine/predicates/query_analyzed_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::QueryAnalyzed do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Query Analyzed #{SecureRandom.hex(4)}", slug: "query-analyzed-#{SecureRandom.hex(4)}", stages: ["analyze_performance", "done"])
    queue.stage_configs.create!(stage_name: "analyze_performance", adapter_type: "fake")
    item = WorkItem.create!(title: "Query health", spec_url: "opaque spec", work_queue: queue, stage_name: "analyze_performance")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when query_analysis artifact has findings" do
    claim = build_claim(artifacts: [{ kind: "query_analysis", data: { "findings" => [{ "issue_type" => "missing_index" }] } }])
    artifact = claim.artifacts.find_by!(kind: "query_analysis")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, finding_count: 1 })
  end

  it "fails when query_analysis artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no query_analysis artifact found")
  end

  it "fails when query_analysis has no findings" do
    claim = build_claim(artifacts: [{ kind: "query_analysis", data: { "findings" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("query_analysis artifact has no findings")
  end
end
```

`spec/services/engine/predicates/query_fixes_drafted_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::QueryFixesDrafted do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Query Fixes #{SecureRandom.hex(4)}", slug: "query-fixes-#{SecureRandom.hex(4)}", stages: ["draft_fixes", "done"])
    queue.stage_configs.create!(stage_name: "draft_fixes", adapter_type: "fake")
    item = WorkItem.create!(title: "Query health", spec_url: "opaque spec", work_queue: queue, stage_name: "draft_fixes")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes when query_patches artifact has a migration" do
    claim = build_claim(artifacts: [{ kind: "query_patches", data: { "migrations" => [{ "filename" => "db/migrate/add_index.rb" }], "code_patches" => [] } }])
    artifact = claim.artifacts.find_by!(kind: "query_patches")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, migration_count: 1, code_patch_count: 0 })
  end

  it "passes when query_patches artifact has a code patch" do
    claim = build_claim(artifacts: [{ kind: "query_patches", data: { "migrations" => [], "code_patches" => [{ "file" => "app/controllers/posts_controller.rb" }] } }])
    artifact = claim.artifacts.find_by!(kind: "query_patches")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, migration_count: 0, code_patch_count: 1 })
  end

  it "fails when query_patches artifact is missing" do
    claim = build_claim

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no query_patches artifact found")
  end

  it "fails when query_patches has no migrations or code patches" do
    claim = build_claim(artifacts: [{ kind: "query_patches", data: { "migrations" => [], "code_patches" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("query_patches artifact has no migrations or code patches")
  end
end
```

**Step 2: Run specs to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/query_inventory_produced_spec.rb \
  spec/services/engine/predicates/query_analyzed_spec.rb \
  spec/services/engine/predicates/query_fixes_drafted_spec.rb
```

Expected: FAIL with uninitialized constants such as `Engine::Predicates::QueryInventoryProduced`.

**Step 3: Commit?**

Do not commit yet; commit after each green task. This task remains RED until Task 2 implements predicates.

---

## Task 2: Implement Query Artifact Predicates

**Objective:** Add minimal predicate classes that pass the specs from Task 1.

**Files:**
- Create: `app/services/engine/predicates/query_inventory_produced.rb`
- Create: `app/services/engine/predicates/query_analyzed.rb`
- Create: `app/services/engine/predicates/query_fixes_drafted.rb`
- Test: the three predicate spec files from Task 1

**Step 1: Write minimal implementation**

`app/services/engine/predicates/query_inventory_produced.rb`:

```ruby
module Engine
  module Predicates
    class QueryInventoryProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "query_inventory").first
        return PredicateResult.fail(reason: "no query_inventory artifact found") unless artifact

        query_count = Array(artifact.data["queries"]).count
        return PredicateResult.fail(reason: "query_inventory artifact has no queries") if query_count.zero?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, query_count: query_count })
      end
    end
  end
end
```

`app/services/engine/predicates/query_analyzed.rb`:

```ruby
module Engine
  module Predicates
    class QueryAnalyzed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "query_analysis").first
        return PredicateResult.fail(reason: "no query_analysis artifact found") unless artifact

        finding_count = Array(artifact.data["findings"]).count
        return PredicateResult.fail(reason: "query_analysis artifact has no findings") if finding_count.zero?

        PredicateResult.pass(evidence: { artifact_id: artifact.id, finding_count: finding_count })
      end
    end
  end
end
```

`app/services/engine/predicates/query_fixes_drafted.rb`:

```ruby
module Engine
  module Predicates
    class QueryFixesDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "query_patches").first
        return PredicateResult.fail(reason: "no query_patches artifact found") unless artifact

        migration_count = Array(artifact.data["migrations"]).count
        code_patch_count = Array(artifact.data["code_patches"]).count
        if migration_count.zero? && code_patch_count.zero?
          return PredicateResult.fail(reason: "query_patches artifact has no migrations or code patches")
        end

        PredicateResult.pass(evidence: {
          artifact_id: artifact.id,
          migration_count: migration_count,
          code_patch_count: code_patch_count
        })
      end
    end
  end
end
```

**Step 2: Run focused specs to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/query_inventory_produced_spec.rb \
  spec/services/engine/predicates/query_analyzed_spec.rb \
  spec/services/engine/predicates/query_fixes_drafted_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/query_inventory_produced.rb \
  app/services/engine/predicates/query_analyzed.rb \
  app/services/engine/predicates/query_fixes_drafted.rb \
  spec/services/engine/predicates/query_inventory_produced_spec.rb \
  spec/services/engine/predicates/query_analyzed_spec.rb \
  spec/services/engine/predicates/query_fixes_drafted_spec.rb
git commit -m "feat: add query health artifact predicates"
```

---

## Task 3: Register Query Predicates

**Objective:** Make the new completion criteria resolvable by `Engine::PredicateRegistry`.

**Files:**
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing registry spec**

Add these expectations to `spec/services/engine/predicate_registry_spec.rb` inside `it "resolves known predicate names"`:

```ruby
expect(described_class.resolve("query_inventory_produced")).to eq(Engine::Predicates::QueryInventoryProduced)
expect(described_class.resolve("query_analyzed")).to eq(Engine::Predicates::QueryAnalyzed)
expect(described_class.resolve("query_fixes_drafted")).to eq(Engine::Predicates::QueryFixesDrafted)
```

**Step 2: Run spec to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate: query_inventory_produced` or equivalent.

**Step 3: Register predicates**

Modify `app/services/engine/predicate_registry.rb` so `PREDICATES` includes:

```ruby
"query_inventory_produced" => Predicates::QueryInventoryProduced,
"query_analyzed" => Predicates::QueryAnalyzed,
"query_fixes_drafted" => Predicates::QueryFixesDrafted,
```

Place them near the other cookbook/artifact predicates. Keep the hash frozen.

**Step 4: Run spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register query health predicates"
```

---

## Task 4: Seed Query Health Queue and Resolve Prompts

**Objective:** Add the portable queue YAML and prompt files, with a seed spec proving the queue loads correctly and prompt contents are resolved instead of persisted as `file://` strings.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Create: `config/queues/query_health.yml`
- Create: `prompts/query_collect.md`
- Create: `prompts/query_analyze.md`
- Create: `prompts/query_draft_fixes.md`

**Step 1: Write failing seed spec**

Append this example to `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the query health queue with resolved prompt files" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "query_health")
  expect(queue.name).to eq("Database Query Health Check")
  expect(queue.stages).to eq(%w[
    collect_queries
    analyze_performance
    draft_fixes
    run_tests
    human_review
    done
  ])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 2
  )

  collect = queue.stage_configs.find_by!(stage_name: "collect_queries")
  expect(collect.adapter_type).to eq("shell_script")
  expect(collect.model_override).to eq("claude-haiku-4-5-20251001")
  expect(collect.allowed_skills).to include("run_tests", "read_repo")
  expect(collect.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
  expect(collect.completion_criteria).to eq(["query_inventory_produced"])
  expect(collect.agent_prompt).to include("# Query Health Collect Queries")
  expect(collect.agent_prompt).not_to start_with("file://")
  expect(collect.adapter_config).to include(
    "output_artifact_kind" => "query_inventory",
    "fixture_app" => "test/fixtures/apps/slow_queries",
    "docker_profile" => "cookbook-query-health"
  )
  expect(collect.adapter_config["commands"].first["artifact"]).to eq("query_inventory")

  analyze = queue.stage_configs.find_by!(stage_name: "analyze_performance")
  expect(analyze.adapter_type).to eq("inline_claude")
  expect(analyze.model_override).to eq("claude-sonnet-4-20250514")
  expect(analyze.completion_criteria).to eq(["query_analyzed"])
  expect(analyze.agent_prompt).to include("# Query Health Analyze Performance")
  expect(analyze.adapter_config).to include(
    "input_artifact_kind" => "query_inventory",
    "output_artifact_kind" => "query_analysis",
    "spawn_target_queue" => "development"
  )

  draft = queue.stage_configs.find_by!(stage_name: "draft_fixes")
  expect(draft.adapter_type).to eq("inline_claude")
  expect(draft.completion_criteria).to eq(["query_fixes_drafted"])
  expect(draft.agent_prompt).to include("# Query Health Draft Fixes")
  expect(draft.adapter_config).to include(
    "input_artifact_kind" => "query_analysis",
    "output_artifact_kind" => "query_patches"
  )

  run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
  expect(run_tests.adapter_type).to eq("shell_script")
  expect(run_tests.completion_criteria).to eq(["tests_passed"])
  expect(run_tests.adapter_config).to include(
    "input_artifact_kind" => "query_patches",
    "output_artifact_kind" => "test_results",
    "docker_profile" => "cookbook-query-health"
  )

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.agent_prompt).to include("DBA")
end
```

**Step 2: Run spec to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb:116
```

Expected: FAIL because `query_health` queue does not exist.

**Step 3: Add YAML and prompt files**

Create `config/queues/query_health.yml` exactly from the YAML target section above.

Create the three prompt files exactly from the prompt target section above.

**Step 4: Run focused spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS for all seed specs, including idempotency. If the line number changed, run the full file rather than relying on the old line number.

**Step 5: Commit**

```bash
git add config/queues/query_health.yml \
  prompts/query_collect.md \
  prompts/query_analyze.md \
  prompts/query_draft_fixes.md \
  spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed query health cookbook queue"
```

---

## Task 5: Add Slow Query Fixture App Skeleton

**Objective:** Add a tiny Rails-like fixture app that exposes the four cookbook query smells for collector/e2e tests without requiring a second full app generator.

**Files:**
- Create: `test/fixtures/apps/slow_queries/README.md`
- Create: `test/fixtures/apps/slow_queries/Gemfile`
- Create: `test/fixtures/apps/slow_queries/config/routes.rb`
- Create: `test/fixtures/apps/slow_queries/app/models/author.rb`
- Create: `test/fixtures/apps/slow_queries/app/models/post.rb`
- Create: `test/fixtures/apps/slow_queries/app/models/wide_report.rb`
- Create: `test/fixtures/apps/slow_queries/app/controllers/posts_controller.rb`
- Create: `test/fixtures/apps/slow_queries/app/views/posts/index.html.erb`
- Create: `test/fixtures/apps/slow_queries/app/services/wide_report_search.rb`
- Create: `test/fixtures/apps/slow_queries/db/schema.rb`
- Create: `test/fixtures/apps/slow_queries/db/seeds.rb`
- Modify: `spec/models/work_queue_seed_spec.rb` or create a dedicated fixture spec if there is already a fixture validation pattern by implementation time.

**Step 1: Write failing fixture existence/content spec**

Prefer a dedicated new spec if no fixture validation exists:

Create `spec/fixtures/slow_queries_fixture_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "slow query fixture app" do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/slow_queries") }

  it "contains the expected query-health smells" do
    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("app/controllers/posts_controller.rb")).to exist
    expect(fixture_root.join("app/views/posts/index.html.erb")).to exist
    expect(fixture_root.join("app/services/wide_report_search.rb")).to exist
    expect(fixture_root.join("db/schema.rb")).to exist

    controller = fixture_root.join("app/controllers/posts_controller.rb").read
    view = fixture_root.join("app/views/posts/index.html.erb").read
    search = fixture_root.join("app/services/wide_report_search.rb").read
    schema = fixture_root.join("db/schema.rb").read

    expect(controller).to include("@posts = Post.all")
    expect(view).to include("post.author.name")
    expect(controller).to include("Post.where(status:")
    expect(search).to include("WideReport.select(\"*\")")
    expect(controller).to include("post.comments.count")
    expect(schema).to include("create_table \"posts\"")
    expect(schema).not_to include("index_posts_on_status")
  end
end
```

If `spec/fixtures/` does not exist, create it with this file.

**Step 2: Run spec to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/fixtures/slow_queries_fixture_spec.rb
```

Expected: FAIL because the fixture files do not exist.

**Step 3: Create fixture files**

`test/fixtures/apps/slow_queries/README.md`:

```markdown
# Slow Queries Fixture App

This fixture supports the `query_health` cookbook. It is intentionally small and Rails-like rather than a complete generated app. Query collectors should be able to scan these files without booting a second Rails application.

Intentional smells:

1. N+1 association access: `PostsController#index` assigns `@posts = Post.all`, and the view calls `post.author.name`.
2. Missing index: `PostsController#published` filters `Post.where(status: ...)`, while `db/schema.rb` has no `index_posts_on_status`.
3. Unnecessary `SELECT *`: `WideReportSearch#call` uses `WideReport.select("*")` even though callers only need two columns.
4. Counter query: the posts index view calls `post.comments.count` instead of using a counter cache.
```

`test/fixtures/apps/slow_queries/Gemfile`:

```ruby
source "https://rubygems.org"

gem "rails", ">= 8.0"
gem "pg"
```

`test/fixtures/apps/slow_queries/config/routes.rb`:

```ruby
Rails.application.routes.draw do
  resources :posts, only: [:index] do
    collection do
      get :published
    end
  end
end
```

`test/fixtures/apps/slow_queries/app/models/author.rb`:

```ruby
class Author < ApplicationRecord
  has_many :posts
end
```

`test/fixtures/apps/slow_queries/app/models/post.rb`:

```ruby
class Post < ApplicationRecord
  belongs_to :author
  has_many :comments
end
```

`test/fixtures/apps/slow_queries/app/models/wide_report.rb`:

```ruby
class WideReport < ApplicationRecord
end
```

`test/fixtures/apps/slow_queries/app/controllers/posts_controller.rb`:

```ruby
class PostsController < ApplicationController
  def index
    @posts = Post.all
  end

  def published
    @posts = Post.where(status: "published").order(created_at: :desc)
  end
end
```

`test/fixtures/apps/slow_queries/app/views/posts/index.html.erb`:

```erb
<% @posts.each do |post| %>
  <article>
    <h2><%= post.title %></h2>
    <p>By <%= post.author.name %></p>
    <p><%= post.comments.count %> comments</p>
  </article>
<% end %>
```

`test/fixtures/apps/slow_queries/app/services/wide_report_search.rb`:

```ruby
class WideReportSearch
  def call(account_id:)
    WideReport.select("*").where(account_id: account_id).map do |report|
      { id: report.id, title: report.title }
    end
  end
end
```

`test/fixtures/apps/slow_queries/db/schema.rb`:

```ruby
ActiveRecord::Schema[8.0].define(version: 2026_05_05_070000) do
  create_table "authors", force: :cascade do |t|
    t.string "name", null: false
    t.timestamps
  end

  create_table "posts", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.string "title", null: false
    t.string "status", null: false
    t.text "body"
    t.timestamps

    t.index ["author_id"], name: "index_posts_on_author_id"
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "post_id", null: false
    t.text "body", null: false
    t.timestamps

    t.index ["post_id"], name: "index_comments_on_post_id"
  end

  create_table "wide_reports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "title", null: false
    t.string "category"
    t.string "region"
    t.string "owner_email"
    t.jsonb "payload", default: {}, null: false
    t.text "internal_notes"
    t.timestamps

    t.index ["account_id"], name: "index_wide_reports_on_account_id"
  end
end
```

`test/fixtures/apps/slow_queries/db/seeds.rb`:

```ruby
author = Author.create!(name: "Ada")
10.times do |index|
  post = Post.create!(author: author, title: "Post #{index}", status: index.even? ? "published" : "draft", body: "Fixture")
  3.times { |comment_index| post.comments.create!(body: "Comment #{comment_index}") }
end

WideReport.create!(account_id: 1, title: "Quarterly", category: "finance", region: "NA", owner_email: "owner@example.com")
```

**Step 4: Run focused spec to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/fixtures/slow_queries_fixture_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add test/fixtures/apps/slow_queries spec/fixtures/slow_queries_fixture_spec.rb
git commit -m "test: add slow query fixture app"
```

---

## Task 6: Verify Queue, Predicates, and Fixture Together

**Objective:** Run a compact regression suite proving the cookbook seed, predicates, fixture, and existing spawn behavior remain healthy.

**Files:**
- No production edits expected.
- If failures reveal missing test coverage or bugs, return to the relevant TDD task and add a RED spec first.

**Step 1: Run focused cookbook suite**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/predicates/query_inventory_produced_spec.rb \
  spec/services/engine/predicates/query_analyzed_spec.rb \
  spec/services/engine/predicates/query_fixes_drafted_spec.rb \
  spec/services/engine/cross_queue_spawn_spec.rb \
  spec/fixtures/slow_queries_fixture_spec.rb
```

Expected: PASS.

**Step 2: Run broader safety specs if time allows**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 3: Check for hardcoded local paths**

Run:

```bash
grep -R "/Users/gregmushen/work/code/taskrail" \
  config/queues/query_health.yml \
  prompts/query_collect.md \
  prompts/query_analyze.md \
  prompts/query_draft_fixes.md \
  test/fixtures/apps/slow_queries \
  app/services/engine/predicates/query_inventory_produced.rb \
  app/services/engine/predicates/query_analyzed.rb \
  app/services/engine/predicates/query_fixes_drafted.rb \
  spec/services/engine/predicates/query_inventory_produced_spec.rb \
  spec/services/engine/predicates/query_analyzed_spec.rb \
  spec/services/engine/predicates/query_fixes_drafted_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/fixtures/slow_queries_fixture_spec.rb
```

Expected: exit code 1 with no matches.

**Step 4: Commit only if verification caused documentation/test command changes**

If Task 6 requires any cleanup commit:

```bash
git add <changed files>
git commit -m "test: verify query health cookbook queue"
```

Otherwise do not create an empty commit.

---

## Fake Docker-Friendly Infrastructure Notes

This cookbook needs these inputs from the shared cookbook infrastructure layer, but should not duplicate them:

- A safe test database or fixture-app execution context, preferably selected by a shared `docker_profile` such as `cookbook-query-health`.
- A shell adapter convention for commands that emit JSON artifacts, used here as `bin/query-health collect --format=json` and `bin/query-health apply-and-test --format=json`.
- Optional Postgres `pg_stat_statements` access in the fake/docker environment. If unavailable, `query_collect.md` explicitly allows collection notes instead of failing.
- A standard way to apply generated patch artifacts in an isolated worktree/container before running tests.

Query-health-specific fixture data lives under `test/fixtures/apps/slow_queries/`; generic Compose services, shared images, credentials, or runner scripts belong in the shared cookbook infrastructure plan.

---

## Implementation Task Checklist

Use this checklist in order:

- [ ] Task 1 RED: add failing specs for `query_inventory_produced`, `query_analyzed`, and `query_fixes_drafted`.
- [ ] Task 2 GREEN: implement the three predicate classes and commit `feat: add query health artifact predicates`.
- [ ] Task 3 RED/GREEN: register predicates in `Engine::PredicateRegistry` and commit `feat: register query health predicates`.
- [ ] Task 4 RED/GREEN: add `config/queues/query_health.yml`, three prompt files, and seed coverage; commit `feat: seed query health cookbook queue`.
- [ ] Task 5 RED/GREEN: add the slow-query fixture app and fixture spec; commit `test: add slow query fixture app`.
- [ ] Task 6 VERIFY: run the focused regression suite and hardcoded-path check.

Expected final implementation commit message if squashing the cookbook work into one commit:

```bash
git commit -m "feat: add database query health cookbook"
```

If preserving the preferred slice-by-slice workflow, keep the task-level commit messages listed above instead of squashing.

---

## Acceptance Criteria

The implementation is complete when:

- `config/queues/query_health.yml` seeds a `query_health` queue with stages `collect_queries`, `analyze_performance`, `draft_fixes`, `run_tests`, `human_review`, and `done`.
- Queue prompts are stored in `prompts/query_collect.md`, `prompts/query_analyze.md`, and `prompts/query_draft_fixes.md`, and seed specs prove `agent_prompt` values are resolved contents, not literal `file://` strings.
- New predicates `query_inventory_produced`, `query_analyzed`, and `query_fixes_drafted` are implemented, registered, and covered by focused specs that assert artifact IDs and actionable counts in evidence.
- The fixture app under `test/fixtures/apps/slow_queries/` contains an N+1 view/controller pair, an unindexed status filter, a `SELECT *` wide-table service, and a count query that should become a counter cache.
- No new file contains a hardcoded absolute checkout path.
- Focused RSpec commands pass with Greg's rbenv path.
- Cross-queue architectural changes are represented by `spawn_work_items` in `query_analyze.md` and target the existing `development` queue.
