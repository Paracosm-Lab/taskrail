# Test Coverage Backfill Cookbook

Source spec: `docs/specs/cookbook-01-test-coverage-backfill.md`

## Queue

Slug: `test_backfill`

Stages:

```text
scan_coverage -> identify_gaps -> generate_tests -> run_tests -> human_review -> done
```

## What it does

The queue scans a target repository for coverage gaps, turns uncovered paths into prioritized test units, generates specs that match repository conventions, runs the generated specs, and sends the result to human review before merge.

## Portable paths

Queue YAML and prompt references are relative to `Rails.root`. Prompt files live under `cookbooks/prompts/test_backfill/`. The `shell_script` stages intentionally omit `working_directory` so `Adapters::ShellScriptAdapter` uses its `Rails.root` default. Do not add absolute checkout paths to queue YAML or fixtures.

## Fixture app

The deterministic fixture app lives in `test/fixtures/apps/untested_app/`. It provides a small `Widget` class with intentionally uncovered behavior for cookbook tests.

## Shared infrastructure

This cookbook does not define shared Docker, database, or network infrastructure. Use the shared cookbook infrastructure setup for those concerns. The cookbook-specific fake shell commands use Ruby stdlib only so they work in local and dockerized Rails environments.

## Verification

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rails db:seed
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb --format documentation
```
