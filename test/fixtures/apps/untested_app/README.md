# Untested App Fixture

This tiny fixture app exists for the Test Coverage Backfill cookbook. It intentionally has behavior in `Widget#reorder_message` that is not covered by its spec so coverage scanning and test generation can use stable, deterministic paths.

The fixture is not a standalone Rails app and should not duplicate shared Docker infrastructure. Cookbook tests should run it from the StupidClaw Rails root with relative paths.
