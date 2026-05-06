# Data Integrity Validator Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `data_integrity` cookbook queue so TaskRail can derive database integrity rules from a Rails app, scan the database with read-only SQL, assess violation impact, draft dry-run-first repair scripts, and stop at a destructive-data human review gate.

**Architecture:** Follow the existing seeded cookbook architecture: portable YAML under `config/queues/`, long prompt bodies loaded through repo-relative `file://` prompt paths, artifact-backed predicates registered in `Engine::PredicateRegistry`, and focused RSpec coverage for queue seeding, predicate contracts, and a Docker-friendly fixture app. The scanning stage uses `shell_script` with explicit read-only safety metadata and deterministic fixture commands; repair scripts are artifacts only and are never executed automatically.

**Tech Stack:** Rails, RSpec, YAML queue seeds, `db/seeds.rb` `file://` prompt resolution via `Rails.root`, `WorkQueue`/`StageConfig`/`Artifact`, `Engine::PredicateRegistry`, inline Claude adapters, shell_script adapter, fake human-review stages, shared cookbook fixture infrastructure, Greg's rbenv Ruby environment.

**Source Spec:** `docs/specs/cookbook-18-data-integrity-validator.md`

---

## Source Requirements Summary

Implement cookbook-18, `Data Integrity Validator`, category `Testing`.

Queue stages:

`define_rules -> scan_violations -> assess_damage -> draft_repairs -> human_review -> done`

Required predicates:

- `rules_defined`: passes when the current claim has an `integrity_rules` artifact with at least one rule.
- `violations_scanned`: passes when the current claim has a `violation_report` artifact with one result per expected rule and aggregate counts.
- `damage_assessed`: passes when the current claim has a `damage_assessment` artifact with findings and priority ordering.
- `repairs_drafted`: passes when the current claim has a `repair_scripts` artifact with at least one idempotent repair and dry-run/prevention details.

Artifacts:

- `integrity_rules`: `{ rules: [{ name, table, type, sql_check, description, severity }] }`
- `violation_report`: `{ results: [{ rule_name, table, passed, violation_count, sample_rows }], total_violations, tables_affected }`
- `damage_assessment`: `{ findings: [{ rule_name, impact, root_cause_hypothesis, scope, urgency, repair_strategy }], priority_order: [] }`
- `repair_scripts`: `{ repairs: [{ violation_ref, script, dry_run_script, prevention_migration, estimated_rows_affected }] }`

Safety:

- The pipeline is read-only until human review.
- `mutate_database` is forbidden on every stage, including `draft_repairs`.
- The shell scan stage may run `SELECT` queries only; no DDL/DML, no migrations, no repair execution.
- Repair scripts are drafted as artifacts with dry-run mode and prevention migrations; humans review and execute separately.

---

## Current Codebase Context

Relevant files and patterns inspected before writing this plan:

- `db/seeds.rb` loads every `config/queues/*.yml`, resolves `agent_prompt: file://...` through `Rails.root.join(relative_path).read`, and upserts `WorkQueue` plus `StageConfig` rows. Do not modify it unless a failing spec proves the existing resolver is insufficient.
- `config/queues/dead_code_removal.yml` is the best current portable cookbook queue example: it uses `file://cookbooks/prompts/...`, repo-relative fixture paths, no `working_directory`, `shell_script` test commands, and fake `human_review`/`done` stages.
- `config/queues/logging_audit.yml`, `config/queues/query_health.yml`, and `config/queues/job_observability.yml` show inline-Claude scan/assess/draft stages plus shell/fake stages and adapter config conventions.
- `app/services/engine/predicate_registry.rb` maps completion criteria names to predicate classes in one hash.
- Existing predicate classes under `app/services/engine/predicates/` generally find an artifact by exact `kind`, validate one required array/object, and return `PredicateResult.pass(evidence: { artifact_id:, ... })` or `PredicateResult.fail(reason: "...")`.
- `app/services/engine/predicates/query_inventory_produced.rb` is the simplest artifact-presence predicate example.
- `app/services/engine/predicates/fixes_drafted.rb` is not reusable for this cookbook because it hardcodes `kind: "fix_patches"`; create a dedicated `RepairsDrafted` predicate for `repair_scripts`.
- `spec/models/work_queue_seed_spec.rb` contains seed assertions for cookbook queues, resolved prompts, adapter configs, and portability guardrails such as no `Rails.root.to_s`, `/Users/`, or `working_directory`.
- `spec/db/seeds/chaos_cookbook_queues_spec.rb` demonstrates compact seed specs that verify every configured stage has a `StageConfig`, resolved prompts, portable Docker paths, and source-spec completion criteria.
- Shared cookbook infrastructure already lives under `cookbooks/` (`cookbooks/docker-compose.yml`, `cookbooks/fake_services/fake_service.rb`, `cookbooks/fixtures/apps/...`, `cookbooks/prompts/...`). Use it; do not create a second top-level Compose stack.
- Current git status contains unrelated untracked files from other cookbook work. Implementation must stage only files touched by each task. This planning card must commit only `docs/plans/cookbooks/18-data-integrity-validator.md`.

Global implementation rules:

- Follow strict TDD for every production/config behavior change: write a failing spec first, run it and confirm the expected RED failure, implement the smallest change, rerun the focused spec, then run relevant broader specs.
- Use Greg's rbenv command shape for every Rails/RSpec command:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Do not hardcode `/Users/gregmushen/work/code/taskrail`, `/Users/`, `Rails.root.to_s`, or any absolute checkout path in queue YAML, prompts, specs, fixtures, scripts, or implementation code.
- Queue YAML should use repo-relative paths and omit `working_directory`; adapters can default to `Rails.root`.
- Prefer cookbook-local prompts and fixtures for this implementation: `file://cookbooks/prompts/data_integrity/...` and `cookbooks/fixtures/apps/data_integrity_app`.
- Commit after each implementation task unless the implementation Kanban card explicitly requests a single final commit; if so, squash task commits before completion.
- This planning task itself must commit only this file with: `git commit -m "docs: plan cookbook 18 data-integrity-validator"`.

---

## Files to Create or Modify During Implementation

Create:

- `config/queues/data_integrity.yml`
- `cookbooks/prompts/data_integrity/define_rules.md`
- `cookbooks/prompts/data_integrity/scan_violations.md`
- `cookbooks/prompts/data_integrity/assess_damage.md`
- `cookbooks/prompts/data_integrity/draft_repairs.md`
- `app/services/engine/predicates/rules_defined.rb`
- `app/services/engine/predicates/violations_scanned.rb`
- `app/services/engine/predicates/damage_assessed.rb`
- `app/services/engine/predicates/repairs_drafted.rb`
- `spec/services/engine/predicates/rules_defined_spec.rb`
- `spec/services/engine/predicates/violations_scanned_spec.rb`
- `spec/services/engine/predicates/damage_assessed_spec.rb`
- `spec/services/engine/predicates/repairs_drafted_spec.rb`
- `spec/services/engine/data_integrity_workflow_integration_spec.rb`
- `spec/system/data_integrity_cookbook_spec.rb` if the implementation wants a higher-level fixture contract separate from the workflow spec; otherwise keep this coverage in `spec/services/engine/data_integrity_workflow_integration_spec.rb`.
- `cookbooks/fixtures/apps/data_integrity_app/README.md`
- `cookbooks/fixtures/apps/data_integrity_app/Gemfile`
- `cookbooks/fixtures/apps/data_integrity_app/app/models/customer.rb`
- `cookbooks/fixtures/apps/data_integrity_app/app/models/order.rb`
- `cookbooks/fixtures/apps/data_integrity_app/app/models/invoice.rb`
- `cookbooks/fixtures/apps/data_integrity_app/app/models/user.rb`
- `cookbooks/fixtures/apps/data_integrity_app/app/models/comment.rb`
- `cookbooks/fixtures/apps/data_integrity_app/db/schema.rb`
- `cookbooks/fixtures/apps/data_integrity_app/db/migrate/20240101000000_create_integrity_fixture.rb`
- `cookbooks/fixtures/apps/data_integrity_app/db/seeds.rb`
- `cookbooks/fixtures/apps/data_integrity_app/scripts/readonly_integrity_scan.rb`
- `cookbooks/fixtures/apps/data_integrity_app/scripts/README.md`
- `docs/cookbooks/data-integrity-validator.md` if the implementation card includes cookbook docs; otherwise create a follow-up docs card.

Modify:

- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Do not modify unless a failing spec proves it is necessary:

- `db/seeds.rb`; prompt file resolution is already implemented and portable.
- Shared adapter classes (`Adapters::InlineClaudeAdapter`, `Adapters::ShellScriptAdapter`, Docker/fake infrastructure).
- `cookbooks/docker-compose.yml`; this cookbook can use static fixture files and a deterministic Ruby scan script. Only add a Compose service if the existing shell adapter cannot run the fixture script, and write a RED spec first.
- Existing generic predicates such as `FixesDrafted`; `repair_scripts` has a different destructive-data safety contract and deserves its own predicate.

---

## Queue YAML Target

Create `config/queues/data_integrity.yml` with this shape. Keep every path repo-relative and omit `working_directory`.

```yaml
name: Data Integrity Validator
slug: data_integrity
stages:
  - define_rules
  - scan_violations
  - assess_damage
  - draft_repairs
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 0
stage_configs:
  define_rules:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [rules_defined]
    agent_prompt: file://cookbooks/prompts/data_integrity/define_rules.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: integrity_rules
      fixture_app: cookbooks/fixtures/apps/data_integrity_app
      read_only: true
      rule_categories:
        - referential_integrity
        - constraint_violation
        - enum_consistency
        - temporal_sanity
        - business_rule
        - staleness
  scan_violations:
    adapter_type: shell_script
    allowed_skills: [query_database_readonly]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [violations_scanned]
    agent_prompt: file://cookbooks/prompts/data_integrity/scan_violations.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: integrity_rules
      output_artifact_kind: violation_report
      fixture_app: cookbooks/fixtures/apps/data_integrity_app
      read_only: true
      sample_row_limit: 10
      disallowed_sql_patterns:
        - "\\bINSERT\\b"
        - "\\bUPDATE\\b"
        - "\\bDELETE\\b"
        - "\\bALTER\\b"
        - "\\bDROP\\b"
        - "\\bTRUNCATE\\b"
      commands:
        - name: data-integrity-readonly-fixture-scan
          command: ruby cookbooks/fixtures/apps/data_integrity_app/scripts/readonly_integrity_scan.rb
          artifact: violation_report
  assess_damage:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [damage_assessed]
    agent_prompt: file://cookbooks/prompts/data_integrity/assess_damage.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: violation_report
      output_artifact_kind: damage_assessment
      fixture_app: cookbooks/fixtures/apps/data_integrity_app
      read_only: true
  draft_repairs:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy, mutate_database]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [repairs_drafted]
    agent_prompt: file://cookbooks/prompts/data_integrity/draft_repairs.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: damage_assessment
      secondary_input_artifact_kind: integrity_rules
      output_artifact_kind: repair_scripts
      fixture_app: cookbooks/fixtures/apps/data_integrity_app
      read_only: true
      require_dry_run: true
      require_idempotent_repairs: true
      spawn_targets:
        missing_validation: development
        repeated_integrity_failure: development
        destructive_repair_review: operations
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: [mutate_database]
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: DATA REPAIRS ARE DESTRUCTIVE. Review every generated repair script, run dry-run mode first, verify before/after counts, inspect prevention migrations separately, then approve or reject manual execution. TaskRail must not execute repairs automatically.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: [mutate_database]
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

Notes:

- The source spec used `file://prompts/integrity_*.md`; this plan intentionally uses `file://cookbooks/prompts/data_integrity/...` to match the newer shared cookbook directory contract used by `dead_code_removal` and `migration_safety` plans.
- `scan_violations` is `shell_script` because the source spec requires executing SQL-like checks. The fixture command must be deterministic and local; in production, the adapter can receive real read-only database connection details through existing secure runner context.
- `draft_repairs` still forbids `mutate_database`; it drafts scripts and migrations as text artifacts only.
- The `disallowed_sql_patterns` config is an explicit safety contract for future adapter/harness validation. Add a failing spec before implementing any adapter enforcement beyond metadata persistence.

---

## Prompt File Targets

### `cookbooks/prompts/data_integrity/define_rules.md`

