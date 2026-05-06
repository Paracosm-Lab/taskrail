# Failure Readiness Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Turn the Proactive Failure Readiness cookbook into a maintained TaskRail cookbook slice: deterministic Sentry alert fixtures feed the existing operations queue, thin instrumentation is scored, runbook drafts are produced, instrumentation-fix work is spawned into the development queue, and the human-review gate preserves production safety.

**Architecture:** Reuse the existing `operations` queue instead of creating a duplicate queue: its `ingest_signals`, `cluster_failures`, `assess_instrumentation`, `map_runbooks`, `draft_runbook`, and human-review stages already match the source cookbook. Add cookbook-specific fixture/contract coverage around the Sentry fixtures, operations seed, response parser, cross-queue spawn, and runbook-draft predicates; add a small fake staging/runbook fixture only where it makes the cookbook runnable in local and Docker-friendly test environments. Keep queue config and prompt references portable via `Rails.root` and relative `file://prompts/...` paths.

**Tech Stack:** Rails, RSpec, seeded YAML queues, `Engine::PredicateRegistry`, `Artifact` and `Report` records, `inline_claude`, `shell_script`, `docker_compose` and `fake` adapters, Sentry JSON fixtures, bash fixture generator, Greg's rbenv Ruby setup.

**Source Spec:** `docs/cookbook-failure-readiness.md`

---

## Current Codebase Context

Relevant existing files inspected before writing this plan:

- `config/queues/operations.yml` already defines the main failure-readiness pipeline: `ingest_signals`, `cluster_failures`, `assess_instrumentation`, `map_runbooks`, `draft_runbook`, `human_review`, `staging_validation`, `publish_runbook`, `done`.
- `prompts/ops_ingest_signals.md`, `prompts/ops_cluster_failures.md`, `prompts/ops_assess_instrumentation.md`, `prompts/ops_map_runbooks.md`, and `prompts/ops_draft_runbook.md` are resolved through `db/seeds.rb` via `file://prompts/...` prompt indirection.
- `db/seeds.rb` already resolves any `agent_prompt` starting with `file://` using `Rails.root.join(relative_path).read`; do not replace this with hardcoded checkout paths.
- `spec/models/work_queue_seed_spec.rb` already verifies the operations queue stages, prompt resolution, Opus runbook drafting, and docker compose staging validation config.
- `test/fixtures/sentry/` already contains four cookbook alerts: `db_pool_timeout.json`, `db_connection_bad.json`, `null_reference.json`, and `rate_limit_thin.json`.
- `bin/generate-sentry-alerts` already dry-runs or posts Sentry store payloads from those fixtures, replacing `event_id` and `timestamp` at send time.
- `spec/system/generate_sentry_alerts_spec.rb` already covers the fixture generator and verifies the rate-limit alert stays intentionally thin.
- `app/services/engine/predicates/clusters_created.rb`, `assessment_complete.rb`, `runbook_mapped.rb`, `runbook_drafted.rb`, and `validation_passed.rb` are existing operations predicates.
- `spec/services/engine/cross_queue_spawn_spec.rb` already covers report-level `spawn_work_items` creating development work items.
- `spec/adapters/adapters/response_parser_spec.rb` covers JSON-block extraction of `spawn_work_items` from freeform agent responses.
- `cookbooks/` contains shared fake-service/Docker infrastructure and must not be duplicated.

Global implementation rules:

- Follow strict TDD from `test-driven-development`: write one failing spec, run it and confirm the expected failure, implement the smallest change, rerun the focused spec, then commit that slice.
- Use Greg's rbenv path prefix for every RSpec command:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Do not hardcode `/Users/gregmushen/work/code/taskrail` or any other absolute checkout path in queue YAML, prompts, fixtures, specs, scripts, or docs.
- Prefer existing operations predicates and queue stages. Add cookbook-specific predicates only if a failing spec proves the generic operation predicate is too weak for the cookbook contract.
- Commit after every completed implementation task. If the Kanban implementation card requests one final commit instead, squash task commits at the end.
- Shared Docker Compose services, fake Sentry servers, and reusable shell adapter mechanics belong in shared cookbook infrastructure. This cookbook may add scenario-specific fixtures, scripts, docs, and specs only.

---

## Files to Create or Modify

Create:

- `spec/system/failure_readiness_cookbook_spec.rb`
- `spec/fixtures/failure_readiness/staging/docker-compose.yml`
- `spec/fixtures/failure_readiness/staging/api/Dockerfile`
- `spec/fixtures/failure_readiness/staging/api/Gemfile`
- `spec/fixtures/failure_readiness/staging/api/config.ru`
- `spec/fixtures/failure_readiness/staging/scripts/pg_observe.sh`
- `spec/fixtures/failure_readiness/staging/scripts/verify_recovery.sh`
- `docs/cookbooks/failure-readiness.md`
- `docs/runbooks/failure-readiness/crm-postgres-unavailable.md`
- `docs/runbooks/failure-readiness/billing-rate-limit.md`

Modify:

- `spec/models/work_queue_seed_spec.rb` only if the operations seed contract needs cookbook-specific assertions not already present.
- `spec/adapters/adapters/response_parser_spec.rb` only if `spawn_work_items` extraction does not preserve enough nested payload for instrumentation-fix tasks.
- `config/queues/operations.yml` only if a failing seed spec proves the existing timeouts, artifact kinds, or staging validation config do not satisfy the cookbook.
- `prompts/ops_assess_instrumentation.md` only if a failing prompt-contract spec proves it does not require development-queue `spawn_work_items` for thin alerts.
- `prompts/ops_draft_runbook.md` only if a failing prompt-contract spec proves it does not require observe/mitigate/verify/escalate sections.

