# API Documentation Sync Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `api_docs_sync` cookbook queue so StupidClaw can inventory application API endpoints, compare them to existing docs, draft missing/stale documentation, validate examples, and block for human review before publishing.

**Architecture:** This is a config-and-predicate cookbook implementation. The queue lives in `config/queues/api_docs_sync.yml`, prompt bodies live in `prompts/docs_*.md`, and new predicate classes inspect successful stage reports/artifacts through the existing `Claim` -> `Report` model boundary. E2E confidence comes from a small fixture Rails API plus seed specs that prove queue portability, prompt file resolution, and predicate registration.

**Tech Stack:** Rails, RSpec, YAML queue seeds, StupidClaw Engine predicates, inline Claude adapters, shell_script validation stage, fake gate stage, docker-friendly example validation via `npx @redocly/cli` or `npx swagger-cli` when available.

**Source spec:** `docs/specs/cookbook-03-api-documentation-sync.md`

**Output queue slug:** `api_docs_sync`

---

## Current Codebase Context

The implementer should start from the current StupidClaw patterns:

- Queue YAML files are stored in `config/queues/*.yml` and loaded by `db/seeds.rb`.
- `db/seeds.rb` resolves `agent_prompt: file://prompts/name.md` relative to `Rails.root`; do not use absolute paths.
- Existing queue seed coverage is in `spec/models/work_queue_seed_spec.rb`.
- Predicate registry is `app/services/engine/predicate_registry.rb`.
- Predicate classes live in `app/services/engine/predicates/*.rb`.
- Predicate specs live in `spec/services/engine/predicates/*_spec.rb`.
- Existing report-backed predicate examples: `Engine::Predicates::ValidationPassed`, `RunbookMapped`, `RunbookDrafted`, `ClustersCreated`, and their specs.
- Test commands on Greg's Mac must initialize rbenv shims with:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`

## Cookbook Behavior to Implement

Stages:

```text
scan_endpoints -> diff_existing_docs -> draft_documentation -> validate_examples -> human_review -> done
```

Artifacts and predicates:

- `endpoint_inventory_produced`: latest successful report has an `endpoint_inventory` artifact/body with a non-empty `endpoints` array.
- `docs_diff_produced`: latest successful report has a `docs_diff` artifact/body.
- `docs_drafted`: latest successful report has a `draft_docs` artifact/body with a non-empty `files` array.
- `docs_validated`: latest successful report has a `validation_results` artifact/body with `valid: true`.

For this implementation, predicates should read from the latest successful `Report` for the claim and accept either of these report body shapes so adapters can evolve without breaking cookbook predicates:

```ruby
{ "endpoint_inventory" => { "framework" => "rails", "endpoints" => [...] } }
{ "artifact_kind" => "endpoint_inventory", "artifact" => { "framework" => "rails", "endpoints" => [...] } }
```

The same pattern applies to `docs_diff`, `draft_docs`, and `validation_results`.

If the artifact is missing or invalid, return `PredicateResult.fail(reason: "...")`. If it passes, return evidence with the report id and a small actionable summary, for example `{ report_id: report.id, endpoint_count: 3 }`.

## Portable Queue YAML Requirements

Create `config/queues/api_docs_sync.yml` with:

- No absolute paths.
- Prompt references only as `file://prompts/docs_scan_endpoints.md`, `file://prompts/docs_diff_existing.md`, and `file://prompts/docs_draft.md`.
- No hardcoded `working_directory`; let shell adapters and runner defaults use `Rails.root` unless a shared infrastructure plan later introduces a standard variable.
- Validation stage should use docker-friendly commands that work in a fresh container if Node is available, but should not add or duplicate shared docker-compose infrastructure.
- Human review and done stages should use the existing `fake` adapter pattern.

Recommended YAML body:

```yaml
name: API Documentation Sync
slug: api_docs_sync
stages:
  - scan_endpoints
  - diff_existing_docs
  - draft_documentation
  - validate_examples
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2
stage_configs:
  scan_endpoints:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [endpoint_inventory_produced]
    agent_prompt: file://prompts/docs_scan_endpoints.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: endpoint_inventory
  diff_existing_docs:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [docs_diff_produced]
    agent_prompt: file://prompts/docs_diff_existing.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: docs_diff
  draft_documentation:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [docs_drafted]
    agent_prompt: file://prompts/docs_draft.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: draft_docs
  validate_examples:
    adapter_type: shell_script
    allowed_skills: [run_validation]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [docs_validated]
    agent_prompt: Validate OpenAPI specs and request/response examples. Report validation_results with valid true only when all examples parse.
    timeout_seconds: 300
    adapter_config:
      output_artifact_kind: validation_results
      commands:
        - name: validate_openapi_if_present
          artifact: validation_results
          command: |
            ruby scripts/validate_api_docs_artifact.rb
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Review generated API documentation before publishing.
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

Note: if `scripts/validate_api_docs_artifact.rb` does not fit current shell_script adapter command conventions, keep `adapter_config.output_artifact_kind: validation_results` and adapt only the command shape to match existing shell_script adapter specs. Do not add shared Docker Compose services in this cookbook.

## Prompt Files to Create

Create these files:

- `prompts/docs_scan_endpoints.md`
- `prompts/docs_diff_existing.md`
- `prompts/docs_draft.md`

Each prompt must specify:

- The required input artifacts.
- The exact JSON object to return.
- No file edits for scan/diff stages.
- Draft stage may propose files in `draft_docs.files` but should not write them directly.
- Security boundaries: read repo only, do not deploy, do not mutate data.

## Fixture Files to Create

Create a small fixture Rails API under `spec/fixtures/api_docs_sync/rails_api/` so tests and future prompt examples have a stable target without relying on StupidClaw's current routes changing:

- `spec/fixtures/api_docs_sync/rails_api/config/routes.rb`
- `spec/fixtures/api_docs_sync/rails_api/app/controllers/api/v1/widgets_controller.rb`
- `spec/fixtures/api_docs_sync/rails_api/app/serializers/widget_serializer.rb`
- `spec/fixtures/api_docs_sync/rails_api/docs/openapi.yml`
- `spec/fixtures/api_docs_sync/rails_api/README.md`

Suggested fixture content:

- Routes:
  - `GET /api/v1/widgets` -> `api/v1/widgets#index`
  - `POST /api/v1/widgets` -> `api/v1/widgets#create`
  - `GET /api/v1/widgets/:id` -> `api/v1/widgets#show`
- Existing docs should document `GET /api/v1/widgets` correctly, document `GET /api/v1/widgets/:id` with a stale/incorrect response, and omit `POST /api/v1/widgets`.
- Serializer should expose `id`, `name`, `status`, `created_at`.
- Controller comments should include at least one auth hint such as `# Requires Bearer token`.

Do not build a full Rails app in the fixture. These files are enough for prompt examples and deterministic specs.

## Implementation Tasks

### Task 1: Add RED seed spec for the API docs queue

**Objective:** Prove the `api_docs_sync` queue is seeded with portable prompt resolution and the expected stage configuration before adding the queue YAML.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Future create: `config/queues/api_docs_sync.yml`
- Future create: `prompts/docs_scan_endpoints.md`
- Future create: `prompts/docs_diff_existing.md`
- Future create: `prompts/docs_draft.md`

**Step 1: Write failing test**

Append a new example before the idempotency spec:

```ruby
it "seeds the api docs sync queue with resolved prompt files" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "api_docs_sync")
  expect(queue.name).to eq("API Documentation Sync")
  expect(queue.stages).to eq(%w[
    scan_endpoints
    diff_existing_docs
    draft_documentation
    validate_examples
    human_review
    done
  ])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 2
  )

  scan = queue.stage_configs.find_by!(stage_name: "scan_endpoints")
  expect(scan.adapter_type).to eq("inline_claude")
  expect(scan.model_override).to eq("claude-haiku-4-5-20251001")
  expect(scan.allowed_skills).to eq(["read_repo"])
  expect(scan.forbidden_skills).to include("edit_files", "deploy")
  expect(scan.completion_criteria).to eq(["endpoint_inventory_produced"])
  expect(scan.agent_prompt).to include("# API Docs Scan Endpoints")
  expect(scan.agent_prompt).to include("endpoint_inventory")
  expect(scan.agent_prompt).not_to start_with("file://")
  expect(scan.adapter_config).to eq("output_artifact_kind" => "endpoint_inventory")

  diff = queue.stage_configs.find_by!(stage_name: "diff_existing_docs")
  expect(diff.adapter_type).to eq("inline_claude")
  expect(diff.model_override).to eq("claude-sonnet-4-20250514")
  expect(diff.completion_criteria).to eq(["docs_diff_produced"])
  expect(diff.agent_prompt).to include("# API Docs Diff Existing Documentation")
  expect(diff.adapter_config).to eq("output_artifact_kind" => "docs_diff")

  draft = queue.stage_configs.find_by!(stage_name: "draft_documentation")
  expect(draft.completion_criteria).to eq(["docs_drafted"])
  expect(draft.agent_prompt).to include("# API Docs Draft Documentation")
  expect(draft.adapter_config).to eq("output_artifact_kind" => "draft_docs")

  validate = queue.stage_configs.find_by!(stage_name: "validate_examples")
  expect(validate.adapter_type).to eq("shell_script")
  expect(validate.completion_criteria).to eq(["docs_validated"])
  expect(validate.allowed_skills).to include("run_validation")
  expect(validate.adapter_config["output_artifact_kind"]).to eq("validation_results")

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.timeout_seconds).to eq(86_400)
end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb:61
```

Expected: FAIL with `ActiveRecord::RecordNotFound` for slug `api_docs_sync`.

**Step 3: Commit?**