```markdown
# Data Integrity: Define Rules

You are the `define_rules` stage for the `data_integrity` queue.

Inputs:
- Repository root from the runner working directory; never assume an absolute path.
- Optional fixture app from adapter config: `cookbooks/fixtures/apps/data_integrity_app`.
- Rails schema files such as `db/schema.rb` and migrations.
- Model validations, enums, associations, callbacks, and business-rule service code.

Task:
1. Read schema, migrations, and models.
2. Derive integrity rules from database constraints, model validations, enum definitions, associations, and obvious business invariants.
3. Include these categories where present: referential integrity, constraint violations, enum consistency, temporal sanity, business rules, and stale denormalized data/counter caches.
4. For every rule, produce a read-only SQL check. The SQL must be a `SELECT` query and must not mutate data.
5. Prefer clear rule names that downstream stages can reference exactly.

Return exactly one `integrity_rules` artifact as JSON:

```json
{
  "rules": [
    {
      "name": "orders_customer_fk_exists",
      "table": "orders",
      "type": "referential_integrity",
      "sql_check": "SELECT * FROM orders WHERE customer_id IS NOT NULL AND customer_id NOT IN (SELECT id FROM customers)",
      "description": "Orders with a customer_id must reference an existing customer.",
      "severity": "critical"
    }
  ]
}
```

Safety:
- Do not edit files.
- Do not deploy.
- Do not mutate the database.
- Do not include `INSERT`, `UPDATE`, `DELETE`, `ALTER`, `DROP`, `TRUNCATE`, migrations, or repair commands in `sql_check`.
```

### `cookbooks/prompts/data_integrity/scan_violations.md`

```markdown
# Data Integrity: Scan Violations

You are the `scan_violations` stage for the `data_integrity` queue.

Inputs:
- `integrity_rules` artifact from the prior stage.
- Read-only database connection supplied by the runner, or fixture data from `cookbooks/fixtures/apps/data_integrity_app`.
- Adapter config `sample_row_limit`, defaulting to 10.

Task:
1. For each integrity rule, validate the SQL is read-only before execution.
2. Run the SQL check as a read-only query.
3. Count total violating rows for each rule.
4. Include up to 10 sample rows for failing rules.
5. Preserve one result for every input rule, even if the rule passes.

Return exactly one `violation_report` artifact as JSON:

```json
{
  "results": [
    {
      "rule_name": "orders_customer_fk_exists",
      "table": "orders",
      "passed": false,
      "violation_count": 2,
      "sample_rows": [{ "id": 42, "customer_id": "missing" }]
    }
  ],
  "total_violations": 2,
  "tables_affected": ["orders"]
}
```

Safety:
- READ-ONLY QUERIES ONLY.
- Never run `INSERT`, `UPDATE`, `DELETE`, `ALTER`, `DROP`, `TRUNCATE`, migrations, repair scripts, or application code that writes data.
- If a rule is not safely executable, mark it failed with an explanatory result rather than trying to rewrite and mutate data.
```

### `cookbooks/prompts/data_integrity/assess_damage.md`

```markdown
# Data Integrity: Assess Damage

You are the `assess_damage` stage for the `data_integrity` queue.

Inputs:
- `violation_report` artifact.
- Optional source context from schema/models when available.

Task:
1. For every failing rule, assess user impact, likely root cause, scope, urgency, and repair strategy.
2. Distinguish active data corruption from stable historical cleanup and cosmetic inconsistency.
3. Prioritize repairs by risk, blast radius, and confidence.
4. Note when prevention work should be spawned to `development` because bad data can recur.

Return exactly one `damage_assessment` artifact as JSON:

```json
{
  "findings": [
    {
      "rule_name": "orders_customer_fk_exists",
      "impact": "Orders with missing customers can crash fulfillment and support views.",
      "root_cause_hypothesis": "Historical migration deleted customers without dependent cleanup or FK enforcement.",
      "scope": "2 orders in fixture; production count from violation_report.",
      "urgency": "fix_now",
      "repair_strategy": "Dry-run delete orphaned draft orders; manually reassign paid orders to a reviewed placeholder customer. Add FK/preventive validation."
    }
  ],
  "priority_order": ["orders_customer_fk_exists"]
}
```

Safety:
- Do not propose automatic execution.
- Flag destructive repairs for human review.
- Preserve uncertainty in root-cause hypotheses instead of inventing facts.
```

### `cookbooks/prompts/data_integrity/draft_repairs.md`

```markdown
# Data Integrity: Draft Repairs

You are the `draft_repairs` stage for the `data_integrity` queue.

Inputs:
- `damage_assessment` artifact.
- `integrity_rules` artifact.
- Schema and source code when available.

Task:
1. Draft repair scripts for urgent or high-priority findings only.
2. Every repair must be idempotent and safe to run twice.
3. Every repair must include a dry-run mode that reports what would change without changing data.
4. Every repair must include count-before and count-after checks.
5. Wrap data changes in transactions where appropriate.
6. Draft prevention migrations or validations separately from data repair scripts.
7. Explicitly state that generated scripts are for human review and manual execution only.

Return exactly one `repair_scripts` artifact as JSON:

```json
{
  "repairs": [
    {
      "violation_ref": "orders_customer_fk_exists",
      "script": "# Ruby/Rails runner script with dry_run: false guarded by manual flag...",
      "dry_run_script": "# Ruby/Rails runner script with dry_run: true, SELECT/count only...",
      "prevention_migration": "class AddOrdersCustomerForeignKey < ActiveRecord::Migration[8.0] ... end",
      "estimated_rows_affected": 2
    }
  ]
}
```

Safety:
- Do not execute any repair.
- Do not deploy.
- Do not mutate the database.
- Include dry-run instructions before any destructive section.
- If a safe repair cannot be drafted, return a finding that blocks for human analysis instead of guessing.
```

---

## Fixture App Target

Create `cookbooks/fixtures/apps/data_integrity_app/` as a minimal Rails-shaped static fixture. It does not need to boot a full Rails server; it needs enough schema/model/source text plus deterministic script output to prove the cookbook can reason about integrity categories.

### Required fixture files

`cookbooks/fixtures/apps/data_integrity_app/README.md`:

```markdown
# Data Integrity Fixture App

Static Rails-shaped fixture for the TaskRail Data Integrity Validator cookbook.

It intentionally contains examples of:
- orphaned foreign-key-like references (`orders.customer_id`)
- invalid enum values (`users.status`)
- negative amounts (`invoices.amount_cents`)
- temporal anomalies (`created_at > updated_at`, future timestamps)
- stale counter cache fields (`customers.orders_count`)

The `scripts/readonly_integrity_scan.rb` script emits deterministic JSON and must not mutate files or databases.
```

`cookbooks/fixtures/apps/data_integrity_app/Gemfile`:

```ruby
source "https://rubygems.org"

gem "rails", "~> 8.0"
gem "sqlite3"
```

`cookbooks/fixtures/apps/data_integrity_app/app/models/customer.rb`:

```ruby
class Customer < ApplicationRecord
  has_many :orders, dependent: :restrict_with_error

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :orders_count, numericality: { greater_than_or_equal_to: 0 }
end
```

