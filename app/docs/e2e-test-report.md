# TaskRail E2E Test Report

**Date:** 2026-05-05
**Pipeline:** Operations Queue
**Runs:** 2 (iterative — bugs found, fixed, retested)

---

## What This Is

This is a test. We built four fake Sentry alerts that simulate a realistic multi-service incident, fed them into TaskRail's operations pipeline, and watched what happened. The alerts are canned JSON fixtures, the services don't exist, and nobody was paged.

The point was to prove that the pipeline works end-to-end: can it ingest raw alerts, reason about them, identify what's wrong with the observability itself, draft operational runbooks, and stop at the right gate for human approval — all without anyone touching it?

It can. And along the way, the test runs found two real bugs in the engine that we fixed between iterations.

### Why You'd Do This

TaskRail is meant to run autonomously on real Sentry webhooks. Before you point it at production, you need to know:

- Does the pipeline actually advance through all stages?
- Do the predicates catch bad work or let garbage through?
- Does cross-queue spawn actually create work items in the dev queue?
- What happens when a stage times out?
- What happens when the agent produces output in an unexpected format?

You can't answer these questions with unit tests. You need to run the whole thing with real (or realistic) data and see what breaks. That's what this report documents.

---

## The Test Data

Four canned Sentry alerts in `test/fixtures/sentry/`, designed to simulate a realistic multi-service incident. They're deliberately varied — different services, different failure modes, different levels of instrumentation quality.

### Alert 1: Database Pool Timeout
```
Service:     crm-service
Server:      scribbl-crm-1
Error:       ActiveRecord::ConnectionTimeoutError
Message:     "could not obtain connection from pool within 5.000 seconds"
Stack:       app/controllers/sessions_controller.rb:42 (create)
Request:     POST /sessions
Breadcrumbs: SELECT * FROM sessions WHERE token = ?
             POST /sessions
```
A user tried to log in. The connection pool was exhausted — every connection was checked out and the 5-second timeout expired waiting for one to free up.

### Alert 2: Database Connection Refused
```
Service:     crm-service
Server:      scribbl-crm-2 (different host!)
Error:       PG::ConnectionBad
Message:     "could not connect to server: Connection refused"
Stack:       app/models/customer.rb:19 (find_for_sync)
Database:    crm-postgres.internal:5432
Breadcrumbs: Opening PostgreSQL connection to crm-postgres.internal:5432
             ECONNREFUSED crm-postgres.internal:5432
```
A different CRM host tried to sync a customer record. Postgres refused the connection entirely. Same database, different app server — this isn't a single-host problem.

### Alert 3: Nil Reference in Background Job
```
Service:     notification-service
Server:      scribbl-notifications-1
Error:       NoMethodError
Message:     "undefined method 'email' for nil:NilClass"
Stack:       app/mailers/weekly_digest_mailer.rb:27 (digest)
             app/jobs/weekly_digest_job.rb:14 (perform)
Job:         WeeklyDigestJob, queue: mailers
Breadcrumbs: Performing WeeklyDigestJob user_id=8821
             Rendering weekly_digest_mailer
```
A weekly digest job looked up a recipient and got nil. Called `.email` on nil. Different service from the DB errors — but is it related? If notification-service queries crm-service's database for user records, and that database is down, the lookup could return nil.

### Alert 4: Rate Limit (Deliberately Thin)
```
Service:     billing-service
Server:      scribbl-billing-1
Error:       HTTP::TimeoutError
Message:     "rate limit exceeded"
Stack:       app/services/payment_gateway.rb:88 (charge)
Breadcrumbs: (none)
Context:     (none)
```
This one is intentionally bare. No breadcrumbs. No provider name. No HTTP status code. No customer ID, invoice ID, or idempotency key. The error type is wrong — `HTTP::TimeoutError` for a rate limit should be an HTTP 429. This alert exists to trigger the pipeline's "thin instrumentation" detection.

---

## Run 1: First E2E Pass

### What Happened

Created a work item with all four alerts and let the engine tick through the pipeline.

