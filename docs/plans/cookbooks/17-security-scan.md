# Security Scan Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the `security_scan` cookbook queue so StupidClaw can scan a repository for OWASP-style vulnerabilities, classify exploitability/severity, draft safe patches for critical/high findings, run fixture tests, and require security-experienced human review.

**Architecture:** Follow the existing seeded queue pattern: add a portable queue YAML under `config/queues/`, keep long agent instructions in prompt files resolved via `file://` through `db/seeds.rb`, add one new artifact predicate (`scan_completed`) to `Engine::PredicateRegistry`, and reuse existing `severity_classified`, `fixes_drafted`, `tests_passed`, and `report_present` predicates. Add a small Docker-friendly vulnerable fixture app under `test/fixtures/apps/vulnerable_security_app/` plus an integration/spec harness that proves the cookbook can identify hardcoded secrets, SQL injection, XSS, auth gaps, CSRF/config issues, and dependency audit placeholders without touching external services.

**Tech Stack:** Rails, RSpec, YAML queue seeds, `Engine::PredicateRegistry`, `Artifact` records, inline Claude adapters, shell_script adapter, fake human-review stages, portable `file://` prompt indirection, rbenv on Greg's Mac.

**Source Spec:** `docs/specs/cookbook-17-security-scan.md`

---

## Current codebase context

Relevant files and patterns inspected before writing this plan:

- `db/seeds.rb` loads every `config/queues/*.yml`, resolves `agent_prompt: file://...` with `Rails.root.join(relative_path).read`, and upserts `WorkQueue`/`StageConfig` records.
- `config/queues/error_handling_audit.yml`, `config/queues/job_observability.yml`, and `config/queues/query_health.yml` are the closest queue examples: inline-Claude scan/classify/draft stages, shell_script test stages, fake `human_review`/`done` stages, and no hardcoded checkout paths.
- `prompts/audit_scan_error_handling.md`, `prompts/audit_classify_severity.md`, and `prompts/audit_draft_fixes.md` are good prompt-shape examples for scan/classify/draft security-style workflows.
- `app/services/engine/predicates/severity_classified.rb` expects a non-empty `severity_report.findings` array and returns `{ artifact_id:, finding_count: }` evidence.
- `app/services/engine/predicates/fixes_drafted.rb` currently checks `fix_patches`; for this cookbook either reuse it by setting `output_artifact_kind: fix_patches`, or update it via TDD to also support `security_patches`. This plan chooses the smaller, less risky route: set `draft_fixes.adapter_config.output_artifact_kind` to `fix_patches` while prompts call out the security patch schema.
- `spec/models/work_queue_seed_spec.rb` has one focused seed assertion per cookbook queue and checks resolved prompts, stage configs, adapter configs, and absence of absolute paths.
- `spec/services/engine/predicate_registry_spec.rb` is the place to add the `scan_completed` registry assertion.
- Shared cookbook infrastructure already lives under `cookbooks/`; this cookbook should not duplicate shared Docker Compose services.

Global implementation rules:

- Strict TDD for every production/config behavior change: write the failing spec first, run it and confirm the expected failure, implement the smallest change, rerun the focused spec, then run the relevant broader specs.
- Use Greg's rbenv command shape for every Rails/RSpec command:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec ...`
- Do not hardcode `/Users/gregmushen/work/code/stupidclaw`, `Rails.root.to_s`, or any user-local absolute path in queue YAML, prompts, fixtures, specs, or implementation code.
- Queue YAML should use portable relative paths only, e.g. `file://prompts/security_scan.md` and `fixture_app: test/fixtures/apps/vulnerable_security_app`.
- Commit after each implementation task unless the Kanban assignment explicitly asks for a single final commit. If a future implementation card asks for one commit, squash the task commits before completing.
- This planning task itself must commit only this file with: `git commit -m "docs: plan cookbook 17 security-scan"`.

---

## Files to create or modify during implementation

Create:

- `config/queues/security_scan.yml`
- `prompts/security_scan.md`
- `prompts/security_classify.md`
- `prompts/security_draft_fixes.md`
- `app/services/engine/predicates/scan_completed.rb`
- `spec/services/engine/predicates/scan_completed_spec.rb`
- `spec/services/engine/security_scan_workflow_integration_spec.rb`
- `test/fixtures/apps/vulnerable_security_app/README.md`
- `test/fixtures/apps/vulnerable_security_app/Gemfile`
- `test/fixtures/apps/vulnerable_security_app/Gemfile.lock` only if the app already tracks fixture lockfiles at implementation time; otherwise omit it.
- `test/fixtures/apps/vulnerable_security_app/config/routes.rb`
- `test/fixtures/apps/vulnerable_security_app/config/application.rb`
- `test/fixtures/apps/vulnerable_security_app/config/environments/production.rb`
- `test/fixtures/apps/vulnerable_security_app/app/controllers/application_controller.rb`
- `test/fixtures/apps/vulnerable_security_app/app/controllers/orders_controller.rb`
- `test/fixtures/apps/vulnerable_security_app/app/controllers/admin/reports_controller.rb`
- `test/fixtures/apps/vulnerable_security_app/app/controllers/webhooks_controller.rb`
- `test/fixtures/apps/vulnerable_security_app/app/models/user.rb`
- `test/fixtures/apps/vulnerable_security_app/app/models/order.rb`
- `test/fixtures/apps/vulnerable_security_app/app/views/orders/show.html.erb`
- `test/fixtures/apps/vulnerable_security_app/app/services/legacy_exporter.rb`
- `test/fixtures/apps/vulnerable_security_app/config/initializers/cors.rb`
- `test/fixtures/apps/vulnerable_security_app/.env.example`
- `docs/cookbooks/security-scan.md` if the implementation task includes cookbook docs; otherwise leave docs creation for a separate docs card.

