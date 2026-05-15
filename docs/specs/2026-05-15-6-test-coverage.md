# Spec: Test coverage backfill (2026-05-15-6)

## Use case

Core engine jobs, adapter implementations, and security scenarios have minimal or no test coverage. These are the highest-risk code paths and need specs before production.

## Scope

In scope:
- EngineTickJob specs (happy path, error path, concurrency)
- CheckAsyncClaimsJob specs (polling, stale detection, backoff)
- Adapter integration tests (shell_script, inline_claude, codex_adapter)
- Security scenario tests (auth bypass, malformed tokens, oversized payloads)

Out of scope:
- TUI test coverage (separate spec)
- E2E pipeline tests (already exist and passing)
- Performance/load tests

## Requirements

### 1) EngineTickJob specs

**File:** `spec/jobs/engine_tick_job_spec.rb`

Tests needed:
- **Happy path:** Create pending work items across multiple queues. Run job. Assert claims created and items progressed.
- **Empty queues:** No pending items. Run job. Assert no errors, no claims created.
- **Adapter failure:** Configure an adapter to raise. Assert the failing item gets a failed claim, other items still process (depends on spec 2026-05-15-1 error isolation).
- **Concurrent ticks:** Run two jobs in parallel threads. Assert no duplicate claims on the same item (depends on spec 2026-05-15-1 pessimistic locking).
- **Mixed statuses:** Queue has pending, running, completed, and blocked items. Assert only pending items are claimed.

### 2) CheckAsyncClaimsJob specs

**File:** `spec/jobs/check_async_claims_job_spec.rb`

Tests needed:
- **Running claim with fresh heartbeat:** Assert claim stays in `running` status.
- **Running claim with stale heartbeat:** Assert claim is marked `failed` (or retried, depending on engine behavior).
- **Running claim with nil heartbeat:** Assert no crash, claim treated as not-yet-stale.
- **Completed async claim:** External adapter has finished. Assert claim is marked `completed` and work item advances.
- **No async claims:** Assert job completes without error.

### 3) Adapter integration tests

**File:** `spec/adapters/` directory

#### ShellScriptAdapter
- **Successful command:** Run `echo hello`. Assert claim completed, output captured in artifact.
- **Failing command:** Run `exit 1`. Assert claim failed, stderr captured.
- **Timeout:** Run `sleep 30` with a 1-second timeout. Assert claim failed with timeout reason.
- **Working directory:** Assert command runs in the specified directory, not the app root.
- **Multiple commands:** Config with 3 commands. Assert all run in sequence, all outputs captured.

#### InlineClaudeAdapter
- **Successful response:** Mock Claude API. Assert claim completed, response stored as artifact.
- **API error:** Mock 500 response. Assert claim failed with error details.
- **Token/cost tracking:** Assert trace events record token counts and cost.

#### CodexAdapter
- **Claim created:** Assert async claim is created with `running` status and external reference.
- **Poll completed:** Mock external completion. Assert claim transitions to `completed`.
- **Poll still running:** Mock external still-running response. Assert claim stays `running`.

Use `webmock` for all external HTTP calls. No real API calls in tests.

### 4) Security scenario tests

**File:** `spec/requests/security_spec.rb`

Tests needed:
- **No auth header:** Request to `/api/v1/work_items` → 401.
- **Malformed auth header:** `Authorization: NotBearer xyz` → 401.
- **Wrong token:** Valid format, wrong value → 401.
- **Admin token on API endpoint:** Should fail (admin and service tokens are separate).
- **Service token on admin endpoint:** Should fail.
- **Empty bearer token:** `Authorization: Bearer ` → 401.
- **SQL injection in query params:** `?stage='; DROP TABLE work_items;--` → no error, no SQL injection (parameterized queries handle this, but verify).
- **Oversized request body:** 2 MB POST to create → 413 (depends on spec 2026-05-15-4).
- **Invalid JSON body:** Malformed JSON → 400.

## Acceptance criteria

- [ ] EngineTickJob has specs covering happy path, empty queues, adapter failure, concurrency, and mixed statuses
- [ ] CheckAsyncClaimsJob has specs covering fresh heartbeat, stale heartbeat, nil heartbeat, completed claim, and empty state
- [ ] ShellScriptAdapter has specs covering success, failure, timeout, working directory, and multi-command
- [ ] InlineClaudeAdapter has specs covering success, API error, and cost tracking
- [ ] CodexAdapter has specs covering claim creation, poll completed, and poll running
- [ ] Security scenario tests cover auth bypass, malformed tokens, wrong token types, injection, and oversized payloads
- [ ] All specs pass in CI