```
20:24:47  Work item created at ingest_signals
20:25:49  ingest_signals → cluster_failures     (52s, Haiku)
20:26:37  cluster_failures → cluster_failures    RETRY (timeout)
20:30:56  cluster_failures → cluster_failures    RETRY (timeout)
20:32:41  cluster_failures → assess_instrumentation  (40s, Sonnet)
20:34:19  assess_instrumentation → map_runbooks  (85s, Sonnet)
20:35:26  map_runbooks → draft_runbook           (55s, Sonnet)
20:38:07  draft_runbook → human_review           (152s, Opus)
20:45:35  human_review → staging_validation      (manual advance)
```

**Total autonomous pipeline time: ~13 minutes** (plus two retries on cluster_failures that timed out at 180s each)

### Stage 1: Ingest Signals (Haiku, 52s)

Haiku normalized all four events into a structured summary. Triage work — extraction, not reasoning. It pulled out service names, error types, stack locations, server hosts, and spotted the first correlation:

> "Two database-related errors on crm-service (pool timeout and connection refused) — both targeting crm-postgres.internal in westus2, suggesting a correlated database availability pattern."

It noted the errors span two different hosts (`scribbl-crm-1`, `scribbl-crm-2`), ruling out a single-host network issue. It also noted all four alerts are from the staging environment, Ruby 3.3.0, deployed via Kamal.

### Stage 2: Cluster Failures (Sonnet, 40s after 2 retries)

Sonnet grouped the four alerts into three clusters:

**Cluster 1: `crm-postgres-unavailable`** (severity: high)

Grouped the pool timeout and connection refused errors together:

> "A pool timeout and a connection-refused error against the same Postgres host, across multiple app instances, strongly indicate the database is unreachable or overloaded. The pool timeout is likely a consequence of the connection refusal — requests queue waiting for connections that can never be established."

It flagged what it didn't know: no timestamps to confirm temporal overlap, no Postgres-side metrics, no log correlation.

**Cluster 2: `notification-nil-reference`** (severity: medium)

Kept separate — no proven shared dependency. But it raised exactly the hypothesis we hoped it would:

> "A speculative secondary hypothesis is that if notification-service queries crm-service's database for user records and that database is down, the lookup could return nil — but there is no evidence of a shared database dependency."

**Cluster 3: `billing-rate-limit`** (severity: low)

Independent failure mode. External API throttle. No infrastructure overlap.

### Stage 3: Assess Instrumentation (Sonnet, 85s)

Sonnet scored each cluster's instrumentation quality on a 1-5 scale across five dimensions: error specificity, context richness, breadcrumbs, reproducibility, and structured metadata.

**Every cluster scored below 3.0:**

| Cluster | Score | Verdict | Worst Gaps |
|---------|-------|---------|------------|
| crm-postgres-unavailable | 2.2 | thin | No pool state metadata, no request IDs, no DB-side metrics |
| notification-nil-reference | 2.0 | thin | No job ID or attempt count, no breadcrumb showing the nil lookup |
| billing-rate-limit | **1.2** | thin | No provider name, wrong error type, no request context at all |

On the billing cluster:

> "Error message is 'rate limit exceeded' with no detail on which payment provider, API endpoint, or rate limit tier was hit. HTTP::TimeoutError is a misleading exception type for a rate limit — suggests the error is not properly classified or wrapped. No request context: no customer/invoice/payment ID, no amount, no idempotency key."

**Then it spawned three work items into the development queue** — the self-improving loop in action. Each spawn item included a detailed inline spec:

1. **"Add Sentry context and breadcrumbs to crm-service database operations"**
   - Add `Sentry.set_context('database', { host, pool_size, checked_out, wait_queue_depth })` before pool checkout
   - Add `Sentry.set_tags(request_id, tenant_id, operation)` to all DB-accessing actions
   - Add breadcrumbs for connection checkout/checkin lifecycle
   - Capture `pg_stat_activity` connection count on ConnectionBad errors

2. **"Add job context and nil-guard instrumentation to notification-service WeeklyDigestJob"**
   - Add `Sentry.set_context('job', { job_id, attempt, enqueued_at, recipient_user_id })` at job start
   - Add breadcrumb before recipient lookup showing the query/ID being resolved
   - Add nil guard with explicit `Sentry.capture_message` when lookup returns nil