Modify:

- `app/services/engine/predicate_registry.rb`
- `spec/services/engine/predicate_registry_spec.rb`
- `spec/models/work_queue_seed_spec.rb`

Do not modify unless a failing spec proves it is necessary:

- `db/seeds.rb` because it already resolves `file://` relative to `Rails.root`.
- `Engine::Predicates::SeverityClassified` because it already validates `severity_report` artifacts.
- `Engine::Predicates::FixesDrafted` if `security_scan.yml` uses `output_artifact_kind: fix_patches` for the draft stage.
- Shared adapter classes (`Adapters::InlineClaudeAdapter`, `Adapters::ShellScriptAdapter`, Docker/fake infrastructure).

---

## Security Scan Queue YAML target

Create `config/queues/security_scan.yml` with this content. Keep prompt paths repo-relative and do not add `working_directory`.

```yaml
name: Security Scan
slug: security_scan
stages:
  - scan_vulnerabilities
  - classify_severity
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
  scan_vulnerabilities:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [scan_completed]
    agent_prompt: file://prompts/security_scan.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: vulnerability_scan
      fixture_app: test/fixtures/apps/vulnerable_security_app
      vulnerability_categories:
        - injection
        - auth
        - xss
        - secrets
        - data_exposure
        - csrf
        - dependencies
        - insecure_config
  classify_severity:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [severity_classified]
    agent_prompt: file://prompts/security_classify.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: vulnerability_scan
      output_artifact_kind: severity_report
      fixture_app: test/fixtures/apps/vulnerable_security_app
  draft_fixes:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    escalation_target: block_and_notify
    completion_criteria: [fixes_drafted]
    agent_prompt: file://prompts/security_draft_fixes.md
    timeout_seconds: 600
    adapter_config:
      input_artifact_kind: severity_report
      output_artifact_kind: fix_patches
      patch_schema_name: security_patches
      spawn_targets:
        hardcoded_secrets: credential_rotation
        insecure_dependencies: dependency_upgrade
        systemic_auth: development
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    escalation_target: block_and_notify
    completion_criteria: [tests_passed]
    agent_prompt: Apply generated security patches to the vulnerable fixture app and run the security scan fixture checks. Report pass/fail with command output.
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: test_results
      commands:
        - name: security scan fixture specs
          artifact: test_results
          command: PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/security_scan_workflow_integration_spec.rb
  human_review:
    adapter_type: fake
    allowed_skills: []
    forbidden_skills: []
    max_retries: 0
    escalation_target: block_and_notify
    completion_criteria: [report_present]
    agent_prompt: Security review — critical and high findings require a security-experienced reviewer. Verify exploitability, proposed patches, credential rotation follow-ups, dependency-upgrade follow-ups, and any systemic-auth development follow-ups before merge.
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

Why `fix_patches` instead of `security_patches`: the current reusable `fixes_drafted` predicate checks a `fix_patches` artifact. The `patch_schema_name: security_patches` adapter config and prompt text preserve the cookbook vocabulary without adding a second generic fixes predicate. If future code needs literal `security_patches`, first add a failing spec for `FixesDrafted` accepting configurable artifact kinds, then implement that separately.

---

### Task 1: Add RED specs for `scan_completed`

**Objective:** Prove the new predicate passes only when the claim has a non-empty `vulnerability_scan` artifact with vulnerabilities.

**Files:**

- Create: `spec/services/engine/predicates/scan_completed_spec.rb`
- Later create: `app/services/engine/predicates/scan_completed.rb`

**Step 1: Write failing test**

Create `spec/services/engine/predicates/scan_completed_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Engine::Predicates::ScanCompleted do
  def build_claim(artifacts: [])
    queue = WorkQueue.create!(
      name: "Security Scan",
      slug: "security-scan-#{SecureRandom.hex(4)}",
      stages: %w[scan_vulnerabilities done]
    )
    queue.stage_configs.create!(stage_name: "scan_vulnerabilities", adapter_type: "fake")
    item = WorkItem.create!(title: "Scan repo", spec_url: "local", work_queue: queue, stage_name: "scan_vulnerabilities")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    artifacts.each { |artifact| Artifact.create!(work_item: item, claim: claim, **artifact) }
    claim
  end

  it "passes with evidence when vulnerability_scan has vulnerabilities" do
    claim = build_claim(artifacts: [
      {
        kind: "vulnerability_scan",
        data: {
          "vulnerabilities" => [
            {
              "category" => "injection",
              "file" => "app/controllers/orders_controller.rb",
              "line" => 12,
              "evidence" => "Order.where(\"id = #{params[:id]}\")",
              "exploitability" => "easy",
              "severity" => "critical"
            }
          ]
        }
      }
    ])
    artifact = claim.artifacts.find_by!(kind: "vulnerability_scan")

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence).to eq({ artifact_id: artifact.id, vulnerability_count: 1 })
  end

  it "fails when vulnerability_scan is missing" do
    result = described_class.new(claim: build_claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("no vulnerability_scan artifact found")
  end

  it "fails when vulnerability_scan has no vulnerabilities" do
    claim = build_claim(artifacts: [
      { kind: "vulnerability_scan", data: { "vulnerabilities" => [] } }
    ])

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("vulnerability_scan artifact has no vulnerabilities")
  end
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/scan_completed_spec.rb
```

Expected: FAIL with `uninitialized constant Engine::Predicates::ScanCompleted`.

**Step 3: Implement minimal predicate**

Create `app/services/engine/predicates/scan_completed.rb`:

```ruby
module Engine
  module Predicates
    class ScanCompleted
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "vulnerability_scan").first
        return PredicateResult.fail(reason: "no vulnerability_scan artifact found") unless artifact

        vulnerabilities = artifact.data.fetch("vulnerabilities", [])
        if vulnerabilities.empty?
          return PredicateResult.fail(reason: "vulnerability_scan artifact has no vulnerabilities")
        end

        PredicateResult.pass(evidence: { artifact_id: artifact.id, vulnerability_count: vulnerabilities.count })
      end
    end
  end