`cookbooks/fixtures/apps/data_integrity_app/app/models/order.rb`:

```ruby
class Order < ApplicationRecord
  belongs_to :customer
  has_many :invoices, dependent: :restrict_with_error

  enum :status, { draft: 0, paid: 1, fulfilled: 2, cancelled: 3 }

  validates :total_cents, numericality: { greater_than_or_equal_to: 0 }
end
```

`cookbooks/fixtures/apps/data_integrity_app/app/models/invoice.rb`:

```ruby
class Invoice < ApplicationRecord
  belongs_to :order

  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :issued_at, presence: true
end
```

`cookbooks/fixtures/apps/data_integrity_app/app/models/user.rb`:

```ruby
class User < ApplicationRecord
  enum :status, { active: "active", inactive: "inactive", suspended: "suspended" }

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
end
```

`cookbooks/fixtures/apps/data_integrity_app/app/models/comment.rb`:

```ruby
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :order, optional: true

  validates :body, presence: true
end
```

`cookbooks/fixtures/apps/data_integrity_app/db/schema.rb` should define `customers`, `orders`, `invoices`, `users`, and `comments` with realistic columns and comments documenting expected broken data. Keep it static and portable.

`cookbooks/fixtures/apps/data_integrity_app/db/seeds.rb` should contain commented/sample fixture rows for at least:

- an order whose `customer_id` is missing,
- a user with `status: "paused"`,
- an invoice with `amount_cents: -500`,
- a record where `created_at > updated_at`,
- a stale `customers.orders_count` mismatch.

`cookbooks/fixtures/apps/data_integrity_app/scripts/readonly_integrity_scan.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

report = {
  results: [
    {
      rule_name: "orders_customer_fk_exists",
      table: "orders",
      passed: false,
      violation_count: 2,
      sample_rows: [{ id: 101, customer_id: "missing-customer" }]
    },
    {
      rule_name: "users_status_enum_valid",
      table: "users",
      passed: false,
      violation_count: 1,
      sample_rows: [{ id: 55, status: "paused" }]
    },
    {
      rule_name: "invoices_amount_non_negative",
      table: "invoices",
      passed: false,
      violation_count: 1,
      sample_rows: [{ id: 77, amount_cents: -500 }]
    },
    {
      rule_name: "timestamps_not_in_future",
      table: "orders",
      passed: false,
      violation_count: 1,
      sample_rows: [{ id: 88, created_at: "2099-01-01T00:00:00Z" }]
    },
    {
      rule_name: "customer_orders_count_matches_orders",
      table: "customers",
      passed: false,
      violation_count: 1,
      sample_rows: [{ id: 12, orders_count: 3, actual_orders_count: 2 }]
    }
  ],
  total_violations: 6,
  tables_affected: %w[orders users invoices customers]
}

puts JSON.pretty_generate(report)
```

Make the script executable in the implementation task with:

```bash
chmod +x cookbooks/fixtures/apps/data_integrity_app/scripts/readonly_integrity_scan.rb
```

---

### Task 1: Add RED specs for the `rules_defined` predicate

**Objective:** Prove `rules_defined` requires an `integrity_rules` artifact with at least one rule containing stable evidence fields.

**Files:**
- Create: `spec/services/engine/predicates/rules_defined_spec.rb`
- Later create: `app/services/engine/predicates/rules_defined.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/rules_defined_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::RulesDefined do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(name: "Data Integrity Validator", slug: "data-integrity-#{SecureRandom.hex(4)}", stages: %w[define_rules done])
    queue.stage_configs.create!(stage_name: "define_rules", adapter_type: "fake")
    item = WorkItem.create!(title: "Define integrity rules", spec_url: "local", work_queue: queue, stage_name: "define_rules")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when integrity_rules has at least one rule" do
    claim = build_claim(artifacts: [
      {
        kind: "integrity_rules",
        data: {
          "rules" => [
            {
              "name" => "orders_customer_fk_exists",
              "table" => "orders",
              "type" => "referential_integrity",
              "sql_check" => "SELECT * FROM orders WHERE customer_id NOT IN (SELECT id FROM customers)",
              "description" => "Orders must reference existing customers.",
              "severity" => "critical"
            }
          ]
        }
      }
    ])

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to include(:artifact_id, rule_count: 1, tables: ["orders"])
  end

  it "fails when the artifact is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no integrity_rules artifact found")
  end

  it "fails when rules are empty" do
    claim = build_claim(artifacts: [{ kind: "integrity_rules", data: { "rules" => [] } }])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("integrity_rules artifact has no rules")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/rules_defined_spec.rb
```

Expected: FAIL with an uninitialized constant for `Engine::Predicates::RulesDefined`.

**Step 3: Write minimal implementation**

Create `app/services/engine/predicates/rules_defined.rb`:

```ruby
module Engine
  module Predicates
    class RulesDefined
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "integrity_rules").first
        return PredicateResult.fail(reason: "no integrity_rules artifact found") unless artifact

        rules = Array(artifact.data["rules"])
        return PredicateResult.fail(reason: "integrity_rules artifact has no rules") if rules.empty?

        tables = rules.filter_map { |rule| rule["table"] }.uniq
        PredicateResult.pass(evidence: { artifact_id: artifact.id, rule_count: rules.count, tables: tables })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/rules_defined_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/rules_defined.rb spec/services/engine/predicates/rules_defined_spec.rb
git commit -m "feat: add data integrity rules predicate"
```

---

### Task 2: Add RED specs for the `violations_scanned` predicate

**Objective:** Prove `violations_scanned` requires a `violation_report` artifact with results, aggregate violation count, and affected tables.

**Files:**
- Create: `spec/services/engine/predicates/violations_scanned_spec.rb`
- Later create: `app/services/engine/predicates/violations_scanned.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/violations_scanned_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ViolationsScanned do
  def build_claim(artifact_data: nil)
    queue = WorkQueue.create!(name: "Data Integrity Validator", slug: "data-integrity-#{SecureRandom.hex(4)}", stages: %w[scan_violations done])
    queue.stage_configs.create!(stage_name: "scan_violations", adapter_type: "fake")
    item = WorkItem.create!(title: "Scan violations", spec_url: "local", work_queue: queue, stage_name: "scan_violations")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    Artifact.create!(work_item: item, claim: claim, kind: "violation_report", data: artifact_data) if artifact_data
    claim
  end

  it "passes with aggregate evidence when report contains scan results" do
    claim = build_claim(artifact_data: {
      "results" => [
        { "rule_name" => "orders_customer_fk_exists", "table" => "orders", "passed" => false, "violation_count" => 2, "sample_rows" => [{ "id" => 101 }] },
        { "rule_name" => "users_status_enum_valid", "table" => "users", "passed" => true, "violation_count" => 0, "sample_rows" => [] }
      ],
      "total_violations" => 2,
      "tables_affected" => ["orders"]
    })

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to include(:artifact_id, result_count: 2, total_violations: 2, tables_affected: ["orders"])
  end

  it "fails when the report is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no violation_report artifact found")
  end

  it "fails when there are no per-rule results" do
    result = described_class.new(claim: build_claim(artifact_data: { "results" => [], "total_violations" => 0, "tables_affected" => [] })).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("violation_report artifact has no results")
  end
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/violations_scanned_spec.rb
```