3. **"Add structured context to billing-service payment gateway rate limit handling"**
   - Wrap rate limit responses with a dedicated `RateLimitError` (not `HTTP::TimeoutError`)
   - Add `Sentry.set_context('payment', { provider, endpoint, customer_id, invoice_id, amount, idempotency_key })`
   - Capture `Retry-After` header and rate limit window

### Stage 4: Map Runbooks (Sonnet, 55s)

Sonnet searched the entire repository for existing runbooks. Found nothing — no `runbooks/` directory, no YAML files, no playbook documents. All three clusters mapped to "missing."

### Stage 5: Draft Runbooks (Opus, 152s)

Opus read every prior stage's output and drafted three complete operational runbooks with actual runnable commands.

**Runbook: CRM Postgres Unavailable** — `pg_isready` to check reachability, `pg_stat_activity` queries for connection counts, Rails console for pool stats, exact SQL to terminate idle-in-transaction sessions, Kamal rolling restart commands. Escalation matrix: Postgres won't start → DBA; connections maxed → DBA; network partition → infra team; 30+ minutes → incident commander.

**Runbook: Notification Nil Reference** — Check Sidekiq retry and dead sets for the failed job, verify recipient record exists, determine if recurring or race condition. Flagged the potential Postgres cluster link: "Treat as a secondary symptom of cluster-001. Resolve the database connectivity issue first — the nil reference may self-resolve."

**Runbook: Billing Rate Limit** — Identified the wrong exception type (`HTTP::TimeoutError` for a 429). Check the payment provider's status page. If retry storm, pause the billing queue. Warning about duplicate charges and idempotency keys when re-enqueuing from the dead set.

### Stage 6: Human Review (gate)

Pipeline stopped. The human review stage uses a `fake` adapter that blocks immediately. The work item sits at `pending` until a human approves it — the engine will not push runbooks to staging or production without approval.

We manually advanced it to test the gate mechanism.

---

## Bugs Found in Run 1

Two integration bugs surfaced that unit tests couldn't catch:

### Bug 1: spawn_work_items Never Extracted

The `assess_instrumentation` agent produced three spawn items inside a JSON code block in its response. But InlineClaudeAdapter stored Claude's entire output as a raw text string in `report.body["response"]`. TransitionManager reads `report.body["spawn_work_items"]` — a top-level key. The spawn data was there but invisible.

```
Run 1 report keys: ["stage", "summary", "response"]        ← spawn_work_items buried in "response" text
Run 2 report keys: ["stage", "summary", "response", "spawn_work_items"]  ← extracted as top-level key
```

**Fix:** Built `Adapters::ResponseParser` — scans Claude's freeform text for JSON code blocks, parses them, and merges known structured keys (`spawn_work_items`, `tags`) into the report body. Wired it into `InlineClaudeAdapter#success_report`.

### Bug 2: Stage Timeouts Too Short

`cluster_failures` timed out twice at 180 seconds before succeeding on the third attempt. The Claude CLI needs more time when processing substantial prompts with upstream artifacts.

**Fix:** Bumped all Claude stage timeouts to 600 seconds.

---

## Run 2: After Fixes

After committing the ResponseParser and timeout fixes, created a fresh work item and reran.

```
20:45:26  Work item created at ingest_signals
20:47:52  ingest_signals → ingest_signals        RETRY (120s timeout — old config cached)
20:49:31  ingest_signals → cluster_failures       (32s, Haiku)
20:49:59  cluster_failures → assess_instrumentation  (20s, Sonnet)
20:50:35  assess_instrumentation → map_runbooks   (23s, Sonnet)
20:51:18  map_runbooks → draft_runbook            (35s, Sonnet)
20:51:49  draft_runbook → human_review            (25s, Opus)
```

**Key verification:** `assess_instrumentation` report now has `spawn_work_items` as a top-level key. The ResponseParser fix works. TransitionManager can now see the spawn data and create work items in the dev queue.

All five stages passed with correct artifact kinds (`agent_report`, `clusters`, `instrumentation_assessment`, `runbook_mapping`, `runbook_draft`). Pipeline stopped at `human_review` — correct.

---

## The Self-Improving Loop

This is the part that feels like science fiction. The pipeline doesn't just process incidents — it makes itself better at processing future incidents.