end
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/scan_completed_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/engine/predicates/scan_completed.rb spec/services/engine/predicates/scan_completed_spec.rb
git commit -m "feat: add scan completed predicate"
```

---

### Task 2: Register `scan_completed`

**Objective:** Make the queue seed's completion criterion resolvable by `Engine::PredicateRegistry`.

**Files:**

- Modify: `spec/services/engine/predicate_registry_spec.rb`
- Modify: `app/services/engine/predicate_registry.rb`

**Step 1: Write failing test**

Add this expectation in the known-predicate example in `spec/services/engine/predicate_registry_spec.rb`, near the other cookbook predicates:

```ruby
expect(described_class.resolve("scan_completed")).to eq(Engine::Predicates::ScanCompleted)
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicate_registry_spec.rb
```

Expected: FAIL with `unknown predicate: scan_completed`.

**Step 3: Implement registry entry**

Add to `PREDICATES` in `app/services/engine/predicate_registry.rb`, next to other cookbook artifact predicates:

```ruby
"scan_completed" => Predicates::ScanCompleted,
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
git commit -m "feat: register security scan predicate"
```

---

### Task 3: Add RED seed spec for the security scan queue

**Objective:** Prove the `security_scan` queue seeds with all stages, resolved prompts, portable paths, security-specific adapter config, and fake human-review/done gates.

**Files:**

- Modify: `spec/models/work_queue_seed_spec.rb`
- Later create: `config/queues/security_scan.yml`
- Later create: `prompts/security_scan.md`
- Later create: `prompts/security_classify.md`
- Later create: `prompts/security_draft_fixes.md`

**Step 1: Write failing test**

Append this example to `spec/models/work_queue_seed_spec.rb`:

```ruby
it "seeds the security scan queue with resolved portable prompts" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "security_scan")
  expect(queue.name).to eq("Security Scan")
  expect(queue.stages).to eq(%w[scan_vulnerabilities classify_severity draft_fixes run_tests human_review done])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)
  expect(queue.config).to include(
    "default_max_retries" => 2,
    "default_timeout_seconds" => 600,
    "default_escalation" => "block_and_notify",
    "max_regression_loops" => 2
  )

  scan = queue.stage_configs.find_by!(stage_name: "scan_vulnerabilities")
  expect(scan.adapter_type).to eq("inline_claude")
  expect(scan.model_override).to eq("claude-sonnet-4-20250514")
  expect(scan.allowed_skills).to eq(%w[read_repo])
  expect(scan.forbidden_skills).to include("edit_files", "deploy")
  expect(scan.completion_criteria).to eq(%w[scan_completed])
  expect(scan.agent_prompt).to include("# Security Scan: Scan Vulnerabilities")
  expect(scan.agent_prompt).to include("vulnerability_scan")
  expect(scan.agent_prompt).not_to start_with("file://")
  expect(scan.agent_prompt).not_to include(Rails.root.to_s)
  expect(scan.adapter_config).to include(
    "output_artifact_kind" => "vulnerability_scan",
    "fixture_app" => "test/fixtures/apps/vulnerable_security_app"
  )
  expect(scan.adapter_config.fetch("vulnerability_categories")).to include(
    "injection", "auth", "xss", "secrets", "data_exposure", "csrf", "dependencies", "insecure_config"
  )

  classify = queue.stage_configs.find_by!(stage_name: "classify_severity")
  expect(classify.adapter_type).to eq("inline_claude")
  expect(classify.model_override).to eq("claude-sonnet-4-20250514")
  expect(classify.completion_criteria).to eq(%w[severity_classified])
  expect(classify.agent_prompt).to include("# Security Scan: Classify Severity")
  expect(classify.agent_prompt).to include("false_positive")
  expect(classify.agent_prompt).not_to start_with("file://")
  expect(classify.adapter_config).to include(
    "input_artifact_kind" => "vulnerability_scan",
    "output_artifact_kind" => "severity_report",
    "fixture_app" => "test/fixtures/apps/vulnerable_security_app"
  )

  draft = queue.stage_configs.find_by!(stage_name: "draft_fixes")
  expect(draft.adapter_type).to eq("inline_claude")
  expect(draft.allowed_skills).to eq(%w[read_repo])
  expect(draft.forbidden_skills).to eq(%w[deploy])
  expect(draft.max_retries).to eq(2)
  expect(draft.completion_criteria).to eq(%w[fixes_drafted])
  expect(draft.agent_prompt).to include("# Security Scan: Draft Fixes")
  expect(draft.agent_prompt).to include("credential_rotation")
  expect(draft.agent_prompt).to include("dependency_upgrade")
  expect(draft.adapter_config).to include(
    "input_artifact_kind" => "severity_report",
    "output_artifact_kind" => "fix_patches",
    "patch_schema_name" => "security_patches"
  )
  expect(draft.adapter_config.fetch("spawn_targets")).to include(
    "hardcoded_secrets" => "credential_rotation",
    "insecure_dependencies" => "dependency_upgrade",
    "systemic_auth" => "development"
  )

  run_tests = queue.stage_configs.find_by!(stage_name: "run_tests")
  expect(run_tests.adapter_type).to eq("shell_script")
  expect(run_tests.allowed_skills).to eq(%w[run_tests])
  expect(run_tests.forbidden_skills).to include("edit_files", "deploy")
  expect(run_tests.completion_criteria).to eq(%w[tests_passed])
  expect(run_tests.adapter_config).to include("output_artifact_kind" => "test_results")
  expect(run_tests.adapter_config).not_to have_key("working_directory")
  expect(run_tests.adapter_config.fetch("commands")).to contain_exactly(
    include(
      "name" => "security scan fixture specs",
      "artifact" => "test_results",
      "command" => "PATH=\"$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH\" bundle exec rspec spec/services/engine/security_scan_workflow_integration_spec.rb"
    )
  )

  human_review = queue.stage_configs.find_by!(stage_name: "human_review")
  expect(human_review.adapter_type).to eq("fake")
  expect(human_review.completion_criteria).to eq(%w[report_present])
  expect(human_review.timeout_seconds).to eq(86_400)
  expect(human_review.agent_prompt).to include("security-experienced reviewer")

  done = queue.stage_configs.find_by!(stage_name: "done")
  expect(done.adapter_type).to eq("fake")
  expect(done.completion_criteria).to eq(%w[report_present])

  serialized_queue = Rails.root.join("config/queues/security_scan.yml").read
  expect(serialized_queue).not_to include(Rails.root.to_s)
  expect(serialized_queue).not_to include("/Users/")
  expect(serialized_queue).not_to include("working_directory:")
  expect(serialized_queue).to include("file://prompts/security_scan.md")
  expect(serialized_queue).to include("file://prompts/security_classify.md")
  expect(serialized_queue).to include("file://prompts/security_draft_fixes.md")
