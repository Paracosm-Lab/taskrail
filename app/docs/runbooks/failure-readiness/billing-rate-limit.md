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