Expected: FAIL with uninitialized constant `Engine::Predicates::ViolationsScanned`.

**Step 3: Write minimal implementation**

Create `app/services/engine/predicates/violations_scanned.rb`:

```ruby
module Engine
  module Predicates
    class ViolationsScanned
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "violation_report").first
        return PredicateResult.fail(reason: "no violation_report artifact found") unless artifact

        results = Array(artifact.data["results"])
        return PredicateResult.fail(reason: "violation_report artifact has no results") if results.empty?

        total_violations = artifact.data.fetch("total_violations", results.sum { |row| row["violation_count"].to_i })
        tables_affected = Array(artifact.data["tables_affected"])
        PredicateResult.pass(evidence: { artifact_id: artifact.id, result_count: results.count, total_violations: total_violations, tables_affected: tables_affected })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/violations_scanned_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/violations_scanned.rb spec/services/engine/predicates/violations_scanned_spec.rb
git commit -m "feat: add data integrity violation predicate"
```

---

### Task 3: Add RED specs for `damage_assessed` and `repairs_drafted`

**Objective:** Prove the assessment and repair predicates enforce non-empty downstream artifacts and safety-relevant repair fields.

**Files:**
- Create: `spec/services/engine/predicates/damage_assessed_spec.rb`
- Create: `spec/services/engine/predicates/repairs_drafted_spec.rb`
- Later create: `app/services/engine/predicates/damage_assessed.rb`
- Later create: `app/services/engine/predicates/repairs_drafted.rb`

**Step 1: Write failing assessment test**

Create `spec/services/engine/predicates/damage_assessed_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::DamageAssessed do
  def build_claim(data: nil)
    queue = WorkQueue.create!(name: "Data Integrity Validator", slug: "data-integrity-#{SecureRandom.hex(4)}", stages: %w[assess_damage done])
    queue.stage_configs.create!(stage_name: "assess_damage", adapter_type: "fake")
    item = WorkItem.create!(title: "Assess damage", spec_url: "local", work_queue: queue, stage_name: "assess_damage")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    Artifact.create!(work_item: item, claim: claim, kind: "damage_assessment", data: data) if data
    claim
  end

  it "passes when damage_assessment has findings and priority order" do
    claim = build_claim(data: {
      "findings" => [
        {
          "rule_name" => "orders_customer_fk_exists",
          "impact" => "Fulfillment crashes",
          "root_cause_hypothesis" => "Missing FK cleanup",
          "scope" => "2 rows",
          "urgency" => "fix_now",
          "repair_strategy" => "Dry-run reassign paid orders"
        }
      ],
      "priority_order" => ["orders_customer_fk_exists"]
    })

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to include(:artifact_id, finding_count: 1, priority_count: 1)
  end

  it "fails with no artifact" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no damage_assessment artifact found")
  end

  it "fails with no findings" do
    result = described_class.new(claim: build_claim(data: { "findings" => [], "priority_order" => [] })).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("damage_assessment artifact has no findings")
  end
end
```

**Step 2: Write failing repair test**

Create `spec/services/engine/predicates/repairs_drafted_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::RepairsDrafted do
  def build_claim(data: nil)
    queue = WorkQueue.create!(name: "Data Integrity Validator", slug: "data-integrity-#{SecureRandom.hex(4)}", stages: %w[draft_repairs done])
    queue.stage_configs.create!(stage_name: "draft_repairs", adapter_type: "fake")
    item = WorkItem.create!(title: "Draft repairs", spec_url: "local", work_queue: queue, stage_name: "draft_repairs")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    Artifact.create!(work_item: item, claim: claim, kind: "repair_scripts", data: data) if data
    claim
  end

  it "passes when repair_scripts has dry-run and prevention details" do
    claim = build_claim(data: {
      "repairs" => [
        {
          "violation_ref" => "orders_customer_fk_exists",
          "script" => "Order.transaction { ... }",
          "dry_run_script" => "puts Order.where(...).count",
          "prevention_migration" => "class AddOrdersCustomerForeignKey < ActiveRecord::Migration[8.0]; end",
          "estimated_rows_affected" => 2
        }
      ]
    })

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to include(:artifact_id, repair_count: 1, dry_run_count: 1)
  end

  it "fails with no artifact" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no repair_scripts artifact found")
  end

  it "fails when repairs are missing" do
    result = described_class.new(claim: build_claim(data: { "repairs" => [] })).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("repair_scripts artifact has no repairs")
  end

  it "fails when a repair lacks a dry-run script" do
    result = described_class.new(claim: build_claim(data: { "repairs" => [{ "violation_ref" => "orders_customer_fk_exists", "script" => "Order.delete_all" }] })).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("repair_scripts artifact has repairs without dry_run_script")
  end
end
```

**Step 3: Run tests to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/damage_assessed_spec.rb spec/services/engine/predicates/repairs_drafted_spec.rb
```

Expected: FAIL with uninitialized constants.

**Step 4: Write minimal implementations**

Create `app/services/engine/predicates/damage_assessed.rb`:

```ruby
module Engine
  module Predicates
    class DamageAssessed
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "damage_assessment").first
        return PredicateResult.fail(reason: "no damage_assessment artifact found") unless artifact

        findings = Array(artifact.data["findings"])
        return PredicateResult.fail(reason: "damage_assessment artifact has no findings") if findings.empty?

        priority_order = Array(artifact.data["priority_order"])
        PredicateResult.pass(evidence: { artifact_id: artifact.id, finding_count: findings.count, priority_count: priority_order.count })
      end
    end
  end