end
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL with `Couldn't find WorkQueue` for slug `security_scan`.

**Step 3: Create queue YAML and prompt placeholders**

Create `config/queues/security_scan.yml` using the YAML target above.

Create minimal prompt files so the seed spec can resolve them; complete them in later tasks:

`prompts/security_scan.md`:

```markdown
# Security Scan: Scan Vulnerabilities

Produce a `vulnerability_scan` artifact with a `vulnerabilities` array.
```

`prompts/security_classify.md`:

```markdown
# Security Scan: Classify Severity

Read the `vulnerability_scan` artifact, remove `false_positive` items with reasoning, and produce a `severity_report` artifact.
```

`prompts/security_draft_fixes.md`:

```markdown
# Security Scan: Draft Fixes

Read critical/high `severity_report` findings and produce `security_patches`-shaped patch data in the configured `fix_patches` artifact. Mention follow-up queues: `credential_rotation`, `dependency_upgrade`, and `development`.
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS for the new security scan example and no regressions in existing seed examples.

**Step 5: Commit**

```bash
git add config/queues/security_scan.yml prompts/security_scan.md prompts/security_classify.md prompts/security_draft_fixes.md spec/models/work_queue_seed_spec.rb
git commit -m "feat: seed security scan queue"
```

---

### Task 4: Fill in the scan prompt

**Objective:** Make `prompts/security_scan.md` explicit enough for an agent to produce the required `vulnerability_scan` schema and avoid destructive changes.

**Files:**

- Modify: `prompts/security_scan.md`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Write failing expectations**

In the security scan seed spec's `scan` section, add expectations that currently fail against the placeholder prompt:

```ruby
expect(scan.agent_prompt).to include("SQL injection")
expect(scan.agent_prompt).to include("command injection")
expect(scan.agent_prompt).to include("hardcoded credentials")
expect(scan.agent_prompt).to include("CSRF")
expect(scan.agent_prompt).to include("bundler-audit")
expect(scan.agent_prompt).to include("severity")
expect(scan.agent_prompt).to include("exploitability")
expect(scan.agent_prompt).to include("Do not edit files")
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL on missing scan prompt details.

**Step 3: Replace prompt content**

Update `prompts/security_scan.md`:

```markdown
# Security Scan: Scan Vulnerabilities

You are the scan stage for the `security_scan` queue. Do not edit files, do not deploy, and do not run destructive commands. Read the repository and produce exactly one `vulnerability_scan` artifact.

Input:
- Repository path or fixture app path from adapter config.
- Source files, config files, dependency manifests, route/controller files, templates, and service objects.

Scan for:
- Injection: SQL injection through interpolated query strings, command injection through `system`, backticks, `Open3`, or shell commands fed by user input, and LDAP/query-builder injection patterns.
- Auth and access control: missing authentication before actions, user A reading user B resources, weak password requirements, and hardcoded credentials.
- XSS: unescaped user input in templates, `html_safe` on user-controlled content, raw HTML helpers, and `dangerouslySetInnerHTML` in JavaScript/React code.
- Secrets: API keys, passwords, bearer tokens, private keys, `.env` files committed to source, and credentials in config.
- Data exposure: password hashes, SSNs, tokens, internal errors, stack traces, or sensitive fields returned from API serializers/controllers.
- CSRF: missing CSRF protections on state-changing endpoints, unsafe skipped forgery protection, and JSON endpoints that mutate state without compensating auth.
- Dependencies: known-CVE signals from `Gemfile`, `Gemfile.lock`, `package.json`, `yarn.lock`, and references to `bundler-audit` or `npm audit` output when available.
- Insecure config: production debug mode, wildcard CORS, missing security headers, insecure cookies, disabled SSL, or verbose exception pages.

For each candidate, decide whether there is concrete evidence. Prefer fewer high-confidence findings over noisy static-analysis guesses.

Artifact schema:

```json
{
  "vulnerabilities": [
    {
      "category": "injection|auth|xss|secrets|data_exposure|csrf|dependencies|insecure_config",
      "file": "repo-relative/path.rb",
      "line": 12,
      "evidence": "short code excerpt or config value",
      "exploitability": "easy|moderate|difficult",
      "severity": "critical|high|medium|low",
      "reasoning": "why this is likely exploitable"
    }
  ]
}
```
```

