# Error Handling Audit Cookbook

Source spec: `docs/specs/cookbook-02-error-handling-audit.md`

The `error_handling_audit` queue scans a repository for unsafe error handling, classifies findings by operational risk, drafts fixes, runs a fixture validation command, and waits for human review.

## Queue Stages

`scan_error_handling -> classify_severity -> draft_fixes -> run_tests -> human_review -> done`

## Artifacts

- `error_patterns`: scan output with `{ patterns: [...] }`. Empty arrays are valid.
- `severity_report`: classified findings with severity, blast radius, data risk, frequency, and recommendation.
- `fix_patches`: proposed patches for findings that can be directly remediated.
- `test_results`: shell validation output from the existing `shell_script` adapter.

## Infrastructure Requirements

This cookbook uses existing TaskRail infrastructure:

- `inline_claude` for scan/classify/draft stages.
- `shell_script` for validation.
- `fake` for human review and terminal done stages.
- Rails.root-relative prompt files under `prompts/`.
- Rails.root-relative fixture files under `test/fixtures/apps/bad_error_handling/`.

It does not add dedicated Docker Compose services. In Docker, run the app with the shared cookbook infrastructure and ensure Ruby is available for the fixture syntax command.

## Cross-Queue Spawn

The classify stage may include `spawn_work_items` in its report body for critical findings that need broader architectural work. Those items should target the `development` queue and include `tags.source = error_handling_audit`.

## Local Verification

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec   spec/services/engine/error_handling_audit_workflow_integration_spec.rb   spec/models/work_queue_seed_spec.rb   spec/services/engine/predicate_registry_spec.rb   spec/services/engine/predicates/error_patterns_found_spec.rb   spec/services/engine/predicates/severity_classified_spec.rb   spec/services/engine/predicates/fixes_drafted_spec.rb
```