end
```

Create `app/services/engine/predicates/repairs_drafted.rb`:

```ruby
module Engine
  module Predicates
    class RepairsDrafted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "repair_scripts").first
        return PredicateResult.fail(reason: "no repair_scripts artifact found") unless artifact

        repairs = Array(artifact.data["repairs"])
        return PredicateResult.fail(reason: "repair_scripts artifact has no repairs") if repairs.empty?

        dry_run_count = repairs.count { |repair| repair["dry_run_script"].present? }
        return PredicateResult.fail(reason: "repair_scripts artifact has repairs without dry_run_script") if dry_run_count != repairs.count

        PredicateResult.pass(evidence: { artifact_id: artifact.id, repair_count: repairs.count, dry_run_count: dry_run_count })
      end
    end
  end
end
```

**Step 5: Run tests to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/damage_assessed_spec.rb spec/services/engine/predicates/repairs_drafted_spec.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git add \
  app/services/engine/predicates/damage_assessed.rb \
  app/services/engine/predicates/repairs_drafted.rb \
  spec/services/engine/predicates/damage_assessed_spec.rb \
  spec/services/engine/predicates/repairs_drafted_spec.rb
git commit -m "feat: add data integrity assessment predicates"
```

---

### Task 4: Register data integrity predicates

**Objective:** Make all four new completion criteria resolvable through `Engine::PredicateRegistry`.

**Files:**
- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing registry assertions**

Add to the known predicate names example in `spec/services/engine/predicate_registry_spec.rb`:

```ruby
expect(described_class.resolve("rules_defined")).to eq(Engine::Predicates::RulesDefined)
expect(described_class.resolve("violations_scanned")).to eq(Engine::Predicates::ViolationsScanned)
expect(described_class.resolve("damage_assessed")).to eq(Engine::Predicates::DamageAssessed)
expect(described_class.resolve("repairs_drafted")).to eq(Engine::Predicates::RepairsDrafted)
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with unknown predicate for `rules_defined`.

**Step 3: Register predicates**

Modify `app/services/engine/predicate_registry.rb` and add these entries near related cookbook predicates:

```ruby
"rules_defined" => Predicates::RulesDefined,
"violations_scanned" => Predicates::ViolationsScanned,
"damage_assessed" => Predicates::DamageAssessed,
"repairs_drafted" => Predicates::RepairsDrafted,
```

**Step 4: Run test to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicate_registry.rb spec/services/engine/predicate_registry_spec.rb
git commit -m "feat: register data integrity predicates"
```

---

### Task 5: Add RED seed spec for the `data_integrity` queue

**Objective:** Prove the queue seeds every stage, resolves prompt files, persists safety/adapter config, and remains portable.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/data_integrity.yml`
- Later create: prompt files under `cookbooks/prompts/data_integrity/`

**Step 1: Write failing seed spec**

Add an example to `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the data integrity validator cookbook queue with read-only safety config" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "data_integrity")
  expect(queue.name).to eq("Data Integrity Validator")
  expect(queue.stages).to eq(%w[define_rules scan_violations assess_damage draft_repairs human_review done])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_max_retries" => 2,
    "default_timeout_seconds" => 600,
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 0
  )

  define = queue.stage_configs.find_by!(stage_name: "define_rules")
  expect(define.adapter_type).to eq("inline_claude")
  expect(define.model_override).to eq("claude-sonnet-4-20250514")
  expect(define.allowed_skills).to eq(["read_repo"])
  expect(define.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
  expect(define.completion_criteria).to eq(["rules_defined"])
  expect(define.agent_prompt).to include("# Data Integrity: Define Rules")
  expect(define.agent_prompt).not_to start_with("file://")
  expect(define.agent_prompt).not_to include(Rails.root.to_s)
  expect(define.adapter_config).to include(
    "output_artifact_kind" => "integrity_rules",
    "fixture_app" => "cookbooks/fixtures/apps/data_integrity_app",
    "read_only" => true
  )

  scan = queue.stage_configs.find_by!(stage_name: "scan_violations")
  expect(scan.adapter_type).to eq("shell_script")
  expect(scan.allowed_skills).to eq(["query_database_readonly"])
  expect(scan.forbidden_skills).to include("edit_files", "deploy", "mutate_database")
  expect(scan.completion_criteria).to eq(["violations_scanned"])
  expect(scan.agent_prompt).to include("# Data Integrity: Scan Violations")
  expect(scan.adapter_config).to include(
    "input_artifact_kind" => "integrity_rules",
    "output_artifact_kind" => "violation_report",
    "read_only" => true,
    "sample_row_limit" => 10
  )
  expect(scan.adapter_config["commands"].first).to include(
    "name" => "data-integrity-readonly-fixture-scan",
    "artifact" => "violation_report"
  )
  expect(scan.adapter_config["commands"].first["command"]).to eq("ruby cookbooks/fixtures/apps/data_integrity_app/scripts/readonly_integrity_scan.rb")

  assess = queue.stage_configs.find_by!(stage_name: "assess_damage")
  expect(assess.completion_criteria).to eq(["damage_assessed"])
  expect(assess.agent_prompt).to include("# Data Integrity: Assess Damage")
  expect(assess.adapter_config).to include("input_artifact_kind" => "violation_report", "output_artifact_kind" => "damage_assessment", "read_only" => true)

  draft = queue.stage_configs.find_by!(stage_name: "draft_repairs")
  expect(draft.completion_criteria).to eq(["repairs_drafted"])
  expect(draft.forbidden_skills).to include("mutate_database")
  expect(draft.agent_prompt).to include("# Data Integrity: Draft Repairs")
  expect(draft.adapter_config).to include(
    "input_artifact_kind" => "damage_assessment",
    "secondary_input_artifact_kind" => "integrity_rules",
    "output_artifact_kind" => "repair_scripts",
    "read_only" => true,
    "require_dry_run" => true,
    "require_idempotent_repairs" => true
  )

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.timeout_seconds).to eq(86_400)
  expect(human_review.forbidden_skills).to include("mutate_database")
  expect(human_review.agent_prompt).to include("DATA REPAIRS ARE DESTRUCTIVE")

  serialized_queue = Rails.root.join("config/queues/data_integrity.yml").read
  expect(serialized_queue).not_to include(Rails.root.to_s)
  expect(serialized_queue).not_to include("/Users/")
  expect(serialized_queue).not_to include("working_directory:")
  expect(serialized_queue).to include("file://cookbooks/prompts/data_integrity/define_rules.md")
  expect(serialized_queue).to include("file://cookbooks/prompts/data_integrity/scan_violations.md")
  expect(serialized_queue).to include("file://cookbooks/prompts/data_integrity/assess_damage.md")
  expect(serialized_queue).to include("file://cookbooks/prompts/data_integrity/draft_repairs.md")
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb:NEW_LINE_NUMBER
```

Expected: FAIL with `Couldn't find WorkQueue` or missing `config/queues/data_integrity.yml`/prompt files.