**Step 4: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add prompts/security_scan.md spec/models/work_queue_seed_spec.rb
git commit -m "docs: expand security scan prompt"
```

---

### Task 5: Fill in classification and draft-fix prompts

**Objective:** Make the second and third inline-Claude stages explicit about exploitability, false positives, critical/high-only patch drafting, and cross-queue follow-ups.

**Files:**

- Modify: `prompts/security_classify.md`
- Modify: `prompts/security_draft_fixes.md`
- Test: `spec/models/work_queue_seed_spec.rb`

**Step 1: Write failing expectations**

Add expectations to the security scan seed spec:

```ruby
expect(classify.agent_prompt).to include("blast radius")
expect(classify.agent_prompt).to include("actively exploitable")
expect(classify.agent_prompt).to include("critical")
expect(classify.agent_prompt).to include("false_positives_removed")
expect(classify.agent_prompt).to include("Group related vulnerabilities")

expect(draft.agent_prompt).to include("critical and high")
expect(draft.agent_prompt).to include("parameterized queries")
expect(draft.agent_prompt).to include("remove `html_safe`")
expect(draft.agent_prompt).to include("environment variables")
expect(draft.agent_prompt).to include("before_action")
expect(draft.agent_prompt).to include("CSRF")
expect(draft.agent_prompt).to include("spawn")
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: FAIL on missing prompt details.

**Step 3: Replace classification prompt**

Update `prompts/security_classify.md`:

```markdown
# Security Scan: Classify Severity

You are the classification stage for the `security_scan` queue. Do not edit files. Read the `vulnerability_scan` artifact and inspect source context before producing one `severity_report` artifact.

For each vulnerability:
- Decide whether it is actually exploitable in context.
- Estimate blast radius: one user, tenant-wide, all users, infrastructure, or credential compromise.
- Decide whether it is actively exploitable, requires privileged access, or is theoretical.
- Classify severity as `critical`, `high`, `medium`, `low`, or `false_positive`.
- Remove false positives with clear reasoning.
- Group related vulnerabilities. Group related vulnerabilities such as "all controllers missing CSRF" as one finding instead of one finding per file.

Artifact schema:

```json
{
  "findings": [
    {
      "vulnerabilities": ["references to vulnerability_scan entries or embedded objects"],
      "severity": "critical|high|medium|low",
      "blast_radius": "who or what can be compromised",
      "exploitability": "easy|moderate|difficult",
      "recommendation": "specific next action"
    }
  ],
  "false_positives_removed": 0
}
```
```

**Step 4: Replace draft prompt**

Update `prompts/security_draft_fixes.md`:

```markdown
# Security Scan: Draft Fixes

You are the fix-drafting stage for the `security_scan` queue. Draft patches only for critical and high severity findings from the `severity_report` artifact. Do not deploy. Prefer minimal, reviewable changes and include tests or test commands when relevant.

Draft fixes by category:
- SQL injection: replace string interpolation with parameterized queries.
- Command injection: avoid shell interpolation, use array argv forms or safe libraries.
- XSS: escape user input and remove `html_safe` on user-controlled data.
- Hardcoded secrets: replace with environment variables or a secrets-manager lookup; do not invent real secret values.
- Missing auth: add `before_action :authenticate!` or the app's equivalent authorization guard.
- Broken access control: scope records to the current user/account/tenant.
- Missing CSRF: restore CSRF tokens or document a safe API-specific compensating control.
- Insecure dependencies: propose version bumps and spawn dependency work instead of silently changing large dependency graphs.

Cross-queue follow-ups:
- Hardcoded secrets should spawn `credential_rotation` work.
- Insecure dependencies should spawn `dependency_upgrade` work.
- Systemic auth issues should spawn `development` work.

The configured artifact kind is `fix_patches` for compatibility with the existing `fixes_drafted` predicate. Use this security patch schema inside it:

```json
{
  "patches": [
    {
      "file": "repo-relative/path.rb",
      "original": "exact original snippet",
      "replacement": "safe replacement snippet",
      "vulnerability_ref": "reference to severity_report finding",
      "severity": "critical|high"
    }
  ],
  "spawn": [
    { "queue": "credential_rotation|dependency_upgrade|development", "reason": "why follow-up is needed" }
  ]
}
```
```

