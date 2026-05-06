# Incident Readiness Scoring Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `incident_readiness` cookbook queue so TaskRail can inventory services, score operational readiness, identify gaps, draft improvements, and stop for human review with a standalone readiness scorecard.

**Architecture:** This cookbook is a seeded queue backed by portable YAML plus prompt files under `prompts/`. It reuses the existing `inline_claude` and `fake` adapters, adds four artifact predicates under `Engine::Predicates`, and verifies queue seeding with file prompt resolution. The implementation should not add shared Docker Compose adapter infrastructure; it should only add docker-friendly fixture inputs and document that fake/dev infrastructure comes from the shared cookbook infrastructure plan.

**Tech Stack:** Rails, RSpec, YAML queue seeds, TaskRail `WorkQueue` / `StageConfig` models, `Engine::PredicateRegistry`, `Engine::PredicateResult`, `inline_claude` adapter, fake gate stages.

**Source spec:** `docs/specs/cookbook-11-incident-readiness-scoring.md`

---

## Implementation Notes and Constraints

- Work from repository root: `/Users/gregmushen/work/code/taskrail`.
- Use strict TDD for production behavior: write the failing spec, run it and confirm the expected failure, implement the minimum change, then rerun the focused spec and related specs.
- Use Greg's Mac rbenv command prefix for focused specs:
  ```bash
  PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...
  ```
- Keep queue YAML portable. Do not hardcode `/Users/gregmushen/work/code/taskrail` or any absolute repo path in YAML, prompt files, seeds, or fixtures.
- Use `file://prompts/readiness_*.md` prompt references because `db/seeds.rb` already resolves `file://` paths relative to `Rails.root`.
- Do not duplicate shared infrastructure from the shared cookbook infrastructure plan. This plan only needs fake/docker-friendly fixture files such as `docker-compose.incident-readiness-fixture.yml` if the implementer wants an explicit fixture; it should not implement a new shared Docker adapter.
- Each task below should be committed independently during implementation if it changes production behavior. The final expected commit message for the whole cookbook slice is listed at the end.

## Files to Create or Modify

Create:
- `config/queues/incident_readiness.yml`
- `prompts/readiness_inventory.md`
- `prompts/readiness_score.md`
- `prompts/readiness_gaps.md`
- `prompts/readiness_draft_improvements.md`
- `app/services/engine/predicates/service_inventory_produced.rb`
- `app/services/engine/predicates/readiness_scored.rb`
- `app/services/engine/predicates/gaps_identified.rb`
- `app/services/engine/predicates/improvements_drafted.rb`
- `spec/services/engine/predicates/service_inventory_produced_spec.rb`
- `spec/services/engine/predicates/readiness_scored_spec.rb`
- `spec/services/engine/predicates/gaps_identified_spec.rb`
- `spec/services/engine/predicates/improvements_drafted_spec.rb`
- `spec/fixtures/incident_readiness/docker-compose.yml`
- `spec/fixtures/incident_readiness/CODEOWNERS`
- `spec/fixtures/incident_readiness/services/api/config/routes.rb`
- `spec/fixtures/incident_readiness/services/api/docs/runbooks/api-down.md`
- `spec/fixtures/incident_readiness/services/worker/README.md`
- `docs/cookbooks/incident-readiness-scoring.md`

Modify:
- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Optional only if existing docs have an index:
- `README.md` or the cookbook index doc that lists available cookbook queues.

---

### Task 1: Add seed spec for the incident_readiness queue shell

**Objective:** Define the seeded queue contract before creating YAML or prompts.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later implementation will create: `config/queues/incident_readiness.yml`

**Step 1: Write failing test**

Append this example near the existing operations queue seed spec:

```ruby
it "seeds the incident readiness queue with resolved prompt files" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "incident_readiness")
  expect(queue.name).to eq("Incident Readiness Scoring")
  expect(queue.stages).to eq(%w[
    inventory_services
    score_readiness
    identify_gaps
    draft_improvements
    human_review
    done
  ])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_max_retries" => 2,
    "default_timeout_seconds" => 600,
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 0
  )

  inventory = queue.stage_configs.find_by!(stage_name: "inventory_services")
  expect(inventory.adapter_type).to eq("inline_claude")
  expect(inventory.model_override).to eq("claude-haiku-4-5-20251001")
  expect(inventory.allowed_skills).to eq(["read_repo"])
  expect(inventory.forbidden_skills).to include("edit_files", "deploy")
  expect(inventory.completion_criteria).to eq(["service_inventory_produced"])
  expect(inventory.agent_prompt).to include("# Readiness Inventory")
  expect(inventory.agent_prompt).to include("service inventory")
  expect(inventory.agent_prompt).not_to start_with("file://")
  expect(inventory.adapter_config).to eq("output_artifact_kind" => "service_inventory")

  score = queue.stage_configs.find_by!(stage_name: "score_readiness")
  expect(score.model_override).to eq("claude-sonnet-4-20250514")
  expect(score.completion_criteria).to eq(["readiness_scored"])
  expect(score.agent_prompt).to include("# Readiness Score")
  expect(score.adapter_config).to eq("output_artifact_kind" => "readiness_scores")

  gaps = queue.stage_configs.find_by!(stage_name: "identify_gaps")
  expect(gaps.completion_criteria).to eq(["gaps_identified"])
  expect(gaps.agent_prompt).to include("# Readiness Gaps")
  expect(gaps.adapter_config).to eq("output_artifact_kind" => "gap_analysis")

  drafts = queue.stage_configs.find_by!(stage_name: "draft_improvements")
  expect(drafts.completion_criteria).to eq(["improvements_drafted"])
  expect(drafts.forbidden_skills).to eq(["deploy"])
  expect(drafts.agent_prompt).to include("# Readiness Draft Improvements")
  expect(drafts.adapter_config).to eq("output_artifact_kind" => "improvement_drafts")

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.completion_criteria).to eq(["report_present"])
  expect(human_review.timeout_seconds).to eq(86_400)
end
```

**Step 2: Run test to verify failure**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb -e "seeds the incident readiness queue with resolved prompt files"
```

Expected: FAIL with `ActiveRecord::RecordNotFound` for slug `incident_readiness`.

**Step 3: Commit the failing test only if your workflow allows RED commits**

Usually do not commit RED. Keep it unstaged until the YAML and prompts are added in Task 2.

---

### Task 2: Add portable queue YAML and prompt files

**Objective:** Seed the incident readiness queue with portable file prompt references and exact stage configuration from the cookbook spec.

**Files:**
- Create: `config/queues/incident_readiness.yml`
- Create: `prompts/readiness_inventory.md`
- Create: `prompts/readiness_score.md`
- Create: `prompts/readiness_gaps.md`
- Create: `prompts/readiness_draft_improvements.md`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Create `config/queues/incident_readiness.yml`**

Use this complete file:

```yaml
name: Incident Readiness Scoring
slug: incident_readiness
stages:
  - inventory_services
  - score_readiness
  - identify_gaps
  - draft_improvements
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
stage_configs:
  inventory_services:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [service_inventory_produced]
    agent_prompt: file://prompts/readiness_inventory.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: service_inventory
  score_readiness:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [readiness_scored]
    agent_prompt: file://prompts/readiness_score.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: readiness_scores
  identify_gaps:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [gaps_identified]
    agent_prompt: file://prompts/readiness_gaps.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: gap_analysis
  draft_improvements:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [improvements_drafted]
    agent_prompt: file://prompts/readiness_draft_improvements.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: improvement_drafts
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review readiness scorecard and improvement drafts.
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

**Step 2: Create `prompts/readiness_inventory.md`**

