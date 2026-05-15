# Spec: Engine safety hardening (2026-05-15-1)

## Use case

The engine has three race/crash conditions that will cause data corruption or job failures under load. These must be fixed before any production traffic.

## Scope

In scope:
- Pessimistic locking on work item claim creation
- Error isolation so one bad adapter doesn't crash the entire tick
- Heartbeat nil guard on new claims

Out of scope:
- Exponential backoff on async polling (separate spec)
- Cross-queue pipe loop detection (separate spec)
- New adapter types

## Requirements

### 1) Pessimistic locking on claim creation

**Problem:** `Engine::Runner#call` queries for pending work items, then creates claims. If two `EngineTickJob` ticks overlap, both can claim the same item.

**Fix:** In `Engine::Runner`, wrap the fetch-and-claim sequence in a transaction with `lock!`:

```ruby
WorkItem.transaction do
  item = WorkItem.lock.where(status: :pending, work_queue: queue).first
  next unless item
  # create claim, proceed with adapter execution
end
```

Alternatively, use `with_lock` on the individual item after selection. The key constraint: a work item in `pending` status must not have two concurrent `running` claims.

**Test:**
- Spawn two threads that both try to claim the same pending item. Assert only one claim is created.
- Verify the losing thread skips gracefully (no error, no claim).

### 2) Error isolation in Engine::Runner

**Problem:** If an adapter raises during execution (timeout, network error, bad config), the entire `EngineTickJob` crashes. No other pending items get processed that tick.

**Fix:** Wrap each item's processing in a `rescue StandardError`:

```ruby
items.each do |item|
  begin
    # existing claim + adapter execution logic
  rescue StandardError => e
    Rails.logger.error("Engine::Runner failed for WorkItem##{item.id}: #{e.message}")
    claim&.update!(status: :failed, metadata: claim.metadata.merge("error" => e.message))
  end
end
```

**Test:**
- Create 3 pending items. Configure the adapter for item 2 to raise. Assert items 1 and 3 still get claimed and processed. Assert item 2's claim is marked `failed` with the error message.

### 3) Heartbeat nil guard

**Problem:** `Claim` has a `HEARTBEAT_STALE_AFTER` constant and stale detection logic. If `last_heartbeat_at` is nil (claim just created, no heartbeat yet), the comparison crashes with a `NoMethodError`.

**Fix:** In the stale check, treat nil as "not yet stale" (the claim was just created):

```ruby
def stale?
  return false if last_heartbeat_at.nil?
  last_heartbeat_at < HEARTBEAT_STALE_AFTER.ago
end
```

**Test:**
- Create a claim with `last_heartbeat_at: nil`. Assert `stale?` returns `false`.
- Create a claim with `last_heartbeat_at: 3.minutes.ago` (beyond threshold). Assert `stale?` returns `true`.
- Create a claim with `last_heartbeat_at: 30.seconds.ago`. Assert `stale?` returns `false`.

## Acceptance criteria

- [ ] No two running claims exist for the same work item under concurrent load
- [ ] A failing adapter does not prevent other pending items from being processed in the same tick
- [ ] Failed claims have `status: :failed` with error details in metadata
- [ ] `Claim#stale?` handles nil `last_heartbeat_at` without crashing
- [ ] All three scenarios have passing specs