Do not commit the failing test alone unless the implementation worker's team workflow requires preserving RED commits. Preferred flow is RED, GREEN, then commit once green for this task.

### Task 2: Add queue YAML and prompt files

**Objective:** Make the seed spec pass by adding portable queue YAML and resolved prompt files.

**Files:**
- Create: `config/queues/api_docs_sync.yml`
- Create: `prompts/docs_scan_endpoints.md`
- Create: `prompts/docs_diff_existing.md`
- Create: `prompts/docs_draft.md`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Write minimal implementation**

Create `config/queues/api_docs_sync.yml` using the recommended YAML in this plan. Keep prompt paths relative:

```yaml
agent_prompt: file://prompts/docs_scan_endpoints.md
```

Do not include any `/Users/...` path.

Create `prompts/docs_scan_endpoints.md`:

```markdown
# API Docs Scan Endpoints

You are the endpoint inventory stage for StupidClaw's API Documentation Sync queue.

Inputs:
- Repository root path supplied by the work item.
- Framework type when provided, such as Rails, Express, Django, or unknown.
- Existing route, controller, serializer, presenter, schema, and inline documentation files.

Rules:
- Read repository files only.
- Do not edit files.
- Do not deploy or mutate databases.
- Prefer deterministic evidence from routes, controllers, serializers, request specs, and schema files.
- If a field is unknown, use null or an empty collection rather than guessing.

Return one JSON object with this shape:

```json
{
  "endpoint_inventory": {
    "framework": "rails",
    "endpoints": [
      {
        "method": "GET",
        "path": "/api/v1/widgets",
        "controller": "Api::V1::WidgetsController#index",
        "params": [],
        "response_shape": {},
        "auth": "Bearer token required",
        "existing_docs": []
      }
    ]
  }
}
```
```

Create `prompts/docs_diff_existing.md`:

```markdown
# API Docs Diff Existing Documentation

You compare endpoint inventory against existing project documentation for StupidClaw's API Documentation Sync queue.

Inputs:
- `endpoint_inventory` artifact from `scan_endpoints`.
- Existing OpenAPI, Swagger, README, wiki, or docs files from the repository.

Rules:
- Read only.
- Classify gaps as missing, stale, incorrect, or undocumented behavior.
- Include concise evidence for each finding.
- Compute `coverage_pct` as documented endpoint count divided by inventory endpoint count, rounded to one decimal place.

Return one JSON object with this shape:

```json
{
  "docs_diff": {
    "missing": [],
    "stale": [],
    "incorrect": [],
    "undocumented_behavior": [],
    "coverage_pct": 75.0
  }
}
```
```

Create `prompts/docs_draft.md`:

```markdown
# API Docs Draft Documentation

You draft API documentation updates for StupidClaw's API Documentation Sync queue.

Inputs:
- `docs_diff` artifact.
- `endpoint_inventory` artifact.
- Existing documentation format and style.

Rules:
- Do not write files directly.
- Draft only the minimum files needed to close the documented gaps.
- Match existing format, naming, indentation, and examples.
- Include auth requirements, request examples, response examples, error responses, pagination/rate-limit notes when discovered, and deprecation notices when applicable.
- Return file paths relative to the target repository root.

Return one JSON object with this shape:

```json
{
  "draft_docs": {
    "format": "openapi_yaml",
    "files": [
      {
        "path": "docs/openapi.yml",
        "content": "openapi: 3.1.0\n...",
        "change_type": "update"
      }
    ]
  }
}
```
```

**Step 2: Run focused seed spec**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 3: Verify portability**

Run:

```bash
rg '/Users/|Rails.root.join\("/|working_directory:' config/queues/api_docs_sync.yml prompts/docs_*.md
```

Expected: no matches. If `rg` exits 1 because there are no matches, that is success.

**Step 4: Commit**

```bash
git add config/queues/api_docs_sync.yml prompts/docs_scan_endpoints.md prompts/docs_diff_existing.md prompts/docs_draft.md spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed api docs sync cookbook queue"
```

### Task 3: Add RED specs for endpoint_inventory_produced predicate

**Objective:** Define the exact pass/fail behavior for endpoint inventory artifacts.

**Files:**
- Create: `spec/services/engine/predicates/endpoint_inventory_produced_spec.rb`
- Future create: `app/services/engine/predicates/endpoint_inventory_produced.rb`
- Future modify: `app/services/engine/predicate_registry.rb`
- Test: `spec/services/engine/predicate_registry_spec.rb`

**Step 1: Write failing predicate spec**