**Step 5: Run test to verify GREEN**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git add prompts/security_classify.md prompts/security_draft_fixes.md spec/models/work_queue_seed_spec.rb
git commit -m "docs: expand security classification prompts"
```

---

### Task 6: Add vulnerable fixture app files

**Objective:** Provide a deterministic, Docker-friendly fixture app with representative vulnerabilities for prompt and workflow tests.

**Files:**

- Create fixture files listed in the "Files to create" section.
- Create or modify: `spec/fixtures/security_scan_fixture_spec.rb` if the project convention prefers fixture contract specs; otherwise put fixture checks in `spec/services/engine/security_scan_workflow_integration_spec.rb` in Task 7.

**Step 1: Write failing fixture contract spec**

Create `spec/fixtures/security_scan_fixture_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "security scan vulnerable fixture" do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/vulnerable_security_app") }

  it "contains representative security issues with portable paths" do
    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("app/controllers/orders_controller.rb")).to exist
    expect(fixture_root.join("app/views/orders/show.html.erb")).to exist
    expect(fixture_root.join("app/services/legacy_exporter.rb")).to exist

    controller = fixture_root.join("app/controllers/orders_controller.rb").read
    expect(controller).to include("Order.where(\"id = #{params[:id]}\")")
    expect(controller).to include("skip_before_action :verify_authenticity_token")
    expect(controller).to include("render json: user.as_json")

    view = fixture_root.join("app/views/orders/show.html.erb").read
    expect(view).to include("html_safe")

    service = fixture_root.join("app/services/legacy_exporter.rb").read
    expect(service).to include("system")
    expect(service).to include("LEGACY_API_KEY")

    cors = fixture_root.join("config/initializers/cors.rb").read
    expect(cors).to include("origins '*'")

    serialized_paths = fixture_root.glob("**/*").select(&:file?).map(&:read).join("\n")
    expect(serialized_paths).not_to include(Rails.root.to_s)
    expect(serialized_paths).not_to include("/Users/")
  end
end
```

If the string interpolation assertion is awkward in Ruby source, assert smaller substrings:

```ruby
expect(controller).to include('Order.where("id = ')
expect(controller).to include('params[:id]')
```

**Step 2: Run test to verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/fixtures/security_scan_fixture_spec.rb
```

Expected: FAIL because fixture files do not exist.

**Step 3: Create fixture app**

Create minimal files. Keep them syntactically valid enough for static checks but intentionally vulnerable.

`test/fixtures/apps/vulnerable_security_app/README.md`:

```markdown
# Vulnerable Security App Fixture

This intentionally vulnerable Rails-style app is for the Security Scan cookbook. It contains SQL injection, command injection, XSS, hardcoded secret, data exposure, missing auth/CSRF, wildcard CORS, and dependency-audit examples. Do not deploy it.
```

`test/fixtures/apps/vulnerable_security_app/Gemfile`:

```ruby
source "https://rubygems.org"

gem "rails", "8.0.0"
gem "rack", "2.2.3" # intentionally old for dependency-audit examples
```

`test/fixtures/apps/vulnerable_security_app/config/routes.rb`:

```ruby
Rails.application.routes.draw do
  resources :orders, only: [:show, :update]
  namespace :admin do
    resources :reports, only: [:index]
  end
  post "/webhooks/legacy", to: "webhooks#create"
end
```

`test/fixtures/apps/vulnerable_security_app/app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  # Intentionally weak fixture base controller.
end
```

`test/fixtures/apps/vulnerable_security_app/app/controllers/orders_controller.rb`:

```ruby
class OrdersController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    @order = Order.where("id = #{params[:id]}").first
    user = User.find(params[:user_id])
    render json: user.as_json
  end

  def update
    order = Order.find(params[:id])
    order.update!(params.permit(:status, :admin_notes))
    render json: order
  end
end
```

`test/fixtures/apps/vulnerable_security_app/app/controllers/admin/reports_controller.rb`:

```ruby
module Admin
  class ReportsController < ApplicationController
    def index
      render plain: LegacyExporter.new.export(params[:path])
    end
  end
end
```

`test/fixtures/apps/vulnerable_security_app/app/controllers/webhooks_controller.rb`:

```ruby
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    render json: { received: true, payload: params.to_unsafe_h }
  end
end
```

`test/fixtures/apps/vulnerable_security_app/app/models/user.rb`:

```ruby
class User < ApplicationRecord
  # password_digest and api_token intentionally exposed by controller fixture.
end
```

`test/fixtures/apps/vulnerable_security_app/app/models/order.rb`:

```ruby
class Order < ApplicationRecord
  belongs_to :user
end
```

`test/fixtures/apps/vulnerable_security_app/app/views/orders/show.html.erb`:

```erb
<h1>Order <%= @order.id %></h1>
<div class="notes"><%= @order.admin_notes.html_safe %></div>
```

`test/fixtures/apps/vulnerable_security_app/app/services/legacy_exporter.rb`:

```ruby
class LegacyExporter
  LEGACY_API_KEY = "sk_live_1234567890abcdef"

  def export(path)
    system("tar -czf /tmp/export.tgz #{path}")
    "exported"
  end
end
```

`test/fixtures/apps/vulnerable_security_app/config/initializers/cors.rb`:

```ruby
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: %i[get post put patch delete options]
  end
end
```

`test/fixtures/apps/vulnerable_security_app/config/application.rb`:

```ruby
require_relative "boot"
require "rails/all"

module VulnerableSecurityApp
  class Application < Rails::Application
    config.load_defaults 8.0
    config.force_ssl = false
  end
end
```

`test/fixtures/apps/vulnerable_security_app/config/environments/production.rb`:

```ruby
Rails.application.configure do
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = false
  config.force_ssl = false
end
```