```markdown
# Readiness Inventory

You are the incident readiness inventory agent. Build a service inventory from the repository and infrastructure files supplied in the claim assignment.

Read-only scope:
- Inspect Docker Compose files, Kubernetes manifests, Procfiles, Rails configuration, service directories, and CODEOWNERS-style ownership files.
- Do not edit files, deploy, or mutate databases.
- Prefer relative repository paths in output.

Return an artifact of kind `service_inventory` with this shape:

```json
{
  "services": [
    {
      "name": "taskrail-api",
      "type": "web",
      "dependencies": ["postgres", "redis"],
      "deployment": "docker-compose",
      "owner": "platform",
      "repo_path": "."
    }
  ]
}
```

A service can be a web app, worker, cron job, or independently deployed component. Include at least one service when evidence supports it. If ownership is not discoverable, use `null` for `owner` and explain the missing evidence in the report.
```

**Step 3: Create `prompts/readiness_score.md`**

```markdown
# Readiness Score

You are the incident readiness scoring agent. Score each inventoried service from the `service_inventory` artifact against the operational readiness rubric.

Dimensions score 0-3 each:
- `health_checks`: `/health`, `/ready`, Docker HEALTHCHECK, Kubernetes probes, or equivalent.
- `alerting`: Sentry DSN, alert rules, PagerDuty, Slack, or escalation integrations.
- `runbooks`: docs under `docs/runbooks/` or similar and evidence they are current.
- `dashboards`: Grafana, Datadog, Prometheus dashboards, or documented dashboard links.
- `logging`: structured logging and suitable log levels.
- `error_handling`: error tracking and contextual exception capture.
- `resilience`: timeouts, retries, circuit breakers, graceful degradation.
- `documentation`: README, architecture docs, API docs, and current operational docs.

Compute `total_score` as the percentage of points earned out of 24. Assign grades: A > 80%, B 60-80%, C 40-60%, D 20-40%, F < 20%.

Return an artifact of kind `readiness_scores` with this shape:

```json
{
  "services": [
    {
      "name": "taskrail-api",
      "scores": {
        "health_checks": 3,
        "alerting": 1,
        "runbooks": 1,
        "dashboards": 0,
        "logging": 2,
        "error_handling": 2,
        "resilience": 1,
        "documentation": 2
      },
      "total_score": 50,
      "grade": "C",
      "critical_gaps": ["No dashboards configured"]
    }
  ],
  "summary": {
    "avg_score": 50,
    "worst_service": "taskrail-api",
    "best_service": "taskrail-api"
  }
}
```

Also include a human-readable scorecard in the report body using the table format from `docs/specs/cookbook-11-incident-readiness-scoring.md`.
```

**Step 4: Create `prompts/readiness_gaps.md`**

```markdown
# Readiness Gaps

You are the incident readiness gap analysis agent. Use the `readiness_scores` artifact to prioritize operational gaps.

Prioritization rules:
- User-facing web services with missing health checks or alerting outrank lower-frequency workers.
- Group platform-wide gaps once when most or all services share the same missing capability.
- Estimate effort as `quick`, `medium`, or `large`.
- Make recommendations actionable and tied to exact evidence from the scores.

Return an artifact of kind `gap_analysis` with this shape:

```json
{
  "platform_gaps": [
    { "gap": "No dashboards configured", "risk": "high", "effort": "medium", "recommendation": "Add service dashboard definitions or links" }
  ],
  "service_gaps": [
    { "service": "taskrail-api", "gap": "No dashboard", "risk": "medium", "effort": "medium", "recommendation": "Create Grafana or Datadog dashboard for API latency and errors" }
  ],
  "priority_order": ["taskrail-api:no-dashboard"]
}
```
```

**Step 5: Create `prompts/readiness_draft_improvements.md`**

```markdown
# Readiness Draft Improvements

You are the incident readiness improvement drafting agent. Use `gap_analysis` plus repository evidence to draft improvements for the top-priority quick and medium gaps.

Allowed work:
- Draft files and patches as artifact content.
- Prefer quick wins first: health check endpoints, alerting config examples, runbook drafts, and structured logging suggestions.
- For large work such as a monitoring overhaul or full runbook suite, recommend spawning a `development` or `operations` queue item rather than trying to draft everything in one claim.

Do not deploy or mutate production systems.

Return an artifact of kind `improvement_drafts` with this shape:

```json
{
  "improvements": [
    {
      "service": "taskrail-api",
      "gap_type": "dashboard",
      "description": "Draft dashboard documentation link placeholder and metrics checklist",
      "files": [
        {
          "path": "docs/runbooks/taskrail-api-dashboard.md",
          "content": "# TaskRail API Dashboard\n\nTrack latency, error rate, queue depth, and database health.\n"
        }
      ]
    }
  ]
}
```

Include a concise scorecard summary in the report so the `human_review` gate is useful even before improvements are applied.
```