**Step 3: Create YAML and prompts**

Create `config/queues/data_integrity.yml` from the Queue YAML Target section.

Create these prompt files from the Prompt File Targets section:

- `cookbooks/prompts/data_integrity/define_rules.md`
- `cookbooks/prompts/data_integrity/scan_violations.md`
- `cookbooks/prompts/data_integrity/assess_damage.md`
- `cookbooks/prompts/data_integrity/draft_repairs.md`

**Step 4: Run test to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb:NEW_LINE_NUMBER
```

Expected: PASS.

**Step 5: Run broader seed spec**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git add \
  config/queues/data_integrity.yml \
  cookbooks/prompts/data_integrity/define_rules.md \
  cookbooks/prompts/data_integrity/scan_violations.md \
  cookbooks/prompts/data_integrity/assess_damage.md \
  cookbooks/prompts/data_integrity/draft_repairs.md \
  spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed data integrity cookbook queue"
```

---

### Task 6: Add the Docker-friendly fixture and read-only scan script

**Objective:** Provide deterministic fixture infrastructure that proves the cookbook covers orphaned records, invalid enums, temporal anomalies, negative amounts, and stale counters without using a real database or mutating data.

**Files:**
- Create fixture files listed in the Fixture App Target section.
- Create or modify: `spec/services/engine/data_integrity_workflow_integration_spec.rb`

**Step 1: Write failing fixture/workflow spec**

Create `spec/services/engine/data_integrity_workflow_integration_spec.rb`:

```ruby
require "rails_helper"
require "json"
require "open3"

RSpec.describe "data integrity cookbook workflow" do
  it "runs the fixture scan script and emits a violation_report without mutations" do
    script = Rails.root.join("cookbooks/fixtures/apps/data_integrity_app/scripts/readonly_integrity_scan.rb")

    stdout, stderr, status = Open3.capture3("ruby", script.to_s)

    expect(status).to be_success, stderr
    report = JSON.parse(stdout)
    expect(report["results"].map { |row| row["rule_name"] }).to include(
      "orders_customer_fk_exists",
      "users_status_enum_valid",
      "invoices_amount_non_negative",
      "timestamps_not_in_future",
      "customer_orders_count_matches_orders"
    )
    expect(report["total_violations"]).to be > 0
    expect(report["tables_affected"]).to include("orders", "users", "invoices", "customers")
  end

  it "can satisfy all data integrity predicates with source-spec artifact kinds" do
    queue = WorkQueue.create!(
      name: "Data Integrity Validator",
      slug: "data-integrity-flow-#{SecureRandom.hex(4)}",
      stages: %w[define_rules scan_violations assess_damage draft_repairs human_review done]
    )
    %w[define_rules scan_violations assess_damage draft_repairs human_review done].each do |stage_name|
      queue.stage_configs.create!(stage_name: stage_name, adapter_type: "fake")
    end
    item = WorkItem.create!(title: "Validate data", spec_url: "local", work_queue: queue, stage_name: "draft_repairs")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)

    Artifact.create!(work_item: item, claim: claim, kind: "integrity_rules", data: {
      "rules" => [{ "name" => "orders_customer_fk_exists", "table" => "orders", "type" => "referential_integrity", "sql_check" => "SELECT * FROM orders", "description" => "Orders must reference customers", "severity" => "critical" }]
    })
    Artifact.create!(work_item: item, claim: claim, kind: "violation_report", data: {
      "results" => [{ "rule_name" => "orders_customer_fk_exists", "table" => "orders", "passed" => false, "violation_count" => 2, "sample_rows" => [{ "id" => 101 }] }],
      "total_violations" => 2,
      "tables_affected" => ["orders"]
    })
    Artifact.create!(work_item: item, claim: claim, kind: "damage_assessment", data: {
      "findings" => [{ "rule_name" => "orders_customer_fk_exists", "impact" => "Crashes", "root_cause_hypothesis" => "Missing FK", "scope" => "2 rows", "urgency" => "fix_now", "repair_strategy" => "Manual review" }],
      "priority_order" => ["orders_customer_fk_exists"]
    })
    Artifact.create!(work_item: item, claim: claim, kind: "repair_scripts", data: {
      "repairs" => [{ "violation_ref" => "orders_customer_fk_exists", "script" => "Order.transaction { ... }", "dry_run_script" => "puts count", "prevention_migration" => "add_foreign_key :orders, :customers", "estimated_rows_affected" => 2 }]
    })

    expect(Engine::Predicates::RulesDefined.new(claim: claim).call).to be_passed
    expect(Engine::Predicates::ViolationsScanned.new(claim: claim).call).to be_passed
    expect(Engine::Predicates::DamageAssessed.new(claim: claim).call).to be_passed
    expect(Engine::Predicates::RepairsDrafted.new(claim: claim).call).to be_passed
  end
end
```

**Step 2: Run test to verify RED**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/data_integrity_workflow_integration_spec.rb
```

Expected: FAIL because the fixture script and fixture files do not exist yet.

**Step 3: Add fixture files**

Create every file from the Fixture App Target section. Keep data static. Do not connect to a real database. Ensure the script emits valid JSON and performs no writes.

**Step 4: Run test to verify GREEN**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/data_integrity_workflow_integration_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add \
  cookbooks/fixtures/apps/data_integrity_app \
  spec/services/engine/data_integrity_workflow_integration_spec.rb
git commit -m "feat: add data integrity cookbook fixture"
```

---

### Task 7: Add a safety regression spec for read-only SQL metadata

**Objective:** Make the destructive-data safety contract explicit: the queue must forbid database mutation and expose disallowed SQL patterns for the scan stage.

**Files:**
- Modify: `spec/models/work_queue_seed_spec.rb` or create: `spec/db/seeds/data_integrity_cookbook_queue_spec.rb`

**Step 1: Write failing safety spec**