`test/fixtures/apps/vulnerable_security_app/.env.example`:

```dotenv
# Example only. The real fixture secret is intentionally in app/services/legacy_exporter.rb.
DATABASE_URL=postgres://localhost/vulnerable_security_app
```

**Step 4: Run fixture contract spec**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/fixtures/security_scan_fixture_spec.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add test/fixtures/apps/vulnerable_security_app spec/fixtures/security_scan_fixture_spec.rb
git commit -m "test: add vulnerable security fixture app"
```

---

### Task 7: Add cookbook workflow integration spec

**Objective:** Prove the seeded queue, predicate registry, artifacts, and transition-compatible predicates work together without calling real LLMs or external scanners.

**Files:**

- Create: `spec/services/engine/security_scan_workflow_integration_spec.rb`
- Possibly modify: `spec/models/work_queue_seed_spec.rb` only if seed assertions need a smaller helper.

**Step 1: Write failing integration spec**

Create `spec/services/engine/security_scan_workflow_integration_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "security scan cookbook workflow" do
  before do
    load Rails.root.join("db/seeds.rb")
  end

  let(:queue) { WorkQueue.find_by!(slug: "security_scan") }
  let(:work_item) do
    WorkItem.create!(
      work_queue: queue,
      title: "Scan vulnerable fixture",
      spec_url: "test/fixtures/apps/vulnerable_security_app",
      stage_name: "scan_vulnerabilities"
    )
  end

  it "accepts the scan, severity, fix, test, and review artifacts expected by the cookbook" do
    scan_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", stage_name: "scan_vulnerabilities", started_at: Time.current)
    vulnerability_artifact = Artifact.create!(
      work_item: work_item,
      claim: scan_claim,
      kind: "vulnerability_scan",
      data: {
        "vulnerabilities" => [
          { "category" => "injection", "file" => "app/controllers/orders_controller.rb", "line" => 5, "evidence" => "Order.where", "exploitability" => "easy", "severity" => "critical" },
          { "category" => "secrets", "file" => "app/services/legacy_exporter.rb", "line" => 2, "evidence" => "LEGACY_API_KEY", "exploitability" => "easy", "severity" => "high" },
          { "category" => "xss", "file" => "app/views/orders/show.html.erb", "line" => 2, "evidence" => "html_safe", "exploitability" => "moderate", "severity" => "high" }
        ]
      }
    )

    scan_result = Engine::PredicateRegistry.resolve("scan_completed").new(claim: scan_claim).call
    expect(scan_result).to be_passed
    expect(scan_result.evidence).to eq({ artifact_id: vulnerability_artifact.id, vulnerability_count: 3 })

    classify_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", stage_name: "classify_severity", started_at: Time.current)
    severity_artifact = Artifact.create!(
      work_item: work_item,
      claim: classify_claim,
      kind: "severity_report",
      data: {
        "findings" => [
          {
            "vulnerabilities" => ["orders_controller SQL injection"],
            "severity" => "critical",
            "blast_radius" => "all orders",
            "exploitability" => "easy",
            "recommendation" => "replace interpolated query with parameterized lookup"
          },
          {
            "vulnerabilities" => ["legacy API key"],
            "severity" => "high",
            "blast_radius" => "third-party account",
            "exploitability" => "easy",
            "recommendation" => "move to environment variable and rotate credential"
          }
        ],
        "false_positives_removed" => 1
      }
    )

    severity_result = Engine::PredicateRegistry.resolve("severity_classified").new(claim: classify_claim).call
    expect(severity_result).to be_passed
    expect(severity_result.evidence).to eq({ artifact_id: severity_artifact.id, finding_count: 2 })

    draft_claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: "completed", stage_name: "draft_fixes", started_at: Time.current)
    patch_artifact = Artifact.create!(
      work_item: work_item,
      claim: draft_claim,
      kind: "fix_patches",
      data: {
        "patches" => [
          { "file" => "app/controllers/orders_controller.rb", "original" => "Order.where", "replacement" => "Order.find_by", "vulnerability_ref" => "orders_controller SQL injection", "severity" => "critical" },
          { "file" => "app/services/legacy_exporter.rb", "original" => "LEGACY_API_KEY", "replacement" => "ENV.fetch", "vulnerability_ref" => "legacy API key", "severity" => "high" }
        ],
        "spawn" => [
          { "queue" => "credential_rotation", "reason" => "hardcoded API key must be rotated" }
        ]
      }
    )

    fixes_result = Engine::PredicateRegistry.resolve("fixes_drafted").new(claim: draft_claim).call
    expect(fixes_result).to be_passed
    expect(fixes_result.evidence).to eq({ artifact_id: patch_artifact.id, patch_count: 2 })
  end
end
```

**Step 2: Run integration spec to verify RED or GREEN depending on prior tasks**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/security_scan_workflow_integration_spec.rb
```

Expected after Tasks 1-6: PASS. If it fails, the failure should identify a missing seed, registry, or artifact-kind mismatch. Add a smaller focused failing spec for that gap before changing production code.

**Step 3: Run related specs**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/scan_completed_spec.rb spec/services/engine/predicate_registry_spec.rb spec/models/work_queue_seed_spec.rb spec/fixtures/security_scan_fixture_spec.rb spec/services/engine/security_scan_workflow_integration_spec.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add spec/services/engine/security_scan_workflow_integration_spec.rb
git commit -m "test: cover security scan workflow artifacts"
```

---

### Task 8: Add optional cookbook docs page

**Objective:** Document how to run the security scan cookbook locally if cookbook docs are in scope for the implementation card.

**Files:**

- Create: `docs/cookbooks/security-scan.md`

**Step 1: Write the docs page**

Create `docs/cookbooks/security-scan.md`:

```markdown
# Security Scan Cookbook

