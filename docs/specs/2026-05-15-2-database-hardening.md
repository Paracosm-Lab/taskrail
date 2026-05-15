# Spec: Database hardening (2026-05-15-2)

## Use case

The database has a wrong deploy config, missing indexes on hot query paths, and no protection against unbounded table growth. These need to be fixed for correctness and performance.

## Scope

In scope:
- Fix Kamal deploy credentials
- Add missing indexes via migration
- Add DB-level enum CHECK constraints

Out of scope:
- Table partitioning (defer until trace volume warrants it)
- Multi-server deployment
- Backup strategy (handled at infra level)

## Requirements

### 1) Fix Kamal deploy credentials

**Problem:** `config/deploy.yml` has copy-pasted Scribbl values:
```yaml
POSTGRES_DB: scribbl_api
POSTGRES_USER: scribbl
```

**Fix:** Update to TaskRail-specific values. Use ENV fetch with no default so misconfiguration fails loudly:
```yaml
POSTGRES_DB: <%= ENV.fetch("POSTGRES_DB") %>
POSTGRES_USER: <%= ENV.fetch("POSTGRES_USER") %>
```

### 2) Add missing indexes

**Problem:** These columns are filtered constantly but have no index:
- `claims.status` — filtered in `CheckAsyncClaimsJob`, engine runner, API
- `work_items.status` — filtered in every list query and engine tick
- `trace_events(trace_id, sequence)` — composite for ordered trace display

**Fix:** Single migration:

```ruby
class AddMissingIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :claims, :status
    add_index :work_items, :status
    add_index :trace_events, [:trace_id, :sequence]
  end
end
```

**Test:**
- After migration, verify indexes exist via `ActiveRecord::Base.connection.indexes(:claims)` etc.

### 3) DB-level enum constraints

**Problem:** Status enums are Rails-level integers with no database CHECK constraint. A bug or direct SQL could insert an invalid integer.

**Fix:** Add CHECK constraints for the key enum columns:

```ruby
class AddEnumConstraints < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      ALTER TABLE work_items ADD CONSTRAINT work_items_status_check
        CHECK (status BETWEEN 0 AND 5);
      ALTER TABLE claims ADD CONSTRAINT claims_status_check
        CHECK (status BETWEEN 0 AND 4);
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE work_items DROP CONSTRAINT work_items_status_check;
      ALTER TABLE claims DROP CONSTRAINT claims_status_check;
    SQL
  end
end
```

Note: Verify the exact enum value ranges from the model definitions before writing the migration.

## Acceptance criteria

- [ ] `config/deploy.yml` uses `ENV.fetch` for database credentials with no hardcoded defaults
- [ ] Indexes exist on `claims.status`, `work_items.status`, `trace_events(trace_id, sequence)`
- [ ] CHECK constraints prevent invalid enum values at the database level
- [ ] All migrations are reversible
