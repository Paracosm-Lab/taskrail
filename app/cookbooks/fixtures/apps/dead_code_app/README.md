# Dead Code Fixture App

Fixture for the dead_code_removal cookbook.

Intentional candidates:
- `unused_charting_gem` dependency is never required.
- `UnusedHelper` is never included.
- `/reports/export` routes to a missing controller action.
- `Customer#stale_score` is never called.
- `UnusedLegacyModel` is never referenced.
- `NoopMigration` has an empty change method.
- `new_reports_ui` is marked removed and fully rolled out.

Safety case:
- `Customer#active?` is dynamically referenced via `public_send(:active?)` and should be classified as `needs_investigation` if considered.