Do not modify unless a failing spec requires it:

- `db/seeds.rb` because it already resolves relative `file://` prompt paths through `Rails.root`.
- Generic adapter classes such as `Adapters::InlineClaudeAdapter`, `Adapters::DockerComposeAdapter`, or `Adapters::ShellScriptAdapter`.
- Shared `cookbooks/docker-compose.yml` or `cookbooks/fake_services/*`.

---

## Target Cookbook Contract

The Failure Readiness cookbook is complete when the implementation proves all of these with deterministic tests:

1. The existing `operations` queue can be seeded with resolved prompt files and portable config.
2. Four Sentry fixtures model the CRM database outage drill:
   - pool timeout: `ActiveRecord::ConnectionTimeoutError`, service `crm-service`, includes useful DB/request breadcrumbs.
   - connection refused: `PG::ConnectionBad`, service `crm-service`, same region/database host family as the pool timeout.
   - nil reference: `NoMethodError`, service `notification-service`.
   - thin rate limit: `HTTP::TimeoutError`, service `billing-service`, deliberately missing provider/status/customer/breadcrumb context.
3. The dry-run generator emits fresh event IDs and timestamps without requiring real Sentry credentials.
4. Operations-stage artifacts can represent the source example: normalized signals, three clusters, instrumentation assessment scores, runbook mappings, and runbook drafts.
5. Thin instrumentation assessment reports can spawn exactly three development work items with inline specs for Sentry context/breadcrumb fixes.
6. Drafted runbooks include operationally useful `observe`, `mitigate`, `verify`, and `escalate` sections.
7. Human review remains a gate before staging validation and publish stages.
8. No new file contains an absolute checkout path.

---

### Task 1: Add a deterministic cookbook fixture contract spec

**Objective:** Prove the Sentry fixture set models the cookbook drill and catches accidental changes that would make alerts too rich or too thin.

**Files:**
- Create: `spec/system/failure_readiness_cookbook_spec.rb`
- Read-only fixture inputs: `test/fixtures/sentry/*.json`

**Step 1: Write failing test**

Create `spec/system/failure_readiness_cookbook_spec.rb` with only the fixture contract examples first:

```ruby
require "rails_helper"
require "json"

RSpec.describe "failure readiness cookbook" do
  let(:fixture_root) { Rails.root.join("test/fixtures/sentry") }

  def fixture(name)
    JSON.parse(fixture_root.join(name).read)
  end

  it "ships the four alert fixtures used by the CRM database outage drill" do
    expected = {
      "db_pool_timeout.json" => ["ActiveRecord::ConnectionTimeoutError", "crm-service"],
      "db_connection_bad.json" => ["PG::ConnectionBad", "crm-service"],
      "null_reference.json" => ["NoMethodError", "notification-service"],
      "rate_limit_thin.json" => ["HTTP::TimeoutError", "billing-service"]
    }

    expected.each do |filename, (exception_type, service)|
      payload = fixture(filename)

      expect(payload.fetch("platform")).to eq("ruby")
      expect(payload.fetch("level")).to eq("error")
      expect(payload.fetch("timestamp")).to eq("REPLACED_AT_SEND_TIME")
      expect(payload.dig("exception", "values", 0, "type")).to eq(exception_type)
      expect(payload.dig("tags", "service")).to eq(service)
      expect(payload.dig("tags", "environment")).to eq("staging")
    end
  end

  it "keeps CRM database alerts correlated enough for causal clustering" do
    pool = fixture("db_pool_timeout.json")
    refused = fixture("db_connection_bad.json")

    expect(pool.dig("tags", "service")).to eq("crm-service")
    expect(refused.dig("tags", "service")).to eq("crm-service")
    expect(pool.dig("tags", "region")).to eq(refused.dig("tags", "region"))
    expect(pool.dig("tags", "database_host")).to eq("crm-postgres.internal")
    expect(refused.dig("tags", "database_host")).to eq("crm-postgres.internal")
    expect(pool.dig("exception", "values", 0, "stacktrace", "frames").to_json).to include("sessions_controller.rb")
    expect(refused.dig("exception", "values", 0, "stacktrace", "frames").to_json).to include("database.yml")
  end

  it "keeps billing rate limit intentionally thin for instrumentation scoring" do
    rate_limit = fixture("rate_limit_thin.json")

    expect(rate_limit.dig("exception", "values", 0, "type")).to eq("HTTP::TimeoutError")
    expect(rate_limit.dig("exception", "values", 0, "value")).to eq("rate limit exceeded")
    expect(rate_limit).not_to have_key("contexts")
    expect(rate_limit).not_to have_key("breadcrumbs")
    expect(rate_limit.fetch("tags").keys).to contain_exactly("service", "environment")
  end
end
```

**Step 2: Run test to verify RED or characterization**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: if the current fixtures already satisfy the intended contract, this may PASS as a characterization test. If it fails, the expected failure should identify a fixture contract gap such as a missing `database_host` tag or the rate-limit fixture being too rich.

**Step 3: Fix fixtures only if the spec is RED**