If `work_queue_seed_spec.rb` is getting too large, create `spec/db/seeds/data_integrity_cookbook_queue_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "data integrity cookbook queue seeds" do
  before do
    Rails.application.load_seed
  end

  it "keeps every data integrity stage read-only until human review" do
    queue = WorkQueue.find_by!(slug: "data_integrity")

    queue.stage_configs.each do |stage|
      expect(stage.forbidden_skills).to include("mutate_database")
    end

    scan = queue.stage_configs.find_by!(stage_name: "scan_violations")
    expect(scan.adapter_config["read_only"]).to eq(true)
    expect(scan.adapter_config["disallowed_sql_patterns"]).to include(
      "\\bINSERT\\b",
      "\\bUPDATE\\b",
      "\\bDELETE\\b",
      "\\bALTER\\b",
      "\\bDROP\\b",
      "\\bTRUNCATE\\b"
    )

    draft = queue.stage_configs.find_by!(stage_name: "draft_repairs")
    expect(draft.adapter_config["require_dry_run"]).to eq(true)
    expect(draft.adapter_config["require_idempotent_repairs"]).to eq(true)
  end
end
```

**Step 2: Run test to verify RED or GREEN**

If Task 5 already included this exact config, this may pass immediately. If it passes immediately, keep it only if it adds non-duplicative coverage; otherwise skip creating a duplicate spec and document that safety was covered in Task 5.

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/db/seeds/data_integrity_cookbook_queue_spec.rb
```

Expected if created before YAML safety fields: FAIL showing missing safety metadata. Expected if Task 5 already implemented the fields: PASS; do not change production code.

**Step 3: Implement only if RED**

Add missing `forbidden_skills`, `read_only`, `disallowed_sql_patterns`, `require_dry_run`, or `require_idempotent_repairs` fields to `config/queues/data_integrity.yml`.

**Step 4: Run tests**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/db/seeds/data_integrity_cookbook_queue_spec.rb spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 5: Commit if files changed**

```bash
git add spec/db/seeds/data_integrity_cookbook_queue_spec.rb config/queues/data_integrity.yml spec/models/work_queue_seed_spec.rb
git commit -m "test: cover data integrity read-only safety"
```

---

### Task 8: Add optional cookbook docs only if requested by the implementation card

**Objective:** Provide user-facing cookbook documentation without blocking the core queue if docs are out of scope.

**Files:**
- Create: `docs/cookbooks/data-integrity-validator.md`

**Step 1: Confirm scope**

If the implementation Kanban card only asks for queue/config/predicates/fixtures, skip this task and create a follow-up docs card. If it asks for cookbook docs, proceed.

**Step 2: Write docs smoke spec first if the repo has docs specs**

Search for docs specs:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec --dry-run spec | grep docs
```

If there is an existing docs index/spec pattern, add a failing assertion for `docs/cookbooks/data-integrity-validator.md`.

**Step 3: Create docs**

Include:

- Use case summary.
- Stage table and artifact contracts.
- Safety callout: read-only until human review, dry-run required, no automatic repair execution.
- Example monthly recurring run.
- Example follow-up routing for repeated violations to `development`.

**Step 4: Run relevant docs tests or smoke search**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec SPEC_PATH_IF_ANY
```

Expected: PASS.

**Step 5: Commit**

```bash
git add docs/cookbooks/data-integrity-validator.md SPEC_PATH_IF_ANY
git commit -m "docs: add data integrity cookbook"
```

---

### Task 9: Final verification before handoff

**Objective:** Verify all focused cookbook behavior passes and no portability regressions were introduced.

**Files:**
- No new files unless a failing verification exposes a bug.

**Step 1: Run focused predicate specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/rules_defined_spec.rb \
  spec/services/engine/predicates/violations_scanned_spec.rb \
  spec/services/engine/predicates/damage_assessed_spec.rb \
  spec/services/engine/predicates/repairs_drafted_spec.rb \
  spec/services/engine/predicate_registry_spec.rb
```

Expected: PASS.

**Step 2: Run seed and workflow specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/models/work_queue_seed_spec.rb \
  spec/services/engine/data_integrity_workflow_integration_spec.rb
```

Expected: PASS.

If `spec/db/seeds/data_integrity_cookbook_queue_spec.rb` was created, include it:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/db/seeds/data_integrity_cookbook_queue_spec.rb
```

Expected: PASS.

**Step 3: Run portability search**

```bash
git grep -n "/Users/gregmushen\|/Users/\|working_directory:" -- \
  config/queues/data_integrity.yml \
  cookbooks/prompts/data_integrity \
  cookbooks/fixtures/apps/data_integrity_app \
  spec/services/engine/data_integrity_workflow_integration_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/db/seeds/data_integrity_cookbook_queue_spec.rb
```

Expected: no matches. If the optional seed spec path does not exist, omit it from the command.

**Step 4: Run broader relevant suite**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine spec/models/work_queue_seed_spec.rb
```

Expected: PASS. If unrelated existing untracked work causes failures, verify the data-integrity focused specs in a clean worktree or document the unrelated failure in the handoff.

**Step 5: Inspect git status**

```bash
git status --short
```

Expected: only intended data-integrity files are staged/modified for this implementation slice. Do not stage unrelated files already present in the shared worktree.

**Step 6: Final commit or squash**

If the implementation card allows task-by-task commits, leave the task commits. If it requires one final commit, squash them into:

```bash
git commit -m "feat: add data integrity validator cookbook"
```

---

## Acceptance Criteria

- `config/queues/data_integrity.yml` exists and seeds a `WorkQueue` with stages exactly:
  `define_rules`, `scan_violations`, `assess_damage`, `draft_repairs`, `human_review`, `done`.
- All stages have matching `StageConfig` records after `db/seeds.rb` runs.
- Prompt files are loaded from repo-relative `file://cookbooks/prompts/data_integrity/...` paths and persisted as resolved markdown content, not literal `file://` strings.
- Queue YAML, prompt files, fixture files, and specs contain no hardcoded absolute checkout paths and no `working_directory` override.
- `rules_defined`, `violations_scanned`, `damage_assessed`, and `repairs_drafted` predicates are implemented, tested, and registered.
- The `scan_violations` stage is explicitly read-only, forbids `mutate_database`, and has a deterministic fixture command that emits a `violation_report` artifact.
- Every stage forbids `mutate_database`; `draft_repairs` drafts scripts only and requires dry-run/idempotent repair metadata.
- Fixture app covers referential integrity, constraint/business-rule violations, invalid enum values, temporal sanity, and stale counters.
- Focused predicate, registry, seed, and workflow specs pass using Greg's rbenv command shape.
- Implementation commits stage only intended files and do not include unrelated untracked work from the shared repo.

---

## Planning Task Commit Instructions

For this Kanban planning card only:

```bash
git add docs/plans/cookbooks/18-data-integrity-validator.md
git commit -m "docs: plan cookbook 18 data-integrity-validator"
```

Do not stage or commit any other file for this planning task.
