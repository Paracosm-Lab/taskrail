# Migration Safety Fixture App

This fixture models a risky database migration: adding `orders.region` as `NOT NULL` with a default on a large existing table.

The unsafe migration (`20240101000000_add_region_to_orders_unsafe.rb`) represents the scary production change that can rewrite or lock a large table.
The safe migration (`20240101000001_add_region_to_orders_safe.rb`) represents the expand/backfill/contract approach:
1. add the column nullable
2. backfill in batches through `OrderBackfill`
3. enforce `NOT NULL` after data is present

The cookbook should identify affected files, flag the unsafe migration as a blocking downtime risk, draft rollback commands, run the deterministic rollback fixture, and produce a runbook.