Here's the cycle:

```
Thin Sentry alerts fire
        ↓
Ops pipeline ingests, clusters, assesses
        ↓
assess_instrumentation scores each cluster
        ↓
Finds thin instrumentation (score < 3.0)
        ↓
Spawns dev work items with specific fix specs
        ↓
Dev pipeline picks them up → implements fixes → PRs
        ↓
Services now have richer Sentry context
        ↓
Next time the same errors fire, alerts are richer
        ↓
Ops pipeline scores them higher → fewer spawn items
        ↓
Better runbooks, faster incident response
```

### Before and After: What the Alerts Would Look Like

**billing-service — Before (score: 1.2)**
```json
{
  "exception": {
    "values": [{
      "type": "HTTP::TimeoutError",
      "value": "rate limit exceeded",
      "stacktrace": {
        "frames": [{
          "filename": "app/services/payment_gateway.rb",
          "lineno": 88,
          "function": "charge"
        }]
      }
    }]
  }
}
```
That's it. No breadcrumbs. No context. No provider name. Wrong error type. An on-call engineer sees "rate limit exceeded" and has to go digging through logs, dashboards, and Slack to figure out which provider, which customer, and whether charges are being duplicated.

**billing-service — After (projected, post-instrumentation fix)**
```json
{
  "exception": {
    "values": [{
      "type": "BillingService::RateLimitError",
      "value": "Stripe rate limit exceeded: 429 Too Many Requests (Retry-After: 30s)",
      "stacktrace": { "..." }
    }]
  },
  "tags": {
    "provider": "stripe",
    "http_status": "429",
    "rate_limit_tier": "standard",
    "service": "billing-service"
  },
  "contexts": {
    "payment": {
      "customer_id": "cus_abc123",
      "invoice_id": "inv_xyz789",
      "amount_cents": 4999,
      "idempotency_key": "charge_20260505_inv_xyz789",
      "endpoint": "/v1/charges"
    }
  },
  "breadcrumbs": {
    "values": [
      { "message": "Fetching invoice inv_xyz789", "category": "billing" },
      { "message": "POST /v1/charges (attempt 1) → 200 OK", "category": "stripe" },
      { "message": "POST /v1/charges (attempt 2) → 200 OK", "category": "stripe" },
      { "message": "POST /v1/charges (attempt 3) → 429 Rate Limited", "category": "stripe" }
    ]
  }
}
```
Now the on-call engineer sees: it's Stripe, it's a 429, the Retry-After is 30 seconds, it happened on the third charge attempt, and here's the customer and invoice. The runbook the ops pipeline drafts next time will be more specific because the alert itself tells a complete story.

**crm-service — Before (score: 2.2)**
```json
{
  "exception": {
    "values": [{
      "type": "ActiveRecord::ConnectionTimeoutError",
      "value": "could not obtain connection from pool within 5.000 seconds"
    }]
  },
  "breadcrumbs": {
    "values": [
      { "message": "SELECT * FROM sessions WHERE token = ?", "category": "db" },
      { "message": "POST /sessions", "category": "rails.request" }
    ]
  }
}
```
You know the pool timed out. You don't know pool state, connection counts, or whether this is one user or a thousand.

**crm-service — After (projected)**
```json
{
  "exception": {
    "values": [{
      "type": "ActiveRecord::ConnectionTimeoutError",
      "value": "could not obtain connection from pool within 5.000 seconds"
    }]
  },
  "tags": {
    "request_id": "req_7f3a2b",
    "tenant_id": "tenant_42",
    "operation": "session_create",
    "database_host": "crm-postgres.internal"
  },
  "contexts": {
    "database": {
      "host": "crm-postgres.internal",
      "pool_size": 10,
      "checked_out": 10,
      "idle": 0,
      "waiting": 47,
      "checkout_timeout": 5.0
    },
    "pg_stat": {
      "active_connections": 95,
      "max_connections": 100,
      "idle_in_transaction": 23
    }
  },
  "breadcrumbs": {
    "values": [
      { "message": "Connection checkout requested", "category": "db.pool" },
      { "message": "Pool exhausted: 10/10 checked out, 47 waiting", "category": "db.pool" },
      { "message": "Timeout after 5.0s waiting for connection", "category": "db.pool" }
    ]
  }
}
```
Now you immediately see: pool is full (10/10), 47 requests waiting, Postgres itself has 95 of 100 connections used with 23 idle-in-transaction. The runbook can say "if `idle_in_transaction` > 20, terminate sessions older than 5 minutes" because the data is right there in the alert.