Use this shape:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::EndpointInventoryProduced do
  def build_claim(reports: [])
    queue = WorkQueue.create!(name: "API Docs", slug: "api-docs-#{SecureRandom.hex(4)}", stages: ["scan", "done"])
    queue.stage_configs.create!(stage_name: "scan", adapter_type: "fake")
    item = WorkItem.create!(title: "Sync docs", spec_url: "opaque spec", work_queue: queue, stage_name: "scan")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    reports.each_with_index do |report, index|
      created_at = report.delete(:created_at) || index.minutes.ago
      Report.create!(work_item: item, claim: claim, stage_name: "scan", created_at: created_at, updated_at: created_at, **report)
    end
    claim
  end

  it "passes when the latest success report has endpoint_inventory with endpoints" do
    claim = build_claim(reports: [
      { status: :success, body: { "endpoint_inventory" => { "framework" => "rails", "endpoints" => [{ "method" => "GET", "path" => "/api/v1/widgets" }] } } }
    ])
    report = claim.reports.success.first

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ report_id: report.id, endpoint_count: 1 })
  end

  it "passes when the report uses generic artifact wrapper shape" do
    claim = build_claim(reports: [
      { status: :success, body: { "artifact_kind" => "endpoint_inventory", "artifact" => { "endpoints" => [{ "method" => "POST", "path" => "/api/v1/widgets" }] } } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence.fetch(:endpoint_count)).to eq(1)
  end

  it "fails when endpoint inventory is missing" do
    claim = build_claim(reports: [{ status: :success, body: {} }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("endpoint inventory artifact missing")
  end

  it "fails when endpoint list is empty" do
    claim = build_claim(reports: [{ status: :success, body: { "endpoint_inventory" => { "endpoints" => [] } } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("endpoint inventory has no endpoints")
  end

  it "uses the newest success report by creation time" do
    claim = build_claim(reports: [
      { status: :success, body: { "endpoint_inventory" => { "endpoints" => [] } }, created_at: 2.minutes.ago },
      { status: :success, body: { "endpoint_inventory" => { "endpoints" => [{ "method" => "GET", "path" => "/new" }] } }, created_at: 1.minute.ago }
    ])

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
  end
end
```

**Step 2: Run test to verify failure**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/endpoint_inventory_produced_spec.rb
```

Expected: FAIL with uninitialized constant `Engine::Predicates::EndpointInventoryProduced`.

### Task 4: Implement endpoint_inventory_produced predicate

**Objective:** Add the predicate class and registry entry.

**Files:**
- Create: `app/services/engine/predicates/endpoint_inventory_produced.rb`
- Modify: `app/services/engine/predicate_registry.rb`
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Test: `spec/services/engine/predicates/endpoint_inventory_produced_spec.rb`

**Step 1: Write minimal implementation**

Create `app/services/engine/predicates/endpoint_inventory_produced.rb`:

```ruby
module Engine
  module Predicates
    class EndpointInventoryProduced
      def initialize(claim:)
        @claim = claim
      end

      def call
        report = @claim.reports.success.order(created_at: :desc).first
        artifact = artifact_from(report)
        return PredicateResult.fail(reason: "endpoint inventory artifact missing") unless artifact

        endpoints = artifact["endpoints"]
        return PredicateResult.fail(reason: "endpoint inventory has no endpoints") unless endpoints.is_a?(Array) && endpoints.any?

        PredicateResult.pass(evidence: { report_id: report.id, endpoint_count: endpoints.size })
      end

      private

      def artifact_from(report)
        return unless report&.body.is_a?(Hash)
        return report.body["endpoint_inventory"] if report.body["endpoint_inventory"].is_a?(Hash)
        return report.body["artifact"] if report.body["artifact_kind"] == "endpoint_inventory" && report.body["artifact"].is_a?(Hash)
      end
    end
  end
end
```

Modify `app/services/engine/predicate_registry.rb`:

```ruby
"endpoint_inventory_produced" => Predicates::EndpointInventoryProduced,
```

Add an assertion to `spec/services/engine/predicate_registry_spec.rb`:

```ruby
expect(described_class.resolve("endpoint_inventory_produced")).to eq(Engine::Predicates::EndpointInventoryProduced)
```

**Step 2: Run focused specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/endpoint_inventory_produced_spec.rb spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/endpoint_inventory_produced.rb app/services/engine/predicate_registry.rb spec/services/engine/predicates/endpoint_inventory_produced_spec.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: add endpoint inventory predicate"
```

### Task 5: Add RED specs for docs_diff_produced predicate

**Objective:** Define docs diff artifact requirements.

**Files:**
- Create: `spec/services/engine/predicates/docs_diff_produced_spec.rb`
- Future create: `app/services/engine/predicates/docs_diff_produced.rb`

**Step 1: Write failing spec**

Model it after Task 3 with these examples:

```ruby
it "passes when latest success report has docs_diff artifact" do
  claim = build_claim(reports: [
    { status: :success, body: { "docs_diff" => { "missing" => [], "stale" => [], "incorrect" => [], "undocumented_behavior" => [], "coverage_pct" => 100.0 } } }
  ])
  report = claim.reports.success.first

  result = described_class.new(claim: claim).call

  expect(result).to be_passed
  expect(result.evidence).to eq({ report_id: report.id, missing_count: 0, stale_count: 0, incorrect_count: 0 })
end

it "passes when latest success report uses generic artifact wrapper" do
  claim = build_claim(reports: [
    { status: :success, body: { "artifact_kind" => "docs_diff", "artifact" => { "missing" => [{ "path" => "/api/v1/widgets" }] } } }
  ])

  result = described_class.new(claim: claim).call

  expect(result).to be_passed
  expect(result.evidence.fetch(:missing_count)).to eq(1)
end

it "fails when docs_diff is missing" do
  claim = build_claim(reports: [{ status: :success, body: {} }])

  result = described_class.new(claim: claim).call

  expect(result).not_to be_passed
  expect(result.reason).to eq("docs diff artifact missing")
end
```

Also include newest-success-report ordering and ignores-newer-failure examples.

**Step 2: Run RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/docs_diff_produced_spec.rb
```

Expected: FAIL with uninitialized constant.

### Task 6: Implement docs_diff_produced predicate

**Objective:** Add docs diff predicate and registry entry.

**Files:**
- Create: `app/services/engine/predicates/docs_diff_produced.rb`
- Modify: `app/services/engine/predicate_registry.rb`
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Test: `spec/services/engine/predicates/docs_diff_produced_spec.rb`

**Step 1: Implement**

Create a predicate like Task 4, but use artifact kind `docs_diff`. It should pass for any Hash artifact and evidence should count arrays:

```ruby
PredicateResult.pass(evidence: {
  report_id: report.id,
  missing_count: Array(artifact["missing"]).size,
  stale_count: Array(artifact["stale"]).size,
  incorrect_count: Array(artifact["incorrect"]).size
})
```

Failure reason: `"docs diff artifact missing"`.

Add registry mapping:

```ruby
"docs_diff_produced" => Predicates::DocsDiffProduced,
```

Add registry spec assertion.

**Step 2: Run focused specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/docs_diff_produced_spec.rb spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/docs_diff_produced.rb app/services/engine/predicate_registry.rb spec/services/engine/predicates/docs_diff_produced_spec.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: add docs diff predicate"
```

### Task 7: Add RED specs for docs_drafted predicate

**Objective:** Require draft docs artifacts to include at least one file.

**Files:**
- Create: `spec/services/engine/predicates/docs_drafted_spec.rb`
- Future create: `app/services/engine/predicates/docs_drafted.rb`

**Step 1: Write failing spec**

Examples:

```ruby
it "passes when draft docs include at least one file" do
  claim = build_claim(reports: [
    { status: :success, body: { "draft_docs" => { "format" => "openapi_yaml", "files" => [{ "path" => "docs/openapi.yml", "content" => "openapi: 3.1.0", "change_type" => "update" }] } } }
  ])
  report = claim.reports.success.first

  result = described_class.new(claim: claim).call

  expect(result).to be_passed
  expect(result.evidence).to eq({ report_id: report.id, file_count: 1, format: "openapi_yaml" })
end

it "fails when draft_docs is missing" do
  claim = build_claim(reports: [{ status: :success, body: {} }])

  result = described_class.new(claim: claim).call

  expect(result).not_to be_passed
  expect(result.reason).to eq("draft docs artifact missing")
end

it "fails when files list is empty" do
  claim = build_claim(reports: [{ status: :success, body: { "draft_docs" => { "files" => [] } } }])

  result = described_class.new(claim: claim).call

  expect(result).not_to be_passed
  expect(result.reason).to eq("draft docs has no files")
end
```

Include wrapper-shape and latest-success ordering examples.

**Step 2: Run RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/docs_drafted_spec.rb
```

Expected: FAIL with uninitialized constant.

### Task 8: Implement docs_drafted predicate

**Objective:** Add docs drafted predicate and registry entry.

**Files:**
- Create: `app/services/engine/predicates/docs_drafted.rb`
- Modify: `app/services/engine/predicate_registry.rb`
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Test: `spec/services/engine/predicates/docs_drafted_spec.rb`

**Step 1: Implement**

Use Task 4 structure with artifact kind `draft_docs`, required non-empty `files` array, and evidence:

```ruby
{ report_id: report.id, file_count: files.size, format: artifact["format"] }
```

Failure reasons:

- `"draft docs artifact missing"`
- `"draft docs has no files"`

Add registry mapping:

```ruby
"docs_drafted" => Predicates::DocsDrafted,
```

Add registry spec assertion.

**Step 2: Run focused specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/docs_drafted_spec.rb spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/docs_drafted.rb app/services/engine/predicate_registry.rb spec/services/engine/predicates/docs_drafted_spec.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: add docs drafted predicate"
```

### Task 9: Add RED specs for docs_validated predicate

**Objective:** Require validation results to explicitly pass before allowing transition.

**Files:**
- Create: `spec/services/engine/predicates/docs_validated_spec.rb`
- Future create: `app/services/engine/predicates/docs_validated.rb`

**Step 1: Write failing spec**

Examples:

```ruby
it "passes when validation_results has valid true" do
  claim = build_claim(reports: [
    { status: :success, body: { "validation_results" => { "valid" => true, "errors" => [] } } }
  ])
  report = claim.reports.success.first

  result = described_class.new(claim: claim).call

  expect(result).to be_passed
  expect(result.evidence).to eq({ report_id: report.id, error_count: 0 })
end

it "fails when validation_results is missing" do
  claim = build_claim(reports: [{ status: :success, body: {} }])

  result = described_class.new(claim: claim).call

  expect(result).not_to be_passed
  expect(result.reason).to eq("validation results artifact missing")
end

it "fails when valid is false and includes errors" do
  claim = build_claim(reports: [
    { status: :success, body: { "validation_results" => { "valid" => false, "errors" => ["docs/openapi.yml: invalid schema"] } } }
  ])

  result = described_class.new(claim: claim).call

  expect(result).not_to be_passed
  expect(result.reason).to eq("API docs validation failed: docs/openapi.yml: invalid schema")
end
```

Include wrapper-shape, latest-success ordering, and ignores-newer-failure examples.

**Step 2: Run RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/docs_validated_spec.rb
```

Expected: FAIL with uninitialized constant.

### Task 10: Implement docs_validated predicate

**Objective:** Add validation predicate and registry entry.

**Files:**
- Create: `app/services/engine/predicates/docs_validated.rb`
- Modify: `app/services/engine/predicate_registry.rb`
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Test: `spec/services/engine/predicates/docs_validated_spec.rb`

**Step 1: Implement**

Use artifact kind `validation_results`. Pass only when `artifact["valid"] == true`. Evidence:

```ruby
{ report_id: report.id, error_count: Array(artifact["errors"]).size }
```

Failure reasons:

- Missing artifact: `"validation results artifact missing"`
- Invalid artifact: prefix `"API docs validation failed"` and append the first error if present.

Add registry mapping:

```ruby
"docs_validated" => Predicates::DocsValidated,
```

Add registry spec assertion.

**Step 2: Run focused specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/docs_validated_spec.rb spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/services/engine/predicates/docs_validated.rb app/services/engine/predicate_registry.rb spec/services/engine/predicates/docs_validated_spec.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: add api docs validation predicate"
```

### Task 11: Add RED fixture coverage for API docs sync fixture app

**Objective:** Add deterministic fixture files that exercise documented, missing, and stale endpoint examples.

**Files:**
- Create: `spec/fixtures/api_docs_sync/rails_api/config/routes.rb`
- Create: `spec/fixtures/api_docs_sync/rails_api/app/controllers/api/v1/widgets_controller.rb`
- Create: `spec/fixtures/api_docs_sync/rails_api/app/serializers/widget_serializer.rb`
- Create: `spec/fixtures/api_docs_sync/rails_api/docs/openapi.yml`
- Create: `spec/fixtures/api_docs_sync/rails_api/README.md`
- Create: `spec/fixtures/api_docs_sync/fixture_contract_spec.rb` or add to an existing fixture/spec location if project conventions differ.

**Step 1: Write failing fixture contract spec**

Create `spec/fixtures/api_docs_sync/fixture_contract_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "api docs sync fixture" do
  let(:root) { Rails.root.join("spec/fixtures/api_docs_sync/rails_api") }

  it "contains documented, missing, and stale endpoint examples" do
    routes = root.join("config/routes.rb").read
    controller = root.join("app/controllers/api/v1/widgets_controller.rb").read
    serializer = root.join("app/serializers/widget_serializer.rb").read
    openapi = root.join("docs/openapi.yml").read

    expect(routes).to include("resources :widgets")
    expect(controller).to include("def index")
    expect(controller).to include("def create")
    expect(controller).to include("def show")
    expect(controller).to include("Requires Bearer token")
    expect(serializer).to include("attributes :id, :name, :status, :created_at")

    expect(openapi).to include("/api/v1/widgets:")
    expect(openapi).to include("get:")
    expect(openapi).to include("/api/v1/widgets/{id}:")
    expect(openapi).not_to include("post:")
    expect(openapi).to include("legacy_status")
  end
end
```

**Step 2: Run RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/fixtures/api_docs_sync/fixture_contract_spec.rb
```

Expected: FAIL because fixture files do not exist.

### Task 12: Implement fixture app files

**Objective:** Add the fixture target for future E2E and prompt examples.

**Files:**
- Create files listed in Task 11.

**Step 1: Create fixture files**

`spec/fixtures/api_docs_sync/rails_api/config/routes.rb`:

```ruby
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :widgets, only: %i[index create show]
    end
  end
end
```

`spec/fixtures/api_docs_sync/rails_api/app/controllers/api/v1/widgets_controller.rb`:

```ruby
module Api
  module V1
    class WidgetsController < ApplicationController
      # Requires Bearer token
      def index
        render json: WidgetSerializer.new(Widget.order(created_at: :desc)).serializable_hash
      end

      # Requires Bearer token
      def create
        widget = Widget.create!(widget_params)
        render json: WidgetSerializer.new(widget).serializable_hash, status: :created
      end

      # Requires Bearer token
      def show
        widget = Widget.find(params[:id])
        render json: WidgetSerializer.new(widget).serializable_hash
      end

      private

      def widget_params
        params.require(:widget).permit(:name, :status)
      end
    end
  end
end
```

`spec/fixtures/api_docs_sync/rails_api/app/serializers/widget_serializer.rb`:

```ruby
class WidgetSerializer
  include JSONAPI::Serializer

  attributes :id, :name, :status, :created_at
end
```

`spec/fixtures/api_docs_sync/rails_api/docs/openapi.yml`:

```yaml
openapi: 3.1.0
info:
  title: Widget API
  version: 1.0.0
paths:
  /api/v1/widgets:
    get:
      summary: List widgets
      security:
        - bearerAuth: []
      responses:
        "200":
          description: Widget list
  /api/v1/widgets/{id}:
    get:
      summary: Show widget with stale response field
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      responses:
        "200":
          description: Widget detail
          content:
            application/json:
              schema:
                type: object
                properties:
                  legacy_status:
                    type: string
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
```

`spec/fixtures/api_docs_sync/rails_api/README.md`:

```markdown
# API Docs Sync Fixture Rails API

This fixture intentionally has one documented endpoint, one stale documented endpoint, and one undocumented endpoint for the `api_docs_sync` cookbook.
```

**Step 2: Run fixture contract spec**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/fixtures/api_docs_sync/fixture_contract_spec.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add spec/fixtures/api_docs_sync
git commit -m "test: add api docs sync fixture app"
```

### Task 13: Add optional validation helper with TDD

**Objective:** Provide the shell_script stage with a docker-friendly validation command that turns draft docs into `validation_results` without adding shared infrastructure.

**Files:**
- Create: `spec/scripts/validate_api_docs_artifact_spec.rb`
- Create: `scripts/validate_api_docs_artifact.rb`
- Modify: `config/queues/api_docs_sync.yml` if command shape needs adjustment.

**Step 1: Write RED script spec**

If the project already has script specs, follow that pattern. Otherwise create `spec/scripts/validate_api_docs_artifact_spec.rb` and test the script as a subprocess with temp files.

Minimum behavior to test:

- It outputs JSON with `{ "validation_results": { "valid": true, "errors": [] } }` when no draft OpenAPI file is present.
- It writes a temp OpenAPI file from `draft_docs.files[*].content` when format is `openapi_yaml`.
- It reports `{ valid: false, errors: [...] }` when YAML parsing fails.
- It does not require Docker or external services.

Example command inside spec:

```ruby
output = IO.popen({ "DRAFT_DOCS_JSON" => draft_docs.to_json }, [RbConfig.ruby, Rails.root.join("scripts/validate_api_docs_artifact.rb").to_s], &:read)
parsed = JSON.parse(output)
expect(parsed.dig("validation_results", "valid")).to eq(true)
```

**Step 2: Run RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/scripts/validate_api_docs_artifact_spec.rb
```

Expected: FAIL because script does not exist.

**Step 3: Implement minimal script**

Create `scripts/validate_api_docs_artifact.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"

errors = []
raw = ENV.fetch("DRAFT_DOCS_JSON", "{}")
parsed = JSON.parse(raw)
draft_docs = parsed["draft_docs"] || parsed.dig("artifact_kind") == "draft_docs" && parsed["artifact"] || {}

Array(draft_docs["files"]).each do |file|
  next unless file["path"].to_s.match?(/openapi|swagger/)
  next unless file["content"]

  begin
    YAML.safe_load(file["content"], permitted_classes: [Date, Time], aliases: true)
  rescue Psych::Exception => e
    errors << "#{file["path"]}: #{e.message}"
  end
end

puts JSON.generate("validation_results" => { "valid" => errors.empty?, "errors" => errors })
```

This helper intentionally validates parseability only. If shared cookbook infrastructure later standardizes `npx swagger-cli validate` or `npx @redocly/cli lint`, wire that in the shared infrastructure plan instead of duplicating it here.

**Step 4: Run script spec**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/scripts/validate_api_docs_artifact_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add scripts/validate_api_docs_artifact.rb spec/scripts/validate_api_docs_artifact_spec.rb config/queues/api_docs_sync.yml
git commit -m "feat: add api docs validation helper"
```

### Task 14: Add cookbook documentation

**Objective:** Document how to use the new queue and its fake/docker-friendly infrastructure expectations.

**Files:**
- Create: `docs/cookbooks/api-documentation-sync.md`
- Modify: `README.md` only if the project currently indexes cookbook docs there; otherwise skip.

**Step 1: Write doc content**

Create `docs/cookbooks/api-documentation-sync.md` with:

```markdown
# API Documentation Sync Cookbook

Source spec: ../specs/cookbook-03-api-documentation-sync.md
Queue slug: api_docs_sync

## What it does

Scans a target app for routes/controllers/serializers, compares the endpoint inventory to existing OpenAPI/Markdown docs, drafts missing or stale docs, validates examples, and blocks for human review.

## Stages

scan_endpoints -> diff_existing_docs -> draft_documentation -> validate_examples -> human_review -> done

## Inputs

- Repository path or checkout context from the work item.
- Framework type when known.
- Existing docs path(s) when known.

## Infrastructure

This cookbook intentionally does not define shared Docker Compose services. The validation stage is shell-script based and should run inside whatever worker container the shared cookbook infrastructure provides. Optional OpenAPI validators such as `npx @redocly/cli lint` can be added later by the shared infrastructure plan.

## Portability

Queue YAML uses `file://prompts/...` prompt references resolved from `Rails.root` by `db/seeds.rb`. Do not add absolute repo paths.
```

**Step 2: No separate RED required?**

Docs-only changes do not require production-code TDD. If README has a cookbook index, add a small doc-link spec only if such specs already exist.

**Step 3: Commit**

```bash
git add docs/cookbooks/api-documentation-sync.md README.md
git commit -m "docs: add api documentation sync cookbook"
```

### Task 15: Run integration verification

**Objective:** Verify the cookbook queue, predicates, fixture, docs, and portability checks together.

**Files:**
- All files touched above.

**Step 1: Run focused RSpec suite**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/services/engine/predicates/endpoint_inventory_produced_spec.rb \
  spec/services/engine/predicates/docs_diff_produced_spec.rb \
  spec/services/engine/predicates/docs_drafted_spec.rb \
  spec/services/engine/predicates/docs_validated_spec.rb \
  spec/fixtures/api_docs_sync/fixture_contract_spec.rb \
  spec/scripts/validate_api_docs_artifact_spec.rb
```

Expected: PASS.

**Step 2: Run portability search**

```bash
rg '/Users/|working_directory:|file:///|Rails.root.join\("/' config/queues/api_docs_sync.yml prompts/docs_*.md docs/cookbooks/api-documentation-sync.md
```

Expected: no matches. If `rg` exits 1 because there are no matches, that is success.

**Step 3: Verify source spec reference**

```bash
rg 'docs/specs/cookbook-03-api-documentation-sync.md|cookbook-03-api-documentation-sync' docs/cookbooks/api-documentation-sync.md config/queues/api_docs_sync.yml prompts/docs_*.md
```

Expected: at least the cookbook docs reference the source spec.

**Step 4: Run full suite if time permits**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec
```

Expected: PASS.

**Step 5: Final commit if any integration fixes were needed**

```bash
git add <fixed files>
git commit -m "fix: verify api docs sync cookbook integration"
```

## Implementation Task Checklist

- [ ] Add RED seed spec for `api_docs_sync`.
- [ ] Add portable `config/queues/api_docs_sync.yml`.
- [ ] Add `prompts/docs_scan_endpoints.md`.
- [ ] Add `prompts/docs_diff_existing.md`.
- [ ] Add `prompts/docs_draft.md`.
- [ ] Add RED/GREEN `endpoint_inventory_produced` predicate and registry entry.
- [ ] Add RED/GREEN `docs_diff_produced` predicate and registry entry.
- [ ] Add RED/GREEN `docs_drafted` predicate and registry entry.
- [ ] Add RED/GREEN `docs_validated` predicate and registry entry.
- [ ] Add API docs sync fixture Rails API files.
- [ ] Add optional `scripts/validate_api_docs_artifact.rb` with tests.
- [ ] Add cookbook documentation.
- [ ] Run focused RSpec command with rbenv PATH.
- [ ] Run portability search to ensure no absolute paths.
- [ ] Commit each completed slice before moving to the next slice.

## Expected Final Commit Message

If squashing the implementation branch, use:

```bash
git commit -m "feat: add api documentation sync cookbook"
```

If preserving the preferred slice-by-slice history, the implementation should end with these commits or close equivalents:

```text
feat: seed api docs sync cookbook queue
feat: add endpoint inventory predicate
feat: add docs diff predicate
feat: add docs drafted predicate
feat: add api docs validation predicate
test: add api docs sync fixture app
feat: add api docs validation helper
docs: add api documentation sync cookbook
```

## Implementation Dependencies

- Existing shared queue seeding via `db/seeds.rb` and `config/queues/*.yml`.
- Existing `inline_claude`, `shell_script`, and `fake` adapter support.
- Existing `read_repo` skill; add `run_validation` skill only if the skill registry requires skill files for all allowed skills.
- Ruby/YAML validation is enough for this cookbook. Full OpenAPI semantic validation can be supplied by shared cookbook infrastructure later through Node-based tools such as `npx @redocly/cli lint` or `npx swagger-cli validate`.
- No new Docker Compose service should be introduced by this cookbook.
