# Cookbook Spec: Background Job Observability

## Use Case

Your Sidekiq/GoodJob/SQS queues process thousands of jobs a day. You know about failures when a customer complains — "my export never arrived," "my invoice wasn't sent," "my sync didn't run." The jobs themselves have no instrumentation, no structured logging, no timeout config, and no dead letter strategy. Some retry forever. Some fail silently. Some have been stuck in the retry set for weeks.

TaskRail scans every job class, checks for instrumentation, scores observability, and drafts the missing pieces. Same pattern as the Sentry alert cookbook, but for your async work.

## Queue: `job_observability`

### Stages

```
scan_job_classes → assess_observability → draft_fixes → run_tests → human_review → done
```

### Stage Details

**scan_job_classes** (Haiku)
- Adapter: `inline_claude`
- Input: repository path, job framework (Sidekiq, GoodJob, ActiveJob, Celery, etc.)
- Task: Find every job/worker class and catalog:
  - Class name, file path, queue name
  - `perform` method signature (what args does it take?)
  - Retry configuration (max retries, backoff, dead letter)
  - Timeout/deadline configuration
  - Error handling (rescue blocks, Sentry capture, logging)
  - Logging statements (structured? contextual?)
  - Idempotency handling (does it check for duplicate work?)
  - Dependencies (database, external APIs, other services)
  - Scheduling (cron, on-demand, event-driven)
- Artifact: `job_inventory` — `{ framework, jobs: [{ class_name, file, queue, args, retry_config, timeout, error_handling, logging, idempotent, dependencies, schedule }] }`
- Predicate: `job_inventory_produced` — artifact exists with at least one job
- Why Haiku: parsing class definitions and configuration, not reasoning

**assess_observability** (Sonnet)
- Adapter: `inline_claude`
- Input: job_inventory artifact, source code
- Task: Score each job on observability dimensions (0-3):
  - **Error capture**: does it report failures to Sentry/error tracking with context?
  - **Structured logging**: does it log start, completion, and key decision points with structured data?
  - **Timeout protection**: does it have a deadline/timeout to prevent stuck jobs?
  - **Retry strategy**: appropriate retry count, backoff, dead letter handling?
  - **Idempotency**: safe to retry? Will duplicate execution cause data corruption?
  - **Context propagation**: does it pass request_id, tenant_id, or correlation IDs?
  - **Metrics**: does it emit duration, success/failure counts, queue depth?
  - Classify each job as `well_instrumented` (score >= 2.0) / `under_instrumented` (1.0-2.0) / `blind` (< 1.0)
  - Flag critical jobs (payments, data sync, notifications) that are `blind`
- Artifact: `observability_assessment` — `{ jobs: [{ class_name, scores: {}, total_score, classification, critical_gaps: [] }], summary: { total_jobs, well_instrumented, under_instrumented, blind, worst_job } }`
- Predicate: `observability_assessed` — artifact exists with assessments
- Why Sonnet: needs to understand what good job observability looks like and make risk judgments

**draft_fixes** (Sonnet)
- Adapter: `inline_claude`
- Input: observability_assessment artifact (blind and under_instrumented jobs), source code
- Task: For each job that needs work, draft fixes prioritized by risk:
  - **Error capture**: wrap perform in Sentry scope with job-specific context
    ```ruby
    Sentry.with_scope do |scope|
      scope.set_context("job", { class: self.class.name, args: arguments, jid: job_id, attempt: executions })
      scope.set_tags(queue: queue_name, tenant: args[:tenant_id])
      # ... existing perform logic
    end
    ```
  - **Structured logging**: add `Rails.logger.info({ event: "job.start", job: class_name, args: sanitized_args }.to_json)` at entry/exit
  - **Timeout**: add `sidekiq_options deadline: 300` or equivalent
  - **Retry config**: set appropriate `retry` count, add `sidekiq_retries_exhausted` handler
  - **Idempotency**: add idempotency key check where applicable
  - Match existing patterns in the codebase
- Artifact: `job_patches` — `{ patches: [{ file, class_name, original, replacement, fix_type, priority }] }`
- Predicate: `fixes_drafted` (reuse)
- Cross-queue spawn: for jobs that need architectural changes (e.g., splitting a monolithic job, adding a dead letter queue), spawn into `development`
- Why Sonnet: needs to write correct instrumentation code

**run_tests** (shell_script)
- Adapter: `shell_script`
- Predicate: `tests_passed` (existing)
- On failure: regress to `draft_fixes`

**human_review** (gate)

### Queue Config

```yaml
name: Background Job Observability
slug: job_observability
stages:
  - scan_job_classes
  - assess_observability
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
  scan_job_classes:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [job_inventory_produced]
    agent_prompt: file://prompts/jobs_scan_classes.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: job_inventory
  assess_observability:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [observability_assessed]
    agent_prompt: file://prompts/jobs_assess_observability.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: observability_assessment
  draft_fixes:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [fixes_drafted]
    agent_prompt: file://prompts/jobs_draft_fixes.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: job_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [tests_passed]
    agent_prompt: Apply job instrumentation patches and run the test suite. Report pass/fail.
    timeout_seconds: 600
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review job observability improvements.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates Needed

- `job_inventory_produced` — checks for `job_inventory` artifact with at least one job
- `observability_assessed` — checks for `observability_assessment` artifact with assessments for all inventoried jobs

### E2E Test Fixtures

Create a fixture app in `test/fixtures/apps/uninstrumented_jobs/` with:

```ruby
# A job with zero instrumentation
class ExportJob < ApplicationJob
  def perform(user_id)
    user = User.find(user_id)
    csv = generate_csv(user.orders)
    S3.upload("exports/#{user_id}.csv", csv)
  end
end

# A job with some instrumentation (the "good" example)
class BillingJob < ApplicationJob
  sidekiq_options retry: 5, queue: :critical, deadline: 300

  def perform(invoice_id)
    Sentry.with_scope do |scope|
      scope.set_context("billing", { invoice_id: invoice_id })
      Rails.logger.info({ event: "billing.start", invoice_id: invoice_id }.to_json)
      # ...
    end
  end

  sidekiq_retries_exhausted do |msg, ex|
    Sentry.capture_exception(ex, extra: { job: msg })
    Rails.logger.error({ event: "billing.exhausted", msg: msg }.to_json)
  end
end

# A job that retries forever with no backoff
class SyncJob < ApplicationJob
  sidekiq_options retry: true  # infinite retries, no dead letter

  def perform(record_id)
    ExternalApi.sync(record_id)  # no timeout, no error handling
  end
end

# A job that swallows errors
class CleanupJob < ApplicationJob
  def perform
    User.inactive.find_each do |user|
      user.anonymize!
    rescue => e
      # silently continue
    end
  end
end
```

### Output Format

The assessment should produce a human-readable scorecard:

```
BACKGROUND JOB OBSERVABILITY — 2026-05-05

Job                Queue      Error  Log  Timeout  Retry  Idemp  Context  CLASS
ExportJob          default      0     0     0        0      0      0      BLIND
SyncJob            default      0     0     0        0      0      0      BLIND
CleanupJob         default      0     0     0        0      0      0      BLIND
BillingJob         critical     3     2     3        3      0      2      OK

Summary: 4 jobs total, 1 well-instrumented, 0 under-instrumented, 3 blind
Worst: ExportJob, SyncJob, CleanupJob (all scoring 0.0)
Critical risk: SyncJob retries infinitely with no timeout or dead letter
```

### Recurring Use

Run after adding new job classes. Compare scores against previous run. Track the ratio of blind → under-instrumented → well-instrumented over time.
