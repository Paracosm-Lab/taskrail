# Billing Provider Rate Limit

## Scope

Use this runbook when the billing provider returns sustained rate-limit responses. Human review required before replaying charges or changing idempotency behavior.

## Observe

- Confirm provider responses include `429` status codes and capture the `Retry-After` header.
- Check whether failures are isolated to one endpoint, tenant, or background job.
- Confirm every retrying request includes an idempotency key.

## Mitigate

- Pause noncritical billing backfills and batch jobs.
- Reduce concurrency for billing workers.
- Honor `Retry-After` before retrying provider calls.
- Preserve idempotency keys across retries to avoid duplicate charges.

## Verify

- Provider responses return to 2xx for normal traffic.
- Queue depth is draining at a controlled rate.
- No duplicate charge alerts or reconciliation mismatches appear.

## Escalate

Human review required if rate limits persist after concurrency reduction, if idempotency cannot be verified, or if customer-visible billing state may be wrong.
