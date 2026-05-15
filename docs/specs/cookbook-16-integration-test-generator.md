# Cookbook Spec: Integration Test Generator

**Category: Testing**

## Use Case

You have unit tests. They pass. Production still breaks because the pieces don't fit together — the API returns a different shape than the frontend expects, the background job assumes a record exists that the controller hasn't created yet, the webhook handler can't parse what the third-party actually sends.

Unit tests verify components in isolation. Integration tests verify that the components work together. Nobody writes them because they're hard to set up, slow to run, and tedious to maintain. TaskRail maps the critical user flows, generates the integration tests, and keeps them current.

## Queue: `integration_tests`

### Stages

```
map_user_flows → identify_boundaries → generate_tests → run_tests → human_review → done
```

### Stage Details

**map_user_flows** (Sonnet)
- Adapter: `inline_claude`
- Input: repository, routes, controllers, documentation
- Task: Identify the critical end-to-end user flows:
  - **Authentication**: sign up → verify email → log in → access protected resource
  - **Core business flow**: create thing → process thing → deliver thing → bill for thing
  - **Background processing**: event fires → job enqueued → job runs → side effects happen
  - **Webhook handling**: external service sends webhook → system processes it → state updates
  - **Error recovery**: operation fails → retry → succeed (or escalate)
  - For each flow: entry point, steps, services involved, data dependencies, expected final state
- Artifact: `user_flows` — `{ flows: [{ name, entry_point, steps: [{ action, service, endpoint_or_method, data_deps }], expected_outcome, services_involved }] }`
- Predicate: `flows_mapped`
- Why Sonnet: needs to understand the business logic and trace cross-service interactions

**identify_boundaries** (Sonnet)
- Adapter: `inline_claude`
- Input: user_flows artifact, source code
- Task: For each flow, identify the integration boundaries — where one component talks to another:
  - Controller → Service → Model → Database
  - Service → External API
  - Controller → Background Job → Side Effect
  - Webhook → Handler → State Change
  - What needs to be real vs. what can be stubbed (e.g., real DB, stubbed external API)
  - What test data needs to exist before the flow starts (factories, fixtures, seed data)
- Artifact: `boundary_map` — `{ flows: [{ name, boundaries: [{ from, to, contract, stub_strategy }], setup_data: [], teardown }] }`
- Predicate: `boundaries_identified`

**generate_tests** (Sonnet)
- Adapter: `inline_claude`
- Input: boundary_map, source code, existing test helpers/factories
- Task: Write integration test files for each flow:
  - Use the project's test framework (RSpec + request specs, pytest, etc.)
  - Set up test data using existing factories/fixtures
  - Make real HTTP requests through the stack (no controller unit test stubs)
  - Assert on final state, not intermediate steps
  - Stub only external services (Stripe, email, etc.) — everything internal is real
  - Include the sad path: what happens when step 3 of 5 fails?
- Artifact: `integration_specs` — `{ specs: [{ path, content, flow_name, boundaries_tested }] }`
- Predicate: `tests_generated` (reuse)

**run_tests** (shell_script)
- Adapter: `shell_script`
- Predicate: `tests_passed` (existing)
- On failure: regress to `generate_tests` — the integration test itself might be wrong

**human_review** (gate)

### Queue Config

```yaml
name: Integration Test Generator
slug: integration_tests
stages:
  - map_user_flows
  - identify_boundaries
  - generate_tests
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 3
stage_configs:
  map_user_flows:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [flows_mapped]
    agent_prompt: file://prompts/integration_map_flows.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: user_flows
  identify_boundaries:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [boundaries_identified]
    agent_prompt: file://prompts/integration_boundaries.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: boundary_map
  generate_tests:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [tests_generated]
    agent_prompt: file://prompts/integration_generate.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: integration_specs
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [tests_passed]
    agent_prompt: Write integration spec files and run the test suite. Report pass/fail.
    timeout_seconds: 600
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review integration tests.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates

- `flows_mapped` — user_flows artifact with at least one flow
- `boundaries_identified` — boundary_map artifact with boundaries for each flow

### E2E Test Fixture

Use TaskRail itself: the flow of "create work item → engine tick → claim created → adapter runs → report stored → predicate checked → stage advanced" is a real integration test that touches the API, the engine, the adapter, and the database.