If the spec fails because the fixture contract is missing source-spec details, update only the affected JSON fixture in `test/fixtures/sentry/`.

Do not add real credentials, real customer PII, or production hostnames. Use fake values from the source spec such as `crm-postgres.internal`, `tenant_42`, `cus_abc123`, and `inv_xyz789` only in fixture content.

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/system/failure_readiness_cookbook_spec.rb test/fixtures/sentry
git commit -m "test: cover failure readiness alert fixtures"
```

If no fixture files changed, commit only `spec/system/failure_readiness_cookbook_spec.rb`.

---

### Task 2: Add operations queue cookbook seed coverage

**Objective:** Prove the seeded operations queue is the cookbook pipeline and preserves the human-review safety gate.

**Files:**
- Modify: `spec/system/failure_readiness_cookbook_spec.rb`
- Modify only if RED: `spec/models/work_queue_seed_spec.rb`
- Modify only if RED: `config/queues/operations.yml`

**Step 1: Write failing seed/contract test**

Append to `spec/system/failure_readiness_cookbook_spec.rb`:

```ruby
it "seeds the operations queue as the failure-readiness pipeline" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "operations")
  expect(queue.stages).to eq(%w[
    ingest_signals
    cluster_failures
    assess_instrumentation
    map_runbooks
    draft_runbook
    human_review
    staging_validation
    publish_runbook
    done
  ])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)

  ingest = queue.stage_configs.find_by!(stage_name: "ingest_signals")
  expect(ingest.adapter_type).to eq("inline_claude")
  expect(ingest.model_override).to eq("claude-haiku-4-5-20251001")
  expect(ingest.completion_criteria).to eq(["report_present"])
  expect(ingest.agent_prompt).to include("# Ops Ingest Signals")
  expect(ingest.agent_prompt).not_to start_with("file://")

  cluster = queue.stage_configs.find_by!(stage_name: "cluster_failures")
  expect(cluster.model_override).to eq("claude-sonnet-4-20250514")
  expect(cluster.completion_criteria).to eq(["clusters_created"])
  expect(cluster.adapter_config).to include("output_artifact_kind" => "clusters")

  assess = queue.stage_configs.find_by!(stage_name: "assess_instrumentation")
  expect(assess.completion_criteria).to eq(["assessment_complete"])
  expect(assess.adapter_config).to include("output_artifact_kind" => "instrumentation_assessment")
  expect(assess.agent_prompt).to include("spawn_work_items")
  expect(assess.agent_prompt).to include("development")

  map = queue.stage_configs.find_by!(stage_name: "map_runbooks")
  expect(map.completion_criteria).to eq(["runbook_mapped"])
  expect(map.adapter_config).to include("output_artifact_kind" => "runbook_mapping")

  draft = queue.stage_configs.find_by!(stage_name: "draft_runbook")
  expect(draft.model_override).to eq("claude-opus-4-20250514")
  expect(draft.completion_criteria).to eq(["runbook_drafted"])
  expect(draft.agent_prompt).to include("Observe")
  expect(draft.agent_prompt).to include("Mitigate")
  expect(draft.agent_prompt).to include("Verify")

  review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(review.adapter_type).to eq("fake")
  expect(review.timeout_seconds).to eq(86_400)

  staging = queue.stage_configs.find_by!(stage_name: "staging_validation")
  expect(staging.adapter_type).to eq("docker_compose")
  expect(staging.completion_criteria).to eq(["validation_passed"])
  expect(staging.adapter_config).not_to have_key("working_directory")

  serialized = Rails.root.join("config/queues/operations.yml").read
  expect(serialized).not_to include(Rails.root.to_s)
  expect(serialized).not_to include("/Users/")
  expect(serialized).to include("file://prompts/ops_ingest_signals.md")
end
```

**Step 2: Run test to verify RED or characterization**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: PASS if existing prompts/config already require the cookbook contract. If RED, expected failures should point to missing prompt terms such as `spawn_work_items`, `Observe`, `Mitigate`, or `Verify`.

**Step 3: Implement minimal config/prompt fixes if needed**

If the spec fails:

- Update `prompts/ops_assess_instrumentation.md` to explicitly require a top-level `spawn_work_items` array for clusters scoring below threshold, with `queue_slug: development`, `title`, `spec_inline`, and `tags`.
- Update `prompts/ops_draft_runbook.md` to explicitly require runbook drafts with `observe`, `mitigate`, `verify`, and `escalation` sections.
- Update `config/queues/operations.yml` only if it has a hardcoded path or missing artifact kind.

Keep all prompt paths relative. Do not add `working_directory` to queue YAML unless a focused adapter spec proves it is required.

**Step 4: Run focused seed and cookbook specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/system/failure_readiness_cookbook_spec.rb \
  spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/system/failure_readiness_cookbook_spec.rb spec/models/work_queue_seed_spec.rb config/queues/operations.yml prompts/ops_assess_instrumentation.md prompts/ops_draft_runbook.md
git commit -m "test: lock failure readiness operations queue contract"
```

Only stage files that actually changed.

---

### Task 3: Add a deterministic pipeline artifact contract test

**Objective:** Prove the cookbook's source example can be represented by existing operations predicates and artifacts without invoking real Claude.

**Files:**
- Modify: `spec/system/failure_readiness_cookbook_spec.rb`

**Step 1: Write failing test**

Append this deterministic artifact contract example:

```ruby
it "models the CRM drill artifacts through the operations predicates" do
  load Rails.root.join("db/seeds.rb")
  queue = WorkQueue.find_by!(slug: "operations")
  item = WorkItem.create!(
    work_queue: queue,
    title: "Failure readiness drill: CRM database outage",
    spec_url: "test://crm-db-drill",
    stage_name: "cluster_failures"
  )

  cluster_claim = Claim.create!(work_item: item, stage_name: "cluster_failures", agent_type: "fake", status: "completed", started_at: Time.current)
  clusters = Artifact.create!(
    work_item: item,
    claim: cluster_claim,
    kind: "clusters",
    data: {
      "clusters" => [
        { "id" => "crm-postgres-unavailable", "severity" => "high", "alerts" => ["db_pool_timeout", "db_connection_bad"] },
        { "id" => "notification-nil-reference", "severity" => "medium", "alerts" => ["null_reference"] },
        { "id" => "billing-rate-limit", "severity" => "low", "alerts" => ["rate_limit_thin"] }
      ]
    }
  )

  cluster_result = Engine::Predicates::ClustersCreated.new(claim: cluster_claim).call
  expect(cluster_result).to be_passed
  expect(cluster_result.evidence).to include(artifact_id: clusters.id)

  item.update!(stage_name: "assess_instrumentation")
  assess_claim = Claim.create!(work_item: item, stage_name: "assess_instrumentation", agent_type: "fake", status: "completed", started_at: Time.current)
  assessment = Artifact.create!(
    work_item: item,
    claim: assess_claim,
    kind: "instrumentation_assessment",
    data: {
      "scores" => [
        { "cluster_id" => "crm-postgres-unavailable", "score" => 2.2, "verdict" => "thin" },
        { "cluster_id" => "notification-nil-reference", "score" => 2.0, "verdict" => "thin" },
        { "cluster_id" => "billing-rate-limit", "score" => 1.2, "verdict" => "thin" }
      ]
    }
  )

  assessment_result = Engine::Predicates::AssessmentComplete.new(claim: assess_claim).call
  expect(assessment_result).to be_passed
  expect(assessment_result.evidence).to eq({ artifact_id: assessment.id })

  item.update!(stage_name: "map_runbooks")
  map_claim = Claim.create!(work_item: item, stage_name: "map_runbooks", agent_type: "fake", status: "completed", started_at: Time.current)
  mapping = Artifact.create!(
    work_item: item,
    claim: map_claim,
    kind: "runbook_mapping",
    data: {
      "mappings" => [
        { "cluster_id" => "crm-postgres-unavailable", "status" => "missing" },
        { "cluster_id" => "notification-nil-reference", "status" => "missing" },
        { "cluster_id" => "billing-rate-limit", "status" => "missing" }
      ]
    }
  )

  mapping_result = Engine::Predicates::RunbookMapped.new(claim: map_claim).call
  expect(mapping_result).to be_passed
  expect(mapping_result.evidence).to include(artifact_id: mapping.id)
end
```

**Step 2: Run RED verification**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: PASS if existing predicates accept these artifact shapes. If RED, implement the minimal predicate fix with a narrower focused spec first. For example, if `RunbookMapped` requires a different key than `mappings`, add or update `spec/services/engine/predicates/runbook_mapped_spec.rb` before changing production predicate code.

**Step 3: Fix only proven predicate gaps**

If a predicate fix is required, keep evidence actionable:

```ruby
PredicateResult.pass(evidence: { artifact_id: artifact.id, mapping_count: mappings.count })
```

Avoid broad schema validation unless the source spec requires it; this is a cookbook contract, not a general artifact schema system.

**Step 4: Run focused specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/system/failure_readiness_cookbook_spec.rb \
  spec/services/engine/predicates/clusters_created_spec.rb \
  spec/services/engine/predicates/assessment_complete_spec.rb \
  spec/services/engine/predicates/runbook_mapped_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/system/failure_readiness_cookbook_spec.rb app/services/engine/predicates spec/services/engine/predicates
