# Spec: Streaming dashboard scalability (2026-05-15-10)

## Use case

The dashboard stream should feel live without polling the entire queue state every two seconds per connected client. The current implementation works for small local data, but it can become expensive as work items and traces grow.

## Scope

In scope:
- Redesign `GET /api/v1/stream` to reduce database load
- Bound stream payload sizes
- Avoid repeated full-table aggregate work
- Add tests for large queues and client disconnects

Out of scope:
- WebSocket migration unless it is clearly simpler
- External pub/sub infrastructure
- Cross-node fanout guarantees

## Requirements

### 1) Define stream semantics

**Problem:** The current stream sends a complete dashboard payload forever. It is unclear whether clients need snapshots, deltas, heartbeat events, or all three.

**Fix:**
- Define event types:
  - `snapshot`: initial bounded dashboard state
  - `work_item_changed`: changed work item payload
  - `costs_changed`: aggregate cost payload
  - `heartbeat`: connection keepalive
- Prefer incremental events after the initial snapshot.
- Include a monotonic cursor or timestamp so clients can resume or reconcile.

**Test:**
- First stream event is a bounded snapshot.
- Subsequent events include changed records only when changes occur.
- Heartbeat events are emitted when no data changes.

### 2) Bound dashboard payloads

**Problem:** `StreamsController` serializes every work item in the selected queue each poll.

**Fix:**
- Apply explicit limits to stream snapshots, for example:
  - active/non-completed items
  - latest N completed items per queue or stage
  - optional `limit` parameter clamped to a max
- Include metadata that tells the client when results are truncated.

**Test:**
- Queue with more than the max item count returns at most the max.
- Response includes truncation metadata.
- Completed items are bounded separately from active items.

### 3) Avoid repeated aggregate queries per client

**Problem:** Every connected client recomputes `Trace` totals every two seconds.

**Fix:**
- Cache dashboard aggregates for a short TTL, or materialize them through a service object.
- Share the same aggregate calculation path between REST and stream endpoints.
- Do not run unbounded trace aggregate queries for every loop iteration.

**Test:**
- Multiple stream ticks within the TTL do not recompute trace totals.
- Cache invalidation or TTL expiry refreshes totals.
- REST cost endpoint and stream payload agree on total fields.

### 4) Make stream lifecycle robust

**Problem:** Long-lived live streams can tie up server resources if they are not bounded and cleaned up predictably.

**Fix:**
- Add a max stream duration or server-side heartbeat/timeout policy.
- Ensure disconnects close the stream without logging noisy backtraces.
- Consider moving stream payload construction into a dedicated service object.

**Test:**
- Client disconnect closes the stream cleanly.
- Max duration exits the loop.
- Exceptions in payload construction are logged and close the stream safely.

## Acceptance criteria

- [ ] Stream contract documents snapshot, delta, heartbeat, and cursor behavior
- [ ] Initial snapshots are bounded and include truncation metadata
- [ ] Stream loop does not serialize every queue item on every tick
- [ ] Trace/cost aggregates are cached or otherwise not recomputed per client tick
- [ ] Client disconnect and max-duration behavior are covered by tests
- [ ] Existing TUI/dashboard behavior is preserved or intentionally migrated
