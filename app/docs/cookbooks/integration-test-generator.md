# Integration Test Generator Cookbook

Source spec: `docs/specs/cookbook-16-integration-test-generator.md`

The `integration_tests` queue maps critical end-to-end user flows, identifies boundaries between components, generates integration specs, runs them, and pauses for human review.

## Stages

1. `map_user_flows`: writes a `user_flows` artifact with critical flows, steps, expected outcomes, and services involved.
2. `identify_boundaries`: writes a `boundary_map` artifact that describes component contracts and real-vs-stubbed boundaries.
3. `generate_tests`: writes an `integration_specs` artifact containing spec paths, contents, flow names, and boundaries tested.
4. `run_tests`: runs the generated/focused integration specs and writes `test_results`.
5. `human_review`: blocks for review before generated tests are accepted.
6. `done`: terminal state.

## Deterministic fixture

The E2E fixture in `spec/e2e/integration_tests_cookbook_spec.rb` uses TaskRail itself as the integration target:

- API request creates a `WorkItem`.
- `Engine::Runner` claims each stage.
- `Adapters::FakeAdapter` emits deterministic reports/artifacts for cookbook stage names.
- Predicates verify `user_flows`, `boundary_map`, `integration_specs`, and `test_results`.
- `Engine::TransitionManager` advances the item to `done`.

This touches the API, engine, adapter, database, report/artifact persistence, predicates, and stage transition logs without calling real Claude, Docker, or external services.

## Infrastructure expectations

This cookbook assumes the shared TaskRail development/test infrastructure is available. It does not define new Docker Compose services. Queue YAML uses repo-relative prompt files and relies on adapter defaults for the working directory.

## Focused tests

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/services/engine/predicates/flows_mapped_spec.rb \
  spec/services/engine/predicates/boundaries_identified_spec.rb \
  spec/services/engine/predicates/tests_generated_spec.rb \
  spec/services/engine/predicate_registry_spec.rb \
  spec/models/work_queue_seed_spec.rb \
  spec/e2e/integration_tests_cookbook_spec.rb
```