**Step 6: Run seed spec to verify GREEN**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb -e "seeds the incident readiness queue with resolved prompt files"
```

Expected: PASS.

**Step 7: Run full seed spec file**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: all examples pass, including idempotency.

**Step 8: Commit**

```bash
git add spec/models/work_queue_seed_spec.rb config/queues/incident_readiness.yml prompts/readiness_inventory.md prompts/readiness_score.md prompts/readiness_gaps.md prompts/readiness_draft_improvements.md
git commit -m "feat: seed incident readiness cookbook queue"
```

---

### Task 3: Add service_inventory_produced predicate

**Objective:** Pass only when a `service_inventory` artifact exists with at least one service.

**Files:**
- Create: `spec/services/engine/predicates/service_inventory_produced_spec.rb`
- Create: `app/services/engine/predicates/service_inventory_produced.rb`

**Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ServiceInventoryProduced do
  let(:queue) { WorkQueue.create!(name: "Incident Readiness", slug: "incident-readiness", stages: %w[inventory]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit services", status: "running") }
  let(:claim) { Claim.create!(work_item: work_item, stage: "inventory", status: "running") }

  it "passes with evidence when a service inventory artifact has at least one service" do
    artifact = claim.artifacts.create!(
      kind: "service_inventory",
      data: { "services" => [{ "name" => "taskrail-api", "type" => "web" }] }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when the inventory artifact is missing" do
    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing service_inventory artifact with services")
  end

  it "fails when the inventory has no services" do
    claim.artifacts.create!(kind: "service_inventory", data: { "services" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing service_inventory artifact with services")
  end
end
```

**Step 2: Run test to verify failure**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/service_inventory_produced_spec.rb
```

Expected: FAIL with an uninitialized constant or missing file for `ServiceInventoryProduced`.

**Step 3: Implement predicate**

```ruby
module Engine
  module Predicates
    class ServiceInventoryProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "service_inventory").detect do |item|
          item.data["services"].is_a?(Array) && item.data["services"].any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing service_inventory artifact with services")
      end
    end
  end
end
```

**Step 4: Run focused spec to verify pass**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/service_inventory_produced_spec.rb
```

Expected: 3 examples pass.

**Step 5: Commit**

```bash
git add spec/services/engine/predicates/service_inventory_produced_spec.rb app/services/engine/predicates/service_inventory_produced.rb
git commit -m "feat: add service inventory predicate"
```

---

### Task 4: Add readiness_scored predicate

**Objective:** Pass only when `readiness_scores` includes one score entry per inventoried service and actionable evidence.

**Files:**
- Create: `spec/services/engine/predicates/readiness_scored_spec.rb`
- Create: `app/services/engine/predicates/readiness_scored.rb`

**Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ReadinessScored do
  let(:queue) { WorkQueue.create!(name: "Incident Readiness", slug: "incident-readiness", stages: %w[score]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit services", status: "running") }
  let(:claim) { Claim.create!(work_item: work_item, stage: "score", status: "running") }

  before do
    claim.artifacts.create!(
      kind: "service_inventory",
      data: { "services" => [{ "name" => "api" }, { "name" => "worker" }] }
    )
  end

  it "passes when every inventoried service has a readiness score" do
    artifact = claim.artifacts.create!(
      kind: "readiness_scores",
      data: {
        "services" => [
          { "name" => "api", "scores" => { "health_checks" => 3 }, "total_score" => 80, "grade" => "B" },
          { "name" => "worker", "scores" => { "health_checks" => 1 }, "total_score" => 40, "grade" => "C" }
        ],
        "summary" => { "avg_score" => 60, "worst_service" => "worker", "best_service" => "api" }
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when a service is missing a score" do
    claim.artifacts.create!(
      kind: "readiness_scores",
      data: { "services" => [{ "name" => "api", "scores" => {}, "total_score" => 80, "grade" => "B" }] }
    )

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("readiness_scores missing scores for inventoried services")
  end
end
```

**Step 2: Run test to verify failure**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/readiness_scored_spec.rb
```

Expected: FAIL with missing predicate constant.

**Step 3: Implement predicate**

```ruby
module Engine
  module Predicates
    class ReadinessScored
      def initialize(claim:)
        @claim = claim
      end

      def call
        inventory = @claim.artifacts.where(kind: "service_inventory").order(created_at: :desc).first
        scores = @claim.artifacts.where(kind: "readiness_scores").order(created_at: :desc).first
        return PredicateResult.fail(reason: "readiness_scores missing scores for inventoried services") unless inventory && scores

        inventoried_names = Array(inventory.data["services"]).filter_map { |service| service["name"] }
        scored_names = Array(scores.data["services"]).filter_map do |service|
          service["name"] if service["scores"].is_a?(Hash) && service.key?("total_score") && service["grade"].present?
        end

        if inventoried_names.any? && (inventoried_names - scored_names).empty?
          PredicateResult.pass(evidence: { artifact_id: scores.id })
        else
          PredicateResult.fail(reason: "readiness_scores missing scores for inventoried services")
        end
      end
    end
  end
end
```

**Step 4: Run focused spec to verify pass**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/readiness_scored_spec.rb
```

Expected: 2 examples pass.

**Step 5: Commit**

```bash
git add spec/services/engine/predicates/readiness_scored_spec.rb app/services/engine/predicates/readiness_scored.rb
git commit -m "feat: add readiness scored predicate"
```

---

### Task 5: Add gaps_identified predicate

**Objective:** Pass only when a `gap_analysis` artifact exists with at least one platform gap, service gap, or priority entry.

**Files:**
- Create: `spec/services/engine/predicates/gaps_identified_spec.rb`
- Create: `app/services/engine/predicates/gaps_identified.rb`

**Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::GapsIdentified do
  let(:queue) { WorkQueue.create!(name: "Incident Readiness", slug: "incident-readiness", stages: %w[gaps]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit services", status: "running") }
  let(:claim) { Claim.create!(work_item: work_item, stage: "gaps", status: "running") }

  it "passes with evidence when gap analysis contains prioritized gaps" do
    artifact = claim.artifacts.create!(
      kind: "gap_analysis",
      data: {
        "platform_gaps" => [{ "gap" => "No dashboards" }],
        "service_gaps" => [],
        "priority_order" => ["platform:no-dashboards"]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when gap analysis is absent or empty" do
    claim.artifacts.create!(kind: "gap_analysis", data: { "platform_gaps" => [], "service_gaps" => [], "priority_order" => [] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing non-empty gap_analysis artifact")
  end
end
```

**Step 2: Run test to verify failure**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/gaps_identified_spec.rb
```

Expected: FAIL with missing predicate constant.

**Step 3: Implement predicate**

```ruby
module Engine
  module Predicates
    class GapsIdentified
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "gap_analysis").detect do |item|
          Array(item.data["platform_gaps"]).any? ||
            Array(item.data["service_gaps"]).any? ||
            Array(item.data["priority_order"]).any?
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing non-empty gap_analysis artifact")
      end
    end
  end
end
```

**Step 4: Run focused spec to verify pass**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/gaps_identified_spec.rb
```

Expected: 2 examples pass.

**Step 5: Commit**

```bash
git add spec/services/engine/predicates/gaps_identified_spec.rb app/services/engine/predicates/gaps_identified.rb
git commit -m "feat: add readiness gap predicate"
```

---

### Task 6: Add improvements_drafted predicate

**Objective:** Pass only when an `improvement_drafts` artifact exists with at least one draft improvement and file content.

**Files:**
- Create: `spec/services/engine/predicates/improvements_drafted_spec.rb`
- Create: `app/services/engine/predicates/improvements_drafted.rb`

**Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ImprovementsDrafted do
  let(:queue) { WorkQueue.create!(name: "Incident Readiness", slug: "incident-readiness", stages: %w[draft]) }
  let(:work_item) { WorkItem.create!(work_queue: queue, title: "Audit services", status: "running") }
  let(:claim) { Claim.create!(work_item: work_item, stage: "draft", status: "running") }

  it "passes with evidence when at least one improvement includes file content" do
    artifact = claim.artifacts.create!(
      kind: "improvement_drafts",
      data: {
        "improvements" => [
          {
            "service" => "api",
            "gap_type" => "health_checks",
            "files" => [{ "path" => "config/routes.rb", "content" => "get '/health'" }]
          }
        ]
      }
    )

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq(artifact_id: artifact.id)
  end

  it "fails when drafts are missing file content" do
    claim.artifacts.create!(kind: "improvement_drafts", data: { "improvements" => [{ "service" => "api", "files" => [] }] })

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing improvement_drafts artifact with file content")
  end
end
```

**Step 2: Run test to verify failure**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/improvements_drafted_spec.rb
```

Expected: FAIL with missing predicate constant.

**Step 3: Implement predicate**

```ruby
module Engine
  module Predicates
    class ImprovementsDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "improvement_drafts").detect do |item|
          Array(item.data["improvements"]).any? do |improvement|
            Array(improvement["files"]).any? { |file| file["path"].present? && file["content"].present? }
          end
        end
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if artifact

        PredicateResult.fail(reason: "missing improvement_drafts artifact with file content")
      end
    end
  end
end
```

**Step 4: Run focused spec to verify pass**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/improvements_drafted_spec.rb
```

Expected: 2 examples pass.

**Step 5: Commit**

```bash
git add spec/services/engine/predicates/improvements_drafted_spec.rb app/services/engine/predicates/improvements_drafted.rb
git commit -m "feat: add improvement drafts predicate"
```

---

### Task 7: Register new predicates

**Objective:** Make the four cookbook predicates resolvable by queue completion criteria.

**Files:**
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing registry spec**

Update the known predicate example to include:

```ruby
expect(described_class.resolve("service_inventory_produced")).to eq(Engine::Predicates::ServiceInventoryProduced)
expect(described_class.resolve("readiness_scored")).to eq(Engine::Predicates::ReadinessScored)
expect(described_class.resolve("gaps_identified")).to eq(Engine::Predicates::GapsIdentified)
expect(described_class.resolve("improvements_drafted")).to eq(Engine::Predicates::ImprovementsDrafted)
```

**Step 2: Run test to verify failure**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate` for the first new predicate.

**Step 3: Register predicates**

Add these entries to `PREDICATES` in `app/services/engine/predicate_registry.rb`:

```ruby
"service_inventory_produced" => Predicates::ServiceInventoryProduced,
"readiness_scored" => Predicates::ReadinessScored,
"gaps_identified" => Predicates::GapsIdentified,
"improvements_drafted" => Predicates::ImprovementsDrafted,
```

Keep alphabetical or existing thematic order readable. Do not remove existing predicates.

**Step 4: Run registry spec**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 5: Run all predicate specs**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb spec/services/engine/predicates
```

Expected: all predicate specs pass.

**Step 6: Commit**

```bash
git add spec/services/engine/predicate_registry_spec.rb app/services/engine/predicate_registry.rb
git commit -m "feat: register incident readiness predicates"
```

---

### Task 8: Add docker-friendly incident readiness fixture app files

**Objective:** Provide a realistic, portable target for e2e cookbook tests without introducing shared infrastructure implementation.

**Files:**
- Create: `spec/fixtures/incident_readiness/docker-compose.yml`
- Create: `spec/fixtures/incident_readiness/CODEOWNERS`
- Create: `spec/fixtures/incident_readiness/services/api/config/routes.rb`
- Create: `spec/fixtures/incident_readiness/services/api/docs/runbooks/api-down.md`
- Create: `spec/fixtures/incident_readiness/services/worker/README.md`
- Test: extend a seed or future e2e spec as appropriate. If no e2e harness exists yet, add docs and fixture files only in this task and leave e2e execution to the shared cookbook infrastructure plan.

**Step 1: Write a failing fixture presence spec if a fixture spec location exists**

If the repo already has fixture validation specs, add:

```ruby
RSpec.describe "incident readiness fixtures" do
  it "provides docker-friendly service evidence without absolute paths" do
    root = Rails.root.join("spec/fixtures/incident_readiness")

    expect(root.join("docker-compose.yml")).to exist
    expect(root.join("CODEOWNERS")).to exist
    expect(root.join("services/api/config/routes.rb")).to exist
    expect(root.join("services/api/docs/runbooks/api-down.md")).to exist
    expect(root.join("services/worker/README.md")).to exist

    contents = root.glob("**/*").select(&:file?).map(&:read).join("\n")
    expect(contents).not_to include("/Users/gregmushen/work/code/taskrail")
  end
end
```

Suggested path if none exists: `spec/fixtures/incident_readiness_fixture_spec.rb`.

**Step 2: Run fixture spec to verify failure**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/fixtures/incident_readiness_fixture_spec.rb
```

Expected: FAIL because fixture files do not exist.

**Step 3: Create `spec/fixtures/incident_readiness/docker-compose.yml`**

```yaml
services:
  api:
    build: ./services/api
    command: bin/rails server -b 0.0.0.0
    depends_on:
      - postgres
      - redis
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
  worker:
    build: ./services/worker
    command: bundle exec sidekiq
    depends_on:
      - redis
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: postgres
  redis:
    image: redis:7-alpine
```

**Step 4: Create fixture ownership and service evidence**

`spec/fixtures/incident_readiness/CODEOWNERS`:
```text
/services/api/ @platform-team
/services/worker/ @platform-team
```

`spec/fixtures/incident_readiness/services/api/config/routes.rb`:
```ruby
Rails.application.routes.draw do
  get "/health", to: "health#show"
end
```

`spec/fixtures/incident_readiness/services/api/docs/runbooks/api-down.md`:
```markdown
# API Down Runbook

Check `/health`, database connectivity, Redis connectivity, and recent error reports.
```

`spec/fixtures/incident_readiness/services/worker/README.md`:
```markdown
# Worker Service

Processes background jobs from Redis. This fixture intentionally lacks a health check and runbook so readiness scoring can find gaps.
```

**Step 5: Run fixture spec to verify pass**

Run:
```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/fixtures/incident_readiness_fixture_spec.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git add spec/fixtures/incident_readiness_fixture_spec.rb spec/fixtures/incident_readiness
git commit -m "test: add incident readiness fixtures"
```

---

### Task 9: Add cookbook documentation

**Objective:** Document how to run and interpret the incident readiness cookbook queue.

**Files:**
- Create: `docs/cookbooks/incident-readiness-scoring.md`
- Optional modify: cookbook index if one exists.

**Step 1: Write docs**

Create:

```markdown
# Incident Readiness Scoring Cookbook

Source spec: `docs/specs/cookbook-11-incident-readiness-scoring.md`

The `incident_readiness` queue audits services for operational readiness and produces a scorecard answering: if this service breaks tonight, are we ready?

Stages:
1. `inventory_services` inventories web, worker, cron, and infrastructure-backed services.
2. `score_readiness` scores health checks, alerting, runbooks, dashboards, logging, error handling, resilience, and documentation.
3. `identify_gaps` ranks service and platform gaps by risk and effort.
4. `draft_improvements` drafts quick wins and recommends cross-queue work for larger fixes.
5. `human_review` stops for review.
6. `done` is terminal.

Artifacts:
- `service_inventory`
- `readiness_scores`
- `gap_analysis`
- `improvement_drafts`

Infrastructure notes:
- The queue uses `inline_claude` and `fake` stages only.
- Docker-friendly fixture files live under `spec/fixtures/incident_readiness`.
- Shared Docker Compose adapter behavior belongs to the shared cookbook infrastructure plan and is not duplicated here.

The scorecard report should use the standalone table format from the source spec so it can be shared directly with an operations or product team.
```

**Step 2: Verify docs mention the source spec and queue slug**

Run:
```bash
ruby -e 'text = File.read("docs/cookbooks/incident-readiness-scoring.md"); abort "missing source spec" unless text.include?("docs/specs/cookbook-11-incident-readiness-scoring.md"); abort "missing slug" unless text.include?("incident_readiness")'
```

Expected: command exits 0.

**Step 3: Commit**

```bash
git add docs/cookbooks/incident-readiness-scoring.md
git commit -m "docs: add incident readiness cookbook guide"
```

---

### Task 10: Run final focused verification

**Objective:** Confirm the whole cookbook slice works and does not break existing seed/predicate behavior.

**Files:**
- No new files.

**Step 1: Run seed specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: all examples pass.

**Step 2: Run predicate specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb spec/services/engine/predicates
```

Expected: all examples pass.

**Step 3: Run fixture spec if added**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/fixtures/incident_readiness_fixture_spec.rb
```

Expected: PASS.

**Step 4: Search for forbidden hardcoded paths**

```bash
rg "/Users/gregmushen/work/code/taskrail" config/queues/incident_readiness.yml prompts/readiness_*.md spec/fixtures/incident_readiness docs/cookbooks/incident-readiness-scoring.md
```

Expected: no matches.

**Step 5: Verify queue YAML uses relative file prompts**

```bash
ruby -ryaml -e 'cfg = YAML.load_file("config/queues/incident_readiness.yml"); prompts = cfg.fetch("stage_configs").values.filter_map { |stage| stage["agent_prompt"] if stage["agent_prompt"].to_s.start_with?("file://") }; abort "bad prompts" unless prompts == ["file://prompts/readiness_inventory.md", "file://prompts/readiness_score.md", "file://prompts/readiness_gaps.md", "file://prompts/readiness_draft_improvements.md"]'
```

Expected: command exits 0.

---

## Implementation Task Checklist

- [ ] RED/GREEN seed spec proves `incident_readiness` queue stages, adapters, prompts, completion criteria, and artifact kinds.
- [ ] `config/queues/incident_readiness.yml` exists and has no absolute paths.
- [ ] Four prompt files exist under `prompts/` and produce `service_inventory`, `readiness_scores`, `gap_analysis`, and `improvement_drafts` artifacts.
- [ ] `service_inventory_produced` predicate is tested and implemented.
- [ ] `readiness_scored` predicate is tested and implemented.
- [ ] `gaps_identified` predicate is tested and implemented.
- [ ] `improvements_drafted` predicate is tested and implemented.
- [ ] `Engine::PredicateRegistry` resolves all four new predicates.
- [ ] Docker-friendly fixture files exist under `spec/fixtures/incident_readiness` and contain no hardcoded checkout paths.
- [ ] Cookbook docs mention `docs/specs/cookbook-11-incident-readiness-scoring.md` and explain shared infrastructure boundaries.
- [ ] Focused seed, predicate, fixture, and portability checks pass with the rbenv command prefix.

## Expected Final Commit Message

```bash
git commit -m "feat: add incident readiness scoring cookbook"
```

If implementing task-by-task with frequent commits, use the per-task commit messages above and optionally finish with a docs/chore commit only if there are remaining uncommitted documentation updates.

## Implementation Dependencies

- Existing `db/seeds.rb` `file://` resolver must remain Rails.root-relative.
- Existing `inline_claude` adapter must support `adapter_config.output_artifact_kind` consistently with the operations queue.
- Existing `report_present` predicate remains sufficient for `human_review` and `done` fake stages.
- Shared docker-compose execution and any reusable e2e cookbook harness should come from the shared cookbook infrastructure plan; this cookbook only supplies docker-friendly fixtures and queue-specific behavior.
