# StupidClaw Runbook

## service-down

**Alert:** `service-down`
**Severity:** critical
**Fires when:** `up{service="stupidclaw"} == 0`
**Meaning:** The StupidClaw API is unavailable to clients.

### Investigate

**Step 1: Check health endpoint**

```bash
curl -fsS https://stupidclaw.example.com/health
```

- If HTTP 200 with `{"status":"ok"...}` -> service is up, check alert staleness.
- If timeout or non-200 -> continue to Step 2.

**Step 2: Check deploy and app logs**

```bash
kamal app logs --since 10m
```

- If crash loop or boot error -> go to Fix A.
- If dependency outage errors -> go to Fix B.

### Diagnosis

| Symptom | Root cause | Fix |
|---|---|---|
| `/health` failing and boot exceptions | bad deploy or startup regression | [Fix A: Roll back deploy](#fix-a-roll-back-deploy) |
| app up but external failures dominate | dependency incident | [Fix B: Enable maintenance and mitigate dependency](#fix-b-enable-maintenance-and-mitigate-dependency) |

### Fix A: Roll back deploy

1. Roll back to last known-good image.
   ```bash
   kamal rollback
   ```
2. Verify deployment settled.
3. **Verify:**
   ```bash
   curl -fsS https://stupidclaw.example.com/health
   ```
   expected output includes `"status":"ok"`.

### Fix B: Enable maintenance and mitigate dependency

1. Enable maintenance mode.
   ```bash
   curl -fsS -X PUT https://stupidclaw.example.com/admin/maintenance \
     -H "Authorization: Bearer $STUPIDCLAW_ADMIN_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"enabled":true}'
   ```
2. Mitigate dependency issue (DB/network/provider) and verify recovery.
3. Disable maintenance mode.
4. **Verify:** `GET /health` returns 200 and request errors normalize.

### Escalate if

- You have tried all fixes and alert still fires after 15 minutes.
- Rollback does not restore service health.
- Database or infrastructure ownership is required for recovery.

## queue-stalled

**Alert:** `queue-stalled`
**Severity:** warning
**Fires when:** `stupidclaw_work_items_stalled_total > 0`
**Meaning:** Work items are not transitioning for longer than the expected processing window.

### Investigate

**Step 1: Check queue state via API**

```bash
curl -fsS https://stupidclaw.example.com/api/v1/work_items?status=in_progress \
  -H "Authorization: Bearer $STUPIDCLAW_SERVICE_TOKEN"
```

- If no stale items -> likely stale alert.
- If stale items present -> continue to Step 2.

**Step 2: Check worker/process status**

```bash
kamal app logs --since 15m | tail -n 200
```

- If repeated adapter failures -> go to Fix A.
- If orchestration is blocked by maintenance or misconfig -> go to Fix B.

### Diagnosis

| Symptom | Root cause | Fix |
|---|---|---|
| repeated adapter execution errors | transient or persistent adapter failure | [Fix A: Retry and isolate failed stage](#fix-a-retry-and-isolate-failed-stage) |
| global stall with maintenance/config issue | operational guardrail active or bad config | [Fix B: Correct runtime settings](#fix-b-correct-runtime-settings) |

### Fix A: Retry and isolate failed stage

1. Retry impacted work item(s):
   ```bash
   bin/stupidclaw retry <WORK_ITEM_ID>
   ```
2. If repeated failures persist, block and escalate to human reviewer.
3. **Verify:** transition logs show forward progress and queue depth drops.

### Fix B: Correct runtime settings

1. Check maintenance state and circuit breakers.
2. Disable unintended maintenance/circuit settings.
3. **Verify:** new work item transitions resume within expected SLA.

### Escalate if

- Queue remains stalled after retries and settings correction.
- Multiple queues are impacted simultaneously.
- Persistent adapter/provider failures require domain owner intervention.
