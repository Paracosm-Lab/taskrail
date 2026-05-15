# Bad Error Handling Fixture

This fixture intentionally contains unsafe patterns for the `error_handling_audit` cookbook:

- `PaymentsController#create` uses a bare `rescue => e`, `puts`, and a generic error message.
- `SyncJob#perform` swallows all exceptions.
- `ExternalApi.sync` performs an HTTP call without an explicit timeout.

Do not clean up these patterns in the fixture unless the cookbook spec changes.
