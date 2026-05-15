# Cookbook Spec: Error Handling Audit

## Use Case

Your codebase has bare `rescue` blocks, swallowed exceptions, generic error messages, and `puts` debugging that made it to production. Every service handles errors differently. Some silently discard failures. Some retry without backoff. Some log the error but lose all context.

TaskRail scans for bad error handling patterns, classifies them by blast radius, drafts fixes with proper Sentry context and structured logging, runs the tests, and queues for review.

## Queue: `error_handling_audit`

### Stages

```
scan_error_handling → classify_severity → draft_fixes → run_tests → human_review → done
```

### Stage Details

**scan_error_handling** (Haiku)
- Adapter: `inline_claude`
- Input: repository path
- Task: Scan for error handling anti-patterns:
  - Bare `rescue => e` or `rescue StandardError`
  - Empty rescue blocks (swallowed exceptions)
  - `puts`/`p`/`pp` for error output instead of structured logging
  - `rescue` without re-raise or Sentry capture
  - Generic error messages with no context (`"something went wrong"`)
  - Missing timeout configuration on HTTP calls
  - Retry without backoff
- Artifact: `error_patterns` — `{ patterns: [{ file, line, type, code_snippet, severity_hint }] }`
- Predicate: `error_patterns_found` — artifact exists (empty patterns array is valid — clean codebase)
- Why Haiku: pattern matching against known anti-patterns, no deep reasoning

**classify_severity** (Sonnet)
- Adapter: `inline_claude`
- Input: error_patterns artifact, source code
- Task: For each pattern, assess:
  - **Blast radius**: user-facing controller? Background job? Internal helper?
  - **Data risk**: could this lose data? Silently drop a payment? Corrupt state?
  - **Frequency**: is this in a hot path or a rarely-hit edge case?
  - Classify as `critical` / `high` / `medium` / `low`
  - Group related patterns (e.g., all bare rescues in the same controller)
- Artifact: `severity_report` — `{ findings: [{ patterns: [...], severity, blast_radius, data_risk, recommendation }] }`
- Predicate: `severity_classified` — artifact exists with findings
- Why Sonnet: needs to understand code context and make judgment calls

**draft_fixes** (Sonnet)
- Adapter: `inline_claude`
- Input: severity_report artifact, source code, existing error handling patterns in repo
- Task: For each finding (starting with critical/high), draft the fix:
  - Replace bare rescues with specific exception types
  - Add `Sentry.capture_exception` with context
  - Add structured logging with request/job/operation context
  - Add timeout configuration where missing
  - Add backoff to retry loops
  - Follow existing patterns in the codebase where good ones exist
- Artifact: `fix_patches` — `{ patches: [{ file, original, replacement, finding_ref, severity }] }`
- Predicate: `fixes_drafted` — artifact has at least one patch
- Why Sonnet: needs to write correct code that matches project style

**run_tests** (shell_script)
- Adapter: `shell_script`
- Input: fix_patches artifact
- Task: Apply patches, run test suite, capture results
- Artifact: `test_results`
- Predicate: `tests_passed` (existing)
- On failure: regress to `draft_fixes` with test output (max 3 loops)

**human_review** (gate)
- Adapter: `fake`
- Blocks for human approval

### Queue Config

```yaml
name: Error Handling Audit
slug: error_handling_audit
stages:
  - scan_error_handling
  - classify_severity
  - draft_fixes
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 3
stage_configs:
  scan_error_handling:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [error_patterns_found]
    agent_prompt: file://prompts/audit_scan_error_handling.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: error_patterns
  classify_severity:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [severity_classified]
    agent_prompt: file://prompts/audit_classify_severity.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: severity_report
  draft_fixes:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [fixes_drafted]
    agent_prompt: file://prompts/audit_draft_fixes.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: fix_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [tests_passed]
    agent_prompt: Apply fix patches and run the test suite. Report pass/fail.
    timeout_seconds: 600
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review error handling fixes before merge.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates Needed

- `error_patterns_found` — checks for `error_patterns` artifact (empty patterns is valid)
- `severity_classified` — checks for `severity_report` artifact with findings
- `fixes_drafted` — checks for `fix_patches` artifact with at least one patch

### E2E Test Fixtures

Create a small fixture app in `test/fixtures/apps/bad_error_handling/` with deliberately bad patterns:

```ruby
# app/controllers/payments_controller.rb
def create
  charge = PaymentGateway.charge(params[:amount])
  render json: charge
rescue => e
  puts e.message
  render json: { error: "something went wrong" }, status: 500
end

# app/jobs/sync_job.rb
def perform(user_id)
  user = User.find(user_id)
  ExternalApi.sync(user)
rescue
  # silently swallowed
end

# app/services/external_api.rb
def self.sync(user)
  HTTP.get("https://api.example.com/sync/#{user.id}")  # no timeout
end
```

### Cross-Queue Spawn

When `classify_severity` finds critical findings that require architectural changes (not just error handling fixes), it can spawn work items into the `development` queue with specs for the larger refactor.