git commit -m "test: cover failure readiness operations artifacts"
```

Only include predicate files/specs if they changed.

---

### Task 4: Add cross-queue instrumentation-fix spawn contract

**Objective:** Prove a thin instrumentation report spawns specific development work items for all three cookbook clusters.

**Files:**
- Modify: `spec/system/failure_readiness_cookbook_spec.rb`
- Modify only if RED: `spec/adapters/adapters/response_parser_spec.rb`
- Modify only if RED: `app/services/engine/transition_manager.rb` or `app/adapters/.../response_parser.rb` matching existing file location

**Step 1: Write failing test**

Append:

```ruby
it "spawns development instrumentation fixes for thin alert clusters" do
  ops_queue = WorkQueue.create!(name: "Operations", slug: "ops-failure-readiness-#{SecureRandom.hex(4)}", stages: %w[assess_instrumentation map_runbooks done])
  ops_queue.stage_configs.create!(stage_name: "assess_instrumentation", adapter_type: "fake", completion_criteria: %w[report_present])
  ops_queue.stage_configs.create!(stage_name: "map_runbooks", adapter_type: "fake")
  dev_queue = WorkQueue.create!(name: "Development", slug: "development", stages: %w[intake build test done])

  item = WorkItem.create!(work_queue: ops_queue, title: "CRM failure drill", spec_url: "test://crm-db-drill", stage_name: "assess_instrumentation")
  claim = Claim.create!(work_item: item, stage_name: "assess_instrumentation", agent_type: "fake", status: "completed", started_at: Time.current)
  Report.create!(
    work_item: item,
    claim: claim,
    stage_name: "assess_instrumentation",
    status: "success",
    body: {
      "spawn_work_items" => [
        {
          "queue_slug" => dev_queue.slug,
          "title" => "Improve crm-service database outage Sentry context",
          "spec_inline" => "Add request_id, tenant_id, database_host, pool stats, pg_stat summary, and breadcrumbs for ActiveRecord::ConnectionTimeoutError and PG::ConnectionBad paths.",
          "tags" => { "domain" => "failure_readiness", "cluster_id" => "crm-postgres-unavailable" }
        },
        {
          "queue_slug" => dev_queue.slug,
          "title" => "Improve notification-service nil reference alert context",
          "spec_inline" => "Add upstream dependency, lookup key, customer/account context, and breadcrumb evidence around nil lookup failures.",
          "tags" => { "domain" => "failure_readiness", "cluster_id" => "notification-nil-reference" }
        },
        {
          "queue_slug" => dev_queue.slug,
          "title" => "Improve billing-service rate limit instrumentation",
          "spec_inline" => "Replace misleading HTTP::TimeoutError with a rate-limit-specific error and add provider, http_status, retry_after, payment IDs, idempotency key, and request breadcrumbs.",
          "tags" => { "domain" => "failure_readiness", "cluster_id" => "billing-rate-limit" }
        }
      ]
    }
  )

  stage_config = ops_queue.stage_configs.find_by!(stage_name: "assess_instrumentation")
  Engine::TransitionManager.new(work_item: item, claim: claim, stage_config: stage_config).call

  expect(item.reload.stage_name).to eq("map_runbooks")
  spawned = WorkItem.where(work_queue: dev_queue).order(:title)
  expect(spawned.count).to eq(3)
  expect(spawned.map(&:title)).to include(
    "Improve billing-service rate limit instrumentation",
    "Improve crm-service database outage Sentry context",
    "Improve notification-service nil reference alert context"
  )
  expect(spawned.map { |work_item| work_item.tags["domain"] }.uniq).to eq(["failure_readiness"])
  expect(spawned.map { |work_item| work_item.metadata["spec_inline"] }).to all(include("context"))
end
```

**Step 2: Run test to verify RED or GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: PASS if current cross-queue spawn supports the cookbook payload. If RED, expected failures should point to malformed tags/metadata handling or a slug collision with already seeded `development` records.

**Step 3: Fix only proven spawn gaps**

If the failure is due to the test's hardcoded `development` slug colliding with seeded data, adjust the test to seed through `load Rails.root.join("db/seeds.rb")` and use `WorkQueue.find_by!(slug: "development")`.

If the failure is real production behavior, add a focused RED spec to `spec/services/engine/cross_queue_spawn_spec.rb` or `spec/adapters/adapters/response_parser_spec.rb` first, then implement the minimal parser/transition fix.

**Step 4: Run focused spawn specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/system/failure_readiness_cookbook_spec.rb \
  spec/services/engine/cross_queue_spawn_spec.rb \
  spec/adapters/adapters/response_parser_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/system/failure_readiness_cookbook_spec.rb spec/services/engine/cross_queue_spawn_spec.rb spec/adapters/adapters/response_parser_spec.rb app/services/engine/transition_manager.rb app/adapters
git commit -m "test: cover failure readiness instrumentation spawns"
```

Only include files that changed.

---

### Task 5: Add runbook draft contract and seed example runbooks

**Objective:** Provide deterministic runbook examples for human review and future staging validation without pretending they are production-approved.

**Files:**
- Modify: `spec/system/failure_readiness_cookbook_spec.rb`
- Create: `docs/runbooks/failure-readiness/crm-postgres-unavailable.md`
- Create: `docs/runbooks/failure-readiness/billing-rate-limit.md`

**Step 1: Write failing tests**

Append:

```ruby
it "stores example runbooks with observe mitigate verify and escalation sections" do
  root = Rails.root.join("docs/runbooks/failure-readiness")

  postgres = root.join("crm-postgres-unavailable.md")
  billing = root.join("billing-rate-limit.md")
  expect(postgres).to exist
  expect(billing).to exist

  [postgres, billing].each do |path|
    content = path.read
    expect(content).to include("## Scope")
    expect(content).to include("## Observe")
    expect(content).to include("## Mitigate")
    expect(content).to include("## Verify")
    expect(content).to include("## Escalate")
    expect(content).to include("Human review required")
    expect(content).not_to include(Rails.root.to_s)
    expect(content).not_to include("/Users/")
  end

  expect(postgres.read).to include("pg_isready -h crm-postgres.internal -p 5432")
  expect(postgres.read).to include("idle_in_transaction")
  expect(billing.read).to include("Retry-After")
  expect(billing.read).to include("idempotency")
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: FAIL because the runbook files do not exist.

**Step 3: Create Postgres outage runbook**

Create `docs/runbooks/failure-readiness/crm-postgres-unavailable.md`:

```markdown
# Runbook Draft: CRM Postgres Unavailable

Human review required before production use.

## Scope

Failure Readiness cookbook fixture for `crm-service` staging alerts involving `ActiveRecord::ConnectionTimeoutError` and `PG::ConnectionBad` against `crm-postgres.internal`.