The `security_scan` queue scans a repository or fixture app for OWASP-style vulnerabilities, classifies exploitability/severity, drafts patches for critical and high findings, runs tests, and requires security-experienced human review.

## Stages

`scan_vulnerabilities -> classify_severity -> draft_fixes -> run_tests -> human_review -> done`

## Fixture

The intentionally vulnerable fixture app lives at `test/fixtures/apps/vulnerable_security_app` and includes examples for SQL injection, command injection, XSS, hardcoded secrets, data exposure, missing CSRF, wildcard CORS, and dependency-audit signals.

## Focused verification

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/security_scan_workflow_integration_spec.rb
```

## Follow-up queues

- Hardcoded secrets: `credential_rotation`
- Insecure dependencies: `dependency_upgrade`
- Systemic auth issues: `development`
```

**Step 2: Verify no hardcoded absolute paths**

Run:

```bash
grep -n "/Users/\|Rails.root.to_s" docs/cookbooks/security-scan.md config/queues/security_scan.yml prompts/security_*.md || true
```

Expected: no output.

**Step 3: Commit**

```bash
git add docs/cookbooks/security-scan.md
git commit -m "docs: add security scan cookbook"
```

---

### Task 9: Final verification before implementation handoff

**Objective:** Prove the whole security-scan slice is green and portable before completion.

**Files:**

- No new files.

**Step 1: Run focused suite**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/predicates/scan_completed_spec.rb spec/services/engine/predicate_registry_spec.rb spec/models/work_queue_seed_spec.rb spec/fixtures/security_scan_fixture_spec.rb spec/services/engine/security_scan_workflow_integration_spec.rb
```

Expected: PASS.

**Step 2: Run broader safe suite**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine spec/models/work_queue_seed_spec.rb spec/fixtures/security_scan_fixture_spec.rb
```

Expected: PASS. If unrelated dirty-worktree files make this fail, do not modify or stage unrelated files. Record the unrelated failure in the handoff and verify this cookbook in a clean temporary worktree with only the security-scan patch applied.

**Step 3: Search for non-portable paths**

Run:

```bash
grep -R -n "/Users/gregmushen\|/Users/\|working_directory:" config/queues/security_scan.yml prompts/security_*.md test/fixtures/apps/vulnerable_security_app spec/services/engine/security_scan_workflow_integration_spec.rb spec/fixtures/security_scan_fixture_spec.rb docs/cookbooks/security-scan.md || true
```

Expected: no output except the command itself in shell history; no source file should contain hardcoded user-local paths or `working_directory:`.

**Step 4: Check git status**

Run:

```bash
git status --short
```

Expected: only intentional security-scan files are dirty before the final implementation commit. Do not stage unrelated files from other cookbook tasks.

**Step 5: Final commit or squash**

If the implementation card asked for per-task commits, leave the task commits as-is. If it asked for one commit, squash to one commit:

```bash
git reset --soft HEAD~8
git commit -m "feat: add security scan cookbook"
```

Then verify:

```bash
git show --stat --oneline HEAD
```

Expected: the commit includes only security-scan queue, prompts, predicate/registry/specs, fixture app, and optional docs.

---

## Implementation acceptance criteria

- `config/queues/security_scan.yml` seeds queue `security_scan` with stages `scan_vulnerabilities`, `classify_severity`, `draft_fixes`, `run_tests`, `human_review`, and `done`.
- Every YAML stage has a persisted `StageConfig`; the seed spec asserts exact stage coverage with `contain_exactly(*queue.stages)`.
- Prompt file indirection is resolved; persisted prompts do not start with `file://`.
- Generated app/config code uses repo-relative paths only; no `/Users/...`, no `Rails.root.to_s` embedded in serialized YAML/prompts/fixtures, and no hardcoded `working_directory:`.
- `scan_completed` exists, has focused predicate tests, is registered in `Engine::PredicateRegistry`, and returns actionable evidence `{ artifact_id:, vulnerability_count: }`.
- `severity_classified` and `fixes_drafted` are reused intentionally; `draft_fixes` emits `fix_patches` for compatibility while preserving `security_patches` schema in adapter config/prompt text.
- The fixture app contains deterministic examples for injection, auth/access-control, XSS, secrets, data exposure, CSRF, dependencies, and insecure config.
- Run-test stage uses Greg's rbenv-safe command string:
  `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/security_scan_workflow_integration_spec.rb`
- Critical/high findings require fake `human_review` with an explicit security-experienced reviewer instruction.
- Cross-queue follow-up intent is encoded for `credential_rotation`, `dependency_upgrade`, and `development`.
- Focused and relevant broader specs pass before completion.

---

## Planning-task completion checklist

For this planning Kanban card only:

1. Save this plan at `docs/plans/cookbooks/17-security-scan.md`.
2. Run:

```bash
git diff -- docs/plans/cookbooks/17-security-scan.md
```

3. Commit only this plan file:

```bash
git add docs/plans/cookbooks/17-security-scan.md
git commit -m "docs: plan cookbook 17 security-scan"
```

4. Capture the commit hash:

```bash
git rev-parse HEAD
```

5. Complete the Kanban task with a summary containing the plan path and commit hash.