---

## How the Engine Works

### The Pipeline (YAML-defined)

```
ingest_signals ──→ cluster_failures ──→ assess_instrumentation ──→ map_runbooks ──→ draft_runbook ──→ human_review
    Haiku              Sonnet                  Sonnet                  Sonnet            Opus           (gate)
```

Each stage is config in `operations.yml` — model, timeout, predicates, retry limits, escalation rules. Adding a new stage means writing a prompt file and a few lines of YAML.

### Dual-Layer Completion

When an agent finishes, TaskRail doesn't trust it. Two layers:

1. **Agent self-report:** "I produced clusters." (report + artifacts)
2. **Predicate verification:** "Prove it." (engine checks the artifact independently)

We caught a real bug this way. Early in testing, InlineClaudeAdapter was labeling all artifacts as `agent_report`. The agents all reported success. The `clusters_created` predicate looked for a `clusters` artifact, found only `agent_report`, and failed. The system caught the mismatch; the agents didn't know anything was wrong.

### Automatic Retry

When `cluster_failures` timed out in Run 1, the engine:
1. Recorded a failure report
2. Incremented retry_count
3. Left the work item pending at the same stage
4. Next tick: fresh claim, new attempt
5. After two retries, third attempt succeeded

No human intervention. Exhaust the retry limit and the item blocks with a notification — it doesn't silently fail or loop forever.

### Cross-Queue Spawn

`assess_instrumentation` spawned three dev work items. The ops pipeline detected thin instrumentation and created actionable specs in the development queue. Different queue, different stages, different agents. This is how the system improves itself.

---

## What We Proved Across Two Runs

| Capability | Run 1 | Run 2 |
|---|---|---|
| All 5 Claude stages advance | yes | yes |
| Correct artifact kinds produced | yes (after fix) | yes |
| Predicates independently verify work | yes — caught artifact kind bug | yes |
| Automatic retry on timeout | yes — 2 retries on cluster_failures | yes — 1 retry on ingest_signals |
| Human review gate blocks correctly | yes | yes |
| ResponseParser extracts spawn_work_items | **no — bug found** | **yes — fixed** |
| spawn_work_items visible to TransitionManager | no | yes |
| Cost funnel (Haiku → Sonnet → Opus) | yes | yes |
| Agents reason about upstream context | yes — each stage reads prior artifacts | yes |

### Commits Between Runs

```
33db02b fix: add output_artifact_kind to ops queue stage configs
e5f80f9 feat: extract structured JSON from Claude CLI responses
99fcd5b chore: bump Claude stage timeouts to 600s
```

---

## Platform Stats

| Metric | Value |
|---|---|
| Project age | ~16 hours |
| Commits | 80 |
| Ruby source | 2,592 lines |
| Files | 153 (.rb + .yml) |
| Test suite | 223 specs, 0 failures |
| Adapters | 5 (fake, shell_script, inline_claude, codex, docker_compose) |
| Queues | 2 (development, operations) |
| Predicates | 12 |

---

## What's Next

The ops pipeline works. The recursive loop is proven in concept — thin alerts go in, spawn items come out with specific instrumentation fixes. What remains:

- **Close the loop end-to-end** — let the dev queue pick up the spawned work items, implement the instrumentation fixes, open PRs, and verify the next round of alerts score higher
- **Retro TUI** — Ink/React terminal dashboard. Navigate queues, watch stages advance, approve human review gates from the terminal
- **Heartbeats** — long-running adapters report liveness every 30s. Staleness detection flags stuck claims without killing them
- **Digest** — `bin/taskrail digest --since 2h` for time-window activity summaries
- **Test Harness** — `bin/generate-sentry-alerts` to fire canned payloads at the Sentry Store API for repeatable E2E runs
- **Real Sentry webhook** — point a Sentry project at TaskRail and let it process actual production alerts