## Observe

```bash
pg_isready -h crm-postgres.internal -p 5432
psql "$CRM_DATABASE_URL" -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"
psql "$CRM_DATABASE_URL" -c "SELECT pid, now() - xact_start AS age, query FROM pg_stat_activity WHERE state = 'idle in transaction' ORDER BY age DESC LIMIT 10;"
```

Check alert context for `pool_size`, `checked_out`, `waiting`, `active_connections`, `max_connections`, and `idle_in_transaction`.

## Mitigate

1. If Postgres is down, page the database owner and restart only through the approved staging/prod database control plane.
2. If `idle_in_transaction` is above the reviewed threshold, terminate sessions older than five minutes after confirming they are safe.
3. If app pools do not drain after database recovery, perform a rolling app restart.

## Verify

```bash
curl -fsS https://crm.staging.scribbl.test/health
curl -fsS -X POST https://crm.staging.scribbl.test/sessions -d '{"token":"fixture"}'
```

Monitor Sentry for 15 minutes and confirm pool stats return to idle capacity.

## Escalate

Escalate to DBA for unavailable Postgres, connection saturation by active queries, or unsafe session termination. Escalate to incident commander if customer-facing outage lasts more than 30 minutes.
```

**Step 4: Create billing rate-limit runbook**

Create `docs/runbooks/failure-readiness/billing-rate-limit.md`:

```markdown
# Runbook Draft: Billing Provider Rate Limit

Human review required before production use.

## Scope

Failure Readiness cookbook fixture for thin `billing-service` rate-limit alerts. The initial alert may incorrectly appear as `HTTP::TimeoutError`; improved instrumentation should emit a provider-specific rate-limit error.

## Observe

```bash
bin/rails runner 'puts Billing::ProviderStatus.summary(provider: "stripe")'
bin/rails runner 'puts Billing::RetryQueue.recent_failures(limit: 20)'
```

Check alert tags/context for `provider`, `http_status`, `Retry-After`, `rate_limit_tier`, customer ID, invoice ID, amount, and idempotency key.

## Mitigate

1. Stop immediate retry storms and confirm exponential backoff honors `Retry-After`.
2. Pause non-critical billing jobs if the provider limit is global.
3. Resume jobs gradually after the provider window clears.

## Verify

Confirm successful provider calls, stable retry queue depth, and no new 429 events for 15 minutes.

## Escalate

Escalate to payments owner when rate limits affect live charges, idempotency is missing, or the provider limit does not recover after the documented window.
```

**Step 5: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git add spec/system/failure_readiness_cookbook_spec.rb docs/runbooks/failure-readiness/crm-postgres-unavailable.md docs/runbooks/failure-readiness/billing-rate-limit.md
git commit -m "docs: add failure readiness runbook drafts"
```

---

### Task 6: Add fake Docker-friendly staging fixture

**Objective:** Provide a tiny staging fixture that can be used by future `staging_validation` work without introducing production dependencies or duplicating shared infrastructure.

**Files:**
- Create: `spec/fixtures/failure_readiness/staging/docker-compose.yml`
- Create: `spec/fixtures/failure_readiness/staging/api/Dockerfile`
- Create: `spec/fixtures/failure_readiness/staging/api/Gemfile`
- Create: `spec/fixtures/failure_readiness/staging/api/config.ru`
- Create: `spec/fixtures/failure_readiness/staging/scripts/pg_observe.sh`
- Create: `spec/fixtures/failure_readiness/staging/scripts/verify_recovery.sh`
- Modify: `spec/system/failure_readiness_cookbook_spec.rb`

**Step 1: Write failing fixture smoke spec**

Append:

```ruby
it "provides a Docker-friendly staging fixture for runbook validation" do
  root = Rails.root.join("spec/fixtures/failure_readiness/staging")

  expect(root.join("docker-compose.yml")).to exist
  expect(root.join("api/config.ru")).to exist
  expect(root.join("scripts/pg_observe.sh")).to exist
  expect(root.join("scripts/verify_recovery.sh")).to exist

  compose = YAML.load_file(root.join("docker-compose.yml"))
  expect(compose.fetch("services").keys).to include("failure-api", "failure-postgres")
  expect(root.join("docker-compose.yml").read).to include("${FAILURE_READINESS_API_PORT:-3938}")
  expect(root.join("docker-compose.yml").read).not_to include(Rails.root.to_s)

  expect(root.join("scripts/pg_observe.sh").read).to include("pg_isready")
  expect(root.join("scripts/verify_recovery.sh").read).to include("service_healthy")
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: FAIL because fixture files do not exist.

**Step 3: Create Docker Compose fixture**

Create `spec/fixtures/failure_readiness/staging/docker-compose.yml`:

```yaml
services:
  failure-api:
    build: ./spec/fixtures/failure_readiness/staging/api
    environment:
      RACK_ENV: staging
      DATABASE_HOST: failure-postgres
    ports:
      - "127.0.0.1:${FAILURE_READINESS_API_PORT:-3938}:9292"
    depends_on:
      - failure-postgres
  failure-postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: failure_readiness_staging
    ports:
      - "127.0.0.1:${FAILURE_READINESS_POSTGRES_PORT:-55438}:5432"
```

**Step 4: Create fake API files**

Create `spec/fixtures/failure_readiness/staging/api/Gemfile`:

```ruby
source "https://rubygems.org"
gem "rack", "~> 3.0"
gem "puma", "~> 6.4"
```

Create `spec/fixtures/failure_readiness/staging/api/Dockerfile`:

```dockerfile
FROM ruby:3.3-alpine
WORKDIR /app
COPY Gemfile /app/Gemfile
RUN bundle install
COPY config.ru /app/config.ru
CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0", "-p", "9292"]
```

Create `spec/fixtures/failure_readiness/staging/api/config.ru`:

```ruby
require "json"

run lambda { |env|
  case env["PATH_INFO"]
  when "/health"
    [200, { "content-type" => "application/json" }, [JSON.generate(ok: true, service: "failure-api")]]
  when "/sessions"
    [200, { "content-type" => "application/json" }, [JSON.generate(ok: true, action: "session-created")]]
  else
    [404, { "content-type" => "application/json" }, [JSON.generate(error: "not_found")]]
  end
}
```

**Step 5: Create deterministic fixture scripts**

Create `spec/fixtures/failure_readiness/staging/scripts/pg_observe.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
pg_isready -h "${FAILURE_READINESS_POSTGRES_HOST:-127.0.0.1}" -p "${FAILURE_READINESS_POSTGRES_PORT:-55438}" || true
cat <<'JSON'
{"active_connections":3,"max_connections":100,"idle_in_transaction":0,"pool_waiting":0}
JSON
```

Create `spec/fixtures/failure_readiness/staging/scripts/verify_recovery.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cat <<'JSON'
{"service_healthy":true,"checks":[{"name":"api_health","passed":true},{"name":"postgres_ready","passed":true}]}
JSON
```

Make scripts executable:

```bash
chmod +x spec/fixtures/failure_readiness/staging/scripts/pg_observe.sh \
  spec/fixtures/failure_readiness/staging/scripts/verify_recovery.sh
```

**Step 6: Run focused test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: PASS. Do not start Docker in this unit/system spec; YAML parsing and script content are enough.

**Step 7: Commit**

```bash
git add spec/system/failure_readiness_cookbook_spec.rb spec/fixtures/failure_readiness/staging
git commit -m "test: add failure readiness staging fixture"
```

---

### Task 7: Add user-facing cookbook documentation

**Objective:** Document how to run the Failure Readiness cookbook and how to interpret the pipeline output.

**Files:**
- Create: `docs/cookbooks/failure-readiness.md`
- Modify: `spec/system/failure_readiness_cookbook_spec.rb`

**Step 1: Write failing docs spec**

Append:

```ruby
it "documents how to run and interpret the failure readiness cookbook" do
  doc = Rails.root.join("docs/cookbooks/failure-readiness.md")
  expect(doc).to exist

  content = doc.read
  expect(content).to include("# Failure Readiness Cookbook")
  expect(content).to include("docs/cookbook-failure-readiness.md")
  expect(content).to include("bin/generate-sentry-alerts --dry-run")
  expect(content).to include("operations")
  expect(content).to include("human_review")
  expect(content).to include("spawn_work_items")
  expect(content).to include("docs/runbooks/failure-readiness")
  expect(content).not_to include(Rails.root.to_s)
  expect(content).not_to include("/Users/")
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: FAIL because the cookbook doc does not exist.

**Step 3: Create docs**

Create `docs/cookbooks/failure-readiness.md`:

```markdown
# Failure Readiness Cookbook

Source spec: `docs/cookbook-failure-readiness.md`

Failure Readiness runs a proactive incident drill before production breaks. It simulates realistic Sentry alerts, feeds them through the `operations` queue, clusters related failures, scores alert instrumentation, drafts runbooks, and spawns development work for thin alerts.

## Stages

1. `ingest_signals`: normalize Sentry events into operational signals.
2. `cluster_failures`: group related failures such as CRM Postgres connection refusal and pool exhaustion.
3. `assess_instrumentation`: score error specificity, context richness, breadcrumbs, reproducibility, and structured metadata. Thin alerts should emit `spawn_work_items` targeting the `development` queue.
4. `map_runbooks`: find matching runbooks or mark them missing/stale.
5. `draft_runbook`: draft observe, mitigate, verify, and escalation steps.
6. `human_review`: gate before staging validation or publishing.
7. `staging_validation`: execute approved runbooks against safe staging/fake infrastructure.
8. `publish_runbook`: write approved runbooks to the service docs convention.

## Fixtures

Sentry fixtures live in `test/fixtures/sentry/`:

- `db_pool_timeout.json`
- `db_connection_bad.json`
- `null_reference.json`
- `rate_limit_thin.json`

Dry-run fixture generation:

```bash
bin/generate-sentry-alerts --alert all --dry-run
```

Use `--dsn` or `SENTRY_DSN` only when intentionally posting to a non-production Sentry project.

## Example runbooks

Draft example runbooks for this cookbook live in `docs/runbooks/failure-readiness/`. They are not production-approved; each includes `Human review required` until an operator validates commands, access, and escalation ownership.

## Focused verification

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/system/failure_readiness_cookbook_spec.rb \
  spec/system/generate_sentry_alerts_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/cross_queue_spawn_spec.rb \
  spec/adapters/adapters/response_parser_spec.rb
```

## Safety notes

- Never run generated runbooks against production without human review.
- Keep fixture paths repo-relative.
- Keep fake staging ports configurable with environment variables.
- Do not store real Sentry credentials in fixtures, docs, queue YAML, or tests.
```

**Step 4: Run focused test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/system/failure_readiness_cookbook_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add spec/system/failure_readiness_cookbook_spec.rb docs/cookbooks/failure-readiness.md
git commit -m "docs: document failure readiness cookbook"
```

---

### Task 8: Run final focused verification

**Objective:** Verify the cookbook contract, generator, seed config, spawn behavior, and portability checks together.

**Files:**
- No new files expected.
- If verification reveals a bug, go back to the relevant task, add or update a RED spec first, then fix.

**Step 1: Run focused cookbook suite**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/system/failure_readiness_cookbook_spec.rb \
  spec/system/generate_sentry_alerts_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicates/clusters_created_spec.rb \
  spec/services/engine/predicates/assessment_complete_spec.rb \
  spec/services/engine/predicates/runbook_mapped_spec.rb \
  spec/services/engine/predicates/runbook_drafted_spec.rb \
  spec/services/engine/cross_queue_spawn_spec.rb \
  spec/adapters/adapters/response_parser_spec.rb
```

Expected: PASS.

**Step 2: Run broader engine safety suite if time allows**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine spec/models/work_queue_seed_spec.rb
```

Expected: PASS. If unrelated pre-existing failures appear, record exact failure names and rerun the focused cookbook suite before handing off.

**Step 3: Verify no hardcoded checkout paths in new/changed cookbook files**

Run:

```bash
ruby -e 'paths = ["spec/system/failure_readiness_cookbook_spec.rb"] + Dir["spec/fixtures/failure_readiness/**/*"].select { |p| File.file?(p) } + Dir["docs/runbooks/failure-readiness/*.md"] + ["docs/cookbooks/failure-readiness.md", "config/queues/operations.yml", "prompts/ops_assess_instrumentation.md", "prompts/ops_draft_runbook.md"]; bad = paths.select { |p| File.exist?(p) && File.read(p).include?("/Users/gregmushen/work/code/taskrail") }; abort("hardcoded paths: #{bad.join(", ")}") unless bad.empty?; puts "portable paths ok"'
```

Expected: `portable paths ok`.

**Step 4: Verify git state before final handoff**

Run:

```bash
git status --short
```

Expected: only unrelated pre-existing worktree changes should remain. If any Failure Readiness files are modified, commit them with the appropriate task-level commit message before handing off.

---

## Fake Docker-Friendly Infrastructure Notes

This cookbook should be runnable without real production dependencies:

- Use `test/fixtures/sentry/*.json` and `bin/generate-sentry-alerts --dry-run` for deterministic alert generation.
- Use `spec/fixtures/failure_readiness/staging/docker-compose.yml` only as a safe validation target. Do not connect it to real Sentry, real Postgres, or production services.
- Keep ports configurable: `FAILURE_READINESS_API_PORT` and `FAILURE_READINESS_POSTGRES_PORT`.
- Scripts under `spec/fixtures/failure_readiness/staging/scripts/` should print deterministic JSON and should be safe to run repeatedly.
- Operations queue YAML should continue to use repo-relative prompt paths and should not specify absolute `working_directory` values.

---

## Implementation Task Checklist

- [ ] Task 1 RED/GREEN: add fixture contract coverage for the four Sentry alert fixtures.
- [ ] Task 2 RED/GREEN: lock the operations queue seed/prompt contract for Failure Readiness.
- [ ] Task 3 RED/GREEN: prove deterministic operation artifacts satisfy clustering, assessment, and runbook mapping predicates.
- [ ] Task 4 RED/GREEN: prove thin instrumentation reports spawn three development work items.
- [ ] Task 5 RED/GREEN: add example draft runbooks with observe/mitigate/verify/escalate sections.
- [ ] Task 6 RED/GREEN: add fake Docker-friendly staging fixture and deterministic helper scripts.
- [ ] Task 7 RED/GREEN: add user-facing cookbook docs.
- [ ] Task 8 VERIFY: run the focused cookbook suite and portability check.

Expected final implementation commit message if squashing the cookbook work into one commit:

```bash
git commit -m "feat: add failure readiness cookbook"
```

If preserving the preferred slice-by-slice workflow, keep the task-level commit messages listed above instead of squashing.

---

## Acceptance Criteria

The implementation is complete when:

- `spec/system/failure_readiness_cookbook_spec.rb` proves the Sentry fixtures, operations queue contract, artifact contract, cross-queue spawn behavior, example runbooks, staging fixture, and docs.
- `test/fixtures/sentry/` continues to include the four source-spec alert fixtures, and `rate_limit_thin.json` remains intentionally thin.
- `bin/generate-sentry-alerts --dry-run` remains covered and emits fresh event IDs/timestamps.
- `config/queues/operations.yml` remains portable, uses resolved `file://prompts/...` prompt references, and preserves `human_review` before staging/publish stages.
- Thin instrumentation reports spawn development work items with actionable specs for CRM database context, notification nil-reference context, and billing rate-limit context.
- Draft runbooks live under `docs/runbooks/failure-readiness/` and clearly state they require human review before production use.
- Cookbook docs live at `docs/cookbooks/failure-readiness.md` and reference `docs/cookbook-failure-readiness.md`.
- Focused RSpec verification passes using Greg's rbenv command prefix.
- No new or changed cookbook file contains a hardcoded absolute checkout path.
